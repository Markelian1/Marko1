"""Small parameter grid on IN-SAMPLE only, then the pick is checked out-of-sample.

Selection score: in-sample t-statistic of the per-trade R with 10 points of
extra cost per trade (at least 150 in-sample trades). The out-of-sample period
(>= 2025-07-01) is never used for selection.

  python3 -I strategy/grid_is_oos.py
"""

import itertools
import sys
from dataclasses import replace
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from backtest import Config, prepare, run, split_stats  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
SPLIT = pd.Timestamp("2025-07-01")
COST = 10.0

FAMILIES = {
    "Donchian + B + C": (Config(trigger="donchian", module_b=True, module_c=True),
                         {"dc_len": [10, 20, 40], "sl_atr": [1.0, 1.5, 2.0], "rr": [1.5, 2.0, 3.0],
                          "c_beta": [0.5, 0.8], "max_hold": [8, 16, 32]}),
    "Momentum + C": (Config(trigger="momentum", module_c=True),
                     {"body_atr": [0.5, 0.8, 1.2], "sl_atr": [1.0, 1.5, 2.0], "rr": [1.5, 2.0, 3.0],
                      "c_beta": [0.5, 0.8], "max_hold": [8, 16, 32]}),
    "Fade + A + B": (Config(trigger="fade", module_a=True, module_b=True),
                     {"a_min_z": [1.5, 2.0, 2.5], "sl_atr": [1.0, 1.5, 2.0], "rr": [1.0, 1.5, 2.0],
                      "body_atr": [0.3, 0.5, 0.8], "max_hold": [4, 8, 16]}),
}


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else ROOT / "data/derived/m15_rkf.csv.gz"
    d = prepare(src)
    summary = []
    for name, (base, grid) in FAMILIES.items():
        keys = list(grid)
        rows = []
        for vals in itertools.product(*grid.values()):
            cfg = replace(base, cost_points=COST, **dict(zip(keys, vals)))
            s = split_stats(run(d, cfg), SPLIT)
            rows.append({**dict(zip(keys, vals)), **s})
        res = pd.DataFrame(rows)
        ok = res[res.IS_trades >= 150]
        best = ok.sort_values("IS_t-stat", ascending=False).iloc[0]
        frac_pos_is = (res["IS_totR"] > 0).mean()
        frac_pos_oos = (res["OOS_totR"] > 0).mean()
        print(f"\n=== {name}: {len(res)} kombinime, kosto {COST:.0f} pike ===")
        print(f"  Kombinime me totR > 0: IS {frac_pos_is:.0%}, OOS {frac_pos_oos:.0%}")
        print("  Top 5 sipas t-stat ne IS (OOS vetem per kontroll):")
        cols = keys + ["IS_trades", "IS_PF", "IS_totR", "IS_t-stat", "OOS_trades", "OOS_PF", "OOS_totR",
                       "OOS_t-stat", "OOS_maxDD_R"]
        print(ok.sort_values("IS_t-stat", ascending=False).head(5)[cols]
              .to_string(index=False, float_format=lambda x: f"{x:6.2f}"))
        summary.append({"familja": name, **{k: best[k] for k in keys},
                        "IS_PF": best["IS_PF"], "IS_t": best["IS_t-stat"],
                        "OOS_trades": best["OOS_trades"], "OOS_PF": best["OOS_PF"],
                        "OOS_totR": best["OOS_totR"], "OOS_t": best["OOS_t-stat"]})
    print("\n=== Zgjedhja me e mire ne IS per cdo familje -> rezultati OOS ===")
    print(pd.DataFrame(summary).to_string(index=False, float_format=lambda x: f"{x:6.2f}"))


if __name__ == "__main__":
    main()
