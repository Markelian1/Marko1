"""Analyze XAUUSD_SessionScanner.mq5 output (<prefix>_slots.csv).

Usage: python3 analyze_scan.py <SCAN_slots.csv>

For every half-hour slot of the day: the breakout and the reversal after
its failure, in R net of the recorded spread, split into the control
period (2020-2021) and 2022-2026. With 48 slots tested, a few will look
good by chance: a slot counts only if it is positive in both periods and
its t-statistic is strong; anything found here still needs a forward test.
"""
import sys

import numpy as np
import pandas as pd

pd.set_option("display.width", 220)
pd.set_option("display.max_rows", 200)


def stats(r: pd.Series) -> pd.Series:
    r = r.dropna()
    n = len(r)
    if n == 0:
        return pd.Series({"n": 0, "avg_R": 0.0, "sum_R": 0.0, "PF": np.nan, "t": 0.0})
    losses = -r[r < 0].sum()
    sd = r.std(ddof=1) if n > 1 else np.nan
    return pd.Series({
        "n": n,
        "avg_R": round(r.mean(), 3),
        "sum_R": round(r.sum(), 1),
        "PF": round(r[r > 0].sum() / losses, 2) if losses > 0 else np.inf,
        "t": round(r.mean() / (sd / np.sqrt(n)), 2) if n > 1 and sd > 0 else 0.0,
    })


def main(path: str) -> None:
    d = pd.read_csv(path, sep=";")
    d["year"] = d.date.str[:4]
    d["period"] = np.where(d.year < "2022", "2020-21", "2022-26")

    # net of one spread per trade, expressed in R
    bo = d[d.bo_dir != "-"].copy()
    bo["net"] = bo.bo_R - bo.spread / bo.bo_risk
    rv = d[d.rv_dir != "-"].copy()
    rv["net"] = rv.rv_R - rv.spread / rv.rv_risk

    print(f"rows {len(d)}  days {d.date.nunique()}  from {d.date.min()} to {d.date.max()}")

    def per_slot(df: pd.DataFrame, label: str) -> pd.DataFrame:
        a = df.groupby("slot").net.apply(stats).unstack()
        p = df.groupby(["slot", "period"]).net.sum().unstack().round(1)
        yrs = df.groupby(["slot", "year"]).net.sum().unstack()
        a["2020-21"] = p.get("2020-21")
        a["2022-26"] = p.get("2022-26")
        a["years+"] = (yrs > 0).sum(axis=1).astype(str) + "/" + yrs.notna().sum(axis=1).astype(str)
        a["both+"] = (a["2020-21"] > 0) & (a["2022-26"] > 0)
        print("\n" + "=" * 100)
        print(f"{label}: per half-hour slot (server time), R net of spread")
        print("=" * 100)
        print(a.to_string())
        return a

    b = per_slot(bo, "BREAKOUT")
    r = per_slot(rv, "REVERSAL after a failed breakout")

    for label, a in (("BREAKOUT", b), ("REVERSAL", r)):
        good = a[a["both+"] & (a.t >= 2.0)].sort_values("t", ascending=False)
        print(f"\n{label}: slots positive in BOTH periods with t >= 2 ({len(good)} of {len(a)}):")
        print(good[["n", "avg_R", "sum_R", "PF", "t", "2020-21", "2022-26", "years+"]].to_string() if len(good) else "  none")
        print(f"  by chance alone about {len(a) * 0.25:.0f} slots would be positive in both periods; "
              f"t >= 3.1 is the bar for {len(a)} tests")


if __name__ == "__main__":
    main(sys.argv[1])
