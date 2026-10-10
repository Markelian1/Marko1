"""Analyze XAUUSD_SweepScanner.mq5 output (SWEEP_signals.csv).

Usage: python3 analyze_sweep.py <SWEEP_signals.csv>

Each signal is a sweep of the day's low (LONG) or high (SHORT) that was
reclaimed. mfe_R is the best move before the stop, so a target of k R
was reached when mfe_R >= k; otherwise the trade lost 1R if the stop was
hit, or ended at end_R. One spread is deducted per trade. A target must
work in 2020-21 and in 2022-26 to count.
"""
import sys

import numpy as np
import pandas as pd

pd.set_option("display.width", 200)


def result(d: pd.DataFrame, k: pd.Series) -> pd.Series:
    r = np.where(d.mfe_R >= k, k, np.where(d.sl_hit == 1, -1.0, np.minimum(d.end_R, k)))
    return pd.Series(r, index=d.index) - d.spread / d.risk


def stats(r: pd.Series, period: pd.Series) -> dict:
    p = r.groupby(period).sum()
    n = len(r)
    return {
        "n": n,
        "win%": round((r > 0).mean() * 100, 1),
        "sum_R": round(r.sum(), 1),
        "avg_R": round(r.mean(), 3),
        "t": round(r.mean() / (r.std() / np.sqrt(n)), 2) if n > 1 else 0.0,
        "2020-21": round(p.get("2020-21", 0.0), 1),
        "2022-26": round(p.get("2022-26", 0.0), 1),
    }


def main(path: str) -> None:
    d = pd.read_csv(path, sep=";")
    d["year"] = d.date.str[:4]
    d["period"] = np.where(d.year < "2022", "2020-21", "2022-26")
    d["hour"] = d.time.str[:2].astype(int)
    d["risk_pct"] = d.risk / d.entry * 100
    print(f"signals {len(d)}  days {d.date.nunique()}  from {d.date.min()} to {d.date.max()}")
    print(d.groupby("dir").size().to_string())
    print("\nrisk as % of price:", d.risk_pct.describe().round(3).to_dict())

    for label, sub in (("all signals", d), ("stop >= 0.10% of price", d[d.risk_pct >= 0.10])):
        rows = {}
        for k in (1, 2, 3, 5, 8):
            rows[f"{k}R"] = stats(result(sub, pd.Series(float(k), index=sub.index)), sub.period)
        day = sub[sub.day_R > 0]
        rows["day range"] = stats(result(day, day.day_R), day.period)
        pdd = sub[sub.pd_R > 0]
        rows["prev day"] = stats(result(pdd, pdd.pd_R), pdd.period)
        print(f"\n== {label}: result per target ==")
        print(pd.DataFrame(rows).T.to_string())

    sub = d[d.risk_pct >= 0.10]
    r3 = result(sub, pd.Series(3.0, index=sub.index))
    print("\n== stop >= 0.10%, target 3R, by hour (server) ==")
    print(pd.DataFrame({h: stats(r3[sub.hour == h], sub.period[sub.hour == h]) for h in sorted(sub.hour.unique())}).T.to_string())
    print("\n== by direction, target 3R ==")
    print(pd.DataFrame({k: stats(r3[sub.dir == k], sub.period[sub.dir == k]) for k in ("LONG", "SHORT")}).T.to_string())
    print("\nreached 8R before the stop:", int((d.mfe_R >= 8).sum()), "of", len(d))


if __name__ == "__main__":
    main(sys.argv[1])
