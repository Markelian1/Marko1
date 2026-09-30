#!/usr/bin/env python3
"""Offline backtest of CRT_1AM_EA (MQL5/Experts/CRT_1AM_EA.mq5, v1.00).

Replays M1 bars (server time) and runs the same rules as the EA:

  - the CRT candle is the 1AM (5AM, 9AM) New York H4 candle
  - range = the H4 candle(s) before it (1AM: 5PM + 9PM candles)
  - sweep of the range high/low; the M15 candle with the extreme is the
    order block; a later M15 close through it (and back inside the range)
    is the signal, which must fall inside the key time
  - filters: daily CRT bias, premium/discount of the previous day, OHLC
    (sell above / buy below the CRT open), spread, min SL, 1 trade a day
  - entry at the first M1 open after the signal candle closes
  - SL beyond the sweep + buffer, TP at 1:RR, exit at 12:00 New York

Stops and targets are checked on M1 bars (bid prices, ask = bid + spread).
When one M1 bar touches both, the stop is assumed to fill first.

Data: same as crt_backtest.py (--mt5 export of M1 bars, or --synthetic N).
With --synthetic and --spread 0 the average R must be close to zero.

Example:
  python3 crt_1am_backtest.py --mt5 XAUUSD_M1_2023.csv XAUUSD_M1_2024.csv
"""
import argparse
import sys
from collections import defaultdict
from datetime import datetime, timezone

from crt_backtest import HEADER, Engine, fmt_row, load_mt5, make_synthetic, stats

M15 = 900
DAY = 86400
MODELS = {"1AM": (1, 2), "5AM": (5, 1), "9AM": (9, 1)}   # CRT hour (NY), H4 candles in the range

DEFAULT = dict(ny_offset=7, models={"1AM": (200, 400)}, bias="d1", prem_disc=True, ohlc=True,
               tp="rr", rr=2.0, min_rr=1.5, sl_buffer=0.30, exit_hhmm=1200, max_day=1,
               min_sl=1.00, min_sl_x=4.0, max_spread=0.50)


def hhmm_min(v):
    return (v // 100) * 60 + v % 100


class ModelDay:
    def __init__(self, key):
        self.key = key
        self.ok = False
        self.done = False
        self.allow = 0
        self.rng_hi = self.rng_lo = self.crt_open = self.pd_mid = 0.0
        self.swept_hi = self.swept_lo = False
        self.sweep_hi = self.sweep_lo = 0.0
        self.ob_sell_low = self.ob_buy_high = 0.0
        self.ob_sell_t = self.ob_buy_t = 0


def run(bars, cfg):
    off = cfg["ny_offset"] * 3600
    m15 = {}      # open time -> [t, o, h, l, c]
    d1 = {}       # server day -> [t, o, h, l, c]
    for t, o, h, l, c, _ in bars:
        for store, k in ((m15, t - t % M15), (d1, t - t % DAY)):
            b = store.get(k)
            if b is None:
                store[k] = [k, o, h, l, c]
            else:
                b[2] = max(b[2], h)
                b[3] = min(b[3], l)
                b[4] = c
    d1_days = sorted(d1)
    d1_index = {d: i for i, d in enumerate(d1_days)}

    eng = Engine()
    d1_fed = 0                       # number of daily bars fed to the engine
    md = {}
    trades, skips = [], defaultdict(int)
    pos = None
    entries_day = defaultdict(int)
    cur_m15 = None

    def init_day(name, crt_ny):
        hour, n_rng = MODELS[name]
        d = ModelDay(crt_ny)
        crt_srv = crt_ny + off
        rng = [m15[k] for k in range(crt_srv - n_rng * 4 * 3600, crt_srv, M15) if k in m15]
        first = next((m15[k] for k in range(crt_srv, crt_srv + 3600, M15) if k in m15), None)
        day = crt_srv - crt_srv % DAY
        i = d1_index.get(day, 0)
        if len(rng) < 4 or first is None or i == 0:
            return d
        prev = d1[d1_days[i - 1]]
        d.rng_hi = max(b[2] for b in rng)
        d.rng_lo = min(b[3] for b in rng)
        d.crt_open = first[1]
        d.pd_mid = (prev[2] + prev[3]) / 2.0
        if cfg["bias"] == "none":
            d.allow = 3
        elif cfg["bias"] == "d1":
            d.allow = eng.state
        else:
            d.allow = 1 if prev[4] > prev[1] else 2 if prev[4] < prev[1] else 0
        d.ok = True
        return d

    def try_enter(name, d, direction, sig_ny, bar):
        t, o, h, l, c, spread = bar
        frm, to = cfg["models"][name]
        m = (sig_ny % DAY) // 60
        if not hhmm_min(frm) <= m < hhmm_min(to):
            return "key time"
        if not d.allow & direction:
            return "bias"
        if pos is not None:
            return "position open"
        day_ny = (t - off) - (t - off) % DAY
        if cfg["max_day"] > 0 and entries_day[day_ny] >= cfg["max_day"]:
            return "max trades"
        if cfg["max_spread"] > 0 and spread > cfg["max_spread"]:
            return "spread"
        bid, ask = o, o + spread
        entry = ask if direction == 1 else bid
        if cfg["ohlc"] and ((direction == 2 and bid < d.crt_open) or (direction == 1 and ask > d.crt_open)):
            return "OHLC"
        if cfg["prem_disc"] and ((direction == 2 and bid < d.pd_mid) or (direction == 1 and ask > d.pd_mid)):
            return "premium/discount"
        sl = d.sweep_lo - cfg["sl_buffer"] if direction == 1 else d.sweep_hi + cfg["sl_buffer"]
        risk = entry - sl if direction == 1 else sl - entry
        if risk <= 0:
            return "SL side"
        if risk < max(cfg["min_sl"], cfg["min_sl_x"] * spread):
            return "SL too small"
        if cfg["tp"] == "rr":
            tp = entry + cfg["rr"] * risk if direction == 1 else entry - cfg["rr"] * risk
        else:
            tp = d.rng_hi if direction == 1 else d.rng_lo
            reward = tp - entry if direction == 1 else entry - tp
            if reward <= 0 or reward / risk < cfg["min_rr"]:
                return "RR"
        entries_day[day_ny] += 1
        return dict(dir=direction, entry=entry, sl=sl, tp=tp, risk=risk, t_in=t, model=name)

    def close(p, price, t, why):
        r = (price - p["entry"]) / p["risk"] if p["dir"] == 1 else (p["entry"] - price) / p["risk"]
        trades.append(dict(p, r=r, t_out=t, why=why))

    for bar in bars:
        t, o, h, l, c, spread = bar
        k = t - t % M15

        # ---- first tick of a new M15 bar: process the closed one --------
        if cur_m15 is not None and k != cur_m15:
            closed = m15[cur_m15]
            today = t - t % DAY
            while d1_fed < len(d1_days) and d1_days[d1_fed] < today:
                db = d1[d1_days[d1_fed]]
                eng.step(db[1], db[2], db[3], db[4])
                d1_fed += 1

            ny = closed[0] - off
            for name in cfg["models"]:
                crt_ny = ny - ny % DAY + MODELS[name][0] * 3600
                if not crt_ny <= ny < crt_ny + 4 * 3600:
                    continue
                d = md.get(name)
                if d is None or d.key != crt_ny:
                    d = md[name] = init_day(name, crt_ny)
                if not d.ok or d.done or d.allow == 0:
                    continue
                _, bo, bh, bl, bc = closed
                if bh > d.rng_hi and (not d.swept_hi or bh > d.sweep_hi):
                    d.swept_hi, d.sweep_hi, d.ob_sell_low, d.ob_sell_t = True, bh, bl, closed[0]
                if bl < d.rng_lo and (not d.swept_lo or bl < d.sweep_lo):
                    d.swept_lo, d.sweep_lo, d.ob_buy_high, d.ob_buy_t = True, bl, bh, closed[0]
                sell = d.swept_hi and closed[0] > d.ob_sell_t and bc < d.ob_sell_low and bc < d.rng_hi
                buy = d.swept_lo and closed[0] > d.ob_buy_t and bc > d.ob_buy_high and bc > d.rng_lo
                for direction, sig in ((2, sell), (1, buy)):
                    if not sig:
                        continue
                    res = try_enter(name, d, direction, ny + M15, bar)
                    if direction == 2:
                        d.ob_sell_t = float("inf")
                    else:
                        d.ob_buy_t = float("inf")
                    if isinstance(res, dict):
                        pos = res
                        d.done = True
                        break
                    skips[res] += 1
        cur_m15 = k

        if pos is None:
            continue

        # ---- exit time ---------------------------------------------------
        if cfg["exit_hhmm"] > 0:
            now_ny = t - off
            exit_ny = now_ny - now_ny % DAY + hhmm_min(cfg["exit_hhmm"]) * 60
            if now_ny < exit_ny:
                exit_ny -= DAY
            if pos["t_in"] - off < exit_ny:
                close(pos, o if pos["dir"] == 1 else o + spread, t, "time")
                pos = None
                continue

        # ---- SL / TP on this M1 bar (stop first when both) ---------------
        if pos["dir"] == 1:
            if l <= pos["sl"]:
                close(pos, pos["sl"], t, "SL")
                pos = None
            elif h >= pos["tp"]:
                close(pos, pos["tp"], t, "TP")
                pos = None
        else:
            if h + spread >= pos["sl"]:
                close(pos, pos["sl"], t, "SL")
                pos = None
            elif l + spread <= pos["tp"]:
                close(pos, pos["tp"], t, "TP")
                pos = None

    return trades, skips


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mt5", nargs="+", help="MT5 M1 bar export file(s)")
    ap.add_argument("--synthetic", type=int, help="number of random-walk M1 bars")
    ap.add_argument("--spread", type=float, default=0.0, help="spread for --synthetic (price units)")
    ap.add_argument("--ny-offset", type=int, default=7, help="server time minus New York time (hours)")
    ap.add_argument("--forward", default="2025-07-01", help="start of the forward period (YYYY-MM-DD)")
    args = ap.parse_args()

    if args.mt5:
        bars, point = load_mt5(args.mt5)
        src = f"MT5 export, {len(bars)} M1 bars, point {point}"
    elif args.synthetic:
        bars = make_synthetic(args.synthetic, args.spread)
        src = f"synthetic random walk, {len(bars)} M1 bars, spread {args.spread}"
    else:
        ap.error("give --mt5 FILE(s) or --synthetic N")
    if not bars:
        sys.exit("no bars loaded")

    first = datetime.fromtimestamp(bars[0][0], timezone.utc)
    last = datetime.fromtimestamp(bars[-1][0], timezone.utc)
    print(f"{src}\n{first:%Y-%m-%d} .. {last:%Y-%m-%d}\n")
    fwd = int(datetime.strptime(args.forward, "%Y-%m-%d").replace(tzinfo=timezone.utc).timestamp())

    base = dict(DEFAULT, ny_offset=args.ny_offset)
    configs = [
        ("EA defaults (1AM)", base),
        ("bias off", dict(base, bias="none")),
        ("bias prev day", dict(base, bias="prev")),
        ("no prem/disc", dict(base, prem_disc=False)),
        ("no OHLC", dict(base, ohlc=False)),
        ("RR 3", dict(base, rr=3.0)),
        ("TP range side", dict(base, tp="range")),
        ("1AM+5AM+9AM", dict(base, max_day=2, models={"1AM": (200, 400), "5AM": (500, 700),
                                                      "9AM": (930, 1100)})),
    ]
    print(HEADER)
    for name, cfg in configs:
        trades, skips = run(bars, cfg)
        print(fmt_row(name, stats(trades)))
        print(fmt_row("  before forward", stats([t for t in trades if t["t_in"] < fwd])))
        print(fmt_row("  forward", stats([t for t in trades if t["t_in"] >= fwd])))
        if name.startswith("EA defaults"):
            by_year = defaultdict(list)
            for t in trades:
                by_year[datetime.fromtimestamp(t["t_in"], timezone.utc).year].append(t)
            for y in sorted(by_year):
                print(fmt_row(f"  {y}", stats(by_year[y])))
            exits = defaultdict(list)
            for t in trades:
                exits[t["why"]].append(t["r"])
            print("  exits: " + ", ".join(f"{k} {len(v)} x {sum(v) / len(v):+.2f}R" for k, v in sorted(exits.items())))
            print("  skipped signals: " + ", ".join(f"{k} {v}" for k, v in sorted(skips.items(), key=lambda x: -x[1])))
            bad = sum(1 for t in trades if (t["dir"] == 1 and not t["sl"] < t["entry"] < t["tp"]) or
                      (t["dir"] == 2 and not t["tp"] < t["entry"] < t["sl"]))
            print(f"  trades with SL/TP on the wrong side: {bad}")
    print()


if __name__ == "__main__":
    main()
