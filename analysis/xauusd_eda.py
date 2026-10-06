"""Analiza e te dhenave XAUUSD (eksport MT5) para ndertimit te EA-se.

Kontrollon nese supozimet e artikullit (Chen, Feng & Palomar) vlejne per
tick volume te XAUUSD:  log-normaliteti, sezonaliteti brenda dites, komponenti
ditor, dinamika brenda dites, dhe lidhja vellim-volatilitet.

  python3 -I analysis/xauusd_eda.py data/xauusd/XAUUSD_M15.csv.gz
"""

import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.dates
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy import stats

ROOT = Path(__file__).resolve().parent
FIG = ROOT / "figures"
FIG.mkdir(exist_ok=True)
sys.path.insert(0, str(ROOT.parent / "model"))
from walkforward import build_grid, load_mt5  # noqa: E402

C1, C2, C3 = "#2563eb", "#dc2626", "#9ca3af"
SESSION_MARKS = {  # ora e serverit (GMT+2/+3, NY 17:00 = 00:00)
    "Tokio": 3.0, "Londer": 10.0, "Te dhena SHBA 8:30 ET": 15.5,
    "NY hapje 9:30 ET": 16.5, "Londer fix 15:00": 17.0,
}


def section(t):
    print("\n" + "=" * 78 + f"\n{t}\n" + "=" * 78)


def structure(df):
    section("1. Struktura e te dhenave")
    d = df["dt"].dt.normalize()
    bpd = df.groupby(d).size()
    print(f"  Bare: {len(df)}  nga {df.dt.min()}  deri {df.dt.max()}")
    print(f"  Dite: {len(bpd)}   dite me 92 bare (01:00-23:45): {(bpd == 92).sum()}")
    print(f"  VOL real = 0 ne te gjitha bare -> perdoret TICK VOLUME")
    first = df.groupby(d)["dt"].min().dt.strftime("%H:%M").value_counts().head(3).to_dict()
    last = df.groupby(d)["dt"].max().dt.strftime("%H:%M").value_counts().head(4).to_dict()
    print(f"  Bari i pare i dites: {first}")
    print(f"  Bari i fundit:       {last}  (21:15/21:30 = mbyllje e hershme festash SHBA)")


def distribution(df):
    section("2. Shperndarja: vellimi vs log-vellimi")
    v = df["tickvol"].astype(float)
    lv = np.log(v[v >= 1])
    for name, x in (("tick volume", v), ("log tick volume", lv)):
        print(f"  {name:16s} skew={stats.skew(x):+.2f}  kurtosis={stats.kurtosis(x):+.2f}")
    fig, axes = plt.subplots(1, 2, figsize=(10, 4))
    for ax, x, title in ((axes[0], v, "Tick volume"), (axes[1], lv, "Log tick volume")):
        (osm, osr), (slope, icpt, _) = stats.probplot(x.sample(20000, random_state=0), dist="norm")
        ax.scatter(osm, osr, s=3, color=C1, alpha=0.4)
        ax.plot(osm, slope * osm + icpt, color=C2, lw=1)
        ax.set_title(f"Q-Q normal: {title}")
        ax.set_xlabel("Kuantilet teorike")
        ax.grid(alpha=0.3)
    axes[0].set_ylabel("Kuantilet e kampionit")
    fig.suptitle("XAUUSD M15: log-vellimi eshte shume me afer normales (si Fig. 1 e artikullit)")
    fig.tight_layout()
    fig.savefig(FIG / "x1_qq_tickvolume.png", dpi=130)
    plt.close(fig)


def seasonality(df, Y, OBS, I):
    section("3. Sezonaliteti brenda dites (forma e phi)")
    ym = np.where(OBS, Y, np.nan)
    med = np.nanmedian(ym, axis=0)
    hours = 1.0 + np.arange(I) * 0.25
    top = np.argsort(med)[::-1][:5]
    low = np.argsort(med)[:5]
    fmt = lambda b: f"{int(hours[b]):02d}:{int(round((hours[b] % 1) * 60)):02d}"
    print("  Bin-et me vellim me te larte:", ", ".join(f"{fmt(b)} ({np.exp(med[b]):.0f})" for b in top))
    print("  Bin-et me vellim me te ulet: ", ", ".join(f"{fmt(b)} ({np.exp(med[b]):.0f})" for b in low))
    print(f"  Raporti max/min i vellimit tipik: {np.exp(med.max() - med.min()):.1f}x")
    sp = df.assign(b=((df.dt.dt.hour * 60 + df.dt.dt.minute - 60) // 15))
    sp = sp[(sp.b >= 0) & (sp.b < I)].groupby("b")["spread"]
    sp_med, sp_95 = sp.median(), sp.quantile(0.95)
    print(f"  Spread median (pike): min {sp_med.min():.0f}, max {sp_med.max():.0f} "
          f"ne {fmt(int(sp_med.idxmax()))}; p95 max {sp_95.max():.0f} ne {fmt(int(sp_95.idxmax()))}")

    fig, axes = plt.subplots(2, 1, figsize=(11, 6), sharex=True,
                             gridspec_kw={"height_ratios": [2, 1]})
    q25, q75 = np.nanpercentile(ym, 25, axis=0), np.nanpercentile(ym, 75, axis=0)
    axes[0].fill_between(hours, np.exp(q25), np.exp(q75), color=C1, alpha=0.15, label="25-75%")
    axes[0].plot(hours, np.exp(med), color=C1, lw=2, label="mediana")
    axes[0].set_ylabel("Tick volume / 15 min")
    axes[0].set_title("XAUUSD M15: profili i vellimit brenda dites (ora e serverit)")
    for name, h in SESSION_MARKS.items():
        for ax in axes:
            ax.axvline(h, color=C3, ls=":", lw=1)
        axes[0].text(h + 0.1, axes[0].get_ylim()[1] * 0.92, name, fontsize=7, rotation=90,
                     va="top", color="#4b5563")
    axes[0].legend(frameon=False, loc="upper left")
    axes[0].grid(alpha=0.3)
    axes[1].plot(1.0 + sp_med.index * 0.25, sp_med.values, color=C2, label="spread median")
    axes[1].plot(1.0 + sp_95.index * 0.25, sp_95.values, color=C2, ls="--", lw=1, label="spread p95")
    axes[1].set_ylabel("Spread (pike)")
    axes[1].set_xlabel("Ora e serverit")
    axes[1].legend(frameon=False)
    axes[1].grid(alpha=0.3)
    axes[1].set_xticks(range(1, 25, 2))
    fig.tight_layout()
    fig.savefig(FIG / "x2_intraday_profile.png", dpi=130)
    plt.close(fig)
    return med


def daily_component(df, Y, OBS, days, med):
    section("4. Komponenti ditor (eta) dhe dinamika brenda dites (mu)")
    ym = np.where(OBS, Y, np.nan)
    resid = ym - med[None, :]
    day_level = np.nanmean(resid, axis=1)
    ac_day = [pd.Series(day_level).autocorr(l) for l in (1, 2, 5, 10, 20)]
    print("  Autokorrelacioni i nivelit ditor (lag 1,2,5,10,20 dite):",
          ", ".join(f"{a:.2f}" for a in ac_day))
    intra = resid - day_level[:, None]
    flat = pd.Series(intra.ravel())
    ac_in = [flat.autocorr(l) for l in (1, 2, 4, 8, 16)]
    print("  Autokorrelacioni brenda dites pas heqjes se nivelit ditor dhe sezonalitetit")
    print("    (lag 1,2,4,8,16 bare):", ", ".join(f"{a:.2f}" for a in ac_in))
    var_tot = np.nanvar(ym - np.nanmean(ym))
    var_season = np.nanvar(np.broadcast_to(med, ym.shape)[OBS])
    var_day = np.nanvar(day_level)
    var_intra = np.nanvar(intra)
    print(f"  Ndarja e variances se log-vellimit: sezonaliteti {var_season / var_tot:.0%}, "
          f"niveli ditor {var_day / var_tot:.0%}, mbetja brenda dites {var_intra / var_tot:.0%}")
    dow = pd.Series(day_level, index=days).groupby(days.dayofweek).mean()
    names = ["E hene", "E marte", "E merkure", "E enjte", "E premte", "E shtune"]
    print("  Niveli ditor sipas dites se javes (exp, 1.00 = mesatare):",
          ", ".join(f"{names[i]} {np.exp(v):.2f}" for i, v in dow.items()))

    fig, axes = plt.subplots(1, 2, figsize=(11, 3.8))
    s = pd.Series(np.exp(day_level), index=days)
    axes[0].plot(s.index, s.values, color=C3, lw=0.6)
    axes[0].plot(s.index, s.rolling(20).mean(), color=C1, lw=1.5, label="mesatare 20 dite")
    axes[0].set_yscale("log")
    axes[0].set_title("Niveli ditor i vellimit (1 = dite tipike)")
    axes[0].xaxis.set_major_formatter(matplotlib.dates.DateFormatter("%Y"))
    axes[0].legend(frameon=False)
    axes[0].grid(alpha=0.3)
    lags = np.arange(1, 25)
    axes[1].bar(lags, [flat.autocorr(l) for l in lags], color=C1)
    axes[1].set_title("Autokorrelacioni brenda dites (mu)")
    axes[1].set_xlabel("Lag (bare 15 min)")
    axes[1].grid(alpha=0.3)
    fig.tight_layout()
    fig.savefig(FIG / "x3_daily_and_intraday.png", dpi=130)
    plt.close(fig)


def volume_volatility(df):
    section("5. Lidhja vellim - volatilitet (baze per modulin C)")
    d = df[(df.tickvol >= 1) & (df.high > df.low)]
    lv, lr = np.log(d.tickvol.astype(float)), np.log(d.high - d.low)
    slope, icpt, r, _, _ = stats.linregress(lv, lr)
    print(f"  log(range) = {icpt:.2f} + {slope:.2f} * log(tick volume)   R^2 = {r * r:.2f}")
    print("  -> range ~ V^%.2f  (hipoteza 'mixture of distributions' jep ~0.5)" % slope)
    fig, ax = plt.subplots(figsize=(6, 4.5))
    hb = ax.hexbin(lv, lr, gridsize=60, cmap="Blues", mincnt=5, bins="log")
    xs = np.linspace(lv.min(), lv.max(), 10)
    ax.plot(xs, icpt + slope * xs, color=C2, label=f"pjerresia {slope:.2f}")
    ax.set_xlabel("log(tick volume)")
    ax.set_ylabel("log(high - low)")
    ax.set_title("Vellimi me i larte -> bare me te gjera")
    ax.legend(frameon=False)
    fig.colorbar(hb, ax=ax, label="log(numri)")
    fig.tight_layout()
    fig.savefig(FIG / "x4_volume_volatility.png", dpi=130)
    plt.close(fig)


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else str(ROOT.parent / "data/xauusd/XAUUSD_M15.csv.gz")
    df = load_mt5(src)
    days, I, Y, OBS, _ = build_grid(df, 60, 1440, 15, 40)
    structure(df)
    distribution(df)
    med = seasonality(df, Y, OBS, I)
    daily_component(df, Y, OBS, days, med)
    volume_volatility(df)
    print(f"\nGrafiket: {FIG}")


if __name__ == "__main__":
    main()
