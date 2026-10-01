#!/usr/bin/env python3
"""Liquidity engine without a clock: swing highs / lows are the liquidity
(stops rest above old highs and below old lows), a sweep is price trading
through one, the setup is the PRO24 pattern on top of it:

  - liquidity: H1 (or H4) swing highs / lows, pivot strength L, alive for
    max_age hours or until taken
  - sweep: an entry-TF bar trades beyond a live level; the bar with the
    sweep extreme is the order block (its low for sells, high for buys)
  - signal: a later entry-TF close back through the order block and back
    under (over) the swept level, within sweep_h hours
  - sniper entry: limit at the order-block level for retest_h hours,
    cancelled if price makes a new extreme first
  - SL beyond the sweep + 0.30, TP rr, out after max_hold hours,
    Friday close 16:00 NY, no entry Friday after 12:00 NY
  - filters: daily trend (close vs 50-day average), optional sweep-bar
    tick volume and volume-profile zone (high-volume price area)

  python3 liq_lab.py      (from backtest/, needs ../data exports)
"""
import sys
sys.path.insert(0, ".")
from collections import defaultdict
from datetime import datetime, timezone

from crt_backtest import load_mt5

DAY, NY = 86400, 7 * 3600


def load_vol(path):
    out = {}
    for line in open(path, encoding="utf-8-sig"):
        p = line.split("\t")
        if p[0][:1].isdigit():
            t = int(datetime.strptime(p[0] + " " + p[1], "%Y.%m.%d %H:%M:%S").replace(tzinfo=timezone.utc).timestamp())
            out[t] = float(p[6])
    return out


def agg(bars, sec):
    out, idx = [], {}
    for t, o, h, l, c, sp in bars:
        k = t - t % sec
        if out and out[-1][0] == k:
            b = out[-1]
            out[-1] = (k, b[1], max(b[2], h), min(b[3], l), c)
        else:
            out.append((k, o, h, l, c))
    return out


DEFAULT = dict(swing_tf=3600, L=3, max_age=72, tf=900, sweep_h=4, retest_h=4, rr=2.0, sl_buffer=0.30,
               max_hold=8, trend=True, sma=50, min_sl=1.0, min_sl_x=4.0, max_spread=0.55,
               sweep_vol=0.0, zone=0.0, zone_days=5, pd24=False, rolling_h=0)


def run_liq(bars, cfg, vols=None):
    cfg = dict(DEFAULT, **cfg)
    tf = cfg["tf"]
    ent = agg(bars, tf)
    sw = agg(bars, cfg["swing_tf"])
    d1 = agg(bars, DAY)
    # daily trend by server day: previous close vs its sma-day average
    trend, closes = {}, []
    for b in d1:
        n = cfg["sma"]
        trend[b[0]] = 0 if len(closes) < n else (1 if closes[-1] > sum(closes[-n:]) / n else 2)
        closes.append(b[4])
    # swing levels, keyed by the time they become known (pivot bar + L bars)
    L = cfg["L"]
    known = defaultdict(list)          # time known -> [(dir, price)]
    for i in range(L, len(sw) - L):
        h, l = sw[i][2], sw[i][3]
        if h > max(x[2] for x in sw[i - L:i]) and h >= max(x[2] for x in sw[i + 1:i + L + 1]):
            known[sw[i + L][0] + cfg["swing_tf"]].append((2, h))
        if l < min(x[3] for x in sw[i - L:i]) and l <= min(x[3] for x in sw[i + 1:i + L + 1]):
            known[sw[i + L][0] + cfg["swing_tf"]].append((1, l))
    # tick volume per entry-TF bar and a 5-day average
    tv = defaultdict(float)
    for t, v in (vols or {}).items():
        tv[t - t % tf] += v

    levels = []                        # [dir, price, born]
    sweep = {1: None, 2: None}         # dir of the trade -> state
    pending = pos = None
    trades = []
    vol_hist, prof = [], []            # recent bar volumes; (close, volume) for the profile
    ent_i = 0
    cur = None

    def close_trade(p, price, t, why):
        r = (price - p["entry"]) / p["risk"] if p["dir"] == 1 else (p["entry"] - price) / p["risk"]
        trades.append(dict(p, r=r, t_out=t, why=why))

    def in_zone(price):
        # high-volume price area of the last zone_days: bins holding the top `zone` share of the volume
        if not prof:
            return True
        lo = min(p for p, v in prof)
        hi = max(p for p, v in prof)
        width = max((hi - lo) / 40.0, 0.5)
        bins = defaultdict(float)
        for p, v in prof:
            bins[int((p - lo) / width)] += v
        total = sum(bins.values())
        acc, keep = 0.0, set()
        for b, v in sorted(bins.items(), key=lambda kv: -kv[1]):
            if acc >= cfg["zone"] * total:
                break
            keep.add(b)
            acc += v
        return int((price - lo) / width) in keep

    for bar in bars:
        t, o, h, l, c, sp = bar
        k = t - t % tf
        if cur is not None and k != cur:
            # ---- an entry-TF bar closed --------------------------------
            while ent_i < len(ent) and ent[ent_i][0] < cur:
                ent_i += 1
            b = ent[ent_i]
            bt, bo, bh, bl, bc = b
            close_t = bt + tf
            for kt in [x for x in known if x <= close_t]:
                for d, p in known.pop(kt):
                    levels.append([d, p, kt])
            levels = [x for x in levels if close_t - x[2] <= cfg["max_age"] * 3600]
            if cfg["rolling_h"]:
                # the liquidity is simply the high / low of the last rolling_h hours (no clock alignment)
                win = [x for x in ent[max(0, ent_i - int(cfg["rolling_h"] * 3600 / tf)):ent_i]]
                levels = [[2, max(x[2] for x in win), bt], [1, min(x[3] for x in win), bt]] if len(win) >= 4 else []
            day = t - t % DAY
            tr = trend.get(day, 0) if cfg["trend"] else 3
            avg_v = sum(vol_hist) / len(vol_hist) if vol_hist else 0.0
            # signals first (an engulfing bar that also makes a new extreme still counts)
            for d in (2, 1):
                s = sweep[d]
                if s is None:
                    continue
                if close_t - s["start"] > cfg["sweep_h"] * 3600:
                    sweep[d] = None
                    continue
                sig = bt > s["ob_t"] and ((d == 2 and bc < s["ob"] and bc < s["level"]) or
                                          (d == 1 and bc > s["ob"] and bc > s["level"]))
                if not sig:
                    continue
                ext = max(s["ext"], bh) if d == 2 else min(s["ext"], bl)
                ok = tr & d
                if ok and cfg["sweep_vol"] and avg_v > 0 and s["vol"] < cfg["sweep_vol"] * avg_v:
                    ok = False
                if ok and cfg["zone"] and not s["zone"]:
                    ok = False
                if ok and cfg["pd24"] and prof:
                    recent = [p for p, v in prof[-int(DAY / tf):]]
                    mid = (max(recent) + min(recent)) / 2
                    ok = (d == 2 and bc > mid) or (d == 1 and bc < mid)
                if ok and pending is None and pos is None:
                    pending = dict(dir=d, level=s["ob"], ext=ext, expires=close_t + cfg["retest_h"] * 3600)
                sweep[d] = None
            # sweeps of live levels
            hit_hi = [x for x in levels if x[0] == 2 and bh > x[1]]
            hit_lo = [x for x in levels if x[0] == 1 and bl < x[1]]
            if hit_hi or (sweep[2] and bh > sweep[2]["ext"]):
                s = sweep[2]
                lvl = max([x[1] for x in hit_hi], default=s["level"] if s else bh)
                if s is None:
                    sweep[2] = dict(start=bt, level=lvl, ext=bh, ob=bl, ob_t=bt, vol=tv[bt], zone=in_zone(lvl))
                else:
                    s.update(level=max(s["level"], lvl), ext=bh, ob=bl, ob_t=bt, vol=max(s["vol"], tv[bt]))
            if hit_lo or (sweep[1] and bl < sweep[1]["ext"]):
                s = sweep[1]
                lvl = min([x[1] for x in hit_lo], default=s["level"] if s else bl)
                if s is None:
                    sweep[1] = dict(start=bt, level=lvl, ext=bl, ob=bh, ob_t=bt, vol=tv[bt], zone=in_zone(lvl))
                else:
                    s.update(level=min(s["level"], lvl), ext=bl, ob=bh, ob_t=bt, vol=max(s["vol"], tv[bt]))
            levels = [x for x in levels if not ((x[0] == 2 and bh > x[1]) or (x[0] == 1 and bl < x[1]))]
            vol_hist.append(tv[bt])
            prof.append((bc, tv[bt] or 1.0))
            n_keep = int(cfg["zone_days"] * DAY / tf)
            if len(vol_hist) > n_keep:
                vol_hist.pop(0)
            if len(prof) > n_keep:
                prof.pop(0)
        cur = k

        ny = t - NY
        wd = (ny // DAY + 3) % 7
        mins = (ny % DAY) // 60
        # ---- retest limit ------------------------------------------------
        if pending is not None and pos is None:
            pd_ = pending
            if t > pd_["expires"]:
                pending = None
            elif (pd_["dir"] == 2 and h + sp > pd_["ext"]) or (pd_["dir"] == 1 and l < pd_["ext"]):
                pending = None
            elif (pd_["dir"] == 2 and h >= pd_["level"]) or (pd_["dir"] == 1 and l + sp <= pd_["level"]):
                pending = None
                d = pd_["dir"]
                fill = max(o, pd_["level"]) if d == 2 else min(o + sp, pd_["level"])
                sl = pd_["ext"] + cfg["sl_buffer"] if d == 2 else pd_["ext"] - cfg["sl_buffer"]
                risk = sl - fill if d == 2 else fill - sl
                if (sp <= cfg["max_spread"] and risk >= max(cfg["min_sl"], cfg["min_sl_x"] * sp)
                        and not (wd == 4 and mins >= 12 * 60)):
                    tp = fill - cfg["rr"] * risk if d == 2 else fill + cfg["rr"] * risk
                    pos = dict(dir=d, entry=fill, sl=sl, tp=tp, risk=risk, t_in=t, fresh=True)
        if pos is None:
            continue
        # ---- exits ---------------------------------------------------------
        if (wd == 4 and mins >= 16 * 60) or t - pos["t_in"] >= cfg["max_hold"] * 3600:
            close_trade(pos, o if pos["dir"] == 1 else o + sp, t, "time")
            pos = None
            continue
        fresh = pos.pop("fresh", False)
        if pos["dir"] == 1:
            if l <= pos["sl"]:
                close_trade(pos, pos["sl"], t, "SL"); pos = None
            elif h >= pos["tp"] and not fresh:
                close_trade(pos, pos["tp"], t, "TP"); pos = None
        else:
            if h + sp >= pos["sl"]:
                close_trade(pos, pos["sl"], t, "SL"); pos = None
            elif l + sp <= pos["tp"] and not fresh:
                close_trade(pos, pos["tp"], t, "TP"); pos = None
    return trades
