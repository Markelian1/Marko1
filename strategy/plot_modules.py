"""Equity curves (in R) of the EA modules on XAUUSD M15, with the IS/OOS split.

  python3 -I strategy/plot_modules.py
"""

import sys
from dataclasses import replace
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.dates
import matplotlib.pyplot as plt
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from backtest import Config, prepare, run  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
SPLIT = pd.Timestamp("2025-07-01")


def main():
    d = prepare(ROOT / "data/derived/m15_rkf.csv.gz")
    sets = [("Baza (pa module)", {}, "#9ca3af"), ("+ C", {"module_c": True}, "#60a5fa"),
            ("+ B + C (default i EA)", {"module_b": True, "module_c": True}, "#2563eb"),
            ("+ A + B + C", {"module_a": True, "module_b": True, "module_c": True}, "#dc2626")]
    fig, axes = plt.subplots(1, 2, figsize=(12, 4), sharey=False)
    for ax, (trig, title) in zip(axes, (("donchian", "Hyrja: breakout Donchian(20)"),
                                        ("momentum", "Hyrja: momentum i barit"))):
        for name, kw, col in sets:
            t = run(d, replace(Config(trigger=trig, cost_points=10.0), **kw))
            ax.plot(t.dt, t.R.cumsum(), color=col, lw=1.4, label=name)
        ax.axvline(SPLIT, color="#111827", ls="--", lw=1)
        ax.text(SPLIT, ax.get_ylim()[1], "  out-of-sample", va="top", fontsize=8)
        ax.axhline(0, color="#6b7280", lw=0.8)
        ax.set_title(title, fontsize=10)
        ax.set_ylabel("R kumulative (kosto +10 pike)")
        ax.xaxis.set_major_formatter(matplotlib.dates.DateFormatter("%Y"))
        ax.grid(alpha=0.3)
    axes[0].legend(frameon=False, fontsize=8)
    fig.suptitle("XAUUSD M15: efekti i moduleve (1R = rreziku i nje tregtie)")
    fig.tight_layout()
    fig.savefig(ROOT / "analysis/figures/x7_equity_modules.png", dpi=130)


if __name__ == "__main__":
    main()
