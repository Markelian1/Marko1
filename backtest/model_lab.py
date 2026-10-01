#!/usr/bin/env python3
"""Model lab: many CRT / time-based models on several timeframes, chosen on
one period and judged on a later one, then combined into a portfolio.

Base data: MT5 M30 export (server time = New York + 7). Higher timeframes
(H1, H4, D1) are built from it, so their candles match the broker's.

Model families
  CRT    the CRT engine of CRT_MTF_EA (parent -> sweep -> close back inside)
         on M30 / H1 / H4; SL beyond the sweep, TP at the CRT target or 1:2
  PDH    turtle soup of the previous day's high / low: a candle trades
         through it and closes back inside; SL beyond the candle, TP 1:2
  ASIA   continuation: first M30 close outside the Asia range (17:00-01:00
         New York) in the London window; SL at the range middle / far side
  H4OB   the CRT_1AM_EA model (Active and Selective rules, M30 entries)
Options: daily trend bias (previous close vs 50-day average) or none,
session (signal between 01:00 and 13:00 New York) or any time.

Selection: a model is kept when, in the selection period, it has at least
25 trades, +0.05R a trade and PF >= 1.10. The test period is never used
to choose. Costs: the broker spread of each bar + InpExtraCost.

  python3 model_lab.py --mt5 ../data/XAUUSD_M30.csv
"""
import argparse
import itertools
import sys
from collections import defaultdict
from datetime import datetime, timezone

from crt_backtest import EV_BEAR, EV_BULL, Engine, load_mt5
from crt_1am_backtest import ACTIVE, SELECTIVE
from crt_1am_backtest import run as run_h4ob

NY = 7 * 3600
DAY = 86400


# ============================================================================
# DATA
# ============================================================================

def aggregate(bars, sec):
    """[(t, o, h, l, c, first_idx, last_idx)] in server time."""
    out = []
    for i, (t, o, h, l, c, _) in enumerate(bars):
        k = t - t % sec
        if out and out[-1][0] == k:
            b = out[-1]
            out[-1] = (k, b[1], max(b[2], h), min(b[3], l), c, b[5], i)
        else:
            out.append((k, o, h, l, c, i, i))
    return out


def trend_by_day(bars, days=50):
    """server day -> 1 (up), 2 (down), 0 (not enough history)."""
    d1 = aggregate(bars, DAY)
    res = {}
    for i, b in enumerate(d1):
        if i < days:
            res[b[0]] = 0
            continue
        closes = [x[4] for x in d1[i - days:i]]
        prev = d1[i - 1][4]
        avg = sum(closes) / days
        res[b[0]] = 1 if prev > avg else 2 if prev < avg else 0
    return res, d1


# ============================================================================
# EXECUTION
# ============================================================================

class Exec:
    def __init__(self, bars, extra_cost):
        self.b = bars
        self.extra = extra_cost

    def trade(self, i, direction, sl, tp_r=None, tp_price=None, max_hold=8 * 3600, min_rr=1.0):
        """Enter at the open of bar i. Returns a trade dict or a skip reason."""
        b = self.b
        if i >= len(b):
            return "end"
        t, o, h, l, c, sp = b[i]
        sp += self.extra
        if sp > 0.50 + self.extra:
            return "spread"
        ny = t - NY
        if (ny // DAY + 3) % 7 == 4 and (ny % DAY) >= 12 * 3600:
            return "friday"
        entry = o + sp if direction == 1 else o
        risk = entry - sl if direction == 1 else sl - entry
        if risk <= 0:
            return "sl side"
        if risk < max(1.0, 4 * sp):
            return "sl small"
        if tp_price is not None:
            reward = tp_price - entry if direction == 1 else entry - tp_price
            if reward <= 0 or reward / risk < min_rr:
                return "rr"
            tp = tp_price
        else:
            tp = entry + tp_r * risk if direction == 1 else entry - tp_r * risk
        for j in range(i, len(b)):
            tj, oj, hj, lj, cj, spj = b[j]
            spj += self.extra
            nyj = tj - NY
            friday_close = (nyj // DAY + 3) % 7 == 4 and (nyj % DAY) >= 16 * 3600
            if j > i and (tj - t >= max_hold or friday_close or tj - b[j - 1][0] > 2 * DAY):
                px = oj if direction == 1 else oj + spj
                r = (px - entry) / risk if direction == 1 else (entry - px) / risk
                return dict(t_in=t, t_out=tj, dir=direction, r=r, why="time")
            if direction == 1:
                if lj <= sl:
                    return dict(t_in=t, t_out=tj, dir=direction, r=(min(sl, oj) - entry) / risk, why="SL")
                if hj >= tp:
                    return dict(t_in=t, t_out=tj, dir=direction, r=(tp - entry) / risk, why="TP")
            else:
                if hj + spj >= sl:
                    return dict(t_in=t, t_out=tj, dir=direction, r=(entry - max(sl, oj + spj)) / risk, why="SL")
                if lj + spj <= tp:
                    return dict(t_in=t, t_out=tj, dir=direction, r=(entry - tp) / risk, why="TP")
        return "end"


def take(signals, ex, one_at_a_time=True):
    """signals: [(entry_idx, dir, sl, kwargs)] in time order."""
    trades, busy_until = [], 0
    for i, d, sl, kw in signals:
        if i >= len(ex.b) or (one_at_a_time and ex.b[i][0] < busy_until):
            continue
        res = ex.trade(i, d, sl, **kw)
        if isinstance(res, dict):
            trades.append(res)
            busy_until = res["t_out"]
    return trades


# ============================================================================
# MODELS
# ============================================================================

def allowed(bias, trend, t, d):
    if bias == "none":
        return True
    return trend.get(t - t % DAY, 0) == d


def in_session(session, t_close):
    if session == "any":
        return True
    h = ((t_close - NY) % DAY) // 3600
    return 1 <= h < 13


def model_crt(bars, ex, trend, tf, bias, session, tp):
    sec = {"M30": 1800, "H1": 3600, "H4": 14400}[tf]
    hold = {"M30": 4, "H1": 8, "H4": 24}[tf] * 3600
    eng = Engine()
    sig = []
    for (k, o, h, l, c, i0, i1) in aggregate(bars, sec):
        ev = eng.step(o, h, l, c)
        if ev not in (EV_BULL, EV_BEAR):
            continue
        d = 1 if ev == EV_BULL else 2
        if not in_session(session, k + sec) or not allowed(bias, trend, k, d):
            continue
        sl = (eng.sweep - 0.30) if d == 1 else (eng.sweep + 0.30)
        kw = dict(tp_price=eng.target) if tp == "target" else dict(tp_r=2.0)
        sig.append((i1 + 1, d, sl, dict(kw, max_hold=hold)))
    return take(sig, ex)


def model_pdh(bars, ex, trend, d1, tf, bias, session):
    sec = {"M30": 1800, "H1": 3600}[tf]
    prev = {d1[i][0]: d1[i - 1] for i in range(1, len(d1))}
    sig, used = [], set()
    for (k, o, h, l, c, i0, i1) in aggregate(bars, sec):
        day = k - k % DAY
        p = prev.get(day)
        if p is None:
            continue
        pdh, pdl = p[2], p[3]
        for d, hit in ((2, h > pdh and pdl < c < pdh), (1, l < pdl and pdl < c < pdh)):
            if not hit or (day, d) in used:
                continue
            used.add((day, d))
            if not in_session(session, k + sec) or not allowed(bias, trend, k, d):
                continue
            sl = h + 0.30 if d == 2 else l - 0.30
            sig.append((i1 + 1, d, sl, dict(tp_r=2.0, max_hold=8 * 3600)))
    return take(sig, ex)


def model_asia(bars, ex, trend, bias, window, stop, rr):
    """First M30 close outside the Asia range (NY 17:00-01:00) inside the window."""
    m30 = aggregate(bars, 1800)
    sig = []
    by_day = defaultdict(list)
    for b in m30:
        ny = b[0] - NY
        by_day[(ny + 7 * 3600) // DAY].append(b)     # NY trading day starting 17:00
    end_h = {"london": 5, "morning": 10}[window]
    for key in sorted(by_day):
        rows = by_day[key]
        asia = [b for b in rows if ((b[0] - NY) % DAY) // 3600 >= 17 or ((b[0] - NY) % DAY) // 3600 < 1]
        if len(asia) < 8:
            continue
        hi = max(b[2] for b in asia)
        lo = min(b[3] for b in asia)
        mid = (hi + lo) / 2
        for b in rows:
            h_ny = ((b[0] - NY) % DAY) // 3600
            if not 1 <= h_ny < end_h:
                continue
            d = 1 if b[4] > hi else 2 if b[4] < lo else 0
            if d == 0:
                continue
            if allowed(bias, trend, b[0], d):
                sl = (mid if stop == "mid" else lo) if d == 1 else (mid if stop == "mid" else hi)
                sig.append((b[6] + 1, d, sl, dict(tp_r=rr, max_hold=8 * 3600)))
            break
    return take(sig, ex)


# ============================================================================
# REPORT
# ============================================================================

def summary(tr):
    n = len(tr)
    if n == 0:
        return dict(n=0, avg=0.0, pf=0.0, total=0.0, dd=0.0)
    rs = [t["r"] for t in tr]
    win = sum(r for r in rs if r > 0)
    loss = -sum(r for r in rs if r < 0)
    eq = peak = dd = 0.0
    for t in sorted(tr, key=lambda x: x["t_out"]):
        eq += t["r"]
        peak = max(peak, eq)
        dd = max(dd, peak - eq)
    return dict(n=n, avg=sum(rs) / n, pf=win / loss if loss else 9.99, total=sum(rs), dd=dd)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mt5", required=True, help="MT5 M30 export")
    ap.add_argument("--split", default="2023-07-01", help="first day of the test period")
    ap.add_argument("--extra-cost", type=float, default=0.10, help="added to every bar's spread (price units)")
    args = ap.parse_args()

    bars, _ = load_mt5([args.mt5])
    split = int(datetime.strptime(args.split, "%Y-%m-%d").replace(tzinfo=timezone.utc).timestamp())
    ex = Exec(bars, args.extra_cost)
    trend, d1 = trend_by_day(bars)
    first = datetime.fromtimestamp(bars[0][0], timezone.utc)
    last = datetime.fromtimestamp(bars[-1][0], timezone.utc)
    print(f"{len(bars)} M30 bars {first:%Y-%m-%d} .. {last:%Y-%m-%d} | selection < {args.split} <= test | extra cost {args.extra_cost}")

    models = {}
    for tf, bias, session, tp in itertools.product(("M30", "H1", "H4"), ("trend", "none"), ("01-13", "any"), ("target", "rr2")):
        models[f"CRT {tf} {bias} {session} {tp}"] = model_crt(bars, ex, trend, tf, bias, session, tp)
    for tf, bias, session in itertools.product(("M30", "H1"), ("trend", "none"), ("01-13", "any")):
        models[f"PDH {tf} {bias} {session}"] = model_pdh(bars, ex, trend, d1, tf, bias, session)
    for bias, window, stop, rr in itertools.product(("trend", "none"), ("london", "morning"), ("mid", "far"), (1.5, 2.0)):
        models[f"ASIA {bias} {window} sl-{stop} rr{rr}"] = model_asia(bars, ex, trend, bias, window, stop, rr)
    # H4OB through its own simulator (same costs: add the extra cost to the bar spreads)
    costed = [(t, o, h, l, c, sp + args.extra_cost) for (t, o, h, l, c, sp) in bars]
    for name, cfg in (("H4OB active-M30 trend", dict(ACTIVE, tf=1800, max_spread=0.5 + args.extra_cost)),
                      ("H4OB active-M30 none", dict(ACTIVE, tf=1800, bias="none", max_spread=0.5 + args.extra_cost)),
                      ("H4OB selective trend", dict(SELECTIVE, max_spread=0.5 + args.extra_cost)),
                      ("H4OB selective none", dict(SELECTIVE, bias="none", max_spread=0.5 + args.extra_cost))):
        models[name] = run_h4ob(costed, cfg)[0]

    years_sel = (split - bars[0][0]) / (365.25 * DAY)
    years_test = (bars[-1][0] - split) / (365.25 * DAY)
    print(f"\n{'model':<34} | {'SELECTION':^30} | {'TEST (unseen)':^30} | kept")
    print(f"{'':<34} | {'n':>5} {'/yr':>5} {'avg R':>7} {'PF':>5} {'DD':>5} | {'n':>5} {'/yr':>5} {'avg R':>7} {'PF':>5} {'DD':>5} |")
    kept = []
    for name, tr in models.items():
        a = summary([t for t in tr if t["t_in"] < split])
        b = summary([t for t in tr if t["t_in"] >= split])
        ok = a["n"] >= 25 and a["avg"] >= 0.05 and a["pf"] >= 1.10
        if ok:
            kept.append(name)
        print(f"{name:<34} | {a['n']:5d} {a['n'] / years_sel:5.0f} {a['avg']:+7.3f} {a['pf']:5.2f} {a['dd']:5.1f} | "
              f"{b['n']:5d} {b['n'] / years_test:5.0f} {b['avg']:+7.3f} {b['pf']:5.2f} {b['dd']:5.1f} | {'KEEP' if ok else ''}")

    print(f"\nKept on the selection period: {len(kept)} of {len(models)}")
    test_pos = [k for k in kept if summary([t for t in models[k] if t["t_in"] >= split])["avg"] > 0]
    print(f"Of those, positive in the unseen test period: {len(test_pos)}")

    # Portfolio of the kept models: each trades on its own, same risk per trade.
    port = [t for k in kept for t in models[k]]
    for label, sub in (("selection", [t for t in port if t["t_in"] < split]), ("TEST (unseen)", [t for t in port if t["t_in"] >= split])):
        s = summary(sub)
        yrs = years_sel if label == "selection" else years_test
        print(f"PORTFOLIO {label:<14} n={s['n']} ({s['n'] / yrs / 250:.2f}/day) avg={s['avg']:+.3f}R PF={s['pf']:.2f} "
              f"total={s['total']:+.1f}R maxDD={s['dd']:.1f}R")
    by = defaultdict(float)
    for t in port:
        by[datetime.fromtimestamp(t["t_in"], timezone.utc).year] += t["r"]
    print("PORTFOLIO by year: " + "  ".join(f"{y}: {r:+.1f}R" for y, r in sorted(by.items())))
    events = sorted([(t["t_in"], 1) for t in port] + [(t["t_out"], -1) for t in port])
    cur = peak = 0
    for _, e in events:
        cur += e
        peak = max(peak, cur)
    print(f"Max positions open at the same time: {peak}")


if __name__ == "__main__":
    main()
