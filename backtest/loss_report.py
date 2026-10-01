#!/usr/bin/env python3
"""Trade journal with a description of every trade, losses first.

Runs CRT_1AM_PRO24 v1.03 (or a CRT_1AM_EA mode) through crt_1am_backtest.py on an
MT5 bar export and writes one CSV row per trade: when, which H4 candle,
direction, prices, how far it went for and against the trade (MFE / MAE in
R), the market context (trend, range, sweep, spread) and a short
description (in Albanian, plain ASCII) of what happened.

It then prints, for every loss type and every context tag, how many trades
and how much R it accounts for, split into the first and second half of the
period: a tag is only worth a new rule when it is bad in both halves.

  python3 loss_report.py --mt5 ../data/XAUUSD_M15.csv --mode pro24 \\
      --start 2023-01-01 --end 2026-09-26
"""
import argparse
import csv
import os
from collections import defaultdict
from datetime import datetime, timezone

from crt_1am_backtest import ACTIVE, SELECTIVE, pro24_set, run
from crt_backtest import load_mt5

NY = 7 * 3600
DAYS = ["e hene", "e marte", "e merkure", "e enjte", "e premte", "e shtune", "e diel"]

LOSS_TYPES = {
    "L1": "kthim i menjehershem: cmimi shkoi kunder menjehere (sweep-i vazhdoi), SL brenda 1 ore",
    "L2": "pa drejtim: trade-i nuk shkoi kurre ne favor, SL pas me shume se 1 ore",
    "L3": "levizje e vogel ne favor (+0.3R deri +1R), pastaj SL",
    "L4": "fitim i humbur: arriti te pakten +1R, pastaj u kthye ne SL",
    "L5": "mbyllje me kohe ne humbje (8 ore ose e premte)",
    "W1": "fitim: preku TP",
    "W2": "mbyllje me kohe ne fitim",
}


def classify(t):
    minutes = (t["t_out"] - t["t_in"]) / 60
    if t["why"] == "TP":
        return "W1"
    if t["why"] == "time":
        return "W2" if t["r"] > 0 else "L5"
    if t["mfe"] >= 1.0:
        return "L4"
    if t["mfe"] >= 0.3:
        return "L3"
    return "L1" if minutes <= 60 else "L2"


def tags(t):
    out = []
    ny = t["t_in"] - NY
    hour = (ny % 86400) // 3600
    if t["model"] == "9PM":
        out.append("qiri 9PM (Asia)")
    if t["model"] == "5PM":
        out.append("qiri 5PM (pas mbylljes ditore)")
    if hour in (8, 9):
        out.append("ora e lajmeve 8-10 NY")
    if (ny // 86400 + 3) % 7 == 4:
        out.append("e premte")
    if t["trend_avg"] and abs(t["prev_close"] - t["trend_avg"]) / t["trend_avg"] < 0.005:
        out.append("trend i dobet (<0.5% nga mesatarja)")
    if t["atr"] and t["risk"] > 0.30 * t["atr"]:
        out.append("SL i madh (>30% e ATR ditore)")
    if t["atr"] and t["risk"] < 0.10 * t["atr"]:
        out.append("SL i vogel (<10% e ATR ditore)")
    if t["rng"] and t["depth"] > 0.5 * t["rng"]:
        out.append("sweep i thelle (>50% e range-it)")
    if t["spread"] > 0.35:
        out.append("spread i larte (>0.35)")
    if t["rng"]:
        pos = (t["entry"] - t["rng_lo"]) / t["rng"]
        if (t["dir"] == 2 and pos < 0.6) or (t["dir"] == 1 and pos > 0.4):
            out.append("hyrje afer mesit te range-it")
    return out


def describe(t, kind, tg):
    minutes = (t["t_out"] - t["t_in"]) / 60
    side = "BUY" if t["dir"] == 1 else "SELL"
    text = f"{t['model']} {side}: {LOSS_TYPES[kind]}"
    if kind == "L4":
        text += f" (maksimumi +{t['mfe']:.1f}R)"
    if kind in ("L1", "L2", "L3", "L4"):
        text += f"; SL pas {minutes:.0f} min"
    if kind in ("L5", "W2"):
        text += f"; {t['r']:+.2f}R pas {minutes / 60:.1f} oresh"
    if tg:
        text += " | " + ", ".join(tg)
    return text


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mt5", required=True, help="MT5 M15 (or finer) bar export")
    ap.add_argument("--mode", default="pro24", choices=("pro24", "combined", "active", "selective"))
    ap.add_argument("--start", default="2023-01-01")
    ap.add_argument("--end", default="2026-09-26")
    ap.add_argument("--out", help="CSV path (default ../reports/<mode>_trades.csv)")
    args = ap.parse_args()

    bars, _ = load_mt5([args.mt5])
    cfgs = {"pro24": pro24_set(), "combined": [ACTIVE, SELECTIVE], "active": [ACTIVE], "selective": [SELECTIVE]}[args.mode]
    t0 = datetime.strptime(args.start, "%Y-%m-%d").replace(tzinfo=timezone.utc).timestamp()
    t1 = datetime.strptime(args.end, "%Y-%m-%d").replace(tzinfo=timezone.utc).timestamp()
    trades = sorted((t for c in cfgs for t in run(bars, c)[0] if t0 <= t["t_in"] < t1), key=lambda x: x["t_in"])
    if not trades:
        raise SystemExit("no trades")

    out = args.out or os.path.join(os.path.dirname(__file__), "..", "reports", f"{args.mode}_trades.csv")
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    rows = []
    for n, t in enumerate(trades, 1):
        kind = classify(t)
        tg = tags(t)
        t["kind"], t["tags"] = kind, tg
        ny = datetime.fromtimestamp(t["t_in"] - NY, timezone.utc)
        rng_pos = (t["entry"] - t["rng_lo"]) / t["rng"] if t["rng"] else 0.0
        trend = (t["prev_close"] - t["trend_avg"]) / t["trend_avg"] * 100 if t["trend_avg"] else 0.0
        rows.append({
            "nr": n,
            "hyrja (server)": datetime.fromtimestamp(t["t_in"], timezone.utc).strftime("%Y-%m-%d %H:%M"),
            "hyrja (NY)": ny.strftime("%Y-%m-%d %H:%M"),
            "dita": DAYS[ny.weekday()],
            "qiriri H4": t["model"],
            "drejtimi": "BUY" if t["dir"] == 1 else "SELL",
            "entry": round(t["entry"], 2),
            "SL": round(t["sl"], 2),
            "TP": round(t["tp"], 2),
            "SL $": round(t["risk"], 2),
            "rezultati R": round(t["r"], 2),
            "dalja": t["why"],
            "minuta": round((t["t_out"] - t["t_in"]) / 60),
            "max ne favor R": round(t["mfe"], 2),
            "max kunder R": round(t["mae"], 2),
            "range low": round(t["rng_lo"], 2),
            "range high": round(t["rng_hi"], 2),
            "sweep": round(t["extreme"], 2),
            "sweep pertej range $": round(t["depth"], 2),
            "hyrja ne range %": round(rng_pos * 100),
            "trendi % nga mesatarja 50d": round(trend, 2),
            "SL / ATR ditore": round(t["risk"] / t["atr"], 2) if t["atr"] else "",
            "spread": round(t["spread"], 2),
            "lloji": kind,
            "pershkrimi": describe(t, kind, tg),
        })
    with open(out, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)

    half = trades[len(trades) // 2]["t_in"]
    A = [t for t in trades if t["t_in"] < half]
    B = [t for t in trades if t["t_in"] >= half]
    avg = lambda xs: sum(x["r"] for x in xs) / len(xs) if xs else 0.0
    total = sum(t["r"] for t in trades)
    print(f"{args.mode}: {len(trades)} trades {args.start} .. {args.end} | total {total:+.1f}R | avg {avg(trades):+.3f}R")
    print(f"CSV: {os.path.abspath(out)}\n")

    print("LOSS / WIN TYPES")
    for k in ("L1", "L2", "L3", "L4", "L5", "W1", "W2"):
        sub = [t for t in trades if t["kind"] == k]
        print(f"  {k} {len(sub):4d} trades {sum(t['r'] for t in sub):+7.1f}R  {LOSS_TYPES[k]}")

    print("\nCONTEXT TAGS (avg R per trade; overall first half "
          f"{avg(A):+.3f}, second half {avg(B):+.3f})")
    by = defaultdict(list)
    for t in trades:
        for g in t["tags"]:
            by[g].append(t)
    for g, sub in sorted(by.items(), key=lambda kv: avg(kv[1])):
        a = [t for t in sub if t["t_in"] < half]
        b = [t for t in sub if t["t_in"] >= half]
        flag = "  <- worse in BOTH halves" if a and b and avg(a) < avg(A) - 0.05 and avg(b) < avg(B) - 0.05 else ""
        print(f"  {g:<38} n={len(sub):4d} win={100 * sum(t['r'] > 0 for t in sub) / len(sub):4.1f}% "
              f"avg={avg(sub):+.3f} total={sum(t['r'] for t in sub):+6.1f}R | 1st {avg(a):+.3f} 2nd {avg(b):+.3f}{flag}")


if __name__ == "__main__":
    main()
