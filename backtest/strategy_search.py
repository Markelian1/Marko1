#!/usr/bin/env python3
"""Broad strategy search on the XAUUSD history (FP Trading M30, 2020.03-2026.09).

About 30 strategy families from the classic trading literature, each on
several timeframes with a small parameter grid:
  trend      MA cross, Donchian, Bollinger / Keltner breakout, Supertrend,
             MACD, ADX/DI, Parabolic SAR, Ichimoku, Heikin-Ashi, TSMOM
  reversion  RSI(2), Bollinger fade, z-score, Stochastic, CCI, N down bars,
             big-bar fade, pivot S1/R1 bounce, buy-the-dip
  breakout   NR4/NR7, inside bar, volatility squeeze, previous day / week high
  price act. engulfing, pin bar, outside bar, fair value gap retest, swing
             failure (liquidity sweep), Fibonacci 61.8% pullback
  control    entries in the trend direction at a fixed rhythm (no signal):
             what the gold uptrend alone gives with the same exits

Execution: signal at the close of a timeframe bar, entry at the next M30
open (or a limit fill), spread of the bar + 0.05, SL first when one M30 bar
touches both, no entry Friday after 12:00 NY, everything closed Friday
16:00 NY, one position at a time per strategy.

Selection: a configuration passes when it has >= 40 trades and PF >= 1.15 in
BOTH 2020.03-2023.06 (in-sample) and 2023.07-2026.09 (out-of-sample).
Hundreds of configurations are tried, so some pass by luck: a family only
counts when several of its neighbours pass too and it beats the control.

  python3 strategy_search.py            (from backtest/, ~5 minutes)
  python3 strategy_search.py --csv out.csv
"""
import argparse
import csv
import os
import sys
from datetime import datetime, timezone
from multiprocessing import Pool

sys.path.insert(0, ".")
from crt_backtest import load_mt5
from model_lab import aggregate

DAY, NY = 86400, 7 * 3600
EXTRA = 0.05
# Execution bars: M30 by default; BASE=M15 or BASE=M5 checks the same signals on finer prices
BASE = os.environ.get("BASE", "M30")
BASE_SEC = {"M30": 1800, "M15": 900, "M5": 300}[BASE]
M30 = load_mt5([f"../data/XAUUSD_{BASE}.csv"])[0]       # the execution bars (name kept for brevity)
N = len(M30)


def ts(y, m, d):
    return datetime(y, m, d, tzinfo=timezone.utc).timestamp()


START, SPLIT, END = ts(2020, 4, 1), ts(2023, 7, 1), ts(2026, 9, 27)
TFS = {"M30": 1800, "H1": 3600, "H4": 14400, "D1": DAY}
if BASE != "M30":
    TFS = {"M15": 900, **TFS} if BASE == "M15" else {"M5": 300, "M15": 900, **TFS}
HOLD = {"M5": 4 * 3600, "M15": 8 * 3600, "M30": 12 * 3600, "H1": 24 * 3600, "H4": 72 * 3600, "D1": 10 * DAY}

# ---------------------------------------------------------------- indicators
def sma(x, n):
    out, s = [None] * len(x), 0.0
    for i, v in enumerate(x):
        s += v
        if i >= n:
            s -= x[i - n]
        if i >= n - 1:
            out[i] = s / n
    return out


def ema(x, n):
    a, e, out = 2.0 / (n + 1), None, [None] * len(x)
    for i, v in enumerate(x):
        e = v if e is None else e + a * (v - e)
        if i >= n - 1:
            out[i] = e
    return out


def rma(x, n):
    out, e = [None] * len(x), None
    for i, v in enumerate(x):
        if i < n - 1:
            continue
        e = sum(x[i - n + 1:i + 1]) / n if e is None else e + (v - e) / n
        out[i] = e
    return out


def stdev(x, n):
    m = sma(x, n)
    out = [None] * len(x)
    for i in range(n - 1, len(x)):
        out[i] = (sum((v - m[i]) ** 2 for v in x[i - n + 1:i + 1]) / n) ** 0.5
    return out


def indicators(b):
    o = [x[1] for x in b]; h = [x[2] for x in b]; l = [x[3] for x in b]; c = [x[4] for x in b]
    n = len(b)
    tr = [h[0] - l[0]] + [max(h[i] - l[i], abs(h[i] - c[i - 1]), abs(l[i] - c[i - 1])) for i in range(1, n)]
    I = dict(o=o, h=h, l=l, c=c, atr=rma(tr, 14))
    for k in (9, 20, 50, 200):
        I[f"ema{k}"] = ema(c, k)
    for k in (5, 20):
        I[f"sma{k}"] = sma(c, k)
    # RSI
    for p in (2, 14):
        g = [0.0] + [max(0.0, c[i] - c[i - 1]) for i in range(1, n)]
        d = [0.0] + [max(0.0, c[i - 1] - c[i]) for i in range(1, n)]
        ag, ad = rma(g, p), rma(d, p)
        I[f"rsi{p}"] = [None if ag[i] is None else (100.0 if ad[i] == 0 else 100 - 100 / (1 + ag[i] / ad[i])) for i in range(n)]
    sd = stdev(c, 20)
    I["sd20"] = sd
    I["bbu"] = [None if sd[i] is None else I["sma20"][i] + 2 * sd[i] for i in range(n)]
    I["bbl"] = [None if sd[i] is None else I["sma20"][i] - 2 * sd[i] for i in range(n)]
    I["bbw"] = [None if sd[i] is None or not I["sma20"][i] else 4 * sd[i] / I["sma20"][i] for i in range(n)]
    I["ku"] = [None if I["atr"][i] is None or I["ema20"][i] is None else I["ema20"][i] + 2 * I["atr"][i] for i in range(n)]
    I["kl"] = [None if I["atr"][i] is None or I["ema20"][i] is None else I["ema20"][i] - 2 * I["atr"][i] for i in range(n)]
    # Stochastic 14,3
    k = [None] * n
    for i in range(13, n):
        hh, ll = max(h[i - 13:i + 1]), min(l[i - 13:i + 1])
        k[i] = 50.0 if hh == ll else 100 * (c[i] - ll) / (hh - ll)
    I["stk"] = k
    I["std"] = [None if i < 15 else sum(k[i - 2:i + 1]) / 3 for i in range(n)]
    # CCI 20
    tp = [(h[i] + l[i] + c[i]) / 3 for i in range(n)]
    tps = sma(tp, 20)
    cci = [None] * n
    for i in range(19, n):
        md = sum(abs(v - tps[i]) for v in tp[i - 19:i + 1]) / 20
        cci[i] = 0.0 if md == 0 else (tp[i] - tps[i]) / (0.015 * md)
    I["cci"] = cci
    # ADX 14
    pdm = [0.0] + [max(h[i] - h[i - 1], 0) if h[i] - h[i - 1] > l[i - 1] - l[i] else 0.0 for i in range(1, n)]
    mdm = [0.0] + [max(l[i - 1] - l[i], 0) if l[i - 1] - l[i] > h[i] - h[i - 1] else 0.0 for i in range(1, n)]
    atr_, pd_, md_ = rma(tr, 14), rma(pdm, 14), rma(mdm, 14)
    pdi = [None if atr_[i] in (None, 0) else 100 * pd_[i] / atr_[i] for i in range(n)]
    mdi = [None if atr_[i] in (None, 0) else 100 * md_[i] / atr_[i] for i in range(n)]
    dx = [0.0 if pdi[i] is None or pdi[i] + mdi[i] == 0 else 100 * abs(pdi[i] - mdi[i]) / (pdi[i] + mdi[i]) for i in range(n)]
    I["pdi"], I["mdi"], I["adx"] = pdi, mdi, rma(dx, 14)
    # MACD 12/26/9
    e12, e26 = ema(c, 12), ema(c, 26)
    mac = [None if e26[i] is None else e12[i] - e26[i] for i in range(n)]
    first = next(i for i in range(n) if mac[i] is not None)
    sig = [None] * first + ema(mac[first:], 9)
    I["macd"], I["macds"] = mac, sig
    # Supertrend 10/3
    a10 = rma(tr, 10)
    st = [0] * n
    up = dn = None
    for i in range(n):
        if a10[i] is None:
            continue
        m = (h[i] + l[i]) / 2
        bu, bd = m + 3 * a10[i], m - 3 * a10[i]
        up = bu if up is None or bu < up or c[i - 1] > up else up
        dn = bd if dn is None or bd > dn or c[i - 1] < dn else dn
        prev = st[i - 1] or 1
        st[i] = 1 if c[i] > up else 2 if c[i] < dn else prev
    I["st"] = st
    # Parabolic SAR 0.02/0.2
    ps = [0] * n
    d, af, ep, sar = 1, 0.02, h[0], l[0]
    for i in range(1, n):
        sar = sar + af * (ep - sar)
        if d == 1:
            sar = min(sar, l[i - 1], l[i - 2] if i > 1 else l[i - 1])
            if l[i] < sar:
                d, sar, ep, af = 2, ep, l[i], 0.02
            elif h[i] > ep:
                ep, af = h[i], min(0.2, af + 0.02)
        else:
            sar = max(sar, h[i - 1], h[i - 2] if i > 1 else h[i - 1])
            if h[i] > sar:
                d, sar, ep, af = 1, ep, h[i], 0.02
            elif l[i] < ep:
                ep, af = l[i], min(0.2, af + 0.02)
        ps[i] = d
    I["psar"] = ps
    # Heikin-Ashi colour
    hao, hac, ha = o[0], c[0], [0] * n
    for i in range(n):
        hac_n = (o[i] + h[i] + l[i] + c[i]) / 4
        hao = (hao + hac) / 2 if i else o[0]
        hac = hac_n
        ha[i] = 1 if hac > hao else 2
    I["ha"] = ha
    # Ichimoku 9/26/52 (cloud of 26 bars ago)
    def mid(i, p):
        return (max(h[i - p + 1:i + 1]) + min(l[i - p + 1:i + 1])) / 2 if i >= p - 1 else None
    ten = [mid(i, 9) for i in range(n)]
    kij = [mid(i, 26) for i in range(n)]
    sa = [None if ten[i] is None or kij[i] is None else (ten[i] + kij[i]) / 2 for i in range(n)]
    sb = [mid(i, 52) for i in range(n)]
    I["ten"], I["kij"] = ten, kij
    I["cloud_hi"] = [None if i < 26 or sa[i - 26] is None or sb[i - 26] is None else max(sa[i - 26], sb[i - 26]) for i in range(n)]
    I["cloud_lo"] = [None if i < 26 or sa[i - 26] is None or sb[i - 26] is None else min(sa[i - 26], sb[i - 26]) for i in range(n)]
    # Donchian of the previous n bars
    for p in (20, 55):
        I[f"dhi{p}"] = [None if i < p else max(h[i - p:i]) for i in range(n)]
        I[f"dlo{p}"] = [None if i < p else min(l[i - p:i]) for i in range(n)]
    return I


B = {tf: aggregate(M30, sec) for tf, sec in TFS.items()}
IND = {tf: indicators(b) for tf, b in B.items()}

# Daily trend by server day: previous close vs its 50-day average (no look-ahead)
TREND, _closes = {}, []
for b in B["D1"]:
    TREND[b[0]] = 0 if len(_closes) < 50 else (1 if _closes[-1] > sum(_closes[-50:]) / 50 else 2)
    _closes.append(b[4])


def trend_at(i):
    t = M30[min(i, N - 1)][0]
    return TREND.get(t - t % DAY, 0)


# Previous server day high / low / close and previous week high / low, by M30 index
PDH, PDL, PDC, PWH, PWL = [None] * N, [None] * N, [None] * N, [None] * N, [None] * N
_dix = {b[0]: k for k, b in enumerate(B["D1"])}
for k, b in enumerate(B["D1"]):
    if k == 0:
        continue
    pb = B["D1"][k - 1]
    wk = [x for x in B["D1"][max(0, k - 7):k] if (b[0] - x[0]) <= 7 * DAY]
    for i in range(b[5], b[6] + 1):
        PDH[i], PDL[i], PDC[i] = pb[2], pb[3], pb[4]
        PWH[i], PWL[i] = max(x[2] for x in wk), min(x[3] for x in wk)


# ---------------------------------------------------------------- execution
def execute(i, d, sl, tp=None, rr=None, hold=8 * 3600, exit_arr=None, price=None):
    """Enter at the open of M30 bar i (or a limit fill at price inside it)."""
    if i >= N:
        return None
    t, o, h, l, c, sp = M30[i]
    sp += EXTRA
    ny = t - NY
    if sp > 0.55 or ((ny // DAY + 3) % 7 == 4 and ny % DAY >= 12 * 3600):
        return None
    entry = (o + sp if d == 1 else o) if price is None else price
    risk = entry - sl if d == 1 else sl - entry
    if risk <= 0 or risk < max(1.0, 4 * sp):
        return None
    if rr is not None:
        tp = entry + rr * risk if d == 1 else entry - rr * risk
    if tp is not None and ((d == 1 and tp <= entry) or (d == 2 and tp >= entry)):
        return None

    def out(px, tj, j, why):
        r = (px - entry) / risk if d == 1 else (entry - px) / risk
        return dict(t_in=t, t_out=tj, j_out=j, dir=d, r=r, why=why, risk=risk)

    for j in range(i, N):
        tj, oj, hj, lj, cj, spj = M30[j]
        spj += EXTRA
        nyj = tj - NY
        if j > i and (tj - t >= hold or ((nyj // DAY + 3) % 7 == 4 and nyj % DAY >= 16 * 3600) or tj - M30[j - 1][0] > 2 * DAY):
            return out(oj if d == 1 else oj + spj, tj, j, "time")
        fill_bar = j == i and price is not None
        if d == 1:
            if lj <= sl:
                return out(min(sl, oj) if j > i else sl, tj, j, "SL")
            if tp is not None and hj >= tp and not fill_bar:
                return out(tp, tj, j, "TP")
        else:
            if hj + spj >= sl:
                return out(max(sl, oj + spj) if j > i else sl, tj, j, "SL")
            if tp is not None and lj + spj <= tp and not fill_bar:
                return out(tp, tj, j, "TP")
        if exit_arr is not None and exit_arr[j] and j + 1 < N:
            nb = M30[j + 1]
            return out(nb[1] if d == 1 else nb[1] + nb[5] + EXTRA, nb[0], j + 1, "signal")
    return None


def take(signals):
    trades, busy = [], -1
    for s in sorted(signals, key=lambda s: s[0]):
        i, d, sl, kw = s
        if i <= busy:
            continue
        r = execute(i, d, sl, **kw)
        if r:
            trades.append(r)
            busy = r["j_out"]
    return trades


def ent(tf, k):
    return B[tf][k][6] + 1


def exit_mask(tf, cond_long, cond_short):
    """M30-indexed exit flags from a condition on closed timeframe bars."""
    el, es = [False] * N, [False] * N
    for k, b in enumerate(B[tf]):
        if cond_long(k):
            el[b[6]] = True
        if cond_short(k):
            es[b[6]] = True
    return {1: el, 2: es}


def atr_exit(tf, k, d, ex, ref=None):
    """SL sl_atr x ATR from the close (or ref), TP rr x risk."""
    a = IND[tf]["atr"][k]
    c = IND[tf]["c"][k] if ref is None else ref
    sl_atr, rr = ex
    return (c - sl_atr * a if d == 1 else c + sl_atr * a), dict(rr=rr, hold=HOLD[tf])


def filt_ok(i, d, filt):
    return not filt or trend_at(i) == d


# ---------------------------------------------------------------- families
EX = [(1.5, 2.0), (2.0, 3.0), (1.0, 2.0)]     # (SL in ATR, TP in R)


def trend_family(cond):
    """cond(I, k) -> 1 buy / 2 sell / 0 at the close of bar k."""
    def gen(tf, filt, ex):
        I, sig = IND[tf], []
        for k in range(210, len(B[tf])):
            d = cond(I, k)
            if not d or I["atr"][k] is None:
                continue
            i = ent(tf, k)
            if i >= N or not filt_ok(i, d, filt):
                continue
            sl, kw = atr_exit(tf, k, d, ex)
            sig.append((i, d, sl, kw))
        return sig
    return gen


def cross(a, b, k):
    return a[k - 1] is not None and b[k - 1] is not None and a[k] is not None and b[k] is not None and \
        (1 if a[k - 1] <= b[k - 1] and a[k] > b[k] else 2 if a[k - 1] >= b[k - 1] and a[k] < b[k] else 0)


def ma_cross(f, s):
    return trend_family(lambda I, k: cross(I[f"ema{f}"], I[f"ema{s}"], k))


def channel_break(up, lo):
    def cond(I, k):
        if I[up][k] is None or I[up][k - 1] is None:
            return 0
        if I["c"][k] > I[up][k] and I["c"][k - 1] <= I[up][k - 1]:
            return 1
        if I["c"][k] < I[lo][k] and I["c"][k - 1] >= I[lo][k - 1]:
            return 2
        return 0
    return trend_family(cond)


def flip(key):
    return trend_family(lambda I, k: I[key][k] if I[key][k] and I[key][k - 1] and I[key][k] != I[key][k - 1] else 0)


def ha_flip(I, k):
    a, b, c = I["ha"][k - 2], I["ha"][k - 1], I["ha"][k]
    return c if a == b and c != b else 0


def adx_di(I, k):
    if I["adx"][k] is None or I["adx"][k] < 20:
        return 0
    return cross(I["pdi"], I["mdi"], k) or 0


def ichimoku(I, k):
    x = cross(I["ten"], I["kij"], k)
    if not x or I["cloud_hi"][k] is None:
        return 0
    if x == 1 and I["c"][k] > I["cloud_hi"][k]:
        return 1
    if x == 2 and I["c"][k] < I["cloud_lo"][k]:
        return 2
    return 0


def tsmom(n):
    def gen(tf, filt, ex):
        I, sig = IND["D1"], []
        for k in range(n, len(B["D1"])):
            d = 1 if I["c"][k] > I["c"][k - n] else 2
            i = ent("D1", k)
            if i >= N or I["atr"][k] is None:
                continue
            a = I["atr"][k]
            sig.append((i, d, I["c"][k] - ex[0] * a if d == 1 else I["c"][k] + ex[0] * a, dict(hold=DAY - 1800)))
        return sig
    return gen


def mean_rev(entry_cond, exit_long, exit_short):
    """Buy weakness in an uptrend / sell strength in a downtrend. ex = ('sig', cat_atr):
    exit on the signal, catastrophe SL; ex = (sl_atr, rr): fixed exits."""
    masks = {}

    def gen(tf, filt, ex):
        I, sig = IND[tf], []
        if ex[0] == "sig" and tf not in masks:
            masks[tf] = exit_mask(tf, lambda k: exit_long(I, k), lambda k: exit_short(I, k))
        for k in range(210, len(B[tf])):
            d = entry_cond(I, k)
            if not d or I["atr"][k] is None:
                continue
            i = ent(tf, k)
            if i >= N or not filt_ok(i, d, filt):
                continue
            a, c = I["atr"][k], I["c"][k]
            if ex[0] == "sig":
                sl = c - ex[1] * a if d == 1 else c + ex[1] * a
                sig.append((i, d, sl, dict(hold=HOLD[tf], exit_arr=masks[tf][d])))
            else:
                sl, kw = atr_exit(tf, k, d, ex)
                sig.append((i, d, sl, kw))
        return sig
    return gen


EXMR = [("sig", 2.0), ("sig", 3.0), (1.5, 1.0), (1.5, 2.0)]


def rsi2(lo):
    return mean_rev(lambda I, k: 0 if I["rsi2"][k] is None else 1 if I["rsi2"][k] < lo else 2 if I["rsi2"][k] > 100 - lo else 0,
                    lambda I, k: I["sma5"][k] is not None and I["c"][k] > I["sma5"][k],
                    lambda I, k: I["sma5"][k] is not None and I["c"][k] < I["sma5"][k])


def zscore(z):
    return mean_rev(lambda I, k: 0 if not I["sd20"][k] else 1 if (I["c"][k] - I["sma20"][k]) / I["sd20"][k] < -z
                    else 2 if (I["c"][k] - I["sma20"][k]) / I["sd20"][k] > z else 0,
                    lambda I, k: I["sma20"][k] is not None and I["c"][k] > I["sma20"][k],
                    lambda I, k: I["sma20"][k] is not None and I["c"][k] < I["sma20"][k])


def stoch_x(I, k):
    x = cross(I["stk"], I["std"], k)
    if x == 1 and I["stk"][k] < 25:
        return 1
    if x == 2 and I["stk"][k] > 75:
        return 2
    return 0


def cci_x(I, k):
    a, b = I["cci"][k - 1], I["cci"][k]
    if a is None or b is None:
        return 0
    return 1 if a < -100 <= b else 2 if a > 100 >= b else 0


def n_bars(n):
    def cond(I, k):
        c = I["c"]
        if all(c[k - j] < c[k - j - 1] for j in range(n)):
            return 1
        if all(c[k - j] > c[k - j - 1] for j in range(n)):
            return 2
        return 0
    return cond


def big_bar(fade, mult=2.5):
    def cond(I, k):
        a = I["atr"][k - 1]
        if a is None or I["h"][k] - I["l"][k] < mult * a:
            return 0
        d = 2 if I["c"][k] > I["o"][k] else 1          # fade: against the bar
        return d if fade else 3 - d
    return cond


BB_FADE_EXITS = [(None, None)]


def bb_fade(tf, filt, ex):
    I, sig = IND[tf], []
    for k in range(210, len(B[tf])):
        if I["bbl"][k] is None or I["bbl"][k - 1] is None:
            continue
        d = 1 if I["c"][k - 1] < I["bbl"][k - 1] and I["c"][k] > I["bbl"][k] else \
            2 if I["c"][k - 1] > I["bbu"][k - 1] and I["c"][k] < I["bbu"][k] else 0
        i = ent(tf, k)
        if not d or i >= N or not filt_ok(i, d, filt):
            continue
        a = I["atr"][k]
        if d == 1:
            sl = min(I["l"][k - 2:k + 1]) - ex[0] * a
        else:
            sl = max(I["h"][k - 2:k + 1]) + ex[0] * a
        kw = dict(tp=I["sma20"][k], hold=HOLD[tf]) if ex[1] == "mid" else dict(rr=ex[1], hold=HOLD[tf])
        sig.append((i, d, sl, kw))
    return sig


def pivot_bounce(tf, filt, ex):
    I, sig = IND[tf], []
    for k in range(210, len(B[tf])):
        i0 = B[tf][k][5]
        if PDH[i0] is None:
            continue
        p = (PDH[i0] + PDL[i0] + PDC[i0]) / 3
        s1, r1 = 2 * p - PDH[i0], 2 * p - PDL[i0]
        d = 1 if I["l"][k] <= s1 < I["c"][k] else 2 if I["h"][k] >= r1 > I["c"][k] else 0
        i = ent(tf, k)
        if not d or i >= N or not filt_ok(i, d, filt) or I["atr"][k] is None:
            continue
        a = I["atr"][k]
        sl = I["l"][k] - ex[0] * a if d == 1 else I["h"][k] + ex[0] * a
        kw = dict(tp=p, hold=HOLD[tf]) if ex[1] == "pivot" else dict(rr=ex[1], hold=HOLD[tf])
        sig.append((i, d, sl, kw))
    return sig


def bar_break(kind):
    """kind 'nr4', 'nr7', 'inside': the next bar closes beyond the pattern bar."""
    def gen(tf, filt, ex):
        I, sig = IND[tf], []
        h, l, c = I["h"], I["l"], I["c"]
        for k in range(210, len(B[tf]) - 1):
            if kind == "inside":
                ok = h[k] < h[k - 1] and l[k] > l[k - 1]
            else:
                n = 4 if kind == "nr4" else 7
                ok = h[k] - l[k] == min(h[j] - l[j] for j in range(k - n + 1, k + 1))
            if not ok:
                continue
            q = k + 1
            d = 1 if c[q] > h[k] else 2 if c[q] < l[k] else 0
            i = ent(tf, q)
            if not d or i >= N or not filt_ok(i, d, filt):
                continue
            sl = l[k] - ex[0] * I["atr"][k] if d == 1 else h[k] + ex[0] * I["atr"][k]
            sig.append((i, d, sl, dict(rr=ex[1], hold=HOLD[tf])))
        return sig
    return gen


def squeeze(tf, filt, ex):
    I, sig = IND[tf], []
    w = I["bbw"]
    armed = -99
    for k in range(260, len(B[tf])):
        if w[k] is not None and all(w[j] is not None for j in range(k - 49, k)) and w[k] <= min(w[k - 49:k]):
            armed = k
        if k - armed > 5 or I["bbu"][k] is None:
            continue
        d = 1 if I["c"][k] > I["bbu"][k] else 2 if I["c"][k] < I["bbl"][k] else 0
        i = ent(tf, k)
        if not d or i >= N or not filt_ok(i, d, filt):
            continue
        sl, kw = atr_exit(tf, k, d, ex)
        sig.append((i, d, sl, kw))
        armed = -99
    return sig


def level_break(which):
    def gen(tf, filt, ex):
        I, sig = IND[tf], []
        hi_, lo_ = (PDH, PDL) if which == "day" else (PWH, PWL)
        for k in range(210, len(B[tf])):
            i1 = B[tf][k][6]
            if hi_[i1] is None or I["atr"][k] is None:
                continue
            c, pc = I["c"][k], I["c"][k - 1]
            d = 1 if c > hi_[i1] >= pc else 2 if c < lo_[i1] <= pc else 0
            i = ent(tf, k)
            if not d or i >= N or not filt_ok(i, d, filt):
                continue
            sl, kw = atr_exit(tf, k, d, ex)
            sig.append((i, d, sl, kw))
        return sig
    return gen


def candle(kind):
    def cond(I, k):
        o, h, l, c, e = I["o"], I["h"], I["l"], I["c"], I["ema20"]
        if e[k] is None:
            return 0
        rng = h[k] - l[k]
        if rng <= 0:
            return 0
        if kind == "engulf":
            if c[k - 1] < o[k - 1] and c[k] > o[k] and o[k] <= c[k - 1] and c[k] >= o[k - 1] and l[k] < e[k]:
                return 1
            if c[k - 1] > o[k - 1] and c[k] < o[k] and o[k] >= c[k - 1] and c[k] <= o[k - 1] and h[k] > e[k]:
                return 2
        elif kind == "pin":
            if min(o[k], c[k]) - l[k] >= 0.66 * rng and c[k] > l[k] + 0.66 * rng and l[k] < e[k]:
                return 1
            if h[k] - max(o[k], c[k]) >= 0.66 * rng and c[k] < h[k] - 0.66 * rng and h[k] > e[k]:
                return 2
        elif kind == "outside":
            if h[k] > h[k - 1] and l[k] < l[k - 1]:
                return 1 if c[k] > h[k - 1] else 2 if c[k] < l[k - 1] else 0
        return 0
    return cond


def candle_family(kind):
    cond = candle(kind)

    def gen(tf, filt, ex):
        I, sig = IND[tf], []
        for k in range(210, len(B[tf])):
            d = cond(I, k)
            i = ent(tf, k)
            if not d or i >= N or not filt_ok(i, d, filt) or I["atr"][k] is None:
                continue
            a = I["atr"][k]
            sl = I["l"][k] - ex[0] * a if d == 1 else I["h"][k] + ex[0] * a   # beyond the pattern bar
            sig.append((i, d, sl, dict(rr=ex[1], hold=HOLD[tf])))
        return sig
    return gen


EXPA = [(0.2, 1.5), (0.2, 2.0), (0.5, 2.0), (0.5, 3.0)]


def limit_fill(i_from, i_to, d, level, cancel):
    """First M30 bar in [i_from, i_to) that trades at the level (ask for buys),
    unless price crosses the cancel level first. Returns (index, fill price)."""
    for j in range(i_from, min(i_to, N)):
        t, o, h, l, c, sp = M30[j]
        sp += EXTRA
        # the fill comes first: a bar that reaches the cancel level passed the limit on its way
        # (execute() then takes the stop on that same bar)
        if d == 1 and l + sp <= level:
            return (j, min(o + sp, level)) if o + sp > cancel else None
        if d == 2 and h >= level:
            return (j, max(o, level)) if o < cancel else None
    return None


FVG_WAIT, FVG_MIN = 10, 0.3    # bars the limit waits, min gap size in ATR


def fvg(tf, filt, ex):
    """Fair value gap (3-bar imbalance) in the trend direction, limit at the gap edge."""
    I, sig = IND[tf], []
    h, l = I["h"], I["l"]
    sec = TFS[tf]
    for k in range(210, len(B[tf])):
        a = I["atr"][k]
        if a is None:
            continue
        if l[k] > h[k - 2] and l[k] - h[k - 2] > FVG_MIN * a:
            d, level, bottom = 1, l[k], h[k - 2]
        elif h[k] < l[k - 2] and l[k - 2] - h[k] > FVG_MIN * a:
            d, level, bottom = 2, h[k], l[k - 2]
        else:
            continue
        i = ent(tf, k)
        if i >= N or not filt_ok(i, d, filt):
            continue
        sl = bottom - ex[0] * a if d == 1 else bottom + ex[0] * a
        f = limit_fill(i, i + FVG_WAIT * sec // BASE_SEC, d, level, sl)
        if f:
            sig.append((f[0], d, sl, dict(rr=ex[1], hold=HOLD[tf], price=f[1])))
    return sig


def pivots(I, L=3):
    """Swing highs / lows: (bar index, price, index at which it is known)."""
    h, l = I["h"], I["l"]
    hi, lo = [], []
    for k in range(L, len(h) - L):
        if h[k] > max(h[k - L:k]) and h[k] >= max(h[k + 1:k + L + 1]):
            hi.append((k, h[k], k + L))
        if l[k] < min(l[k - L:k]) and l[k] <= min(l[k + 1:k + L + 1]):
            lo.append((k, l[k], k + L))
    return hi, lo


def sfp(tf, filt, ex):
    """Swing failure: a bar trades through a known swing high and closes back under it."""
    I, sig = IND[tf], []
    hi, lo = pivots(I)
    lv = [(p[2], 2, p[1], p[0]) for p in hi] + [(p[2], 1, p[1], p[0]) for p in lo]
    lv.sort()
    live, q = [], 0
    for k in range(210, len(B[tf])):
        while q < len(lv) and lv[q][0] <= k:
            live.append(lv[q][1:])
            q += 1
        live = [x for x in live if k - x[2] <= 60]
        a = I["atr"][k]
        if a is None:
            continue
        for x in list(live):
            d, p = x[0], x[1]
            if (d == 2 and I["h"][k] > p > I["c"][k]) or (d == 1 and I["l"][k] < p < I["c"][k]):
                live.remove(x)
                i = ent(tf, k)
                if i < N and filt_ok(i, d, filt):
                    sl = I["h"][k] + ex[0] * a if d == 2 else I["l"][k] - ex[0] * a
                    sig.append((i, d, sl, dict(rr=ex[1], hold=HOLD[tf])))
                break
            if (d == 2 and I["c"][k] > p) or (d == 1 and I["c"][k] < p):
                live.remove(x)                       # taken and accepted: not a failure
    return sig


def fib_pullback(tf, filt, ex):
    """Uptrend leg swing low -> swing high: buy limit at the 61.8% retracement."""
    I, sig = IND[tf], []
    hi, lo = pivots(I)
    sec = TFS[tf]
    for (kh, ph, known) in hi:
        prev_lo = [x for x in lo if x[0] < kh]
        if not prev_lo or known >= len(B[tf]):
            continue
        kl, pl, _ = prev_lo[-1]
        if ph - pl < 1.5 * (I["atr"][kh] or 1e9):
            continue
        level = ph - 0.618 * (ph - pl)
        i = ent(tf, known)
        if i >= N or not filt_ok(i, 1, filt):
            continue
        sl = pl - ex[0] * I["atr"][kh]
        f = limit_fill(i, i + 20 * sec // BASE_SEC, 1, level, sl)
        if f:
            sig.append((f[0], 1, sl, dict(tp=ph if ex[1] == "high" else None, rr=None if ex[1] == "high" else ex[1],
                                           hold=HOLD[tf], price=f[1])))
    for (kl, pl, known) in lo:
        prev_hi = [x for x in hi if x[0] < kl]
        if not prev_hi or known >= len(B[tf]):
            continue
        kh, ph, _ = prev_hi[-1]
        if ph - pl < 1.5 * (I["atr"][kl] or 1e9):
            continue
        level = pl + 0.618 * (ph - pl)
        i = ent(tf, known)
        if i >= N or not filt_ok(i, 2, filt):
            continue
        sl = ph + ex[0] * I["atr"][kl]
        f = limit_fill(i, i + 20 * sec // BASE_SEC, 2, level, sl)
        if f:
            sig.append((f[0], 2, sl, dict(tp=pl if ex[1] == "high" else None, rr=None if ex[1] == "high" else ex[1],
                                           hold=HOLD[tf], price=f[1])))
    return sig


def dip_buy(tf, filt, ex):
    """D1: a day that moved more than 1 ATR against the trend, enter the next day with the trend."""
    I, sig = IND["D1"], []
    for k in range(60, len(B["D1"])):
        a = I["atr"][k - 1]
        if a is None:
            continue
        move = I["c"][k] - I["c"][k - 1]
        d = 1 if move < -a else 2 if move > a else 0
        i = ent("D1", k)
        if not d or i >= N or not filt_ok(i, d, True):
            continue
        sl = I["c"][k] - ex[0] * a if d == 1 else I["c"][k] + ex[0] * a
        sig.append((i, d, sl, dict(rr=ex[1], hold=ex[2] * DAY)))
    return sig


def control(every):
    """No signal: an entry in the trend direction every `every` bars, same exits."""
    def gen(tf, filt, ex):
        I, sig = IND[tf], []
        for k in range(210, len(B[tf]), every):
            i = ent(tf, k)
            if i >= N or I["atr"][k] is None:
                continue
            d = trend_at(i)
            if not d:
                continue
            sl, kw = atr_exit(tf, k, d, ex)
            sig.append((i, d, sl, kw))
        return sig
    return gen


# ---------------------------------------------------------------- the grid
def grid():
    G = []
    T3 = ("M30", "H1", "H4")
    T4 = ("M30", "H1", "H4", "D1")

    def add(fam, name, gen, tfs, filts, exits):
        for tf in tfs:
            for f in filts:
                for ex in exits:
                    G.append((fam, f"{name} {tf}{' trend' if f else ''} ex{ex}", gen, tf, f, ex))
    for f, s in ((9, 20), (20, 50), (50, 200)):
        add("MA cross", f"EMA{f}/{s}", ma_cross(f, s), T4, (True, False), EX)
    add("Donchian", "Donchian20", channel_break("dhi20", "dlo20"), T4, (True, False), EX)
    add("Donchian", "Donchian55", channel_break("dhi55", "dlo55"), T4, (True, False), EX)
    add("Bollinger breakout", "BB20 break", channel_break("bbu", "bbl"), T4, (True, False), EX)
    add("Keltner breakout", "Keltner break", channel_break("ku", "kl"), T4, (True, False), EX)
    add("Supertrend", "Supertrend flip", flip("st"), T4, (True, False), EX)
    add("MACD", "MACD cross", trend_family(lambda I, k: cross(I["macd"], I["macds"], k) or 0), T4, (True,), EX)
    add("ADX/DI", "ADX DI cross", trend_family(adx_di), T4, (True, False), EX)
    add("Parabolic SAR", "PSAR flip", flip("psar"), T4, (True,), EX)
    add("Ichimoku", "Ichimoku TK", trend_family(ichimoku), T4, (True, False), EX)
    add("Heikin-Ashi", "HA flip", trend_family(ha_flip), T3, (True,), EX)
    for n in (20, 60, 120):
        add("TSMOM", f"TSMOM {n}d", tsmom(n), ("D1",), (False,), [(2.0,), (3.0,)])
    for lo in (5, 10, 20):
        add("RSI(2)", f"RSI2<{lo}", rsi2(lo), T4, (True,), EXMR)
    for z in (2.0, 2.5):
        add("Z-score", f"z>{z}", zscore(z), T4, (True,), EXMR)
    add("Stochastic", "Stoch cross", mean_rev(stoch_x, lambda I, k: I["stk"][k] is not None and I["stk"][k] > 80,
                                              lambda I, k: I["stk"][k] is not None and I["stk"][k] < 20), T4, (True,), EXMR)
    add("CCI", "CCI -100 cross", mean_rev(cci_x, lambda I, k: I["cci"][k] is not None and I["cci"][k] > 100,
                                          lambda I, k: I["cci"][k] is not None and I["cci"][k] < -100), T4, (True,), EXMR)
    for n in (3, 4):
        add("N bars", f"{n} down bars", mean_rev(n_bars(n), lambda I, k: I["c"][k] > I["h"][k - 1],
                                                 lambda I, k: I["c"][k] < I["l"][k - 1]), T4, (True,), EXMR)
    add("Big bar", "big bar fade", mean_rev(big_bar(True), lambda I, k: False, lambda I, k: False), T4, (True, False), EX)
    add("Big bar", "big bar follow", trend_family(big_bar(False)), T4, (True, False), EX)
    add("Bollinger fade", "BB fade", bb_fade, T4, (True, False), [(0.3, "mid"), (0.3, 1.5), (0.3, 2.0)])
    add("Pivot S1/R1", "pivot bounce", pivot_bounce, ("M30", "H1"), (True, False), [(0.3, "pivot"), (0.3, 1.5), (0.3, 2.0)])
    add("Buy the dip", "dip D1", dip_buy, ("D1",), (True,), [(1.5, 1.5, 3), (2.0, 2.0, 5), (1.5, 1.0, 2)])
    for kind in ("nr4", "nr7", "inside"):
        add("NR / inside", f"{kind} break", bar_break(kind), T4, (True, False), [(0.0, 1.5), (0.0, 2.0), (0.3, 3.0)])
    add("Squeeze", "BB squeeze break", squeeze, T4, (True, False), EX)
    add("Level break", "prev day high/low", level_break("day"), ("M30", "H1", "H4"), (True, False), EX)
    add("Level break", "prev week high/low", level_break("week"), ("H1", "H4", "D1"), (True, False), EX)
    for kind in ("engulf", "pin", "outside"):
        add("Candles", kind, candle_family(kind), T4, (True, False), EXPA)
    add("Fair value gap", "FVG retest", fvg, T4, (True, False), EXPA)
    add("Swing failure", "SFP", sfp, T4, (True, False), EXPA)
    add("Fibonacci", "fib 61.8", fib_pullback, ("H1", "H4", "D1"), (True, False), [(0.2, "high"), (0.2, 1.5), (0.5, 2.0)])
    for every in (8, 24):
        add("CONTROL (no signal)", f"trend entry every {every}", control(every), T4, (True,), EX)
    return G


def stats(tr):
    rs = [t["r"] for t in tr]
    if not rs:
        return dict(n=0, pf=0.0, avg=0.0, win=0.0, tot=0.0)
    w = sum(r for r in rs if r > 0)
    lo = -sum(r for r in rs if r < 0) or 1e-9
    return dict(n=len(rs), pf=w / lo, avg=sum(rs) / len(rs), win=100 * sum(r > 0 for r in rs) / len(rs), tot=sum(rs))


G = grid()


def run_one(idx):
    fam, name, gen, tf, filt, ex = G[idx]
    tr = [t for t in take(gen(tf, filt, ex)) if START <= t["t_in"] < END]
    a = stats([t for t in tr if t["t_in"] < SPLIT])
    b = stats([t for t in tr if t["t_in"] >= SPLIT])
    bl = stats([t for t in tr if t["t_in"] >= SPLIT and t["dir"] == 1])
    bs = stats([t for t in tr if t["t_in"] >= SPLIT and t["dir"] == 2])
    sl_rate = 100 * sum(t["why"] == "SL" for t in tr) / max(1, len(tr))
    return dict(family=fam, name=name, a=a, b=b, bl=bl, bs=bs, sl=sl_rate)


def passes(r, pf=1.15, n=40):
    return r["a"]["n"] >= n and r["b"]["n"] >= n and r["a"]["pf"] >= pf and r["b"]["pf"] >= pf


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv")
    args = ap.parse_args()
    print(f"{len(G)} configurations, {len(set(g[0] for g in G))} families", flush=True)
    with Pool(4) as p:
        res = p.map(run_one, range(len(G)), chunksize=4)
    fams = {}
    for r in res:
        fams.setdefault(r["family"], []).append(r)
    print(f"\n{'family':22} {'configs':>7} {'pass':>5}  best (min PF of the two periods)")
    def score(rs):
        ok = [min(r["a"]["pf"], r["b"]["pf"]) for r in rs if r["a"]["n"] >= 40 and r["b"]["n"] >= 40]
        return max(ok) if ok else 0.0
    for fam, rs in sorted(fams.items(), key=lambda kv: -score(kv[1])):
        ok = [r for r in rs if r["a"]["n"] >= 40 and r["b"]["n"] >= 40]
        best = max(ok, key=lambda r: min(r["a"]["pf"], r["b"]["pf"])) if ok else None
        npass = sum(passes(r) for r in rs)
        s = (f"{best['name']:40} IS n{best['a']['n']:4d} PF{best['a']['pf']:5.2f} | OOS n{best['b']['n']:4d} PF{best['b']['pf']:5.2f}"
             f" (long {best['bl']['pf']:4.2f} / short {best['bs']['pf']:4.2f})") if best else "-"
        print(f"{fam:22} {len(rs):7d} {npass:5d}  {s}")
    print("\nall passing configurations:")
    for r in sorted([r for r in res if passes(r)], key=lambda r: -min(r["a"]["pf"], r["b"]["pf"])):
        print(f"  {r['family']:20} {r['name']:44} IS n{r['a']['n']:4d} PF{r['a']['pf']:5.2f} win{r['a']['win']:5.1f}% | "
              f"OOS n{r['b']['n']:4d} PF{r['b']['pf']:5.2f} win{r['b']['win']:5.1f}% {r['b']['tot']:+6.1f}R | "
              f"OOS long PF {r['bl']['pf']:4.2f} short PF {r['bs']['pf']:4.2f} | SL hit {r['sl']:4.1f}%")
    print("\nhighest win rates (both periods >= 40 trades):")
    hw = sorted([r for r in res if r["a"]["n"] >= 40 and r["b"]["n"] >= 40], key=lambda r: -min(r["a"]["win"], r["b"]["win"]))[:12]
    for r in hw:
        print(f"  {r['name']:52} win {r['a']['win']:5.1f}% / {r['b']['win']:5.1f}%  PF {r['a']['pf']:4.2f} / {r['b']['pf']:4.2f}  SL hit {r['sl']:4.1f}%")
    if args.csv:
        with open(args.csv, "w", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(["family", "config", "IS n", "IS PF", "IS win", "OOS n", "OOS PF", "OOS win", "OOS R", "OOS long PF", "OOS short PF", "SL hit %"])
            for r in res:
                w.writerow([r["family"], r["name"], r["a"]["n"], round(r["a"]["pf"], 3), round(r["a"]["win"], 1), r["b"]["n"],
                            round(r["b"]["pf"], 3), round(r["b"]["win"], 1), round(r["b"]["tot"], 1), round(r["bl"]["pf"], 3),
                            round(r["bs"]["pf"], 3), round(r["sl"], 1)])


if __name__ == "__main__":
    main()
