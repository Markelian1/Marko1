"""Analyze XAUUSD_StabilityScanner.mq5 output (STAB_slots.csv).

Usage: python3 analyze_stability.py <STAB_slots.csv>

Reversal trades of the NY and Asia sessions for every range length and
target, with the v2.2 rules: stops under 0.10% of price are skipped and
one spread is deducted per trade. A setting is robust when its
neighbours work too, not only the chosen one (range 30, target 2.0).
"""
import itertools
import sys

import numpy as np
import pandas as pd

pd.set_option("display.width", 200)

MIN_STOP_PCT = 0.10


def main(path: str) -> None:
    d = pd.read_csv(path, sep=";")
    d["year"] = d.date.str[:4]
    d["period"] = np.where(d.year < "2022", "2020-21", "2022-26")
    rv = d[(d.rv_dir != "-") & (d.rv_risk / d.rv_entry * 100 >= MIN_STOP_PCT)].copy()
    rv["net"] = rv.rv_R - rv.spread / rv.rv_risk

    def summary(g: pd.DataFrame) -> pd.Series:
        r = g.net
        p = g.groupby("period").net.sum()
        yrs = g.groupby("year").net.sum()
        return pd.Series({
            "n": len(r),
            "sum_R": round(r.sum(), 1),
            "avg_R": round(r.mean(), 3),
            "t": round(r.mean() / (r.std() / np.sqrt(len(r))), 2),
            "2020-21": round(p.get("2020-21", 0.0), 1),
            "2022-26": round(p.get("2022-26", 0.0), 1),
            "years+": f"{(yrs > 0).sum()}/{len(yrs)}",
        })

    print(f"days {d.date.nunique()}  from {d.date.min()} to {d.date.max()}")
    per = rv.groupby(["session", "range", "rr"]).apply(summary, include_groups=False)
    print("\nEach session alone (reversal, R net of spread, stops >= 0.10% of price):")
    print(per.to_string())

    rows = []
    for ny, asia, rr in itertools.product(sorted(rv.range.unique()), sorted(rv.range.unique()), sorted(rv.rr.unique())):
        g = rv[((rv.session == "NY") & (rv.range == ny) | (rv.session == "ASIA") & (rv.range == asia)) & (rv.rr == rr)]
        s = summary(g)
        s["NY range"], s["ASIA range"], s["target"] = ny, asia, rr
        rows.append(s)
    port = pd.DataFrame(rows).set_index(["NY range", "ASIA range", "target"]).sort_values("sum_R", ascending=False)
    print("\nNY + Asia together, all 36 combinations:")
    print(port.to_string())
    both = ((port["2020-21"] > 0) & (port["2022-26"] > 0)).sum()
    print(f"\npositive overall: {(port.sum_R > 0).sum()}/36   positive in both periods: {both}/36")
    print(f"chosen setting (30, 30, 2.0): rank {list(port.index).index((30, 30, 2.0)) + 1} of 36")


if __name__ == "__main__":
    main(sys.argv[1])
