#!/usr/bin/env python3
"""Offline backtest of CRT_MTF_EA (MQL5/Experts/CRT_MTF_EA.mq5, v1.21).

Replays M1 bars, builds the entry-timeframe candles from them and runs the
same CRT engine and "CRT close" entry rules as the EA:

  - CRT: parent -> sweep -> close back inside (EngineStep in the EA)
  - entry at the first M1 open after the entry-TF candle closes
  - SL beyond the sweep wick (C2) + buffer, TP at the CRT target
  - filters: session, max trades/day, min SL ($ and x spread), min sweep %,
    min reward:risk, one position at a time, close on CRT invalidation

Stops and targets are checked on M1 bars. When one M1 bar touches both,
the stop is assumed to fill first (conservative).

Results are in R (multiples of the risk per trade), so they do not depend
on account size. "% (0.5%/trade)" compounds 0.5% risk per trade.

Data:
  --mt5 FILE      MT5 bar export (Ctrl+U > Bars > XAUUSD, M1 > Request >
                  Export). Tab separated, server time, spread in points.
                  Several files (e.g. one per year) can be given.
  --synthetic N   random-walk M1 bars, to check the simulator itself: with
                  --spread 0 the average R must be close to zero.

Example:
  python3 crt_backtest.py --mt5 XAUUSD_M1_2023.csv XAUUSD_M1_2024.csv \
      --tf M5 M15 M30 H1 H4
"""
import argparse
import random
import sys
from collections import defaultdict
from datetime import datetime, timezone

TF_SECONDS = {"M5": 300, "M15": 900, "M30": 1800, "H1": 3600, "H4": 14400}

EV_NONE, EV_PARENT, EV_BULL, EV_BEAR, EV_MID, EV_TARGET, EV_INVALID, EV_EXPANSION, EV_DOUBLE = range(9)


# ============================================================================
# DATA
# ============================================================================

def load_mt5(paths):
    """Returns sorted [(t, open, high, low, close, spread_price)] in server time."""
    rows = {}
    digits = 0
    for path in paths:
        with open(path, encoding="utf-8-sig", errors="replace") as fh:
            for line in fh:
                parts = line.strip().replace(",", "\t").split("\t")
                if len(parts) < 6 or not parts[0][:1].isdigit():
                    continue
                if "." in parts[2]:
                    digits = max(digits, len(parts[2].split(".")[1]))
                dt = datetime.strptime(parts[0] + " " + parts[1], "%Y.%m.%d %H:%M:%S")
                t = int(dt.replace(tzinfo=timezone.utc).timestamp())
                spread_pts = float(parts[8]) if len(parts) > 8 else 0.0
                rows[t] = (t, float(parts[2]), float(parts[3]), float(parts[4]), float(parts[5]), spread_pts)
    point = 10.0 ** -digits if digits else 0.01
    bars = [(t, o, h, l, c, sp * point) for (t, o, h, l, c, sp) in (rows[k] for k in sorted(rows))]
    return bars, point


def make_synthetic(n, spread, seed=1):
    rnd = random.Random(seed)
    price = 2000.0
    t = int(datetime(2023, 1, 2, tzinfo=timezone.utc).timestamp())
    bars = []
    while len(bars) < n:
        if datetime.fromtimestamp(t, timezone.utc).weekday() < 5:
            o = price
            c = o + rnd.gauss(0, 0.45)
            h = max(o, c) + abs(rnd.gauss(0, 0.25))
            l = min(o, c) - abs(rnd.gauss(0, 0.25))
            bars.append((t, o, h, l, c, spread))
            price = c
        t += 60
    return bars


# ============================================================================
# CRT ENGINE (mirror of EngineStep in the EA)
# ============================================================================

class Engine:
    def __init__(self):
        self.has_parent = False
        self.state = 0
        self.id = 0
        self.ph = self.pl = self.mid = self.target = self.sweep = 0.0

    def _parent(self, h, l):
        self.has_parent = True
        self.ph, self.pl, self.mid = h, l, (h + l) / 2.0
        self.target = self.sweep = 0.0
        self.state = 0
        self.id += 1

    def step(self, o, h, l, c):
        if not self.has_parent:
            self._parent(h, l)
            return EV_PARENT
        if self.state == 0:
            swept_low, swept_high = l <= self.pl, h >= self.ph
            if c > self.ph or c < self.pl:
                self._parent(h, l)
                return EV_EXPANSION
            if swept_low and swept_high:
                self._parent(h, l)
                return EV_DOUBLE
            if swept_low:
                self.state, self.target, self.sweep = 1, self.ph, l
                self.mid = (self.ph + self.pl) / 2.0
                self.id += 1
                return EV_BULL
            if swept_high:
                self.state, self.target, self.sweep = 2, self.pl, h
                self.mid = (self.ph + self.pl) / 2.0
                self.id += 1
                return EV_BEAR
            return EV_NONE
        bull = self.state == 1
        if (h >= self.target) if bull else (l <= self.target):
            self._parent(h, l)
            return EV_TARGET
        if (c < self.pl) if bull else (c > self.ph):
            self._parent(h, l)
            return EV_INVALID
        return EV_NONE


# ============================================================================
# SIMULATION
# ============================================================================

def in_session(t, cfg):
    if not cfg["session"]:
        return True
    d = datetime.fromtimestamp(t, timezone.utc)
    m = d.hour * 60 + d.minute
    s, e = cfg["sess_start"] * 60, cfg["sess_end"] * 60
    if s == e:
        return True
    return s <= m < e if s < e else (m >= s or m < e)


def run(bars, tf, cfg):
    tf_sec = TF_SECONDS[tf]
    eng = Engine()
    trades = []
    skips = defaultdict(int)
    pos = None
    day_count = defaultdict(int)
    cur = None                                   # [bucket, o, h, l, c]

    def close_pos(exit_price, t, why):
        nonlocal pos
        d = pos["dir"]
        r = ((exit_price - pos["entry"]) if d == 1 else (pos["entry"] - exit_price)) / pos["risk"]
        r -= cfg["commission"] / (pos["risk"] * cfg["contract"])
        trades.append(dict(t_in=pos["t"], t_out=t, dir=d, r=r, why=why, tf=tf, risk=pos["risk"]))
        pos = None

    for (t, o, h, l, c, spread) in bars:
        bucket = t - t % tf_sec

        # ----------------------------------------------------------------
        # Entry-TF candle closed before this M1 bar: run the engine and
        # act at this bar's open (the EA acts on the first tick after).
        # ----------------------------------------------------------------
        if cur is not None and bucket != cur[0]:
            prev_id = eng.id
            ev = eng.step(cur[1], cur[2], cur[3], cur[4])

            if ev == EV_INVALID and pos is not None and cfg["close_on_invalid"] and pos["crt"] == prev_id:
                exit_price = o if pos["dir"] == 1 else o + spread
                close_pos(exit_price, t, "invalid")

            if ev in (EV_BULL, EV_BEAR):
                d = 1 if ev == EV_BULL else 2
                why = None
                rng = eng.ph - eng.pl
                depth = (eng.pl - eng.sweep) if d == 1 else (eng.sweep - eng.ph)
                entry = o + spread if d == 1 else o
                sl = eng.sweep - cfg["sl_buffer"] if d == 1 else eng.sweep + cfg["sl_buffer"]
                risk = (entry - sl) if d == 1 else (sl - entry)
                reward = (eng.target - entry) if d == 1 else (entry - eng.target)
                if cfg["min_sweep_pct"] > 0 and (rng <= 0 or depth < rng * cfg["min_sweep_pct"] / 100.0):
                    why = "shallow sweep"
                elif not in_session(t, cfg):
                    why = "outside session"
                elif pos is not None:
                    why = "position open"
                elif cfg["max_day"] > 0 and day_count[t // 86400] >= cfg["max_day"]:
                    why = "max trades/day"
                elif cfg["max_spread"] > 0 and spread > cfg["max_spread"]:
                    why = "spread"
                elif risk <= 0:
                    why = "sl wrong side"
                elif risk < max(cfg["min_sl"], cfg["min_sl_x"] * spread):
                    why = "min sl"
                elif reward <= 0:
                    why = "target passed"
                elif cfg["min_rr"] > 0 and reward / risk < cfg["min_rr"]:
                    why = "min rr"
                if why:
                    skips[why] += 1
                else:
                    pos = dict(dir=d, entry=entry, sl=sl, tp=eng.target, risk=risk, crt=eng.id, t=t)
                    day_count[t // 86400] += 1
            cur = None

        if cur is None:
            cur = [bucket, o, h, l, c]
        else:
            cur[2] = max(cur[2], h)
            cur[3] = min(cur[3], l)
            cur[4] = c

        # ----------------------------------------------------------------
        # Stop / target inside this M1 bar (bid prices; asks = bid + spread)
        # ----------------------------------------------------------------
        if pos is not None:
            if pos["dir"] == 1:
                if o <= pos["sl"]:
                    close_pos(o, t, "sl gap")
                elif l <= pos["sl"]:
                    close_pos(pos["sl"], t, "sl")
                elif h >= pos["tp"]:
                    close_pos(pos["tp"], t, "tp")
            else:
                ao, ah, al = o + spread, h + spread, l + spread
                if ao >= pos["sl"]:
                    close_pos(ao, t, "sl gap")
                elif ah >= pos["sl"]:
                    close_pos(pos["sl"], t, "sl")
                elif al <= pos["tp"]:
                    close_pos(pos["tp"], t, "tp")

    return trades, skips


# ============================================================================
# REPORT
# ============================================================================

def stats(trades, risk_pct=0.5):
    n = len(trades)
    if n == 0:
        return dict(n=0, win=0.0, avg=0.0, total=0.0, pf=0.0, dd=0.0, ret=0.0)
    rs = [t["r"] for t in trades]
    wins = sum(r for r in rs if r > 0)
    losses = -sum(r for r in rs if r < 0)
    eq, peak, dd = 0.0, 0.0, 0.0
    for r in rs:
        eq += r
        peak = max(peak, eq)
        dd = max(dd, peak - eq)
    bal = 1.0
    for r in rs:
        bal *= 1.0 + risk_pct / 100.0 * r
    return dict(n=n, win=100.0 * sum(r > 0 for r in rs) / n, avg=sum(rs) / n, total=sum(rs),
                pf=wins / losses if losses > 0 else float("inf"), dd=dd, ret=100.0 * (bal - 1.0))


def fmt_row(label, s):
    return (f"{label:<22} {s['n']:>6} {s['win']:>6.1f}% {s['avg']:>+7.3f} {s['total']:>+9.1f} "
            f"{s['pf']:>6.2f} {s['dd']:>8.1f} {s['ret']:>+9.1f}%")


HEADER = f"{'':<22} {'trades':>6} {'win':>7} {'avg R':>7} {'total R':>9} {'PF':>6} {'max DD R':>8} {'% 0.5%/tr':>10}"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mt5", nargs="+", help="MT5 M1 bar export file(s)")
    ap.add_argument("--synthetic", type=int, help="number of random-walk M1 bars")
    ap.add_argument("--spread", type=float, default=0.0, help="spread for --synthetic (price units)")
    ap.add_argument("--tf", nargs="+", default=["M5", "M15", "M30", "H1", "H4"])
    ap.add_argument("--commission", type=float, default=0.0, help="round-turn commission per lot ($)")
    ap.add_argument("--contract", type=float, default=100.0, help="contract size (XAUUSD = 100 oz)")
    ap.add_argument("--no-filters", action="store_true", help="also run without the v1.20 filters")
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
    spreads = sorted(b[5] for b in bars)
    print(f"{src}\n{first:%Y-%m-%d} .. {last:%Y-%m-%d} | median spread {spreads[len(spreads) // 2]:.3f}\n")

    # EA v1.21 defaults
    v121 = dict(session=True, sess_start=10, sess_end=20, max_day=3, max_spread=0.50, min_sl=1.00,
                min_sl_x=4.0, min_sweep_pct=10.0, min_rr=1.0, sl_buffer=0.30, close_on_invalid=True,
                commission=args.commission, contract=args.contract)
    configs = [("filters v1.21", v121)]
    if args.no_filters:
        raw = dict(v121, session=False, max_day=0, max_spread=0.0, min_sl=0.0, min_sl_x=0.0, min_sweep_pct=0.0)
        configs.insert(0, ("no filters (v1.10)", raw))

    for name, cfg in configs:
        print(f"=== {name} ===")
        print(HEADER)
        for tf in args.tf:
            trades, skips = run(bars, tf, cfg)
            print(fmt_row(f"{tf}", stats(trades)))
            by_year = defaultdict(list)
            for t in trades:
                by_year[datetime.fromtimestamp(t["t_in"], timezone.utc).year].append(t)
            for y in sorted(by_year):
                print(fmt_row(f"  {y}", stats(by_year[y])))
        print()


if __name__ == "__main__":
    main()
