#!/usr/bin/env python3
"""Portfolio lab: which extra strategies make PRO24 better as a whole?

Each candidate runs on its own (one position at a time, same costs and
Friday close as the other labs) and is judged in three periods:
2020.03-2022.06, 2022.07-2024.06, 2024.07-2026.09. A candidate is only
worth adding when PRO24 + candidate (same risk per trade) has a better
total R / max drawdown than PRO24 alone in every period.

  python3 strategy_lab.py          (from backtest/, needs ../data exports)
"""
import sys
sys.path.insert(0, ".")
from datetime import datetime, timezone

from crt_1am_backtest import run, pro24_set
from crt_backtest import load_mt5
from model_lab import Exec, aggregate

DAY = 86400
NY = 7 * 3600
m30 = load_mt5(["../data/XAUUSD_M30.csv"])[0]
m15 = load_mt5(["../data/XAUUSD_M15.csv"])[0]
EXTRA = 0.05
ex = Exec(m30, EXTRA)
P = [datetime(2020, 3, 1, tzinfo=timezone.utc).timestamp(), datetime(2022, 7, 1, tzinfo=timezone.utc).timestamp(),
     datetime(2024, 7, 1, tzinfo=timezone.utc).timestamp(), datetime(2026, 9, 27, tzinfo=timezone.utc).timestamp()]
NAMES = ["2020.03-22.06", "2022.07-24.06", "2024.07-26.09"]

d1 = aggregate(m30, DAY)
trend, closes = {}, []
for b in d1:                                   # previous close vs its 50-day average
    s = sum(closes[-50:]) / 50 if len(closes) >= 50 else None
    trend[b[0]] = 0 if s is None else (1 if closes[-1] > s else 2)
    closes.append(b[4])


def tday(t):
    return trend.get(t - t % DAY, 0)


def atr(bars, i, n=14):
    rs = [bars[j][2] - bars[j][3] for j in range(max(0, i - n), i)]
    return sum(rs) / len(rs) if rs else 0.0


def take(signals, bars=None, exe=None):
    bars, exe = bars or m30, exe or ex
    trades, busy = [], 0
    for i, d, sl, kw in sorted(signals, key=lambda s: s[0]):
        if i >= len(bars) or bars[i][0] < busy:
            continue
        r = exe.trade(i, d, sl, **kw)
        if isinstance(r, dict):
            trades.append(r)
            busy = r["t_out"]
    return trades


# ---------------------------------------------------------------- candidates
def nr7(rr=2.0):
    """Narrowest day of the last 7: next day, an M30 close beyond its high
    (uptrend) or low (downtrend); SL at the other side, TP rr, 24h."""
    sig = []
    for i in range(8, len(d1) - 1):
        rngs = [b[2] - b[3] for b in d1[i - 6:i + 1]]
        if rngs[-1] != min(rngs):
            continue
        k, o, h, l, c, i0, i1 = d1[i]
        tr = tday(d1[i + 1][0])
        for j in range(d1[i + 1][5], d1[i + 1][6] + 1):
            cj = m30[j][4]
            if tr == 1 and cj > h:
                sig.append((j + 1, 1, l, dict(tp_r=rr, max_hold=24 * 3600)))
                break
            if tr == 2 and cj < l:
                sig.append((j + 1, 2, h, dict(tp_r=rr, max_hold=24 * 3600)))
                break
    return take(sig)


def inside_day(rr=2.0, hold=24, bars=None, exe=None, conf=1800):
    """Inside day (high/low inside the previous day): next day, an M30 close
    beyond its high (uptrend) or low (downtrend); SL at the other side."""
    bars = bars or m30
    dd = aggregate(bars, DAY)
    sig = []
    for i in range(2, len(dd) - 1):
        if not (dd[i][2] < dd[i - 1][2] and dd[i][3] > dd[i - 1][3]):
            continue
        k, o, h, l, c, i0, i1 = dd[i]
        tr = tday(dd[i + 1][0])
        n0, n1 = dd[i + 1][5], dd[i + 1][6]
        for j in range(n0, n1 + 1):
            if (bars[j][0] + (bars[1][0] - bars[0][0])) % conf:
                continue                      # only at the close of a confirmation bar
            cj = bars[j][4]
            if tr == 1 and cj > h:
                sig.append((j + 1, 1, l, dict(tp_r=rr, max_hold=hold * 3600)))
                break
            if tr == 2 and cj < l:
                sig.append((j + 1, 2, h, dict(tp_r=rr, max_hold=hold * 3600)))
                break
    return take(sig, bars, exe)


def ema_pullback(tf=14400, n=20, rr=2.0, hold=48):
    """Daily trend up: an H4 bar dips under its EMA20 and closes back above;
    buy the next open, SL under that bar's low - 0.5 ATR, TP rr."""
    bars = aggregate(m30, tf)
    sig, ema, a = [], None, 2.0 / (n + 1)
    for i, (k, o, h, l, c, i0, i1) in enumerate(bars):
        prev = ema
        ema = c if ema is None else ema + a * (c - ema)
        if prev is None or i < 30:
            continue
        tr, at = tday(k), atr(bars, i)
        if tr == 1 and l < prev < c:
            sig.append((i1 + 1, 1, l - 0.5 * at, dict(tp_r=rr, max_hold=hold * 3600)))
        elif tr == 2 and h > prev > c:
            sig.append((i1 + 1, 2, h + 0.5 * at, dict(tp_r=rr, max_hold=hold * 3600)))
    return take(sig)


def donchian(tf=14400, n=20, rr=2.0, hold=48):
    bars = aggregate(m30, tf)
    sig = []
    for i in range(n, len(bars)):
        k, o, h, l, c, i0, i1 = bars[i]
        hi = max(b[2] for b in bars[i - n:i])
        lo = min(b[3] for b in bars[i - n:i])
        tr, at = tday(k), atr(bars, i)
        if tr == 1 and c > hi:
            sig.append((i1 + 1, 1, c - 2 * at, dict(tp_r=rr, max_hold=hold * 3600)))
        elif tr == 2 and c < lo:
            sig.append((i1 + 1, 2, c + 2 * at, dict(tp_r=rr, max_hold=hold * 3600)))
    return take(sig)


def crt_daily(tf=3600, hold=24, retest=8, bars=None, **kw):
    """The PRO24 engine on the daily candle: range = previous day, sweep of
    it, order-block break on tf, retest, trend, premium/discount."""
    base = dict(pro24_set()[0], models={"D1": None}, model_defs={"D1": (17, 1)}, candle=DAY, tf=tf,
                max_hold=hold * 3600, retest_sec=retest * 3600, max_spread=0.55, **kw)
    c = [(t, o, h, l, cl, sp + EXTRA) for (t, o, h, l, cl, sp) in (bars or m30)]
    return run(c, base)[0]


def pro24():
    c30 = [(t, o, h, l, c, sp + EXTRA) for (t, o, h, l, c, sp) in m30 if t < m15[0][0]]
    c15 = [(t, o, h, l, c, sp + EXTRA) for (t, o, h, l, c, sp) in m15]
    return ([t for c in pro24_set() for t in run(c30, dict(c, tf=1800, max_spread=0.55))[0]] +
            [t for c in pro24_set() for t in run(c15, dict(c, max_spread=0.55))[0]])


# ---------------------------------------------------------------- scoring
def stats(tr):
    tr = sorted(tr, key=lambda x: x["t_out"])
    eq = peak = dd = 0.0
    for t in tr:
        eq += t["r"]
        peak = max(peak, eq)
        dd = max(dd, peak - eq)
    rs = [t["r"] for t in tr]
    w = sum(r for r in rs if r > 0)
    lo = -sum(r for r in rs if r < 0) or 1e-9
    return len(rs), w / lo, sum(rs), dd


def cell(tr):
    n, pf, tot, dd = stats(tr)
    return f"{n:4d} PF{pf:5.2f} {tot:+6.1f}R dd{dd:5.1f} r/dd{tot / dd if dd else 0:5.1f}"


def split(tr, k):
    return [t for t in tr if P[k] <= t["t_in"] < P[k + 1]]


if __name__ == "__main__":
    base = pro24()
    cands = [("NR7 day breakout", nr7()), ("inside day breakout", inside_day()),
             ("EMA20 pullback H4", ema_pullback()), ("EMA20 pullback H1", ema_pullback(tf=3600, hold=24)),
             ("Donchian 20 H4", donchian()), ("CRT daily + H1 OB", crt_daily()),
             ("CRT daily + M30 OB", crt_daily(tf=1800))]
    print(f"{'':22}" + " | ".join(f"{n:^43}" for n in NAMES))
    print(f"{'PRO24 v1.08':22}" + " | ".join(cell(split(base, k)) for k in range(3)))
    for name, tr in cands:
        print(f"{name:22}" + " | ".join(cell(split(tr, k)) for k in range(3)))
        print(f"{'  + PRO24':22}" + " | ".join(cell(split(base + tr, k)) for k in range(3)))
