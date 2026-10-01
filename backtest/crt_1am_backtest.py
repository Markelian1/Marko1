#!/usr/bin/env python3
"""Offline backtest of CRT_1AM_EA (MQL5/Experts/CRT_1AM_EA.mq5, v1.05).

Replays M1 bars (server time) and runs the same rules as the EA:

  - the CRT candle is the 1AM (5AM, 9AM) New York H4 candle
  - range = the H4 candle(s) before it (1AM: 5PM + 9PM candles)
  - sweep of the range high/low; the M15 candle with the extreme is the
    order block; a later M15 close through it (and back inside the range)
    is the signal, which must fall inside the key time
  - order block and signal on the entry timeframe (M30 by default)
  - filters: daily trend (previous close vs 50-day average), premium/
    discount of the range, OHLC (sell above / buy below the CRT open),
    spread, min SL, 1 trade a day
  - entry at the first M1 open after the signal candle closes
  - SL beyond the sweep + buffer, TP at 1:RR, exit at 12:00 New York

Stops and targets are checked on M1 bars (bid prices, ask = bid + spread).
When one M1 bar touches both, the stop is assumed to fill first.

Data: MT5 bar exports (any timeframe up to the entry timeframe; M30 bars
give the M30 model, finer bars only refine the SL/TP order), or
--synthetic N random-walk M1 bars. With --synthetic and --spread 0 the
average R must be close to zero.

Example:
  python3 crt_1am_backtest.py --mt5 ../data/XAUUSD_M30.csv
"""
import argparse
import sys
from collections import defaultdict
from datetime import datetime, timezone

from crt_backtest import HEADER, Engine, fmt_row, load_mt5, make_synthetic, stats

M15 = 900
DAY = 86400
# CRT hour (NY), H4 candles in the range
MODELS = {"1AM": (1, 2), "5AM": (5, 1), "9AM": (9, 1), "1PM": (13, 1), "5PM": (17, 1), "9PM": (21, 1)}

# EA "Selective" mode: the PDF key times, M30 entries, out at 12:00 New York.
DEFAULT = dict(ny_offset=7, tf=1800, sma=50,
               models={"1AM": (200, 400), "5AM": (500, 700), "9AM": (930, 1100)}, bias="sma", pd="range", ohlc=True,
               tp="rr", rr=2.0, min_rr=1.5, sl_buffer=0.30, exit_hhmm=1200, max_hold=0, max_day=1, fri_close=1600,
               skip_hours=(8, 9),
               min_sl=1.00, min_sl_x=4.0, max_spread=0.50)
SELECTIVE = DEFAULT
# EA "Active" mode: every H4 candle from 1AM to 5PM, M15 entries, no OHLC rule,
# trades held up to 8 hours, up to 5 trades a day.
ACTIVE = dict(DEFAULT, tf=900, ohlc=False, exit_hhmm=0, max_hold=8 * 3600, max_day=5,
              models={"1AM": (100, 500), "5AM": (500, 900), "9AM": (900, 1300), "1PM": (1300, 1700)})
# EA "Any time" mode: Active rules on all six H4 candles, no news pause
# (None = no key time, the whole candle).
ANYTIME = dict(ACTIVE, skip_hours=(), models={n: None for n in MODELS})
# CRT_1AM_PRO24.mq5 v1.02: the Any-time rules with a retest limit entry (wait up to 4 hours)
PRO24 = dict(ANYTIME, entry="retest", retest_sec=4 * 3600)


def pro24_set(per_candle=True, reentry=True, selective=False):
    """CRT_1AM_PRO24 v1.06 as a list of independent runs: one position per
    H4 candle (each candle its own run), re-entry, no retest against the
    trend, optionally the Selective model (off by default: it trades fixed
    key times). The v1.05 daily loss limit is not simulated."""
    base = dict(PRO24, reentry=reentry, bias_first=True)
    cfgs = [dict(base, models={n: None}) for n in MODELS] if per_candle else [base]
    if selective:
        cfgs.append(dict(SELECTIVE, skip_hours=()))
    return cfgs


def hhmm_min(v):
    return (v // 100) * 60 + v % 100


class ModelDay:
    def __init__(self, key):
        self.key = key
        self.ok = False
        self.done = False
        self.allow = 0
        self.rng_hi = self.rng_lo = self.crt_open = self.pd_mid = self.atr = 0.0
        self.prev_close = self.trend_avg = 0.0
        self.swept_hi = self.swept_lo = False
        self.sweep_hi = self.sweep_lo = 0.0
        self.ob_sell_low = self.ob_buy_high = 0.0
        self.ob_sell_t = self.ob_buy_t = 0


def run(bars, cfg):
    off = cfg["ny_offset"] * 3600
    M15 = cfg["tf"]                 # entry timeframe in seconds (1800 = M30, 900 = M15)
    CANDLE = cfg.get("candle", 4 * 3600)               # CRT candle length (H4 by default)
    defs = cfg.get("model_defs", MODELS)              # name -> (start hour NY, candles in the range)
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
    trades, skips, funnel = [], defaultdict(int), defaultdict(int)
    pos = None
    entries_day = defaultdict(int)
    cur_m15 = None
    recent = []                      # ranges of the last 20 closed entry-TF bars
    pending = None                   # retest limit order waiting for a fill

    def init_day(name, crt_ny):
        hour, n_rng = defs[name]
        d = ModelDay(crt_ny)
        crt_srv = crt_ny + off
        n_rng = cfg.get("range_candles", {}).get(name, n_rng)
        rng = [m15[k] for k in range(crt_srv - n_rng * CANDLE, crt_srv, M15) if k in m15]
        # first bar of the candle (the 5PM candle starts after the daily break)
        first = next((m15[k] for k in range(crt_srv, crt_srv + CANDLE, M15) if k in m15), None)
        day = crt_srv - crt_srv % DAY
        i = d1_index.get(day, 0)
        if len(rng) < 4 or first is None or i == 0:
            return d
        prev = d1[d1_days[i - 1]]
        d.rng_hi = max(b[2] for b in rng)
        d.rng_lo = min(b[3] for b in rng)
        d.crt_open = first[1]
        d.pd_mid = ((prev[2] + prev[3]) if cfg["pd"] == "prev" else (d.rng_hi + d.rng_lo)) / 2.0
        prev_dir = 1 if prev[4] > prev[1] else 2 if prev[4] < prev[1] else 0
        closes = [d1[x][4] for x in d1_days[max(0, i - cfg["sma"]):i]]
        d.prev_close = prev[4]
        d.trend_avg = sum(closes) / len(closes) if closes else 0.0
        sma_dir = 0 if len(closes) < cfg["sma"] else 1 if prev[4] > sum(closes) / len(closes) else 2
        if cfg.get("sma2") and sma_dir:
            c2 = [d1[x][4] for x in d1_days[max(0, i - cfg["sma2"]):i]]
            dir2 = 1 if prev[4] > sum(c2) / len(c2) else 2
            sma_dir = sma_dir if dir2 == sma_dir else 0
        rngs = [d1[x][2] - d1[x][3] for x in d1_days[max(0, i - 14):i]]
        d.atr = sum(rngs) / len(rngs)
        if cfg["bias"] == "none":
            d.allow = 3
        elif cfg["bias"] == "d1":
            d.allow = eng.state
        elif cfg["bias"] == "prev":
            d.allow = prev_dir
        elif cfg["bias"] == "sma":
            d.allow = sma_dir
        elif cfg["bias"] == "long":
            d.allow = 1
        else:
            d.allow = eng.state or prev_dir
        d.ok = True
        return d

    def try_enter(name, d, direction, sig_ny, bar, extreme, price=None):
        t, o, h, l, c, spread = bar
        key = cfg["models"][name]
        m = (sig_ny % DAY) // 60
        if key is not None and not hhmm_min(key[0]) <= m < hhmm_min(key[1]):
            return "key time"
        if not d.allow & direction:
            return "bias"
        if pos is not None:
            return "position open"
        ny_t = t - off
        if (ny_t // DAY + 3) % 7 in cfg.get("skip_wdays", ()):
            return "weekday"
        if (ny_t % DAY) // 3600 in cfg.get("skip_hours", ()):
            return "news hour"
        if cfg.get("fri_close", 0) > 0 and (ny_t // DAY + 3) % 7 == 4 and (ny_t % DAY) // 60 >= hhmm_min(cfg["fri_close"]) - 240:
            return "Friday"
        day_ny = (t - off) - (t - off) % DAY
        if cfg["max_day"] > 0 and entries_day[day_ny] >= cfg["max_day"]:
            return "max trades"
        if cfg["max_spread"] > 0 and spread > cfg["max_spread"]:
            return "spread"
        bid, ask = o, o + spread
        if price is not None:                 # limit fill at a given price
            bid, ask = (price, price + spread) if direction == 2 else (price - spread, price)
        entry = ask if direction == 1 else bid
        if cfg["ohlc"] and ((direction == 2 and bid < d.crt_open) or (direction == 1 and ask > d.crt_open)):
            return "OHLC"
        if cfg["pd"] != "off" and ((direction == 2 and bid < d.pd_mid) or (direction == 1 and ask > d.pd_mid)):
            return "premium/discount"
        sl = extreme - cfg["sl_buffer"] if direction == 1 else extreme + cfg["sl_buffer"]
        risk = entry - sl if direction == 1 else sl - entry
        if risk <= 0:
            return "SL side"
        if risk < max(cfg["min_sl"], cfg["min_sl_x"] * spread):
            return "SL too small"
        if cfg.get("max_sl_atr") and risk > cfg["max_sl_atr"] * d.atr:
            return "SL too big"
        if cfg.get("min_rng_atr") and d.rng_hi - d.rng_lo < cfg["min_rng_atr"] * d.atr:
            return "small range"
        depth = (extreme - d.rng_hi) if direction == 2 else (d.rng_lo - extreme)
        if cfg.get("max_depth_rng") and depth > cfg["max_depth_rng"] * (d.rng_hi - d.rng_lo):
            return "deep sweep"
        if cfg["tp"] == "rr":
            tp = entry + cfg["rr"] * risk if direction == 1 else entry - cfg["rr"] * risk
        else:
            tp = d.rng_hi if direction == 1 else d.rng_lo
            reward = tp - entry if direction == 1 else entry - tp
            if reward <= 0 or reward / risk < cfg["min_rr"]:
                return "RR"
        entries_day[day_ny] += 1
        return dict(dir=direction, entry=entry, sl=sl, tp=tp, risk=risk, t_in=t, model=name,
                    rng=d.rng_hi - d.rng_lo, rng_hi=d.rng_hi, rng_lo=d.rng_lo, crt_open=d.crt_open, pd_mid=d.pd_mid,
                    extreme=extreme, depth=(extreme - d.rng_hi) if direction == 2 else (d.rng_lo - extreme),
                    atr=d.atr, spread=spread, prev_close=d.prev_close, trend_avg=d.trend_avg,
                    mfe=0.0, mae=0.0)

    def close(p, price, t, why):
        r = (price - p["entry"]) / p["risk"] if p["dir"] == 1 else (p["entry"] - price) / p["risk"]
        if "part" in p:                       # part of the position was closed earlier
            r = p["part"] + (1 - cfg["pc_frac"]) * r
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
            avg_rng = sum(recent) / len(recent) if recent else 0.0
            spike = cfg.get("spike", 0) > 0 and avg_rng > 0 and closed[2] - closed[3] > cfg["spike"] * avg_rng
            recent.append(closed[2] - closed[3])
            if len(recent) > 20:
                recent.pop(0)
            for name in cfg["models"]:
                crt_ny = ny - (ny - defs[name][0] * 3600) % DAY     # latest start of this candle
                if not crt_ny <= ny < crt_ny + CANDLE:
                    continue
                d = md.get(name)
                if d is None or d.key != crt_ny:
                    d = md[name] = init_day(name, crt_ny)
                    funnel["candles"] += 1
                    funnel["no data" if not d.ok else "no bias" if d.allow == 0 else "watched"] += 1
                if not d.ok or d.done or d.allow == 0:
                    continue
                _, bo, bh, bl, bc = closed
                # signals first: an engulfing candle that also makes a new extreme still counts
                sell = d.swept_hi and closed[0] > d.ob_sell_t and bc < d.ob_sell_low and bc < d.rng_hi
                buy = d.swept_lo and closed[0] > d.ob_buy_t and bc > d.ob_buy_high and bc > d.rng_lo
                for direction, sig in ((2, sell), (1, buy)):
                    if not sig:
                        continue
                    funnel["OB breaks"] += 1
                    extreme = max(d.sweep_hi, bh) if direction == 2 else min(d.sweep_lo, bl)
                    if cfg.get("entry") == "retest" and not spike:
                        # limit at the broken order-block level, valid for retest_sec
                        res = "pending"
                        if cfg.get("bias_first") and not d.allow & direction:
                            res = "bias"                          # never wait for a retest against the bias
                        elif pending is None and pos is None:
                            level = d.ob_sell_low if direction == 2 else d.ob_buy_high
                            pending = dict(name=name, d=d, dir=direction, level=level, extreme=extreme,
                                           sig_ny=ny + M15, expires=t + cfg.get("retest_sec", 7200))
                    else:
                        res = "spike" if spike else try_enter(name, d, direction, ny + M15, bar, extreme)
                    if direction == 2:
                        d.ob_sell_t = float("inf")
                    else:
                        d.ob_buy_t = float("inf")
                    if isinstance(res, dict):
                        pos = res
                        d.done = not cfg.get("reentry")      # reentry: keep watching this candle
                        break
                    skips[res] += 1
                if d.done:
                    continue
                if bh > d.rng_hi and (not d.swept_hi or bh > d.sweep_hi):
                    if not d.swept_hi:
                        funnel["high sweeps"] += 1
                    d.swept_hi, d.sweep_hi, d.ob_sell_low, d.ob_sell_t = True, bh, bl, closed[0]
                if bl < d.rng_lo and (not d.swept_lo or bl < d.sweep_lo):
                    if not d.swept_lo:
                        funnel["low sweeps"] += 1
                    d.swept_lo, d.sweep_lo, d.ob_buy_high, d.ob_buy_t = True, bl, bh, closed[0]
        cur_m15 = k

        # ---- retest limit order --------------------------------------------
        if pending is not None and pos is None:
            pd_ = pending
            if t > pd_["expires"] or pd_["d"].done:
                pending = None
            elif (pd_["dir"] == 2 and h + spread > pd_["extreme"]) or (pd_["dir"] == 1 and l < pd_["extreme"]):
                pending = None                                        # new extreme first: setup gone
                skips["retest invalid"] += 1
            elif (pd_["dir"] == 2 and h >= pd_["level"]) or (pd_["dir"] == 1 and l + spread <= pd_["level"]):
                fill = max(o, pd_["level"]) if pd_["dir"] == 2 else min(o + spread, pd_["level"])
                res = try_enter(pd_["name"], pd_["d"], pd_["dir"], pd_["sig_ny"], bar, pd_["extreme"], price=fill)
                pending = None
                if isinstance(res, dict):
                    pos = res
                    pd_["d"].done = not cfg.get("reentry")
                else:
                    skips[res] += 1

        if pos is None:
            continue

        # ---- exit time ---------------------------------------------------
        fri = cfg.get("fri_close", 0)
        if fri > 0 and ((t - off) // DAY + 3) % 7 == 4 and ((t - off) % DAY) // 60 >= hhmm_min(fri):
            close(pos, o if pos["dir"] == 1 else o + spread, t, "time")
            pos = None
            continue
        if cfg.get("max_hold", 0) > 0 and t - pos["t_in"] >= cfg["max_hold"]:
            close(pos, o if pos["dir"] == 1 else o + spread, t, "time")
            pos = None
            continue
        if cfg["exit_hhmm"] > 0:
            now_ny = t - off
            exit_ny = now_ny - now_ny % DAY + hhmm_min(cfg["exit_hhmm"]) * 60
            if now_ny < exit_ny:
                exit_ny -= DAY
            if pos["t_in"] - off < exit_ny:
                close(pos, o if pos["dir"] == 1 else o + spread, t, "time")
                pos = None
                continue

        # ---- best / worst excursion so far, in R ---------------------------
        if pos["dir"] == 1:
            pos["mfe"] = max(pos["mfe"], (h - pos["entry"]) / pos["risk"])
            pos["mae"] = min(pos["mae"], (l - pos["entry"]) / pos["risk"])
        else:
            pos["mfe"] = max(pos["mfe"], (pos["entry"] - l - spread) / pos["risk"])
            pos["mae"] = min(pos["mae"], (pos["entry"] - h - spread) / pos["risk"])

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
        # ---- partial close at +pc_r and stop to break-even (next bar on) -
        if pos is not None and cfg.get("pc_r", 0) > 0 and "part" not in pos:
            trig = pos["entry"] + cfg["pc_r"] * pos["risk"] if pos["dir"] == 1 else pos["entry"] - cfg["pc_r"] * pos["risk"]
            if (pos["dir"] == 1 and h >= trig) or (pos["dir"] == 2 and l + spread <= trig):
                pos["part"] = cfg["pc_frac"] * cfg["pc_r"]
                pos["sl"] = pos["entry"]
        # ---- trailing stop after +trail_start R, trail_dist R behind -------
        if pos is not None and cfg.get("trail_start", 0) > 0:
            dist = cfg["trail_dist"] * pos["risk"]
            if pos["dir"] == 1 and h - pos["entry"] >= cfg["trail_start"] * pos["risk"]:
                pos["sl"] = max(pos["sl"], h - dist)
            elif pos["dir"] == 2 and pos["entry"] - (l + spread) >= cfg["trail_start"] * pos["risk"]:
                pos["sl"] = min(pos["sl"], l + spread + dist)
        # ---- break-even after +be_r (from the next bar on) ---------------
        if pos is not None and cfg.get("be_r", 0) > 0:
            trig = pos["entry"] + cfg["be_r"] * pos["risk"] if pos["dir"] == 1 else pos["entry"] - cfg["be_r"] * pos["risk"]
            if (pos["dir"] == 1 and h >= trig) or (pos["dir"] == 2 and l + spread <= trig):
                pos["sl"] = max(pos["sl"], pos["entry"]) if pos["dir"] == 1 else min(pos["sl"], pos["entry"])

    return trades, skips, funnel


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mt5", nargs="+", help="MT5 M1 bar export file(s)")
    ap.add_argument("--synthetic", type=int, help="number of random-walk M1 bars")
    ap.add_argument("--spread", type=float, default=0.0, help="spread for --synthetic (price units)")
    ap.add_argument("--ny-offset", type=int, default=7, help="server time minus New York time (hours)")
    ap.add_argument("--forward", default="2024-01-01", help="start of the forward period (YYYY-MM-DD)")
    args = ap.parse_args()

    if args.mt5:
        bars, point = load_mt5(args.mt5)
        src = f"MT5 export, {len(bars)} bars, point {point}"
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
        ("EA Active mode", dict(ACTIVE, ny_offset=args.ny_offset)),
        ("  Active, entry M30", dict(ACTIVE, ny_offset=args.ny_offset, tf=1800)),
        ("  Active, trend 20", dict(ACTIVE, ny_offset=args.ny_offset, sma=20)),
        ("  Active, trend 100", dict(ACTIVE, ny_offset=args.ny_offset, sma=100)),
        ("  Active, bias off", dict(ACTIVE, ny_offset=args.ny_offset, bias="none")),
        ("  Active, OHLC on", dict(ACTIVE, ny_offset=args.ny_offset, ohlc=True)),
        ("  Active, hold 4h", dict(ACTIVE, ny_offset=args.ny_offset, max_hold=4 * 3600)),
        ("  Active, RR 1.5", dict(ACTIVE, ny_offset=args.ny_offset, rr=1.5)),
        ("EA Selective mode", base),
        ("  Selective, 1AM only", dict(base, models={"1AM": (200, 400)})),
        ("  Selective, entry M15", dict(base, tf=900)),
        ("  Selective, trend 20", dict(base, sma=20)),
        ("  Selective, trend 100", dict(base, sma=100)),
        ("  Selective, bias off", dict(base, bias="none")),
        ("  Selective, OHLC off", dict(base, ohlc=False)),
        ("  Selective, RR 1.5", dict(base, rr=1.5)),
        ("  Selective, RR 3", dict(base, rr=3.0)),
    ]
    print(HEADER)
    for name, cfg in configs:
        trades, skips, funnel = run(bars, cfg)
        print(fmt_row(name, stats(trades)))
        print(fmt_row("  before forward", stats([t for t in trades if t["t_in"] < fwd])))
        print(fmt_row("  forward", stats([t for t in trades if t["t_in"] >= fwd])))
        if name.startswith("EA "):
            by_year = defaultdict(list)
            for t in trades:
                by_year[datetime.fromtimestamp(t["t_in"], timezone.utc).year].append(t)
            for y in sorted(by_year):
                print(fmt_row(f"  {y}", stats(by_year[y])))
            exits = defaultdict(list)
            for t in trades:
                exits[t["why"]].append(t["r"])
            print("  exits: " + ", ".join(f"{k} {len(v)} x {sum(v) / len(v):+.2f}R" for k, v in sorted(exits.items())))
            print("  funnel: " + ", ".join(f"{k} {v}" for k, v in funnel.items()))
            print("  skipped signals: " + ", ".join(f"{k} {v}" for k, v in sorted(skips.items(), key=lambda x: -x[1])))
            bad = sum(1 for t in trades if (t["dir"] == 1 and not t["sl"] < t["entry"] < t["tp"]) or
                      (t["dir"] == 2 and not t["tp"] < t["entry"] < t["sl"]))
            print(f"  trades with SL/TP on the wrong side: {bad}")
    print()


if __name__ == "__main__":
    main()
