"""Analyze the CSV journal written by XAUUSD_NY_OpenRangeBreakout_v18.mq5.

Usage: python3 analyze_journal.py <sessions.csv> <trades.csv>

sessions.csv has one row per session with the filter decision and an
unfiltered "shadow" trade (first M1 close beyond the range, SL at the
opposite side, TP at rr x width from the broken side), so filters and
exits can be evaluated offline over every session, traded or not.
"""
import sys

import pandas as pd

pd.set_option("display.width", 200)
pd.set_option("display.max_columns", 30)


def summarize(r: pd.Series) -> dict:
    """Stats for a series of trade results in R."""
    wins = r[r > 0].sum()
    losses = -r[r < 0].sum()
    return {
        "n": len(r),
        "win%": round(100 * (r > 0).mean(), 1) if len(r) else 0.0,
        "avg_R": round(r.mean(), 3) if len(r) else 0.0,
        "sum_R": round(r.sum(), 1),
        "PF": round(wins / losses, 2) if losses > 0 else float("inf"),
    }


def table(df: pd.DataFrame, by, col: str) -> pd.DataFrame:
    return pd.DataFrame({k: summarize(g[col]) for k, g in df.groupby(by, observed=True)}).T


def main(sess_path: str, trades_path: str) -> None:
    s = pd.read_csv(sess_path, sep=";")
    t = pd.read_csv(trades_path, sep=";")
    s["year"] = s["date"].str[:4]
    t["year"] = t["open_time"].str[:4]

    print("=" * 80)
    print("REAL TRADES (filters on)")
    print("=" * 80)
    print(table(t, "year", "result_R"))
    print("\nby direction x year:")
    print(table(t, ["year", "dir"], "result_R"))
    print("\nexit reasons:")
    print(t.groupby("exit_reason")["result_R"].agg(["count", "mean", "sum"]).round(3))

    sl = t[t.exit_reason == "SL"]
    print(f"\nSL losers: {len(sl)}")
    for k in (0.5, 1.0):
        print(f"  reached +{k}R before the stop: {(sl.mfe_R >= k).sum()}")
    print("  minutes to stop (median):", sl.minutes.median())
    print("  stopped within 60 min:", (sl.minutes <= 60).sum())

    # ---------------- shadow (every session, no filters) ----------------
    sh = s[s.sh_dir != "-"].copy()
    sh["ext"] = 0.0
    long_ = sh.sh_dir == "LONG"
    sh.loc[long_, "ext"] = (sh.sh_entry - sh.range_high) / sh.width
    sh.loc[~long_, "ext"] = (sh.range_low - sh.sh_entry) / sh.width
    sh["with_trend"] = ((sh.sh_dir == "LONG") & (sh.px_vs_sma_pct > 0)) | (
        (sh.sh_dir == "SHORT") & (sh.px_vs_sma_pct < 0)
    )
    sh["hour"] = sh.sh_time.str[11:13]

    print("\n" + "=" * 80)
    print(f"SHADOW: first breakout on every session (no filters)  sessions={len(s)}  breakouts={len(sh)}")
    print("=" * 80)
    print(table(sh, "year", "sh_R"))
    print("\nby filter decision (what the filters removed):")
    print(table(sh, "decision", "sh_R"))
    print("\nwith / against the 50-day SMA trend, per year:")
    print(table(sh, ["year", "with_trend"], "sh_R"))

    sh["ratio_b"] = pd.cut(sh.ratio, [0, 0.5, 0.7, 0.85, 1.0, 1.25, 1.5, 2, 99])
    print("\nrange vs 20-day median (ratio buckets):")
    print(table(sh[sh.ratio > 0], "ratio_b", "sh_R"))
    print("\nratio buckets x year (avg_R):")
    rb = sh[sh.ratio > 0].groupby(["ratio_b", "year"], observed=True)["sh_R"].mean().unstack().round(2)
    print(rb)

    sh["ext_b"] = pd.cut(sh.ext, [-99, 0.1, 0.25, 0.5, 1, 99])
    print("\nentry extension beyond the range (x width):")
    print(table(sh, "ext_b", "sh_R"))
    print("\nbreakout hour (server):")
    print(table(sh, "hour", "sh_R"))
    print("\nweekday:")
    print(table(sh, "weekday", "sh_R"))

    print("\noutcomes:")
    print(sh.groupby("sh_outcome")["sh_R"].agg(["count", "mean", "sum"]).round(3))

    # ---------------- exit alternatives on the shadow ----------------
    print("\n" + "=" * 80)
    print("EXIT ALTERNATIVES on all shadow breakouts (exact, from MFE and order flags)")
    print("=" * 80)
    base = sh.sh_R
    be = sh.sh_R.where(~((sh.sh_hit_1R == 1) & (sh.sh_back_to_entry_after_1R == 1)), 0.0)
    rows = {"current (TP 2x width)": summarize(base), "breakeven at +1R": summarize(be)}
    for k in (0.5, 0.75, 1.0, 1.25, 1.5):
        alt = sh.sh_R.where(~(sh.sh_mfe_R >= k), k)
        rows[f"TP at {k}R"] = summarize(alt)
    print(pd.DataFrame(rows).T)

    # ---------------- false breakouts / reversal potential ----------------
    print("\n" + "=" * 80)
    print("FALSE BREAKOUTS: shadow stopped out, how far did price run the other way?")
    print("=" * 80)
    fb = sh[sh.sh_outcome == "SL"].copy()
    fb["run_other_side_w"] = 0.0
    lo = fb.sh_dir == "LONG"
    fb.loc[lo, "run_other_side_w"] = (fb.range_low - fb.low_after_range) / fb.width
    fb.loc[~lo, "run_other_side_w"] = (fb.high_after_range - fb.range_high) / fb.width
    print(f"stopped-out breakouts: {len(fb)}")
    for k in (1, 2, 3):
        print(f"  price later ran >= {k}x width beyond the OTHER side: {(fb.run_other_side_w >= k).sum()}")
    print("  (upper bound for a stop-and-reverse rule: the order of the moves is unknown)")

    # ---------------- v1.9: reversal module ----------------
    if "module" in t.columns:
        print("\n" + "=" * 80)
        print("REAL TRADES BY MODULE (v1.9)")
        print("=" * 80)
        print(table(t, ["module", "year"], "result_R"))
        print(table(t, "module", "result_R"))
    if "rv_dir" in s.columns:
        rv = s[s.rv_dir != "-"].copy()
        print("\n" + "=" * 80)
        print(f"SHADOW REVERSAL after every stopped-out shadow breakout: {len(rv)}")
        print("=" * 80)
        print(table(rv, "year", "rv_R"))
        print(table(rv, "rv_dir", "rv_R"))
        both = sh.groupby("year").sh_R.sum().add(rv.groupby("year").rv_R.sum(), fill_value=0)
        print("\nshadow breakout + shadow reversal, sum R by year:")
        print(both.round(1).to_string())


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
