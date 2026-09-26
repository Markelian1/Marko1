"""Cumulative R of the ORB modules on XAUUSD 2020-2026 (from the v1.9 journal)."""
import matplotlib
matplotlib.use("Agg")
import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import pandas as pd

SURFACE, INK, INK2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"
BLUE, ORANGE, AQUA = "#2a78d6", "#eb6834", "#1baf7a"   # categorical slots 1-3 (validated)

t = pd.read_csv("analysis/data/ORB_trades_v19_2020-2026.csv", sep=";")
s = pd.read_csv("analysis/data/ORB_sessions_v19_2020-2026.csv", sep=";")
t["when"] = pd.to_datetime(t.open_time, format="%Y.%m.%d %H:%M")
s["when"] = pd.to_datetime(s.date, format="%Y.%m.%d")

series = [
    ("Breakout (v1.8)", t[t.module == "BREAKOUT"].sort_values("when"), "when", "result_R", BLUE),
    ("Reverse pas breakout-it të filtruar (v1.9)", t[t.module == "REVERSAL"].sort_values("when"), "when", "result_R", ORANGE),
    ("Reverse Hunter v2.0 (vetëm reverse)", s[s.rv_dir != "-"].sort_values("when"), "when", "rv_R", AQUA),
]

fig, ax = plt.subplots(figsize=(12, 6.2), dpi=150)
fig.patch.set_facecolor(SURFACE)
ax.set_facecolor(SURFACE)

split = pd.Timestamp("2022-01-01")
ax.axvspan(pd.Timestamp("2020-03-01"), split, color="#f1f0ec", zorder=0, linewidth=0)
ax.text(pd.Timestamp("2020-03-20"), 0.97, "Kontrolli 2020–2021\n(të dhëna të reja)", transform=ax.get_xaxis_transform(),
        va="top", ha="left", fontsize=9, color=INK2)
ax.text(pd.Timestamp("2022-01-20"), 0.97, "2022–2026\n(ku u zgjodhën rregullat)", transform=ax.get_xaxis_transform(),
        va="top", ha="left", fontsize=9, color=INK2)
ax.axhline(0, color=INK2, linewidth=1, zorder=1)

for label, df, xcol, ycol, color in series:
    y = df[ycol].cumsum()
    ax.plot(df[xcol], y, color=color, linewidth=2, zorder=3, label=label, solid_capstyle="round")
    ax.scatter(df[xcol].iloc[-1], y.iloc[-1], s=36, color=color, edgecolor=SURFACE, linewidth=2, zorder=4)
    ax.annotate(f"{y.iloc[-1]:+.1f}R", (df[xcol].iloc[-1], y.iloc[-1]), xytext=(8, 0), textcoords="offset points",
                va="center", fontsize=10, color=INK, fontweight="bold")

ax.set_title("Fitimi i grumbulluar në R (ari, 2020 – 2026)", loc="left", fontsize=15, color=INK, pad=14, fontweight="bold")
ax.set_ylabel("R (1R = sa rrezikohet në një trade)", color=INK2, fontsize=10)
ax.grid(axis="y", color=GRID, linewidth=0.8)
ax.grid(axis="x", visible=False)
for spine in ("top", "right", "left"):
    ax.spines[spine].set_visible(False)
ax.spines["bottom"].set_color(GRID)
ax.tick_params(colors=INK2, labelsize=9, length=0)
ax.xaxis.set_major_locator(mdates.YearLocator())
ax.xaxis.set_major_formatter(mdates.DateFormatter("%Y"))
ax.set_xlim(pd.Timestamp("2020-03-01"), pd.Timestamp("2027-01-15"))
leg = ax.legend(loc="lower right", frameon=False, fontsize=10, labelcolor=INK)
fig.text(0.01, 0.01, "Burimi: ditari CSV i EA v1.9 (MT5, XAUUSD M5). Reverse Hunter = reverse pas çdo breakout-i të dështuar, pa filtra.",
         fontsize=8, color=INK2)
fig.tight_layout(rect=(0, 0.03, 1, 1))
fig.savefig("analysis/charts/equity_R_2020-2026.png", facecolor=SURFACE)
print("saved")
