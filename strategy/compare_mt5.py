"""Python mirror vs MT5 Strategy Tester: XAUUSD M5 and M15, 2026-01-01 .. 2026-10-01.

MT5 runs with EA v1.00 (FP Markets demo, hedge, defaults, 10,000 USD, 1% risk):
  M5 : net -683.87 (-6.84%), PF 0.96, expected payoff -0.61 (=> ~1121 deals), max equity DD 25.47%
  M15: net -1619.46 (-16.19%), PF 0.88, expected payoff -1.62 (=> ~1000 deals), max equity DD 22.44%
v1.00 re-entered pending module-B slices after SL/TP (fixed in v1.01); the
"v1.00" rows emulate that behaviour.
EA v1.01, M15, same period: net -1414.67 (-14.15%), PF 0.90, expected payoff -1.48
(=> ~956 deals), max equity DD 21.06%  -> matched by Python v1.01 with ~22 points cost.

  python3 -I model/walkforward.py data/xauusd/XAUUSD_M5.csv.gz \
      data/derived/m5_rkf_2026.csv.gz --bin-min 5 --from-date 2025-12-01
  python3 -I strategy/compare_mt5.py
"""

import sys
from dataclasses import replace
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from backtest import Config, prepare, run, stats  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
MT5 = {
    "M5": {"fills (=deals MT5)": 1121, "PF": 0.96, "maxDD_R": 25.5, "1%risk_x": 1 - 0.0684},
    "M15": {"fills (=deals MT5)": 1000, "PF": 0.88, "maxDD_R": 22.4, "1%risk_x": 1 - 0.1619},
}
MT5_V101 = {"M15": {"fills (=deals MT5)": 956, "PF": 0.90, "maxDD_R": 21.1, "1%risk_x": 1 - 0.1415}}
SRC = {"M5": ("data/derived/m5_rkf_2026.csv.gz", "2025-12-29"), "M15": ("data/derived/m15_rkf.csv.gz", None)}
COLS = ["trades", "fills (=deals MT5)", "win%", "PF", "totR", "maxDD_R", "1%risk_x"]


def main():
    ea = Config(trigger="donchian", module_b=True, module_c=True)  # EA defaults
    for tf, (path, warm) in SRC.items():
        d = prepare(ROOT / path)
        if warm:
            d = d[d.dt >= warm].reset_index(drop=True)  # warm-up for ATR/Donchian
        rows = {"MT5 Strategy Tester (EA v1.00)": MT5[tf]}
        if tf in MT5_V101:
            rows["MT5 Strategy Tester (EA v1.01)"] = MT5_V101[tf]
        for name, cfg in [("Python: si EA v1.00, kosto 7", replace(ea, cost_points=7, emulate_v100_reentry=True)),
                          ("Python: EA v1.01, kosto 0", ea),
                          ("Python: EA v1.01, kosto 7", replace(ea, cost_points=7)),
                          ("Python: EA v1.01, kosto 22", replace(ea, cost_points=22)),
                          ("Python: baza pa module, kosto 7", Config(cost_points=7)),
                          ("Python: + C, kosto 7", Config(module_c=True, cost_points=7))]:
            t = run(d, cfg)
            t = t[t.dt >= "2026-01-01"]
            s = stats(t)
            s["fills (=deals MT5)"] = int(t.n_fills.sum())
            rows[name] = s
        print(f"\n=== XAUUSD {tf}, 2026-01-01 .. 2026-10-01 ===")
        print(pd.DataFrame(rows).T.reindex(columns=COLS).to_string(float_format=lambda x: f"{x:8.3f}"))
    print("\n1%risk_x = equity perfundimtare / fillestare me 1% rrezik per sinjal")


if __name__ == "__main__":
    main()
