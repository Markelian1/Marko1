#!/usr/bin/env python3
"""Simulation of GOOGLE_STRATEG_XAUUSD.mq5 (v1.10) and its improved version
GOOGLE_STRATEG_PRO.mq5 (v2.00).

The EA's rules (server time):
  - range = high / low of the M15 bars from InpRangeStart (11:30) to InpRangeEnd (14:30)
  - at 14:30: trend = last closed H1 close vs EMA 200 H1; one stop order a day:
      up:   buy stop at range high + buffer (15 pips = 1.50 $)
      down: sell stop at range low - buffer
    SL = entry -/+ (range / 2 + buffer), TP = InpRewardRatio (3) x SL
    the order is placed only while the price is on the right side of the
    entry (the EA retries every tick), it is deleted at 18:00
  - break-even at +1R: SL to entry + 2 points
  - no time exit, no Friday close; a new order every day even if a trade is open

With the SL in the middle of the range the fill bar decides a lot: on M15 /
M5 bars it is unknown whether the stop filled before the low. "pess" assumes
the SL was hit after the fill whenever the bar reaches it, otherwise the bar
path (open - low - high - close on a rising bar) decides. MT5 (PF 0.95 in
2023-26) is between the two; with the SL beyond the whole range both give the
same result.

  python3 google_strateg.py
"""
import bisect
import bisect
import sys
from datetime import datetime, timezone

sys.path.insert(0, ".")
from crt_backtest import load_mt5

EXTRA = 0.05
DAY = 86400
NY = 7 * 3600


def hm(s):
    h, m = s.split(":")
    return int(h) * 3600 + int(m) * 60


def run(bars, start="11:30", end="14:30", cancel="18:00", buf=1.5, rr=3.0, be=True, be_off=0.02, trend="ema200h1",
        fri_close=False, max_hold=0, d1_trend=None, ny_times=False, invert=False, pess=False, both=False,
        max_rng=0.0, min_rng=0.0, sl_full=False, market=False):
    n = len(bars)
    off = -NY if ny_times else 0           # ny_times: the clock strings are New York time
    # H1 EMA 200 of closes, by H1 bar start
    h1 = {}
    for t, o, h, l, c, sp in bars:
        h1[t - t % 3600] = c
    ema, e = {}, None
    for k in sorted(h1):
        e = h1[k] if e is None else e + (h1[k] - e) * 2 / 201
        ema[k] = (h1[k], e)
    rs, re_, cx = hm(start), hm(end), hm(cancel)
    trades = []
    days = sorted({(t + off) - (t + off) % DAY for t, *_ in bars})
    times = [b[0] for b in bars]
    # daily ranges (server days) for the range-size filter
    dh = {}
    for t, o, h, l, c, sp in bars:
        k = t - t % DAY
        x = dh.get(k)
        dh[k] = (max(x[0], h), min(x[1], l)) if x else (h, l)
    dkeys = sorted(dh)
    drng = [dh[k][0] - dh[k][1] for k in dkeys]
    for day in days:
        d0 = day - off
        a, b = bisect.bisect_left(times, d0 + rs), bisect.bisect_left(times, d0 + re_)
        if b - a < 2:
            continue
        hi = max(x[2] for x in bars[a:b])
        lo = min(x[3] for x in bars[a:b])
        rng = hi - lo
        if rng <= 0:
            continue
        place_t = d0 + re_
        if max_rng or min_rng:
            k = bisect.bisect_left(dkeys, place_t - place_t % DAY)
            if k < 15:
                continue
            atr = sum(drng[k - 14:k]) / 14
            if (max_rng and rng > max_rng * atr) or (min_rng and rng < min_rng * atr):
                continue
        if both:
            d = 0
        elif trend == "ema200h1":
            k = place_t - place_t % 3600 - 3600
            if k not in ema:
                continue
            c1, e1 = ema[k]
            d = 1 if c1 > e1 else 2 if c1 < e1 else 0
        elif trend == "d1":
            d = d1_trend.get(place_t - place_t % DAY, 0)
        else:
            d = 0
        if not d and not both:
            continue
        if invert:
            d = 3 - d
        dist = rng / 2 + buf
        end_i = min(bisect.bisect_left(times, d0 + cx), n)

        def fill(d):
            # the order is placed at the first bar that opens on the right side of
            # the entry (the EA retries every tick) and lives until the cancel time
            entry = hi + buf if d == 1 else lo - buf
            placed = False
            for i in range(b, end_i):
                t, o, h, l, c, sp = bars[i]
                sp += EXTRA
                if not placed:
                    if (d == 1 and o + sp < entry) or (d == 2 and o > entry):
                        placed = True
                    else:
                        continue
                if (d == 1 and h + sp >= entry) or (d == 2 and l <= entry):
                    return i
            return None

        if both:                                   # buy stop and sell stop, the first fill cancels the other
            f1, f2 = fill(1), fill(2)
            if f1 is None and f2 is None:
                continue
            if f1 is not None and f2 is not None and f1 == f2:
                continue                           # both levels in one bar: unknown order, skipped
            d = 1 if f2 is None or (f1 is not None and f1 < f2) else 2
            fill_i = f1 if d == 1 else f2
        elif market:                               # control: no breakout, in at the range end
            fill_i = b
        else:
            fill_i = fill(d)
            if fill_i is None:
                continue
        entry = hi + buf if d == 1 else lo - buf
        if market:
            entry = bars[b][1] + (bars[b][5] + EXTRA if d == 1 else 0)
        if sl_full:                                # SL beyond the other side of the range
            dist = rng + 2 * buf
        sl = entry - dist if d == 1 else entry + dist
        tp = entry + rr * dist if d == 1 else entry - rr * dist
        t, o, h, l, c, sp = bars[fill_i]
        px = max(o + sp + 0, entry) if d == 1 else min(o, entry)      # a gap through the stop fills at the open
        risk = px - sl if d == 1 else sl - px
        cur_sl = sl
        res = None
        # on the fill bar the path is open -> low -> high -> close for a rising bar
        # (open -> high -> low -> close for a falling one): for a buy filled on a
        # rising bar the low came before the fill, on a falling bar after it
        up_bar = c >= o
        with_fill = (up_bar if d == 1 else not up_bar) and not pess and not market   # pess: the stop is always hit first
        for j in range(fill_i, n):
            tj, oj, hj, lj, cj, spj = bars[j]
            spj += EXTRA
            nyj = tj - NY
            first = j == fill_i
            if not first and ((fri_close and (nyj // DAY + 3) % 7 == 4 and nyj % DAY >= 16 * 3600) or
                              (max_hold and tj - t >= max_hold)):
                ex = oj if d == 1 else oj + spj
                res = ((ex - px) if d == 1 else (px - ex), tj, "time")
                break
            if d == 1:
                if (lj <= cur_sl and (not first or not with_fill)) or (first and cj <= cur_sl):
                    ex = min(cur_sl, oj) if not first else cur_sl
                    res = (ex - px, tj, "SL" if cur_sl < px else "BE")
                    break
                if hj >= tp and (not first or with_fill):
                    res = (tp - px, tj, "TP")
                    break
                if be and (not first or with_fill) and hj >= px + risk and cur_sl < px:
                    cur_sl = px + be_off
            else:
                if (hj + spj >= cur_sl and (not first or not with_fill)) or (first and cj + spj >= cur_sl):
                    ex = max(cur_sl, oj + spj) if not first else cur_sl
                    res = (px - ex, tj, "SL" if cur_sl > px else "BE")
                    break
                if lj + spj <= tp and (not first or with_fill):
                    res = (px - tp, tj, "TP")
                    break
                if be and (not first or with_fill) and lj + spj <= px - risk and cur_sl > px:
                    cur_sl = px - be_off
        if res:
            trades.append(dict(t_in=t, t_out=res[1], dir=d, r=res[0] / risk, why=res[2]))
    return trades


def run_fade(bars, start="11:30", end="14:30", cancel="18:00", buf=0.5, rr=2.0, tp_mode="rr", trend=None,
             d1_trend=None, ema_side=False, pess=True, max_hold=0, min_sweep=0.0):
    """The opposite idea (CRT on the session range): after the range end a bar
    trades beyond the range high (low) and closes back inside: sell (buy) at the
    next bar open, SL beyond the sweep extreme + buf, TP = rr x risk, or the
    other side of the range (tp_mode "range") or its middle ("mid")."""
    n = len(bars)
    times = [b[0] for b in bars]
    h1 = {}
    for t, o, h, l, c, sp in bars:
        h1[t - t % 3600] = c
    ema, e = {}, None
    for k in sorted(h1):
        e = h1[k] if e is None else e + (h1[k] - e) * 2 / 201
        ema[k] = (h1[k], e)
    rs, re_, cx = hm(start), hm(end), hm(cancel)
    trades = []
    days = sorted({t - t % DAY for t in times})
    for d0 in days:
        a, b = bisect.bisect_left(times, d0 + rs), bisect.bisect_left(times, d0 + re_)
        if b - a < 2:
            continue
        hi = max(x[2] for x in bars[a:b])
        lo = min(x[3] for x in bars[a:b])
        rng = hi - lo
        if rng <= 0:
            continue
        allow = {1, 2}
        if trend == "d1":
            dt = d1_trend.get(d0, 0)
            allow = {dt} if dt else set()
        elif trend == "ema200h1":
            k = d0 + re_ - 3600
            k -= k % 3600
            if k not in ema:
                continue
            c1, e1 = ema[k]
            allow = {1} if c1 > e1 else {2}
            if ema_side:                            # fade against the H1 trend only
                allow = {3 - x for x in allow}
        end_i = min(bisect.bisect_left(times, d0 + cx), n - 1)
        ext_h, ext_l = hi, lo
        sig = None
        for i in range(b, end_i):
            t, o, h, l, c, sp = bars[i]
            ext_h, ext_l = max(ext_h, h), min(ext_l, l)
            if 2 in allow and ext_h - hi > min_sweep and c < hi and h >= ext_h:
                sig = (i, 2, ext_h)
                break
            if 1 in allow and lo - ext_l > min_sweep and c > lo and l <= ext_l:
                sig = (i, 1, ext_l)
                break
        if not sig:
            continue
        i, d, ext = sig
        t, o, h, l, c, sp = bars[i + 1]
        sp += EXTRA
        px = o + sp if d == 1 else o
        sl = ext - buf if d == 1 else ext + buf
        risk = px - sl if d == 1 else sl - px
        if risk <= 0:
            continue
        if tp_mode == "range":
            tp = hi if d == 1 else lo
        elif tp_mode == "mid":
            tp = (hi + lo) / 2
        else:
            tp = px + rr * risk if d == 1 else px - rr * risk
        if (d == 1 and tp <= px) or (d == 2 and tp >= px):
            continue
        res = None
        for j in range(i + 1, n):
            tj, oj, hj, lj, cj, spj = bars[j]
            spj += EXTRA
            if max_hold and tj - t >= max_hold:
                ex = oj if d == 1 else oj + spj
                res = ((ex - px) if d == 1 else (px - ex), tj, "time")
                break
            if d == 1:
                if lj <= sl:
                    res = (min(sl, oj) - px, tj, "SL")
                    break
                if hj >= tp:
                    res = (tp - px, tj, "TP")
                    break
            else:
                if hj + spj >= sl:
                    res = (px - max(sl, oj + spj), tj, "SL")
                    break
                if lj + spj <= tp:
                    res = (px - tp, tj, "TP")
                    break
        if res:
            trades.append(dict(t_in=t, t_out=res[1], dir=d, r=res[0] / risk, why=res[2]))
    return trades


def stats(tr):
    rs = [t["r"] for t in tr]
    if not rs:
        return "n   0"
    w = sum(r for r in rs if r > 0)
    lo = -sum(r for r in rs if r < 0) or 1e-9
    eq = pk = dd = 0.0
    for t in sorted(tr, key=lambda x: x["t_out"]):
        eq += t["r"]
        pk = max(pk, eq)
        dd = max(dd, pk - eq)
    return f"n{len(rs):4d} win {100 * sum(r > 0 for r in rs) / len(rs):4.1f}% PF {w / lo:4.2f} {sum(rs):+6.1f}R dd {dd:5.1f}"


def money(tr, t0, t1, risk):
    bal = pk = 1.0
    dd = 0.0
    for t in sorted([t for t in tr if t0 <= t["t_in"] < t1], key=lambda x: x["t_out"]):
        bal *= 1 + risk * t["r"]
        pk = max(pk, bal)
        dd = max(dd, 1 - bal / pk)
    return 100 * (bal - 1), 100 * dd


if __name__ == "__main__":
    from model_lab import aggregate
    ts = lambda y, m, d: datetime(y, m, d, tzinfo=timezone.utc).timestamp()
    D = {tf: load_mt5([f"../data/XAUUSD_{tf}.csv"])[0] for tf in ("M30", "M15", "M5", "M1")}
    d1 = aggregate(D["M30"], DAY)
    d1t, cl = {}, []
    for bb in d1:
        d1t[bb[0]] = 0 if len(cl) < 50 else (1 if cl[-1] > sum(cl[-50:]) / 50 else 2)
        cl.append(bb[4])
    # 1. the MT5 test: 2023.01.01 - 2026.09.26 (MT5: 627 trades, 384 long, 243 short, PF 0.95)
    for pess in (True, False):
        for tf in ("M15", "M5"):
            x = [t for t in run(D[tf], pess=pess) if ts(2023, 1, 1) <= t["t_in"] < ts(2026, 9, 26)]
            print(f"as delivered, {tf} bars, fill bar {'worst case' if pess else 'bar path  '}: {stats(x)} "
                  f"long {sum(t['dir'] == 1 for t in x)} short {sum(t['dir'] == 2 for t in x)}")
    # 2. step by step, worst case on the fill bar
    P = [("20.03-22.06", "M30", ts(2020, 3, 1), ts(2022, 7, 1)), ("22.07-24.06", "M15", ts(2022, 7, 1), ts(2024, 7, 1)),
         ("24.07-26.09", "M15", ts(2024, 7, 1), ts(2026, 9, 27)), ("M5 25.07-26.09", "M5", ts(2025, 7, 1), ts(2026, 9, 27)),
         ("M1 26.06-26.09", "M1", ts(2026, 6, 25), ts(2026, 9, 27))]

    def pf(tr):
        w = sum(t["r"] for t in tr if t["r"] > 0)
        lo = -sum(t["r"] for t in tr if t["r"] < 0) or 1e-9
        return f"PF {w / lo:4.2f} {sum(t['r'] for t in tr):+6.1f}R n{len(tr):3d}"

    def row(name, dirs=(1, 2), **kw):
        kw.setdefault("pess", True)
        out = [pf([t for t in run(D[tf], d1_trend=d1t, **kw) if a <= t["t_in"] < b and t["dir"] in dirs]) for _, tf, a, b in P]
        print(f"  {name:50} | " + " | ".join(out))

    imp = dict(trend="d1", be=False, sl_full=True)
    v2 = dict(imp, start="15:00", end="17:00", cancel="21:00")
    print(f"  {'':50} | " + " | ".join(f"{p[0]:^22}" for p in P))
    row("as delivered")
    row("+ trend D1 (close vs SMA 50) for EMA 200 H1", trend="d1")
    row("+ no break-even", trend="d1", be=False)
    row("+ SL beyond the whole range (improved)", **imp)
    row("  same, TP 2R", rr=2.0, **imp)
    row("  same, range 15:00-17:00, cancel 21:00 (v2.00)", **v2)
    row("  v2.00 buys", dirs=(1,), **v2)
    row("  v2.00 sells", dirs=(2,), **v2)
    print("controls: no breakout, in at the range end in the D1 trend, same SL and TP")
    row("control 11:30-14:30", market=True, **imp)
    row("control 15:00-17:00", market=True, **v2)
    row("control 15:00-17:00 buys", dirs=(1,), market=True, **v2)
    print("neighbours of v2.00")
    for w in (("14:30", "16:30", "21:00"), ("15:30", "17:30", "21:00"), ("15:00", "17:00", "19:00"), ("08:00", "11:00", "15:00")):
        row(f"range {w[0]}-{w[1]}, cancel {w[2]}", **dict(imp, start=w[0], end=w[1], cancel=w[2]))
    print("the opposite (fade the failed breakout, CRT style), 11:30-14:30, D1 trend, TP 2R")
    for tf_lab, tf, a, b in P[:3]:
        print(f"  {tf_lab}: {stats([t for t in run_fade(D[tf], trend='d1', d1_trend=d1t) if a <= t['t_in'] < b])}")
