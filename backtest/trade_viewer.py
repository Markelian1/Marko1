#!/usr/bin/env python3
"""Builds an interactive HTML trade viewer from a GOLD_MULTI_PRO journal.

Every trade of the journal is drawn on the M15 history: candles, the
time-based range and the sweep (CRT setups), entry, SL, TP, the exit and
the analysis the EA wrote when it opened the trade.

  python3 trade_viewer.py ../reports/gold_multi_pro_mt5_journal.csv out.html
"""
import csv
import json
import sys
from datetime import datetime, timezone


def ts(s):
    return int(datetime.strptime(s, "%Y.%m.%d %H:%M").replace(tzinfo=timezone.utc).timestamp())


def load_trades(path):
    raw = open(path, "rb").read()
    text = raw.decode("utf-16") if raw[:2] in (b"\xff\xfe", b"\xfe\xff") else raw.decode("latin-1")
    out = []
    for r in csv.DictReader(text.splitlines()):
        d = 1 if r["drejtimi"] == "BUY" else -1
        e, risk, R = float(r["entry"]), float(r["SL $"]), float(r["rezultati R"])
        out.append(dict(
            nr=int(r["nr"]), t=ts(r["hyrja (server)"]), ny=r["hyrja (NY)"], day=r["dita"], s=r["strategjia"],
            d=d, e=e, sl=float(r["SL"]), tp=float(r["TP"]), risk=risk, R=R, x=round(e + d * R * risk, 2),
            out=r["dalja"], m=int(r["minuta"]), mfe=float(r["max ne favor R"]), mae=float(r["max kunder R"]),
            lo=float(r["range low"]), hi=float(r["range high"]), sw=float(r["sweep"]),
            tr=float(r["trendi % nga mesatarja"]), k=r["lloji"], desc=r["pershkrimi"],
            why=r.get("arsyeja e hyrjes (analiza)", ""), pos=r.get("pozicioni", ""),
        ))
    return out


def load_bars(path, t0, t1):
    bars = []
    for line in open(path, encoding="utf-8-sig"):
        p = line.split("\t")
        if not p[0][:1].isdigit():
            continue
        t = int(datetime.strptime(p[0] + " " + p[1], "%Y.%m.%d %H:%M:%S").replace(tzinfo=timezone.utc).timestamp())
        if t0 <= t <= t1:
            bars.append((t, *(round(float(v) * 100) for v in p[2:6])))
    bars.sort()
    flat, pt, pc = [], 0, 0
    for t, o, h, l, c in bars:
        flat += [t // 60 - pt, o - pc, h - o, l - o, c - o]
        pt, pc = t // 60, c
    return flat


def main():
    journal, out = sys.argv[1], sys.argv[2]
    bars_path = sys.argv[3] if len(sys.argv) > 3 else "../data/XAUUSD_M15.csv"
    trades = load_trades(journal)
    flat = load_bars(bars_path, min(t["t"] for t in trades) - 12 * 86400, max(t["t"] + t["m"] * 60 for t in trades) + 4 * 86400)
    data = json.dumps(dict(trades=trades, bars=flat), separators=(",", ":"))
    html = open(__file__.replace("trade_viewer.py", "trade_viewer_template.html")).read().replace("__DATA__", data)
    open(out, "w").write(html)
    print(f"{len(trades)} trades, {len(flat) // 5} M15 bars -> {out} ({len(html) / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
