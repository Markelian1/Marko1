"""Python mirror of the KalmanVolume XAUUSD EA, for research and ablation.

Bars are MT5 bid prices; longs enter at ask (= bid + spread) and exit at bid,
shorts enter at bid and exit at ask. Stops/targets are checked on each bar's
high/low; if both are touched in the same bar the stop is assumed first.
Results are in R (multiples of the initial stop distance) so that periods with
different gold prices and volatility are comparable.

Modules (each can be switched on/off, as in the EA):
  A  volume-surprise filter: standardized innovation of the signal bar
     z = log(actual/forecast) / sqrt(S) compared with a_min_z (and a_max_z)
  B  VWAP-style sliced entry: the position is built over b_slices bars, sized by
     the dynamic volume forecast (eq. 41 of the paper)
  C  volume regime: day-activity band from eta, and stop distance scaled by
     (forecast volume next H bars / volume of the last 14 bars) ** c_beta
"""

from dataclasses import dataclass, field, replace
from pathlib import Path

import numpy as np
import pandas as pd

POINT = 0.01


@dataclass
class Config:
    trigger: str = "donchian"        # donchian | momentum | fade
    dc_len: int = 20
    body_atr: float = 0.5            # momentum/fade: min |close-open| in ATR
    trade_start: int = 900           # server time HHMM, entries allowed from
    trade_end: int = 2000            # ... until (exclusive)
    flat_at: int = 2330              # close everything at/after this time
    sl_atr: float = 1.5
    rr: float = 2.0
    max_hold: int = 16               # bars
    max_trades_day: int = 2
    cost_points: float = 0.0         # extra round-trip cost (commission/slippage)
    module_a: bool = False
    a_min_z: float = 2.0             # take signals only when z >= a_min_z ...
    a_max_z: float = 99.0            # ... and z <= a_max_z
    module_b: bool = False
    b_slices: int = 3
    module_c: bool = False
    c_act_min: float = 0.0
    c_act_max: float = 99.0
    c_beta: float = 0.5
    c_lo: float = 0.6
    c_hi: float = 1.8
    c_horizon_note: str = field(default="fmeanH = mean forecast of next 8 bars", repr=False)
    # EA v1.00 kept executing pending B slices after SL/TP had closed the position
    # (re-entering when price came back inside SL..TP). Only for reproducing that run.
    emulate_v100_reentry: bool = False


def prepare(path):
    d = pd.read_csv(path, parse_dates=["dt", "day"]).sort_values("dt").reset_index(drop=True)
    tr = np.maximum(d.high - d.low, np.maximum((d.high - d.close.shift()).abs(),
                                               (d.low - d.close.shift()).abs()))
    d["atr"] = tr.rolling(14).mean()  # = MT5 iATR (simple average of true range)
    d["ratio"] = np.exp(d.innov)
    d["z"] = d.innov / np.sqrt(d.S)
    d["vol14"] = d.tickvol.rolling(14).mean()
    d["hhmm"] = d.dt.dt.hour * 100 + d.dt.dt.minute
    d["date"] = d.dt.dt.normalize()
    return d


def run(d, cfg):
    o, h, l, c = (d[x].to_numpy(float) for x in ("open", "high", "low", "close"))
    spr = d.spread.to_numpy(float) * POINT
    atr, zs = d.atr.to_numpy(), d.z.to_numpy()
    act, fmean, vol14 = d.activity.to_numpy(), d.fmeanH.to_numpy(), d.vol14.to_numpy()
    fh = d[["fh1", "fh2", "fh3", "fh4"]].to_numpy() if "fh1" in d else None
    hhmm, date = d.hhmm.to_numpy(), d.date.to_numpy()
    dch = d.high.rolling(cfg.dc_len).max().shift(1).to_numpy()
    dcl = d.low.rolling(cfg.dc_len).min().shift(1).to_numpy()
    n = len(d)
    cost = cfg.cost_points * POINT

    trades = []
    pos = None            # dict while a trade is live
    day_count, cur_day = 0, None
    for j in range(n):
        if date[j] != cur_day:
            cur_day, day_count = date[j], 0
        if pos is not None:
            dr = pos["dir"]
            # 1) pending slice executes at this bar's open
            if pos["pending"] and pos["next_bar"] == j:
                px_bid = o[j]
                live_ok = (px_bid > pos["sl"] and px_bid < pos["tp"]) if dr > 0 else \
                          (px_bid + spr[j] < pos["sl"] and px_bid + spr[j] > pos["tp"])
                if live_ok:
                    w = pos["pending"].pop(0)
                    if cfg.module_b and fh is not None and pos["pending"]:
                        # eq. 41: slice = remaining * V(next) / sum V(remaining bins)
                        k = min(len(pos["pending"]) + 1, fh.shape[1])
                        f = np.exp(fh[j - 1, :k])
                        w = (1.0 - pos["filled"]) * f[0] / f.sum()
                    elif not pos["pending"]:
                        w = 1.0 - pos["filled"]
                    entry = px_bid + spr[j] if dr > 0 else px_bid
                    pos["fills"].append((w, entry))
                    pos["filled"] += w
                    pos["next_bar"] = j + 1
                else:
                    pos["pending"] = []
            # 2) exits on this bar
            if pos["fills"]:
                exit_px, reason = None, None
                if dr > 0:
                    if l[j] <= pos["sl"]:
                        exit_px, reason = min(o[j], pos["sl"]) if o[j] < pos["sl"] else pos["sl"], "SL"
                    elif h[j] >= pos["tp"]:
                        exit_px, reason = max(o[j], pos["tp"]) if o[j] > pos["tp"] else pos["tp"], "TP"
                else:
                    ah, al, ao = h[j] + spr[j], l[j] + spr[j], o[j] + spr[j]
                    if ah >= pos["sl"]:
                        exit_px, reason = max(ao, pos["sl"]) if ao > pos["sl"] else pos["sl"], "SL"
                    elif al <= pos["tp"]:
                        exit_px, reason = min(ao, pos["tp"]) if ao < pos["tp"] else pos["tp"], "TP"
                if reason is None and (j - pos["bar"] >= cfg.max_hold or hhmm[j] >= cfg.flat_at
                                       or (j + 1 < n and date[j + 1] != date[j])):
                    exit_px = c[j] if dr > 0 else c[j] + spr[j]
                    reason = "time"
                if reason is not None:
                    filled = sum(w for w, _ in pos["fills"])
                    pnl = sum(w * dr * (exit_px - e) for w, e in pos["fills"]) - cost * filled
                    trades.append({"dt": d.dt.iat[pos["bar"]], "dir": dr, "R": pnl / pos["risk"],
                                   "filled": filled, "n_fills": len(pos["fills"]),
                                   "reason": reason, "bars": j - pos["bar"],
                                   "risk_pts": pos["risk"] / POINT})
                    if cfg.emulate_v100_reentry and pos["pending"]:
                        pos["fills"], pos["next_bar"] = [], j + 1
                    else:
                        pos = None
            elif not pos["pending"]:
                pos = None
        # 3) signal at the close of bar j
        if pos is not None or day_count >= cfg.max_trades_day or j + 1 >= n:
            continue
        if not (cfg.trade_start <= hhmm[j] < cfg.trade_end) or not np.isfinite(atr[j]):
            continue
        body = c[j] - o[j]
        if cfg.trigger == "donchian":
            if not np.isfinite(dch[j]):
                continue
            sig = 1 if c[j] > dch[j] else (-1 if c[j] < dcl[j] else 0)
        else:
            sig = int(np.sign(body)) if abs(body) >= cfg.body_atr * atr[j] else 0
            if cfg.trigger == "fade":
                sig = -sig
        if sig == 0:
            continue
        if cfg.module_a and not (np.isfinite(zs[j]) and cfg.a_min_z <= zs[j] <= cfg.a_max_z):
            continue
        adj = 1.0
        if cfg.module_c:
            if not (cfg.c_act_min <= act[j] <= cfg.c_act_max):
                continue
            if np.isfinite(vol14[j]) and vol14[j] > 0:
                adj = float(np.clip((fmean[j] / vol14[j]) ** cfg.c_beta, cfg.c_lo, cfg.c_hi))
        dist = cfg.sl_atr * atr[j] * adj
        ref = c[j] + spr[j] if sig > 0 else c[j]
        slices = cfg.b_slices if cfg.module_b else 1
        pos = {"dir": sig, "bar": j, "risk": dist, "sl": ref - sig * dist,
               "tp": ref + sig * cfg.rr * dist, "pending": [1.0 / slices] * slices,
               "next_bar": j + 1, "fills": [], "filled": 0.0}
        day_count += 1
    return pd.DataFrame(trades)


def stats(t, years=None):
    if t.empty:
        return {"trades": 0}
    r = t.R.to_numpy()
    eq = np.cumsum(r)
    dd = np.max(np.maximum.accumulate(eq) - eq)
    wins, losses = r[r > 0].sum(), -r[r < 0].sum()
    yrs = years or max((t.dt.max() - t.dt.min()).days / 365.25, 0.25)
    growth = np.prod(1 + 0.01 * r)
    return {"trades": len(r), "win%": 100 * (r > 0).mean(), "avgR": r.mean(),
            "PF": wins / losses if losses > 0 else np.inf, "totR": r.sum(),
            "maxDD_R": dd, "R/yr": r.sum() / yrs,
            "t-stat": r.mean() / (r.std(ddof=1) / np.sqrt(len(r))) if len(r) > 2 else np.nan,
            "1%risk_x": growth}


def split_stats(t, split):
    out = {}
    for name, part in (("IS", t[t.dt < split]), ("OOS", t[t.dt >= split])):
        for k, v in stats(part).items():
            out[f"{name}_{k}"] = v
    return out


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    d = prepare(root / "data/derived/m15_rkf.csv.gz")
    cfg = Config()
    print(stats(run(d, cfg)))
    print(stats(run(d, replace(cfg, module_a=True))))
