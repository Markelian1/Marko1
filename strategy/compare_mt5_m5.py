"""Python mirror vs MT5 Strategy Tester: XAUUSD M5, 2026-01-01 .. 2026-10-01.

MT5 run (FP Markets demo, hedge, EA defaults, 10,000 USD, 1% risk):
  net profit -683.87 (-6.84%), PF 0.96, expected payoff -0.61 (=> ~1121 deals),
  max equity drawdown 25.47%.

  python3 -I model/walkforward.py data/xauusd/XAUUSD_M5.csv.gz \
      data/derived/m5_rkf_2026.csv.gz --bin-min 5 --from-date 2025-12-01
  python3 -I strategy/compare_mt5_m5.py
"""

import sys
from dataclasses import replace
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from backtest import Config, prepare, run, stats  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
MT5 = {"trades": float("nan"), "fills (=deals MT5)": 1121, "win%": float("nan"), "PF": 0.96,
       "totR": float("nan"), "maxDD_R": 25.5, "1%risk_x": 1 - 0.0684}


def main():
    d = prepare(ROOT / "data/derived/m5_rkf_2026.csv.gz")
    d = d[d.dt >= "2025-12-29"].reset_index(drop=True)  # warm-up for ATR/Donchian
    ea = Config(trigger="donchian", module_b=True, module_c=True)  # EA defaults
    rows = {"MT5 Strategy Tester": MT5}
    for name, cfg in [("Python: EA default, kosto 0", ea),
                      ("Python: EA default, kosto 7 pike", replace(ea, cost_points=7)),
                      ("Python: baza pa module", Config()),
                      ("Python: + C", Config(module_c=True)),
                      ("Python: + A + B + C", replace(ea, module_a=True))]:
        t = run(d, cfg)
        t = t[t.dt >= "2026-01-01"]
        s = stats(t)
        s["fills (=deals MT5)"] = int(t.n_fills.sum())
        rows[name] = s
    cols = ["trades", "fills (=deals MT5)", "win%", "PF", "totR", "maxDD_R", "1%risk_x"]
    print(pd.DataFrame(rows).T[cols].to_string(float_format=lambda x: f"{x:8.3f}"))
    print("\n1%risk_x = equity perfundimtare / fillestare me 1% rrezik per sinjal "
          "(MT5: 9316.13 / 10000)")


if __name__ == "__main__":
    main()
