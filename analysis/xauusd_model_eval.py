"""Sa mire e parashikon modeli Kalman tick volume te XAUUSD? (out-of-sample)

Krahason parashikimet walk-forward (model/walkforward.py, rifitim cdo dite me
60 ditet e meparshme) me benchmark-et e artikullit dhe me dy benchmark dinamike
te thjeshta, qe artikulli nuk i ka.

  python3 -I analysis/xauusd_model_eval.py
"""

import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent
DER = ROOT.parent / "data/derived"
FIG = ROOT / "figures"
sys.path.insert(0, str(ROOT.parent / "model"))
from walkforward import build_grid, load_mt5  # noqa: E402

I = 92


def mape(actual, fc):
    m = np.isfinite(fc) & (actual > 0)
    return np.abs(actual[m] - fc[m]) / actual[m]


def main():
    rkf = pd.read_csv(DER / "m15_rkf.csv.gz", parse_dates=["dt", "day"])
    kf = pd.read_csv(DER / "m15_kf.csv.gz", parse_dates=["dt", "day"])
    df = load_mt5(ROOT.parent / "data/xauusd/XAUUSD_M15.csv.gz")
    days, _, Y, OBS, ROWS = build_grid(df, 60, 1440, 15, 40)
    V = np.where(OBS, np.exp(Y), np.nan)
    day_pos = {d: k for k, d in enumerate(days)}

    e = rkf[["row", "day", "bin", "tickvol", "f_prior", "innov", "z"]].copy()
    e = e.merge(kf[["row", "f_prior"]].rename(columns={"f_prior": "f_kf"}), on="row")
    k = e["day"].map(day_pos).to_numpy()
    b = e["bin"].to_numpy()
    act = e["tickvol"].to_numpy(float)

    fc = {"RKF dinamik": np.exp(e["f_prior"].to_numpy()),
          "KF dinamik": np.exp(e["f_kf"].to_numpy())}
    # RM statik (artikulli): mesatarja e te njejtit bin ne N ditet e meparshme
    cum = np.cumsum(np.nan_to_num(V), axis=0)
    cnt = np.cumsum(np.isfinite(V), axis=0)

    def rm_fc(kk, bb, n):
        out = np.full(len(kk), np.nan)
        ok = (kk >= n) & (bb >= 0)
        hi, lo, bo = kk[ok] - 1, kk[ok] - n - 1, bb[ok]
        s = cum[hi, bo] - np.where(lo >= 0, cum[np.maximum(lo, 0), bo], 0)
        c = cnt[hi, bo] - np.where(lo >= 0, cnt[np.maximum(lo, 0), bo], 0)
        out[ok] = np.where(c > 0, s / np.maximum(c, 1), np.nan)
        return out

    for n in (5, 10, 20, 40):
        fc[f"RM statik {n}d"] = rm_fc(k, b, n)
    # benchmark dinamik naiv: vellimi i barit te meparshem (brenda dites)
    prev = np.full(len(e), np.nan)
    has_prev = b > 0
    prev[has_prev] = V[k[has_prev], b[has_prev] - 1]
    fc["Naiv: bari i meparshem"] = prev
    # naiv me sezonalitet: bari i meparshem * profili RM20(b) / RM20(b-1)
    fc["Naiv sezonal"] = prev * fc["RM statik 20d"] / rm_fc(k, b - 1, 20)

    print("=" * 78)
    print("MAPE out-of-sample e tick volume XAUUSD M15 "
          f"({e.day.min().date()} .. {e.day.max().date()}, {len(e)} bare)")
    print("=" * 78)
    rows = []
    for name, f in fc.items():
        err = mape(act, f)
        rows.append((name, err.mean(), np.median(err), len(err)))
    tab = pd.DataFrame(rows, columns=["modeli", "MAPE mesatare", "MAPE mediane", "n"])
    best_rm = tab[tab.modeli.str.startswith("RM")].sort_values("MAPE mesatare").iloc[0]
    print(tab.to_string(index=False, float_format=lambda x: f"{x:.3f}"))
    r = tab.set_index("modeli")["MAPE mesatare"]
    print(f"\n  RKF dinamik vs RM me i mire ({best_rm.modeli}): "
          f"{100 * (best_rm['MAPE mesatare'] - r['RKF dinamik']) / best_rm['MAPE mesatare']:.1f}% "
          f"permiresim (artikulli: 64%)")
    print(f"  RKF dinamik vs naiv sezonal: "
          f"{100 * (r['Naiv sezonal'] - r['RKF dinamik']) / r['Naiv sezonal']:.1f}%")
    print(f"  RKF vs KF: {100 * (r['KF dinamik'] - r['RKF dinamik']) / r['KF dinamik']:.2f}%")
    print(f"  Bare ku filtri robust preu outlier (z != 0): {(e.z != 0).mean():.1%}")

    e["year"] = e.day.dt.year
    print("\n  MAPE mesatare sipas vitit:")
    for y, g in e.groupby("year"):
        ii = g.index.to_numpy()
        vals = {n: mape(act[ii], fc[n][ii]).mean() for n in ("RKF dinamik", best_rm.modeli, "Naiv sezonal")}
        print(f"    {y}: " + "  ".join(f"{n} {v:.3f}" for n, v in vals.items()))

    # kalibrimi: a jane gabimet log simetrike? -> perdorim exp(f) si mediane
    innov = e["innov"].dropna()
    print(f"\n  Inovacioni log(aktual/parashikim): mesatare {innov.mean():+.3f}, "
          f"std {innov.std():.3f}, p5 {innov.quantile(.05):+.2f}, p95 {innov.quantile(.95):+.2f}")
    print(f"  -> vellimi real > 1.5x parashikimit ne {(innov > np.log(1.5)).mean():.1%} te bareve, "
          f"> 2x ne {(innov > np.log(2)).mean():.1%}")

    fig, axes = plt.subplots(1, 2, figsize=(11, 4))
    order = ["RKF dinamik", "KF dinamik", "Naiv sezonal", "Naiv: bari i meparshem",
             best_rm.modeli]
    vals = [r[o] for o in order]
    cols = ["#2563eb", "#60a5fa", "#f59e0b", "#fbbf24", "#9ca3af"]
    axes[0].barh(order[::-1], vals[::-1], color=cols[::-1])
    for i, v in enumerate(vals[::-1]):
        axes[0].text(v + 0.003, i, f"{v:.3f}", va="center", fontsize=8)
    axes[0].set_xlabel("MAPE mesatare (me e ulet = me mire)")
    axes[0].set_title("Parashikimi i tick volume, XAUUSD M15")
    axes[0].grid(axis="x", alpha=0.3)
    sample = e[e.day == e.day.iloc[-92 * 10]]
    hrs = 1 + sample.bin * 0.25
    axes[1].plot(hrs, sample.tickvol, color="#111827", lw=1.2, label="aktual")
    axes[1].plot(hrs, np.exp(sample.f_prior), color="#2563eb", lw=1.2, label="RKF dinamik")
    axes[1].plot(hrs, fc[best_rm.modeli][sample.index], color="#9ca3af", lw=1.2, ls="--",
                 label=best_rm.modeli)
    axes[1].set_title(f"Shembull: {sample.day.iloc[0].date()}")
    axes[1].set_xlabel("Ora e serverit")
    axes[1].legend(frameon=False, fontsize=8)
    axes[1].grid(alpha=0.3)
    fig.tight_layout()
    fig.savefig(FIG / "x5_model_forecast.png", dpi=130)
    plt.close(fig)


if __name__ == "__main__":
    main()
