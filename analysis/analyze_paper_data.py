"""Analiza e te dhenave nga Chen, Feng & Palomar (2016/2018),
"Forecasting Intraday Trading Volume: A Kalman Filter Approach" (SSRN 3101695).

Te dhenat jane tabelat 1-4 te artikullit, te hedhura ne analysis/data/*.csv.
Ekzekutimi:  python3 analysis/analyze_paper_data.py
Rezultati:   tabela ne terminal + grafike ne analysis/figures/
"""

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy import stats

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data"
FIG = ROOT / "figures"
FIG.mkdir(exist_ok=True)

# Rreshti "Average" i botuar ne artikull, per te verifikuar transkriptimin.
PAPER_AVG_MAPE = {"dyn_rkf_mean": 0.46, "dyn_kf_mean": 0.47, "dyn_cmem_mean": 0.65,
                  "st_rkf_mean": 0.61, "st_kf_mean": 0.62, "st_cmem_mean": 0.90,
                  "st_rm_mean": 1.28}
PAPER_AVG_VWAP = {"dyn_rkf_mean": 6.38, "dyn_kf_mean": 6.39, "dyn_cmem_mean": 7.01,
                  "st_rkf_mean": 6.85, "st_kf_mean": 6.89, "st_cmem_mean": 7.71,
                  "st_rm_mean": 7.48}

C_RKF, C_CMEM, C_RM = "#2563eb", "#f59e0b", "#9ca3af"
C_STOCK, C_ETF = "#2563eb", "#dc2626"


def improvement(bench, model):
    """Ekuacioni (38) i artikullit: permiresimi ne % kundrejt benchmark-ut."""
    return 100.0 * (bench - model) / bench


def section(title):
    print("\n" + "=" * 78 + f"\n{title}\n" + "=" * 78)


def load():
    meta = pd.read_csv(DATA / "table2_data_summary.csv")
    mape = pd.read_csv(DATA / "table3_volume_mape.csv")
    vwap = pd.read_csv(DATA / "table4_vwap_tracking_bps.csv")
    outl = pd.read_csv(DATA / "table1_outlier_robustness.csv")
    meta["cv"] = meta["std"] / meta["mean"]            # koeficienti i variacionit
    meta["q95_q5"] = meta["q95"] / meta["q5"]          # gjeresia e shperndarjes
    meta["region"] = meta["country"].map(
        {"U.S.": "SHBA", "France": "Europe", "U.K.": "Europe", "Germany": "Europe",
         "Netherlands": "Europe", "Japan": "Azi", "Hong Kong": "Azi"})
    m = meta.merge(mape, on="ticker").merge(vwap, on="ticker", suffixes=("", "_vwap"))
    return meta, mape, vwap, outl, m


def check_transcription(mape, vwap):
    section("1. Verifikimi i transkriptimit (mesatarja e llogaritur vs artikulli)")
    ok = True
    for name, df, ref in (("MAPE", mape, PAPER_AVG_MAPE), ("VWAP bps", vwap, PAPER_AVG_VWAP)):
        for col, val in ref.items():
            got = df[col].mean()
            flag = "OK" if abs(got - val) <= 0.011 else "KUJDES"
            ok &= flag == "OK"
            print(f"  {name:9s} {col:14s} artikulli={val:6.2f}  llogaritur={got:6.3f}  {flag}")
    print("  => Transkriptimi perputhet me rreshtin 'Average'." if ok
          else "  => Ka mosperputhje, kontrollo CSV-te!")


def headline_claims(mape, vwap):
    section("2. Pretendimet kryesore te artikullit (mesatare) dhe versioni me MEDIANE")
    rows = []
    for label, df in (("Vellimi MAPE", mape), ("VWAP bps", vwap)):
        for model, bench in (("dyn_rkf_mean", "st_rm_mean"),
                             ("dyn_rkf_mean", "dyn_cmem_mean"),
                             ("st_rkf_mean", "st_rm_mean"),
                             ("st_rkf_mean", "st_cmem_mean")):
            per_ticker = improvement(df[bench], df[model])
            rows.append({
                "metrika": label,
                "krahasimi": f"{model.replace('_mean', '')} vs {bench.replace('_mean', '')}",
                "perm_mesatares_%": improvement(df[bench].mean(), df[model].mean()),
                "mediana_per_titull_%": per_ticker.median(),
                "min_%": per_ticker.min(),
                "fitore": f"{(per_ticker > 0).sum()}/{len(df)}",
            })
    out = pd.DataFrame(rows)
    print(out.to_string(index=False, float_format=lambda x: f"{x:6.1f}"))
    print("\n  Shenim: RM ekziston vetem si parashikim STATIK. Krahasimi 64% eshte")
    print("  'dinamik KF vs statik RM' -> nje pjese e fitimit vjen thjesht nga perdorimi")
    print("  i informacionit brenda dites. Krahasimi i drejte (statik vs statik) eshte me i vogel.")
    return out


def outlier_tickers(m):
    section("3. Titujt problematike (std e MAPE >> mesatarja) qe shtremberojne mesataren")
    m = m.assign(ratio=m["dyn_rkf_std"] / m["dyn_rkf_mean"])
    bad = m[m["ratio"] > 2].sort_values("ratio", ascending=False)
    print(bad[["ticker", "name", "type", "dyn_rkf_mean", "dyn_rkf_std", "ratio"]]
          .to_string(index=False, float_format=lambda x: f"{x:6.2f}"))
    clean = m[m["ratio"] <= 2]
    print(f"\n  Pa keta {len(bad)} tituj: MAPE dinamik RKF mesatar = {clean['dyn_rkf_mean'].mean():.3f}"
          f"  (me te gjithe: {m['dyn_rkf_mean'].mean():.3f})")
    print(f"  Mediana e MAPE dinamik RKF (te gjithe) = {m['dyn_rkf_mean'].median():.3f}")
    return bad["ticker"].tolist()


def by_group(m):
    section("4. Rezultatet sipas grupit (mediane)")
    cols = ["dyn_rkf_mean", "st_rkf_mean", "st_rm_mean", "dyn_rkf_mean_vwap", "st_rm_mean_vwap"]
    for g in ("type", "region"):
        t = m.groupby(g)[cols].median()
        t["perm_vol_%"] = improvement(t["st_rm_mean"], t["dyn_rkf_mean"])
        t["perm_vwap_%"] = improvement(t["st_rm_mean_vwap"], t["dyn_rkf_mean_vwap"])
        t["n"] = m.groupby(g).size()
        print(t.to_string(float_format=lambda x: f"{x:7.2f}"))
        print()


def drivers(m):
    section("5. Cfare e ben vellimin te veshtire per t'u parashikuar? (Spearman)")
    m = m.assign(perm_vs_rm=improvement(m["st_rm_mean"], m["dyn_rkf_mean"]),
                 perm_vwap_vs_rm=improvement(m["st_rm_mean_vwap"], m["dyn_rkf_mean_vwap"]),
                 log_mean=np.log(m["mean"]))
    pairs = [("cv", "dyn_rkf_mean", "CV i vellimit  -> MAPE dinamik RKF"),
             ("q95_q5", "dyn_rkf_mean", "Q95/Q5         -> MAPE dinamik RKF"),
             ("log_mean", "dyn_rkf_mean", "log(qarkullimi) -> MAPE dinamik RKF"),
             ("cv", "perm_vs_rm", "CV i vellimit  -> permiresimi vs RM"),
             ("perm_vs_rm", "perm_vwap_vs_rm", "Perm. vellimi  -> perm. VWAP"),
             ("dyn_rkf_mean", "dyn_rkf_mean_vwap", "MAPE vellimi   -> gabim VWAP (bps)")]
    for x, y, label in pairs:
        rho, p = stats.spearmanr(m[x], m[y])
        print(f"  {label:40s} rho={rho:+.2f}  p={p:.3f}")
    return m


def dynamic_vs_static(m):
    section("6. Sa ndihmon perditesimi brenda dites (dinamik vs statik, RKF)?")
    g = improvement(m["st_rkf_mean"], m["dyn_rkf_mean"])
    gv = improvement(m["st_rkf_mean_vwap"], m["dyn_rkf_mean_vwap"])
    print(f"  Vellimi MAPE: mediana {g.median():.1f}%  (min {g.min():.1f}%, max {g.max():.1f}%)")
    print(f"  VWAP bps    : mediana {gv.median():.1f}%  (min {gv.min():.1f}%, max {gv.max():.1f}%)")
    d = m["st_rkf_mean_vwap"] - m["dyn_rkf_mean_vwap"]
    print(f"  Kursimi absolut VWAP nga dinamika: mediana {d.median():.2f} bps")


def rkf_vs_kf(m, outl):
    section("7. Robust KF (Lasso) vs KF standard")
    d = m["dyn_kf_mean"] - m["dyn_rkf_mean"]
    print(f"  Te dhena te pastra (Tabela 3): diferenca mesatare MAPE = {d.mean():+.4f}"
          f"  (RKF me i mire ne {(d > 0).sum()}, barazim {(d == 0).sum()}, me keq {(d < 0).sum()})")
    print("\n  Me outliers artificiale (Tabela 1), rritja e MAPE dinamik nga 'none' ne 'large':")
    for t, grp in outl.groupby("ticker", sort=False):
        g = grp.set_index("outliers")
        for col in ("dyn_rkf", "dyn_kf", "st_rm"):
            base, large = g.loc["none", col], g.loc["large", col]
            print(f"    {t:4s} {col:8s} {base:.2f} -> {large:.2f}  (+{100 * (large - base) / base:5.1f}%)")
    n_fail = outl["dyn_cmem"].isna().sum()
    print(f"\n  CMEM deshton (N/A) ne {n_fail} nga {len(outl)} skenare -> modeli konkurrent eshte i brishte.")


def vwap_economics(m):
    section("8. Vlera ekonomike ne VWAP (bps; 1 bps = 0.01%)")
    gain = m["st_rm_mean_vwap"] - m["dyn_rkf_mean_vwap"]
    print(f"  Kursimi dinamik RKF vs RM: mesatare {gain.mean():.2f} bps, mediana {gain.median():.2f} bps")
    print(f"  Tituj ku kursimi > 1 bps: {(gain > 1).sum()}/{len(m)}")
    worse = m[m["dyn_rkf_mean_vwap"] > m[["dyn_cmem_mean_vwap", "st_rm_mean_vwap"]].min(axis=1)]
    print("  Tituj ku RKF dinamik NUK eshte me i miri ne VWAP:",
          ", ".join(worse["ticker"]) or "asnje")
    ratio = (improvement(m["st_rm_mean_vwap"], m["dyn_rkf_mean_vwap"]).median()
             / improvement(m["st_rm_mean"], m["dyn_rkf_mean"]).median())
    print(f"  Perkthimi: 1% permiresim ne vellim ~ {ratio:.2f}% permiresim ne VWAP (mediane).")
    print("  -> Gabimi VWAP dominohet nga levizja e cmimit, jo nga parashikimi i vellimit.")


# --------------------------------------------------------------------------- grafiket

def fig_mape(m):
    d = m.sort_values("dyn_rkf_mean")
    y = np.arange(len(d))
    fig, ax = plt.subplots(figsize=(8, 9))
    ax.scatter(d["st_rm_mean"], y, color=C_RM, label="RM (statik, benchmark)", zorder=3)
    ax.scatter(d["dyn_cmem_mean"], y, color=C_CMEM, label="CMEM dinamik", zorder=3)
    ax.scatter(d["dyn_rkf_mean"], y, color=C_RKF, label="Robust KF dinamik", zorder=4)
    for yi, (a, b) in enumerate(zip(d["dyn_rkf_mean"], d["st_rm_mean"])):
        ax.plot([a, b], [yi, yi], color="#e5e7eb", zorder=1)
    ax.set_yticks(y, d["ticker"])
    ax.set_xscale("log")
    ax.set_xlabel("MAPE i vellimit jashte kampionit (shkalle log)")
    ax.set_title("Gabimi i parashikimit te vellimit sipas titullit")
    ax.legend(loc="lower right", frameon=False)
    ax.grid(axis="x", alpha=0.3)
    fig.tight_layout()
    fig.savefig(FIG / "01_mape_per_ticker.png", dpi=130)
    plt.close(fig)


def fig_dispersion(m):
    fig, ax = plt.subplots(figsize=(7, 5))
    for typ, col, lab in (("stock", C_STOCK, "Aksione"), ("etf", C_ETF, "ETF")):
        s = m[m["type"] == typ]
        ax.scatter(s["q95_q5"], s["dyn_rkf_mean"], color=col, label=lab)
        for _, r in s.iterrows():
            ax.annotate(r["ticker"], (r["q95_q5"], r["dyn_rkf_mean"]), fontsize=7,
                        xytext=(3, 2), textcoords="offset points", color="#374151")
    rho, p = stats.spearmanr(m["q95_q5"], m["dyn_rkf_mean"])
    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlabel("Gjeresia e shperndarjes se vellimit, Q95 / Q5 (log)")
    ax.set_ylabel("MAPE dinamik RKF (log)")
    ax.set_title(f"Vellim me i shperndare -> parashikim me i keq (Spearman rho={rho:.2f}, p={p:.3f})",
                 fontsize=10)
    ax.legend(frameon=False)
    ax.grid(alpha=0.3)
    fig.tight_layout()
    fig.savefig(FIG / "02_dispersion_vs_mape.png", dpi=130)
    plt.close(fig)


def fig_outliers(outl):
    levels = ["none", "small", "medium", "large"]
    fig, axes = plt.subplots(1, 3, figsize=(11, 3.8), sharey=False)
    for ax, (t, g) in zip(axes, outl.groupby("ticker", sort=False)):
        g = g.set_index("outliers").loc[levels]
        x = np.arange(len(levels))
        ax.plot(x, g["dyn_rkf"], "o-", color=C_RKF, label="Robust KF")
        ax.plot(x, g["dyn_kf"], "s--", color="#60a5fa", label="KF standard")
        ax.plot(x, g["dyn_cmem"], "^-", color=C_CMEM, label="CMEM (N/A = deshtoi)")
        ax.plot(x, g["st_rm"], "d:", color=C_RM, label="RM statik")
        ax.set_xticks(x, ["pa", "te vogla", "mesatare", "te medha"])
        ax.set_title(t)
        ax.grid(alpha=0.3)
    axes[0].set_ylabel("MAPE dinamik")
    axes[0].legend(frameon=False, fontsize=8)
    fig.suptitle("Qendrueshmeria ndaj outliers artificiale (Tabela 1)")
    fig.tight_layout()
    fig.savefig(FIG / "03_outlier_robustness.png", dpi=130)
    plt.close(fig)


def fig_translation(m):
    x = improvement(m["st_rm_mean"], m["dyn_rkf_mean"])
    y = improvement(m["st_rm_mean_vwap"], m["dyn_rkf_mean_vwap"])
    fig, ax = plt.subplots(figsize=(7, 5))
    ax.scatter(x, y, color=C_RKF)
    for t, xi, yi in zip(m["ticker"], x, y):
        ax.annotate(t, (xi, yi), fontsize=7, xytext=(3, 2), textcoords="offset points")
    ax.axhline(0, color="#6b7280", lw=0.8)
    lim = max(x.max(), y.max()) + 5
    ax.plot([0, lim], [0, lim], color="#d1d5db", ls="--", label="1:1")
    ax.set_xlabel("Permiresimi i vellimit vs RM (%)")
    ax.set_ylabel("Permiresimi i VWAP vs RM (%)")
    ax.set_title("Parashikim shume me i mire i vellimit != VWAP shume me i mire")
    ax.legend(frameon=False)
    ax.grid(alpha=0.3)
    fig.tight_layout()
    fig.savefig(FIG / "04_volume_vs_vwap_gain.png", dpi=130)
    plt.close(fig)


def main():
    meta, mape, vwap, outl, m = load()
    check_transcription(mape, vwap)
    headline_claims(mape, vwap)
    outlier_tickers(m)
    by_group(m)
    m = drivers(m)
    dynamic_vs_static(m)
    rkf_vs_kf(m, outl)
    vwap_economics(m)
    fig_mape(m)
    fig_dispersion(m)
    fig_outliers(outl)
    fig_translation(m)
    print(f"\nGrafiket u ruajten ne {FIG}")


if __name__ == "__main__":
    main()
