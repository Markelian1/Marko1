"""A ka informacion "volume surprise" per cmimin e XAUUSD?

Perdor daljet walk-forward te modelit (data/derived/m15_rkf.csv.gz): per cdo
bar M15, surprise = vellimi real / parashikimi i bere PARA barit.
Pyetjet:
  1. A parashikon surprise volatilitetin e ardhshem?           (moduli C)
  2. Pas nje bari me surprise te larte, cmimi vazhdon apo kthehet? (moduli A)
  3. A jane breakout-et me surprise te larte me te mira?        (A + hyrja)
  4. A ndikon aktiviteti i dites (eta) ne breakout?             (moduli C)

  python3 -I analysis/xauusd_signal_research.py
"""

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent
DER = ROOT.parent / "data/derived"
FIG = ROOT / "figures"
SPLIT = pd.Timestamp("2025-07-01")  # in-sample < SPLIT <= out-of-sample
BUCKETS = [0, 0.67, 1.0, 1.5, 2.0, np.inf]
LABELS = ["<0.67x", "0.67-1x", "1-1.5x", "1.5-2x", ">2x"]


def load():
    d = pd.read_csv(DER / "m15_rkf.csv.gz", parse_dates=["dt", "day"]).sort_values("dt")
    d = d.reset_index(drop=True)
    tr = np.maximum(d.high - d.low, np.maximum((d.high - d.close.shift()).abs(),
                                               (d.low - d.close.shift()).abs()))
    d["atr"] = tr.rolling(14).mean()  # = MT5 iATR (simple average of true range)
    d["ratio"] = np.exp(d.innov)
    d["dir"] = np.sign(d.close - d.open)
    d["hhmm"] = d.dt.dt.hour * 100 + d.dt.dt.minute
    for h in (4, 8, 16):
        fwd = d.close.shift(-h) - d.close
        d[f"fwd{h}"] = fwd / d.atr
        d[f"fvol{h}"] = (d.high.rolling(h).max().shift(-h) - d.low.rolling(h).min().shift(-h)) / d.atr
    d["dc_hi"] = d.high.rolling(20).max().shift(1)
    d["dc_lo"] = d.low.rolling(20).min().shift(1)
    d["brk"] = np.where(d.close > d.dc_hi, 1, np.where(d.close < d.dc_lo, -1, 0))
    d["bucket"] = pd.cut(d.ratio, BUCKETS, labels=LABELS, right=False)
    d["sample"] = np.where(d.dt < SPLIT, "IS", "OOS")
    # vetem ore tregtimi (09:00-20:00 server) dhe brenda te njejtes dite per fwd16
    d = d[(d.hhmm >= 900) & (d.hhmm < 2000)]
    return d.dropna(subset=["ratio", "fwd16", "atr"])


def table(d, value, by, signed_by=None):
    v = d[value] * (d[signed_by] if signed_by else 1)
    g = v.groupby([d["sample"], d[by]], observed=True)
    t = g.agg(["mean", "count"]).unstack(0)
    se = g.std().unstack(0) / np.sqrt(g.count().unstack(0))
    t.columns = [f"{a}_{b}" for a, b in t.columns]
    for s in ("IS", "OOS"):
        t[f"t_{s}"] = t[f"mean_{s}"] / se[s]
    return t[["mean_IS", "t_IS", "count_IS", "mean_OOS", "t_OOS", "count_OOS"]]


def fmt(t):
    return t.to_string(float_format=lambda x: f"{x:7.3f}")


def main():
    d = load()
    print(f"Bare ne analize (09:00-20:00 server): {len(d)}  IS < {SPLIT.date()} <= OOS")

    print("\n1. Surprise -> volatiliteti i 8 bareve te ardhshme (range / ATR)")
    print(fmt(table(d, "fvol8", "bucket")))

    print("\n2. Surprise -> kthimi i 8 bareve te ardhshme, ne drejtim te barit (ATR)")
    print("   (+ = vazhdim, - = kthim mbrapsht)")
    print(fmt(table(d[d.dir != 0], "fwd8", "bucket", signed_by="dir")))

    b = d[d.brk != 0]
    print(f"\n3. Breakout Donchian(20) ne mbyllje ({len(b)} bare) -> kthimi 8 bare, ne drejtim te breakout")
    print(fmt(table(b, "fwd8", "bucket", signed_by="brk")))
    print("\n   ... dhe 16 bare")
    print(fmt(table(b, "fwd16", "bucket", signed_by="brk")))

    d["act_b"] = pd.cut(d.activity, [0, 0.8, 1.0, 1.25, 1.6, np.inf],
                        labels=["<0.8", "0.8-1", "1-1.25", "1.25-1.6", ">1.6"])
    b = d[d.brk != 0]
    print("\n4. Breakout sipas aktivitetit te dites (eta) -> kthimi 16 bare (ATR)")
    print(fmt(table(b, "fwd16", "act_b", signed_by="brk")))

    # Grafik: 2 dhe 3
    fig, axes = plt.subplots(1, 3, figsize=(13, 3.8))
    for ax, (data, val, sb, title) in zip(axes, [
        (d, "fvol8", None, "Volatiliteti 8 bare (range/ATR)"),
        (d[d.dir != 0], "fwd8", "dir", "Kthimi 8 bare ne drejtim te barit (ATR)"),
        (d[d.brk != 0], "fwd16", "brk", "Breakout D20: kthimi 16 bare (ATR)")]):
        t = table(data, val, "bucket", signed_by=sb)
        for s_ in ("IS", "OOS"):  # mos vizato kova me pak vezhgime
            t.loc[t[f"count_{s_}"] < 30, f"mean_{s_}"] = np.nan
        x = np.arange(len(t))
        ax.bar(x - 0.2, t.mean_IS, 0.4, color="#2563eb", label="IS 2022-25")
        ax.bar(x + 0.2, t.mean_OOS, 0.4, color="#f59e0b", label="OOS 2025-26")
        ax.set_xticks(x, t.index, fontsize=8)
        ax.set_xlabel("Vellimi real / parashikimi")
        ax.set_title(title, fontsize=10)
        ax.axhline(0, color="#6b7280", lw=0.8)
        ax.grid(axis="y", alpha=0.3)
    axes[0].legend(frameon=False, fontsize=8)
    fig.suptitle("XAUUSD M15: cfare ndodh pas nje 'volume surprise' (kovat me < 30 raste nuk vizatohen)")
    fig.tight_layout()
    fig.savefig(FIG / "x6_surprise_effects.png", dpi=130)
    plt.close(fig)


if __name__ == "__main__":
    main()
