"""Walk-forward run of the Kalman volume model over an MT5 bar export.

Mirrors what the EA does live: every new day the model is re-fitted (EM) on the
previous `train_days` complete days, then filtered bar by bar through the day.
For every bar it writes the one-step forecast made BEFORE the bar closed, the
innovation (surprise) and the post-update state used for decisions at the close:
day activity, log forecasts fh1..fh4 for the next four bars and the mean
forecast volume over the next `horizon` bars.

Usage:
  python3 -I model/walkforward.py data/xauusd/XAUUSD_M15.csv.gz out.csv.gz \
      [--train-days 60] [--robust-k 3] [--session 0100-2400] [--horizon 8]
"""

import argparse
import math
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kalman_volume import KalmanVolume  # noqa: E402


def load_mt5(path):
    df = pd.read_csv(path, sep="\t")
    df.columns = [c.strip("<>").lower() for c in df.columns]
    if "time" in df.columns:
        df["dt"] = pd.to_datetime(df["date"] + " " + df["time"], format="%Y.%m.%d %H:%M:%S")
    else:
        df["dt"] = pd.to_datetime(df["date"], format="%Y.%m.%d")
    return df.drop(columns=[c for c in ("date", "time") if c in df.columns])


def build_grid(df, start_min, end_min, bin_min, min_bins):
    """Return (days, bins, y[n_days, I], obs[n_days, I], row_index[n_days, I])."""
    I = (end_min - start_min) // bin_min
    mins = df["dt"].dt.hour * 60 + df["dt"].dt.minute
    b = (mins - start_min) // bin_min
    inside = (mins >= start_min) & (b < I) & ((mins - start_min) % bin_min == 0)
    d = df["dt"].dt.normalize()
    sub = pd.DataFrame({"d": d[inside], "b": b[inside].astype(int),
                        "v": df.loc[inside, "tickvol"].astype(float), "row": df.index[inside]})
    counts = sub.groupby("d").size()
    days = counts.index[counts >= min_bins]
    sub = sub[sub["d"].isin(days)]
    day_pos = pd.Series(np.arange(len(days)), index=days)
    y = np.zeros((len(days), I))
    obs = np.zeros((len(days), I), dtype=bool)
    rows = -np.ones((len(days), I), dtype=int)
    di = day_pos[sub["d"]].to_numpy()
    bi = sub["b"].to_numpy()
    v = sub["v"].to_numpy()
    ok = v >= 1
    y[di[ok], bi[ok]] = np.log(v[ok])
    obs[di[ok], bi[ok]] = True
    rows[di, bi] = sub["row"].to_numpy()
    return days, I, y, obs, rows


def parse_session(s):
    a, b = s.split("-")
    return int(a[:2]) * 60 + int(a[2:]), int(b[:2]) * 60 + int(b[2:])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--train-days", type=int, default=60)
    ap.add_argument("--robust-k", type=float, default=3.0)
    ap.add_argument("--session", default="0100-2400")
    ap.add_argument("--bin-min", type=int, default=15)
    ap.add_argument("--min-bins", type=int, default=40)
    ap.add_argument("--horizon", type=int, default=8)
    ap.add_argument("--warm-iters", type=int, default=5)
    ap.add_argument("--cold-iters", type=int, default=30)
    a = ap.parse_args()

    df = load_mt5(a.src)
    s0, s1 = parse_session(a.session)
    days, I, Y, OBS, ROWS = build_grid(df, s0, s1, a.bin_min, a.min_bins)
    print(f"{len(days)} days x {I} bins, observed {OBS.mean():.3%}", flush=True)

    m = KalmanVolume(I, robust_k=a.robust_k)
    out = []
    t0 = time.time()
    for k in range(a.train_days, len(days)):
        y = Y[k - a.train_days:k].ravel()
        o = OBS[k - a.train_days:k].ravel()
        its = m.fit(y, o, max_iter=a.warm_iters if m.fitted else a.cold_iters,
                    tol=1e-4, warm_start=True)
        p = m.params()
        for b in range(I):
            f_prior = m.forecast_log(1)
            observed = bool(OBS[k, b])
            e, S, z = m.update(Y[k, b], observed)
            if ROWS[k, b] < 0:
                continue
            fsum = sum(math.exp(m.forecast_log(h)) for h in range(1, a.horizon + 1))
            fh = [m.forecast_log(h) for h in range(1, 5)]
            out.append((ROWS[k, b], days[k], b, f_prior, e if observed else np.nan, S, z,
                        m.day_activity(), *fh, fsum / a.horizon, its,
                        p["a_eta"], p["a_mu"], p["s_eta2"], p["s_mu2"], p["r"]))
        if (k - a.train_days) % 50 == 0:
            el = time.time() - t0
            print(f"day {k}/{len(days)} {days[k].date()} iters={its} "
                  f"a_eta={p['a_eta']:.3f} a_mu={p['a_mu']:.3f} r={p['r']:.4f} "
                  f"[{el:.0f}s]", flush=True)

    cols = ["row", "day", "bin", "f_prior", "innov", "S", "z", "activity",
            "fh1", "fh2", "fh3", "fh4", "fmeanH", "em_iters",
            "a_eta", "a_mu", "s_eta2", "s_mu2", "r"]
    res = pd.DataFrame(out, columns=cols)
    res = res.merge(df, left_on="row", right_index=True).sort_values("row")
    res.to_csv(a.out, index=False, float_format="%.6g")
    print(f"wrote {len(res)} rows to {a.out} in {time.time() - t0:.0f}s")


if __name__ == "__main__":
    main()
