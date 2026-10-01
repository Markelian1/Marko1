#!/usr/bin/env python3
"""Simulation of GOLD_MULTI_PRO.mq5: the six setups as one portfolio.

  1-3  CRT H4, daily CRT, inside day      (crt_1am_backtest.py via strategy_lab.py)
  4-6  displacement, Bollinger pullback,  (strategy_search.py, M30 execution;
       CCI pullback                        H4 signals with wide stops, the same on M15 / M5)

Prints every setup and the portfolio for 2020.03-22.06, 2022.07-24.06 and
2024.07-26.09, and the money result at 0.1% risk per trade. The daily loss
limit and the max drawdown stop of the EA are not simulated.

  python3 gold_multi_pro.py      (from backtest/)
"""
import sys
from datetime import datetime, timezone

sys.path.insert(0, ".")
import strategy_lab as L
import strategy_search as S


def setups():
    cci = S.mean_rev(S.cci_x, lambda I, k: I["cci"][k] is not None and I["cci"][k] > 100,
                     lambda I, k: I["cci"][k] is not None and I["cci"][k] < -100)
    return {
        "1 CRT H4": L.pro24(),
        "2 Daily CRT": L.crt_daily(tf=1800),
        "3 Inside day": L.inside_day(),
        "4 Displacement": S.take(S.trend_family(S.big_bar(False, 2.5))("H4", False, (1.5, 2.0))),
        "5 BB pullback": S.take(S.bb_fade("H4", True, (0.3, "mid"))),
        "6 CCI pullback": S.take(cci("H4", True, ("sig", 2.0))),
    }


def money(tr, t0, t1, risk=0.001):
    x = sorted([t for t in tr if t0 <= t["t_in"] < t1], key=lambda t: t["t_out"])
    bal = peak = 1.0
    dd = 0.0
    cl = mcl = 0
    for t in x:
        bal *= 1 + risk * t["r"]
        peak = max(peak, bal)
        dd = max(dd, 1 - bal / peak)
        cl = cl + 1 if t["r"] < 0 else 0
        mcl = max(mcl, cl)
    return len(x), 100 * (bal - 1), 100 * dd, mcl, 100 * sum(t["r"] > 0 for t in x) / max(1, len(x))


def main():
    st = setups()
    print(f"{'':16}" + " | ".join(f"{n:^43}" for n in L.NAMES))
    allt = []
    for name, tr in st.items():
        allt += tr
        print(f"{name:16}" + " | ".join(L.cell(L.split(tr, k)) for k in range(3)))
    print(f"{'PORTFOLIO':16}" + " | ".join(L.cell(L.split(allt, k)) for k in range(3)))
    base = st["1 CRT H4"] + st["2 Daily CRT"] + st["3 Inside day"]
    print(f"{'(setups 1-3)':16}" + " | ".join(L.cell(L.split(base, k)) for k in range(3)))
    t23 = datetime(2023, 1, 1, tzinfo=timezone.utc).timestamp()
    t26 = datetime(2026, 9, 26, tzinfo=timezone.utc).timestamp()
    print("\nat 0.1% risk per trade:")
    for name, tr in (("all six", allt), ("setups 1-3", base)):
        for lab, t0, t1 in (("2020.03-2026.09", L.P[0], L.P[3]), ("2023.01-2026.09 (MT5 test)", t23, t26)):
            n, p, dd, mcl, win = money(tr, t0, t1)
            print(f"  {name:11} {lab:27} {n:5d} trades  win {win:4.1f}%  profit {p:+6.1f}%  max DD {dd:4.2f}%  "
                  f"max losses in a row {mcl}")


if __name__ == "__main__":
    main()
