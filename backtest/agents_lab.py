#!/usr/bin/env python3
"""Classic non-clock strategies tested as extra agents next to PRO24: RSI(2)
pullback in the daily trend (H1/H4), Donchian breakout in the trend (H1/H4)
and NR7 day breakout in the trend. M30 history, chosen nowhere, split
2020.02-2023.06 / 2023.07-2026.09.  Run: python3 agents_lab.py (from backtest/)
"""
import sys
sys.path.insert(0, ".")
from collections import defaultdict
from datetime import datetime, timezone
from crt_backtest import load_mt5
from model_lab import aggregate, Exec
m30 = load_mt5(["../data/XAUUSD_M30.csv"])[0]
ex = Exec(m30, 0.05)
SPLIT = datetime(2023, 7, 1, tzinfo=timezone.utc).timestamp()
d1 = aggregate(m30, 86400)
def sma(xs, n): return sum(xs[-n:]) / n if len(xs) >= n else None
# daily trend state by day: close vs SMA50
trend = {}
closes = []
for b in d1:
    s50 = sma(closes, 50)
    trend[b[0]] = 0 if s50 is None else (1 if closes[-1] > s50 else 2)
    closes.append(b[4])
def tday(t): return trend.get(t - t % 86400, 0)
def atr(bars, i, n=14):
    rs = [bars[j][2] - bars[j][3] for j in range(max(0, i - n), i)]
    return sum(rs) / len(rs) if rs else 0
def rsi2(cl):
    if len(cl) < 3: return 50
    g = [max(0, cl[k] - cl[k - 1]) for k in range(len(cl) - 2, len(cl))]
    l = [max(0, cl[k - 1] - cl[k]) for k in range(len(cl) - 2, len(cl))]
    return 100.0 if sum(l) == 0 else 100 - 100 / (1 + sum(g) / sum(l))
def take(signals):
    trades, busy = [], 0
    for i, d, sl, kw in signals:
        if i >= len(m30) or m30[i][0] < busy: continue
        r = ex.trade(i, d, sl, **kw)
        if isinstance(r, dict): trades.append(r); busy = r["t_out"]
    return trades
def agent_rsi2(tf, lo=10, hold_bars=6, stop_atr=2.0, rr=None):
    bars = aggregate(m30, tf); sig = []; cl = []
    for i, (k, o, h, l, c, i0, i1) in enumerate(bars):
        cl.append(c)
        if i < 20: continue
        r = rsi2(cl); tr = tday(k); a = atr(bars, i)
        if tr == 1 and r < lo:
            sig.append((i1 + 1, 1, c - stop_atr * a, dict(tp_r=rr or 1.0, max_hold=hold_bars * tf)))
        elif tr == 2 and r > 100 - lo:
            sig.append((i1 + 1, 2, c + stop_atr * a, dict(tp_r=rr or 1.0, max_hold=hold_bars * tf)))
    return take(sig)
def agent_donchian(tf, n=20, stop_atr=2.0, rr=2.0, hold=48):
    bars = aggregate(m30, tf); sig = []
    for i in range(n, len(bars)):
        k, o, h, l, c, i0, i1 = bars[i]
        hi = max(b[2] for b in bars[i - n:i]); lo = min(b[3] for b in bars[i - n:i]); tr = tday(k); a = atr(bars, i)
        if tr == 1 and c > hi: sig.append((i1 + 1, 1, c - stop_atr * a, dict(tp_r=rr, max_hold=hold * 3600)))
        elif tr == 2 and c < lo: sig.append((i1 + 1, 2, c + stop_atr * a, dict(tp_r=rr, max_hold=hold * 3600)))
    return take(sig)
def agent_nr7(rr=2.0):
    sig = []
    for i in range(8, len(d1) - 1):
        rngs = [b[2] - b[3] for b in d1[i - 6:i + 1]]
        if rngs[-1] != min(rngs): continue
        k, o, h, l, c, i0, i1 = d1[i]; tr = tday(d1[i + 1][0])
        # next day: enter on a break of today's high (buy) / low (sell) in trend direction, on M30 closes
        nk, no, nh, nl, nc, n0, n1 = d1[i + 1]
        for j in range(n0, n1 + 1):
            tj, oj, hj, lj, cj, _ = m30[j]
            if tr == 1 and cj > h: sig.append((j + 1, 1, l, dict(tp_r=rr, max_hold=24 * 3600))); break
            if tr == 2 and cj < l: sig.append((j + 1, 2, h, dict(tp_r=rr, max_hold=24 * 3600))); break
    return take(sig)
def st(tr):
    if not tr: return "n=0"
    eq = peak = dd = 0
    for t in sorted(tr, key=lambda x: x["t_out"]):
        eq += t["r"]; peak = max(peak, eq); dd = max(dd, peak - eq)
    rs = [t["r"] for t in tr]; w = sum(r for r in rs if r > 0); l = -sum(r for r in rs if r < 0) or 1
    return f"n={len(rs):4d} avg={sum(rs)/len(rs):+.3f} PF={w/l:.2f} tot={sum(rs):+6.1f} DD={dd:5.1f}"
def show(name, tr):
    print(f"{name:<36} | 2020.02-2023.06 {st([t for t in tr if t['t_in'] < SPLIT])} | 2023.07-2026.09 {st([t for t in tr if t['t_in'] >= SPLIT])}")
for tf, lab in ((3600, "H1"), (14400, "H4")):
    for lo in (5, 10):
        show(f"RSI2 pullback {lab} <{lo}, TP 1R", agent_rsi2(tf, lo))
        show(f"RSI2 pullback {lab} <{lo}, TP 2R", agent_rsi2(tf, lo, rr=2.0))
for tf, lab in ((3600, "H1"), (14400, "H4")):
    for n in (20, 55):
        show(f"Donchian {lab} {n}-bar breakout", agent_donchian(tf, n))
show("NR7 day breakout (trend)", agent_nr7())
