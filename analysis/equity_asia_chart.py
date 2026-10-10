"""Cumulative R 2020-2026: the robot v2.2 (NY + Asia) and the two Asia settings,
with the two months a TradingView 5m chart shows marked."""
import matplotlib
matplotlib.use("Agg")
import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import pandas as pd

SURFACE, INK, INK2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"
BLUE, ORANGE, AQUA = "#2a78d6", "#eb6834", "#1baf7a"   # categorical slots 1-3 (validated)

ea = pd.read_csv("analysis/data/MRH_trades_v22_2020-2026.csv", sep=";")
ea["when"] = pd.to_datetime(ea.open_time, format="%Y.%m.%d %H:%M")
st = pd.read_csv("analysis/data/STAB_slots_2020-2026.csv", sep=";")
st = st[(st.session == "ASIA") & (st.rv_dir != "-") & (st.rv_risk / st.rv_entry * 100 >= 0.10)].copy()
st["when"] = pd.to_datetime(st.date, format="%Y.%m.%d")
st["net"] = st.rv_R - st.spread / st.rv_risk

series = [
    ("Robot-i v2.2: New York + Azia", ea.sort_values("when"), "result_R", AQUA, 0),
    ("Azia v2.2: range 30, TP 2.0", st[(st.range == 30) & (st.rr == 2.0)].sort_values("when"), "net", BLUE, -8),
    ("Azia v2.3: range 40, TP 1.5", st[(st.range == 40) & (st.rr == 1.5)].sort_values("when"), "net", ORANGE, 8),
]

fig, ax = plt.subplots(figsize=(12, 6.2), dpi=150)
fig.patch.set_facecolor(SURFACE)
ax.set_facecolor(SURFACE)

tv0, tv1 = pd.Timestamp("2026-08-01"), pd.Timestamp("2026-10-10")
ax.axvspan(tv0, tv1, color="#f1f0ec", zorder=0, linewidth=0)
ax.annotate("Këtu shikon TradingView\n(2 muajt e fundit)", xy=(mdates.date2num(tv0), 0.06), xycoords=ax.get_xaxis_transform(),
            xytext=(-8, 0), textcoords="offset points", ha="right", va="bottom", fontsize=9, color=INK2)
ax.axhline(0, color=INK2, linewidth=1, zorder=1)

for label, df, col, color, dy in series:
    y = df[col].cumsum()
    ax.plot(df.when, y, color=color, linewidth=2, zorder=3, label=label, solid_capstyle="round")
    ax.scatter(df.when.iloc[-1], y.iloc[-1], s=36, color=color, edgecolor=SURFACE, linewidth=2, zorder=4)
    ax.annotate(f"{y.iloc[-1]:+.0f}R", (df.when.iloc[-1], y.iloc[-1]), xytext=(8, dy), textcoords="offset points",
                va="center", fontsize=10, color=INK, fontweight="bold")

ax.set_title("Fitimi i grumbulluar në R, ari 2020 – 2026", loc="left", fontsize=15, color=INK, pad=14, fontweight="bold")
ax.set_ylabel("R (1R = sa rrezikohet në një trade)", color=INK2, fontsize=10)
ax.grid(axis="y", color=GRID, linewidth=0.8)
for spine in ("top", "right", "left"):
    ax.spines[spine].set_visible(False)
ax.spines["bottom"].set_color(GRID)
ax.tick_params(colors=INK2, labelsize=9, length=0)
ax.xaxis.set_major_locator(mdates.YearLocator())
ax.xaxis.set_major_formatter(mdates.DateFormatter("%Y"))
ax.set_xlim(pd.Timestamp("2020-03-01"), pd.Timestamp("2027-01-31"))
ax.legend(loc="upper left", bbox_to_anchor=(0, 0.9), frameon=False, fontsize=10, labelcolor=INK)
fig.text(0.01, 0.01, "Burimi: ditari i robotit v2.2 në MT5 dhe skaneri i stabilitetit (pas spread-it). Të dhënat mbarojnë më 25 shtator 2026.",
         fontsize=8, color=INK2)
fig.tight_layout(rect=(0, 0.03, 1, 1))
fig.savefig("analysis/charts/equity_asia_2020-2026.png", facecolor=SURFACE)
print("saved")
