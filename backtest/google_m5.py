#!/usr/bin/env python3
"""GOOGLE STRATEG on the 5 minute timeframe: five entry logics on closed M5 bars.

Every server day: range = high / low of the bars from `start` to `end`;
from `end` to `cancel` the closed signal bars are scanned for one entry:

  close   a bar closes beyond the range (+ buf) -> market at the next open
  retest  after that close, a limit at the range edge
  fvg     a bar closes beyond the range and leaves a fair value gap
          (low[i] > high[i-2] for a buy) -> limit at the middle of the gap
  pb      after the breakout close, the first bar against it is the
          pullback; stop order 0.10 $ beyond it; cancelled when a bar
          closes back inside the range
  fade    a bar trades beyond the range and closes back inside (sweep)
          -> market the other way at the next open (CRT idea)
  ctrl    control without a signal: market at the range end in the trend

SL: "range" (other side of the range - buf), "mid" (middle of the range),
"bar" (beyond the signal bar: the breakout / pullback / sweep bar).
TP = rr x risk (fade "range": the other side of the range).
Exit "eod": out at 23:00 server (16:00 New York) if still open.
Trend filter: "d1" (yesterday's close vs SMA 50 D1), "ema" (last H1 close
vs EMA 200 H1, the original EA), "none". The fade takes only the side of
the trend (a sweep of the low in an uptrend -> buy).

Fills and exits can run on finer bars than the signals (M1 check). On a
bar that reaches both SL and TP the SL counts; an order filled inside a
bar is stopped on that bar if the bar reaches the SL.

  python3 google_m5.py            (grid, multiprocessing)
  python3 google_m5.py check      (the two logics of GOOGLE_STRATEG_PRO v3.00: controls,
                                   neighbours, M1 execution, together, with GOLD MULTI PRO)
"""
import bisect
import itertools
import sys
from datetime import datetime, timezone
from multiprocessing import Pool

sys.path.insert(0, ".")
from crt_backtest import load_mt5

EXTRA = 0.05
DAY = 86400
MIN_RISK = 1.0


def hm(s):
    h, m = s.split(":")
    return int(h) * 3600 + int(m) * 60


def trend_maps(m30):
    """D1 trend by server day and H1 EMA 200 trend by H1 bar start, from M30 bars."""
    days, hours = {}, {}
    for t, o, h, l, c, sp in m30:
        days[t - t % DAY] = c
        hours[t - t % 3600] = c
    d1, cl = {}, []
    for k in sorted(days):
        d1[k] = 0 if len(cl) < 50 else (1 if cl[-1] > sum(cl[-50:]) / 50 else 2)
        cl.append(days[k])
    ema, e = {}, None
    for k in sorted(hours):
        e = hours[k] if e is None else e + (hours[k] - e) * 2 / 201
        ema[k] = 1 if hours[k] > e else 2
    return d1, ema


class Exec:
    def __init__(self, bars):
        self.b = bars
        self.t = [x[0] for x in bars]
        self.n = len(bars)

    def at(self, t):
        return bisect.bisect_left(self.t, t)

    def market(self, t, d):
        j = self.at(t)
        if j >= self.n:
            return None
        o, sp = self.b[j][1], self.b[j][5] + EXTRA
        return j, (o + sp if d == 1 else o)

    def pending(self, t0, t1, d, level, kind, cancel_px=None, cancel_close=None):
        """limit or stop order alive from t0 to t1; returns (index, fill price) or None.
        cancel_px: cancelled when the price trades there first (TP before the fill);
        cancel_close: cancelled when a bar closes beyond it (back inside the range)."""
        for j in range(self.at(t0), self.at(t1)):
            t, o, h, l, c, sp = self.b[j]
            sp += EXTRA
            if kind == "limit":
                if d == 1 and l + sp <= level:
                    return j, min(level, o + sp)
                if d == 2 and h >= level:
                    return j, max(level, o)
            else:
                if d == 1 and h + sp >= level:
                    return j, max(level, o + sp)
                if d == 2 and l <= level:
                    return j, min(level, o)
            if cancel_px is not None and ((d == 1 and h >= cancel_px) or (d == 2 and l + sp <= cancel_px)):
                return None
            if cancel_close is not None and ((d == 1 and c < cancel_close) or (d == 2 and c > cancel_close)):
                return None
        return None

    def exit(self, j, d, px, sl, tp, eod, tp_first_bar):
        for k in range(j, self.n):
            t, o, h, l, c, sp = self.b[k]
            sp += EXTRA
            if eod and t >= eod and k > j:
                ex = o if d == 1 else o + sp
                return (ex - px) if d == 1 else (px - ex), t, "eod"
            if d == 1:
                if l <= sl:
                    return (min(sl, o) if k > j else sl) - px, t, "SL"
                if h >= tp and (k > j or tp_first_bar):
                    return tp - px, t, "TP"
            else:
                if h + sp >= sl:
                    return px - (max(sl, o + sp) if k > j else sl), t, "SL"
                if l + sp <= tp and (k > j or tp_first_bar):
                    return px - tp, t, "TP"
        return None


def run(sig, ex, d1, ema, logic="close", start="15:00", end="17:00", cancel="21:00", buf=0.5, sl_mode="range",
        rr=2.0, trend="d1", exit_mode="none", t0=0, t1=1e18):
    times = [b[0] for b in sig]
    rs, re_, cx = hm(start), hm(end), hm(cancel)
    trades = []
    days = sorted({t - t % DAY for t in times if t0 <= t < t1})
    for day in days:
        a, b = bisect.bisect_left(times, day + rs), bisect.bisect_left(times, day + re_)
        if b - a < 2:
            continue
        hi = max(x[2] for x in sig[a:b])
        lo = min(x[3] for x in sig[a:b])
        if hi - lo <= 0:
            continue
        if trend == "d1":
            dt = d1.get(day, 0)
            allow = {dt} if dt else set()
        elif trend == "ema":
            k = day + re_ - 3600
            dt = ema.get(k - k % 3600, 0)
            allow = {dt} if dt else set()
        else:
            allow = {1, 2}
        if not allow:
            continue
        e_end = min(bisect.bisect_left(times, day + cx), len(sig) - 1)
        stop_t = day + cx
        eod = day + 23 * 3600 if exit_mode == "eod" else 0
        mid = (hi + lo) / 2
        res = None
        brk = {1: False, 2: False}              # pb: a breakout close was seen
        if logic == "ctrl":                     # control: no signal, market at the range end in the trend
            d = min(allow) if len(allow) == 1 else 0
            m = ex.market(day + re_, d) if d else None
            if m:
                j, px = m
                sl = {"range": lo - buf if d == 1 else hi + buf, "mid": mid, "bar": mid}[sl_mode]
                risk = px - sl if d == 1 else sl - px
                if risk >= MIN_RISK:
                    res = (d, j, px, sl, px + rr * risk if d == 1 else px - rr * risk, True)
        for i in range(max(b, 2), e_end if logic != "ctrl" else 0):
            t, o, h, l, c, sp = sig[i]
            nt = sig[i + 1][0]
            if logic == "fade":
                if 2 in allow and h > hi and c < hi:
                    d, sl, tp_px = 2, max(x[2] for x in sig[b:i + 1]) + buf, lo
                elif 1 in allow and l < lo and c > lo:
                    d, sl, tp_px = 1, min(x[3] for x in sig[b:i + 1]) - buf, hi
                else:
                    continue
                m = ex.market(nt, d)
                if m:
                    j, px = m
                    risk = px - sl if d == 1 else sl - px
                    tp = tp_px if sl_mode == "range" else (px + rr * risk if d == 1 else px - rr * risk)
                    if risk >= MIN_RISK:
                        res = (d, j, px, sl, tp, True)
                break                           # the first sweep of the day only
            done = False
            for d in allow:
                beyond = (d == 1 and c > hi + buf) or (d == 2 and c < lo - buf)
                edge = hi if d == 1 else lo
                if logic in ("close", "retest") and beyond:
                    done = True
                    if logic == "close":
                        m = ex.market(nt, d)
                        if not m:
                            break
                        j, px = m
                        sl = {"range": lo - buf if d == 1 else hi + buf, "mid": mid,
                              "bar": l - buf if d == 1 else h + buf}[sl_mode]
                        risk = px - sl if d == 1 else sl - px
                        if risk >= MIN_RISK:
                            res = (d, j, px, sl, px + rr * risk if d == 1 else px - rr * risk, True)
                    else:
                        sl = {"range": lo - buf if d == 1 else hi + buf, "mid": mid,
                              "bar": min(l, hi - MIN_RISK) - buf if d == 1 else max(h, lo + MIN_RISK) + buf}[sl_mode]
                        risk = edge - sl if d == 1 else sl - edge
                        if risk >= MIN_RISK:
                            tp = edge + rr * risk if d == 1 else edge - rr * risk
                            f = ex.pending(nt, stop_t, d, edge, "limit", cancel_px=tp)
                            if f:
                                res = (d, f[0], f[1], sl, tp, False)
                    break
                if logic == "fvg" and beyond:
                    h2, l2 = sig[i - 2][2], sig[i - 2][3]
                    if d == 1 and l > h2:
                        level, sl = (l + h2) / 2, {"range": lo - buf, "mid": mid, "bar": sig[i - 1][3] - buf}[sl_mode]
                    elif d == 2 and h < l2:
                        level, sl = (h + l2) / 2, {"range": hi + buf, "mid": mid, "bar": sig[i - 1][2] + buf}[sl_mode]
                    else:
                        continue                # no gap on this bar: keep scanning
                    risk = level - sl if d == 1 else sl - level
                    if risk < MIN_RISK:
                        continue
                    done = True
                    tp = level + rr * risk if d == 1 else level - rr * risk
                    f = ex.pending(nt, stop_t, d, level, "limit", cancel_px=tp)
                    if f:
                        res = (d, f[0], f[1], sl, tp, False)
                    break
                if logic == "pb":
                    if not brk[d]:
                        brk[d] = beyond
                        continue
                    if (d == 1 and c < hi) or (d == 2 and c > lo):
                        done = True             # closed back inside the range: failed breakout
                        break
                    if (d == 1 and c < o) or (d == 2 and c > o):     # the pullback bar
                        level = h + 0.1 if d == 1 else l - 0.1
                        sl = {"range": lo - buf if d == 1 else hi + buf, "mid": mid,
                              "bar": l - buf if d == 1 else h + buf}[sl_mode]
                        risk = level - sl if d == 1 else sl - level
                        if risk < MIN_RISK:
                            continue
                        done = True
                        tp = level + rr * risk if d == 1 else level - rr * risk
                        f = ex.pending(nt, stop_t, d, level, "stop", cancel_close=edge)
                        if f:
                            res = (d, f[0], f[1], sl, tp, False)
                        break
            if done:
                break
        if not res:
            continue
        d, j, px, sl, tp, tp_first = res
        risk = px - sl if d == 1 else sl - px
        if risk <= 0 or (d == 1 and tp <= px) or (d == 2 and tp >= px):
            continue
        out = ex.exit(j, d, px, sl, tp, eod, tp_first)
        if out:
            trades.append(dict(t_in=ex.b[j][0], t_out=out[1], dir=d, r=out[0] / risk, why=out[2]))
    return trades


def pf(tr):
    w = sum(t["r"] for t in tr if t["r"] > 0)
    lo = -sum(t["r"] for t in tr if t["r"] < 0) or 1e-9
    return w / lo, sum(t["r"] for t in tr), len(tr)


def dd_r(tr):
    eq = pk = dd = 0.0
    for t in sorted(tr, key=lambda x: x["t_out"]):
        eq += t["r"]
        pk = max(pk, eq)
        dd = max(dd, pk - eq)
    return dd


ts = lambda y, m, d: datetime(y, m, d, tzinfo=timezone.utc).timestamp()
# signal timeframe, period: M5 is the 5 minute EA; M15 / M30 are the same logic on coarser bars (more history)
P = [("M30 2020.03-22.06", "M30", ts(2020, 3, 1), ts(2022, 7, 1)),
     ("M15 2022.07-25.04", "M15", ts(2022, 7, 1), ts(2025, 5, 1)),
     ("M5 2025.05-25.12", "M5", ts(2025, 5, 6), ts(2026, 1, 1)),
     ("M5 2026.01-26.09", "M5", ts(2026, 1, 1), ts(2026, 9, 27))]
W = [("11:30", "14:30", "18:00"), ("15:00", "17:00", "21:00"), ("16:30", "17:00", "21:00"),
     ("10:00", "11:00", "15:00"), ("01:00", "09:00", "14:00")]
G = None
DATA = None


def grid():
    out = []
    for w, logic, slm, rr, tr, exm in itertools.product(W, ("close", "retest", "fvg", "pb", "fade"), ("range", "mid", "bar"),
                                                          (1.5, 2.0, 3.0), ("d1", "ema", "none"), ("none", "eod")):
        if logic == "fade" and slm == "mid":
            continue                            # fade: SL beyond the sweep; "range" = TP at the other side
        if logic == "fade" and slm == "range" and rr != 2.0:
            continue
        out.append(dict(start=w[0], end=w[1], cancel=w[2], logic=logic, sl_mode=slm, rr=rr, trend=tr, exit_mode=exm))
    return out


def run_one(k):
    kw = G[k]
    res = []
    for lab, tf, a, b in P:
        bars = DATA[tf]
        res.append(pf(run(bars, Exec(bars), DATA["d1"], DATA["ema"], t0=a, t1=b, **kw)))
    return k, res


def name(kw):
    return (f"{kw['start']}-{kw['end']} c{kw['cancel']} {kw['logic']:6} SL {kw['sl_mode']:5} rr {kw['rr']} "
            f"{kw['trend']:4} exit {kw['exit_mode']}")


def load():
    D = {tf: load_mt5([f"../data/XAUUSD_{tf}.csv"])[0] for tf in ("M30", "M15", "M5", "M1")}
    D["d1"], D["ema"] = trend_maps(D["M30"])
    return D


# the two logics of GOOGLE_STRATEG_PRO v3.00
L1 = dict(logic="close", start="15:00", end="17:00", cancel="21:00", sl_mode="mid", rr=3.0, trend="d1", exit_mode="eod")
L2 = dict(logic="retest", start="01:00", end="09:00", cancel="14:00", sl_mode="range", rr=2.0, trend="d1", exit_mode="none")


def check(D):
    def trades(kw, exec_tf=None, a=None, b=None):
        out = []
        for lab, tf, t0, t1 in P:
            if a is None:
                out.append(run(D[tf], Exec(D[tf]), D["d1"], D["ema"], t0=t0, t1=t1, **kw))
        if a is not None:
            return run(D["M5"], Exec(D[exec_tf]), D["d1"], D["ema"], t0=a, t1=b, **kw)
        return out

    def cells(res):
        return " | ".join(f"PF {p:4.2f} {r:+6.1f}R n{n:3d}" for p, r, n in map(pf, res))

    def money(tr, risk=0.0025):
        bal = pk = 1.0
        dd = 0.0
        for t in sorted(tr, key=lambda x: x["t_out"]):
            bal *= 1 + risk * t["r"]
            pk = max(pk, bal)
            dd = max(dd, 1 - bal / pk)
        return 100 * (bal - 1), 100 * dd

    def sh(t, dm):
        x = hm(t) // 60 + dm
        return f"{x // 60:02d}:{x % 60:02d}"

    print(f"  {'':46} | " + " | ".join(f"{p[0]:^22}" for p in P))
    for lab, kw in (("1 NY CLOSE M5", L1), ("2 AZIA RETEST M5", L2)):
        print(lab)
        rows = [("as chosen", kw), ("control: market at the range end, same SL/TP", dict(kw, logic="ctrl"))]
        rows += [(f"rr {rr}", dict(kw, rr=rr)) for rr in (1.5, 2.0, 3.0) if rr != kw["rr"]]
        rows += [(f"exit {'none' if kw['exit_mode'] == 'eod' else '23:00'}", dict(kw, exit_mode="none" if kw["exit_mode"] == "eod" else "eod"))]
        rows += [(f"buffer {bf}", dict(kw, buf=bf)) for bf in (0.25, 1.0)]
        rows += [(f"times shifted {dm:+d} min", dict(kw, start=sh(kw["start"], dm), end=sh(kw["end"], dm), cancel=sh(kw["cancel"], dm)))
                 for dm in (-30, 30)]
        rows += [("trend EMA 200 H1 (original)", dict(kw, trend="ema")), ("no trend filter", dict(kw, trend="none"))]
        for name, k in rows:
            print(f"  {name:46} | {cells(trades(k))}")
        a, b = ts(2026, 6, 23), ts(2026, 9, 27)
        p5, p1 = pf(trades(kw, "M5", a, b)), pf(trades(kw, "M1", a, b))
        print(f"  2026.06.23-09.26, fills / exits on M5 bars: PF {p5[0]:.2f} {p5[1]:+.1f}R n{p5[2]} | on M1 bars: PF {p1[0]:.2f} {p1[1]:+.1f}R n{p1[2]}")
    import google_strateg as GS
    v2 = [[t for t in GS.run(D[tf], trend="d1", d1_trend=D["d1"], be=False, sl_full=True, pess=True, start="15:00", end="17:00",
                              cancel="21:00") if a <= t["t_in"] < b] for _, tf, a, b in P]
    r1, r2 = trades(L1), trades(L2)
    both = [x + y for x, y in zip(r1, r2)]
    print("at 0.25% risk, 2020.03-2026.09 (M30 / M15 / M5 bars) and on M5 bars only (2025.05-2026.09):")
    for lab, res in (("v2.00 stop order", v2), ("1 NY CLOSE M5", r1), ("2 AZIA RETEST M5", r2), ("v3.00: 1 + 2", both)):
        p, dd = money([t for x in res for t in x])
        q, qd = money(res[2] + res[3])
        print(f"  {lab:18} | {cells(res)} | {p:+5.1f}% DD {dd:4.1f}% | M5: {q:+5.1f}% DD {qd:.1f}%")
    import gold_multi_pro as GMP
    import strategy_lab as SL
    gmp = [t for tr in GMP.setups().values() for t in tr]
    print("GOLD MULTI PRO with the M5 logics (0.1% risk):")
    for lab, tr in (("GOLD MULTI PRO", gmp), ("+ 1 NY CLOSE M5", gmp + sum(r1, [])), ("+ 2 AZIA RETEST M5", gmp + sum(r2, [])),
                    ("+ 1 + 2", gmp + sum(r1, []) + sum(r2, []))):
        n, p, dd, mcl, win = GMP.money(tr, SL.P[0], SL.P[3])
        print(f"  {lab:20}" + " | ".join(SL.cell(SL.split(tr, k)) for k in range(3)) + f" | {p:+.1f}% DD {dd:.2f}%")


if __name__ == "__main__" and sys.argv[1:] == ["check"]:
    check(load())
elif __name__ == "__main__":
    DATA = load()
    G = grid()
    with Pool() as pool:
        rows = dict(pool.map(run_one, range(len(G)), chunksize=8))
    print(f"{len(G)} variants")
    print(f"  {'':66} | " + " | ".join(f"{p[0]:^26}" for p in P))

    def show(ks, title):
        print(title)
        for k in ks:
            print(f"  {name(G[k]):66} | " + " | ".join(f"PF {p:4.2f} {r:+6.1f}R n{n:4d}" for p, r, n in rows[k]))

    # selection on the first three periods only (M30, M15, the first M5 half); the 2026 M5 half is out of sample
    ok = [k for k in rows if all(rows[k][i][2] >= 40 for i in range(3))]
    best = sorted(ok, key=lambda k: -min(rows[k][i][0] for i in range(3)))
    show(best[:30], "best 30 by the worst PF of the first three periods (2026 = out of sample):")
    for logic in ("close", "retest", "fvg", "pb", "fade"):
        ks = [k for k in best if G[k]["logic"] == logic][:3]
        show(ks, f"best of logic '{logic}':")
    oos = [k for k in best[:30] if rows[k][3][0] > 1.0]
    print(f"of the best 30, {len(oos)} also win in 2026 (out of sample)")
