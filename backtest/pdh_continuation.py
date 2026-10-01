#!/usr/bin/env python3
"""Simulation of SweepContinuation_PDH_PDL_MT5.mq5 (Roboquant AI, v1.00).

Same rules as the EA, on the chart timeframe bars:
  - session = server-time day starting at InpSessionStartHour (after the
    InpServerToETOffset shift); PDH / PDL = high / low of the previous session
  - on each closed bar: if it trades >= InpMinBreakPts beyond PDH (PDL) and
    closes beyond it, buy (sell) at market (next bar open)
  - SL = signal bar low - InpStopBufferPts (high + buffer), TP = RR x risk
    measured from the signal close, no time stop, no Friday close
  - ATR(14) (simple average of the true range, like iATR) of the closed bar
    must be >= its average of the 50 bars before it
  - one trade a day, one per level, one position at a time
The EA's yyyymmdd - 1 session id is kept (it makes a second session roll
on the first day of each month).

  python3 pdh_continuation.py
"""
import sys
from datetime import datetime, timezone

sys.path.insert(0, ".")
from crt_backtest import load_mt5

EXTRA = 0.05


def ymd(t):
    d = datetime.fromtimestamp(t, timezone.utc)
    return d.year * 10000 + d.month * 100 + d.day, d.hour


def run(bars, start_hour=18, et_offset=0, min_break=0.20, buf=1.50, max_stop=30.0, rr=2.0, atr_filter=True,
        atr_n=14, atr_ma=50, stop_basis=1, max_day=1, fri_close=False):
    n = len(bars)
    tr = [bars[0][2] - bars[0][3]] + [max(bars[i][2] - bars[i][3], abs(bars[i][2] - bars[i - 1][4]),
                                          abs(bars[i][3] - bars[i - 1][4])) for i in range(1, n)]
    atr = [None] * n
    s = 0.0
    for i in range(n):
        s += tr[i]
        if i >= atr_n:
            s -= tr[i - atr_n]
        if i >= atr_n - 1:
            atr[i] = s / atr_n
    trades = []
    cur = 0
    ph, pl = -1e18, 1e18
    lh = ll = None
    armed = False
    today = 0
    ldone = sdone = False
    pos = None
    for i in range(1, n - 1):
        t, o, h, l, c, sp = bars[i]
        # ---- open position: SL / TP on this bar (stop first), entry bar included
        if pos is not None and i >= pos["i"]:
            d = pos["d"]
            spr = sp + EXTRA
            ny = t - 7 * 3600
            if fri_close and (ny // 86400 + 3) % 7 == 4 and ny % 86400 >= 16 * 3600:
                px = o if d == 1 else o + spr
                trades.append(dict(t_in=pos["t"], t_out=t, dir=d, r=(px - pos["e"]) / pos["risk"] * (1 if d == 1 else -1)))
                pos = None
            elif d == 1 and l <= pos["sl"]:
                trades.append(dict(t_in=pos["t"], t_out=t, dir=1, r=(min(pos["sl"], o) - pos["e"]) / pos["risk"]))
                pos = None
            elif d == 1 and h >= pos["tp"]:
                trades.append(dict(t_in=pos["t"], t_out=t, dir=1, r=(pos["tp"] - pos["e"]) / pos["risk"]))
                pos = None
            elif d == 2 and h + spr >= pos["sl"]:
                trades.append(dict(t_in=pos["t"], t_out=t, dir=2, r=(pos["e"] - max(pos["sl"], o + spr)) / pos["risk"]))
                pos = None
            elif d == 2 and l + spr <= pos["tp"]:
                trades.append(dict(t_in=pos["t"], t_out=t, dir=2, r=(pos["e"] - pos["tp"]) / pos["risk"]))
                pos = None
        # ---- the EA's logic on the closed bar i (orders fill at the open of bar i + 1)
        date, hour = ymd(t + et_offset * 3600)
        sess = date if hour >= start_hour else date - 1
        if cur == 0:
            cur = sess
        elif sess != cur:
            if ph > -1e18:
                lh, ll = ph, pl
            ph, pl = -1e18, 1e18
            armed = False
            today = 0
            ldone = sdone = False
            cur = sess
        if lh is not None and not armed and hour >= start_hour:
            armed = True
        ph, pl = max(ph, h), min(pl, l)
        if not armed or today >= max_day or pos is not None:
            continue
        if atr_filter:
            if i < atr_ma + atr_n or atr[i] is None:
                continue
            avg = sum(atr[i - atr_ma:i]) / atr_ma
            if atr[i] < avg:
                continue
        nb = bars[i + 1]
        spr = nb[5] + EXTRA
        if not ldone and h > lh and h - lh >= min_break and c > lh:
            sl = (lh if stop_basis == 0 else l) - buf
            risk0 = c - sl
            if risk0 > 0 and (max_stop <= 0 or risk0 <= max_stop):
                e = nb[1] + spr
                tp = c + rr * risk0
                if e - sl > 0 and tp > e:
                    pos = dict(i=i + 1, t=nb[0], d=1, e=e, sl=sl, tp=tp, risk=e - sl)
                    today += 1
                    ldone = True
                    continue
        if not sdone and l < ll and ll - l >= min_break and c < ll:
            sl = (ll if stop_basis == 0 else h) + buf
            risk0 = sl - c
            if risk0 > 0 and (max_stop <= 0 or risk0 <= max_stop):
                e = nb[1]
                tp = c - rr * risk0
                if sl - e > 0 and tp < e:
                    pos = dict(i=i + 1, t=nb[0], d=2, e=e, sl=sl, tp=tp, risk=sl - e)
                    today += 1
                    sdone = True
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


if __name__ == "__main__":
    ts = lambda y, m, d: datetime(y, m, d, tzinfo=timezone.utc).timestamp()
    data = {tf: load_mt5([f"../data/XAUUSD_{tf}.csv"])[0] for tf in ("M5", "M15", "M30")}
    P = [("2020.03-22.06", ts(2020, 3, 1), ts(2022, 7, 1)), ("2022.07-24.06", ts(2022, 7, 1), ts(2024, 7, 1)),
         ("2024.07-26.09", ts(2024, 7, 1), ts(2026, 9, 27)), ("2025.07-26.09", ts(2025, 7, 1), ts(2026, 9, 27))]
    variants = [("as delivered (offset 0, session 18:00 server)", {}),
                ("ET offset -7 (session 18:00 New York)", dict(et_offset=-7)),
                ("as delivered, no ATR filter", dict(atr_filter=False)),
                ("as delivered + Friday close 16:00 NY", dict(fri_close=True))]
    for tf, bars in data.items():
        print(f"--- chart {tf} ({datetime.fromtimestamp(bars[0][0], timezone.utc):%Y.%m} - "
              f"{datetime.fromtimestamp(bars[-1][0], timezone.utc):%Y.%m})")
        for name, kw in variants:
            tr = run(bars, **kw)
            cells = [f"{lab} {stats([t for t in tr if a <= t['t_in'] < b])}" for lab, a, b in P
                     if bars[0][0] <= a + 40 * 86400 or (lab == "2025.07-26.09" and tf == "M5")]
            print(f"  {name:48} | " + " | ".join(cells))
