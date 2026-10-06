"""Ablation of the EA modules on XAUUSD M15 (in-sample vs out-of-sample).

Every combination of modules A/B/C is run for each entry trigger with the same
fixed defaults, so the effect of each module is measured, not tuned. A small
grid search is then run on IN-SAMPLE only and the chosen settings are reported
on the untouched OUT-OF-SAMPLE period.

  python3 -I strategy/ablation.py
"""

import itertools
import sys
from dataclasses import replace
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from backtest import Config, prepare, run, split_stats, stats  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
SPLIT = pd.Timestamp("2025-07-01")
COLS = ["IS_trades", "IS_win%", "IS_avgR", "IS_PF", "IS_totR", "IS_maxDD_R", "IS_t-stat",
        "OOS_trades", "OOS_win%", "OOS_avgR", "OOS_PF", "OOS_totR", "OOS_maxDD_R", "OOS_t-stat"]


def fmt(df):
    return df.to_string(float_format=lambda x: f"{x:7.2f}")


def ablation(d, base, cost):
    rows = {}
    for a, b, c in itertools.product((False, True), repeat=3):
        name = "base" if not (a or b or c) else "+".join(m for m, on in zip("ABC", (a, b, c)) if on)
        cfg = replace(base, module_a=a, module_b=b, module_c=c, cost_points=cost)
        rows[name] = split_stats(run(d, cfg), SPLIT)
    return pd.DataFrame(rows).T[COLS]


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else ROOT / "data/derived/m15_rkf.csv.gz"
    d = prepare(src)
    print(f"Te dhenat: {d.dt.min()} .. {d.dt.max()}   IS < {SPLIT.date()} <= OOS")
    for trig in ("donchian", "momentum", "fade"):
        for cost in (0.0, 10.0):
            print(f"\n=== Hyrja: {trig}   kosto shtese {cost:.0f} pike/tregti ===")
            print(fmt(ablation(d, Config(trigger=trig), cost)))


if __name__ == "__main__":
    main()
