---
name: lpx-set-analyzer
description: Analyze a NEW MT5 walk-forward optimization XML (LPX or any EA) and pick the best set by real probability criteria, then validate its backtest XLSX. Use whenever the user uploads an MT5 optimization XML for a new instrument/timeframe/EA and asks "cual es el mejor set", "analiza esto", "que set uso", or uploads a backtest XLSX to verify a chosen set. Works standalone for any instrument and any prop-firm account.
---

# LPX Set Analyzer — PoPey Academy (edición comunidad)

Selects the best parameter set from an MT5 walk-forward optimization by out-of-sample probability, not raw profit. Then validates the chosen set's backtest. Run the bundled scripts — do not re-derive the pipeline by hand.

## Step 1 — Parse & analyze the optimization XML

```bash
python3 scripts/analyze_optimization.py <file.xml> [--target-months 2] [--risk 0.5] [--min-trades 95] [--dd-weight 0.16]
    [--fwd-frac 0.5] [--months N] [--rr-col ATR_RR] [--rr 2.5] [--plateau-min 0.5] [--out-dir .]
```

The script does, in order:
1. **Parse** SpreadsheetML (namespace `urn:schemas-microsoft-com:office:spreadsheet`, iterparse — files are ~30MB). Auto-detects param columns after the 11 standard metric columns; `true/false` inputs are kept. The test period is read from the title (`YYYY.MM.DD-YYYY.MM.DD`); if it is missing the script warns and you pass `--months`.
2. **Structure check**: corr(ProfitFactor, ForwardResult) must be ≈1.0 → confirms main metrics (Profit/DD/Trades) are the OOS forward segment. If it correlates with BackResult instead, the export is not walk-forward — stop and tell the user.
3. **Population report**: % profitable OOS, PF distribution, DD distribution. Benchmarks from validated instruments: GER40 66%, USDJPY 55%, XAU 42%, USOIL 27% (elite peaks), GBP-London 24%, GBP-NY 16% (rejected). Under ~20% = weak edge; treat as diversifier-only or recommend re-optimization.
4. **Session diagnostic**: profitability by LiquidityHour. If the edge rises monotonically toward a boundary of the tested range, the true edge likely sits OUTSIDE the range → recommend re-optimizing with extended hours before trusting any set. (This caught GBP-NY→London and USOIL 19h.)
5. **Hard gates**: Profit>0, FwdPF≥1.20, BackPF≥1.20, FwdPF≥0.85·BackPF, Sharpe>0, Recovery>0, Trades≥min-trades. Frequency matters more than RR for short target windows.
6. **Rank survivors**: z-composite (Sharpe .28 / Recovery .24 / FwdPF .18 / −DD .16 / IS-OOS consistency .08 / Trades .06; raise DD weight to .24 for volatile instruments like oil), then **Monte Carlo** the top 40 (WinRate=FwdPF/(FwdPF+RR), conservative frequency = forward is 1/2 of period, `--fwd-frac`) and re-rank by P(positive over target window), tiebreak worst-5%, median.
7. **Plateau check**: winner's neighbors (±1 grid step in each optimized param) must also be survivors — at least `--plateau-min` (50%) of the existing ones (`plat` column = surviving/existing). Solitary spikes are rejected and the script picks the best plateau member instead; if none of the top 40 is on a plateau it says so — prefer re-optimizing.

Output: winner's full input set (copy-paste ready), top-10 table, population verdict, gate fail counts, and any session-boundary warning. Files in `--out-dir`: `set_analyzer_top.csv` and `set_analyzer_winner.txt` (key=value, feed it to Step 2 with `--set`).

## Step 2 — Validate the backtest XLSX

When the user returns with the MT5 backtest report of the chosen set:

```bash
python3 scripts/validate_backtest.py <file.xlsx> [--expected-pf 1.46] [--deploy-risk 0.3] [--set set_analyzer_winner.txt]
    [--target 5] [--pf-tol 0.05] [--window-months 2] [--out-dir .]
```

Checks, in order:
1. Params in the report header match the recommended set (`--set`; any mismatch except RiskPercent → do not deploy); note the RiskPercent it ran at (user runs them at arbitrary risk — everything normalizes; ranking is risk-invariant).
2. **PF match**: report PF (`Factor de Beneficio`) within ±0.05 (`--pf-tol`) of optimization FwdPF (all 5 validated sets matched: 1.474/1.46, 1.646/1.66, 1.487/1.46, 2.024/1.99, 1.40 GBP). Mismatch → wrong set or data issue, do not deploy.
3. Realized-close stream from Balance diffs, starting from the report's `Depósito inicial` (handles partial closes; entry commissions ride with the next close; close-level win% ≠ report win%, expected).
4. Rolling 2-month calendar windows at deploy risk: median, P(>0), P(≥5%), worst, worst-5%; MaxDD; worst close / biggest win vs prop limits; monthly table. Stream saved to `set_analyzer_backtest.csv` (r at native risk).
5. **Directional bias**: shorts vs longs count. Long-only = regime-dependent → flag loudly (XAU, USOIL are long-only on 2024-26 bulls).
6. **Day-of-week attribution** by ENTRY day ('in' rows set entry time; 'out'/'out by' carry profit). Edge concentrated in one day = fragile → reject or fix session (GBP-NY hung on Friday; GBP-London spread across all 5 days).
7. **Multi-day/weekend holds** count → matters for prop-firm Master rules (weekend close).

## Judgment rules the scripts can't make

- Probability of hitting the target beats maximum profit. Frequency beats RR when the window is short.
- Never deploy from optimization alone; always demand the backtest.
- Diagnose before discarding: a weak population is often the wrong SESSION for the instrument (GBP needed London, JPY needed Tokyo 02-05 server), not a bad instrument. Session map (server GMT+3 summer / GMT+2 winter; Japan has no DST): London open ≈ 09-13, NY ≈ 15-20, Tokyo ≈ 02-05.
- If two configs of the same set are compared (e.g., day filters), measure rolling-window distributions of BOTH — summaries lie; and check per-day edge to detect overfit day-picking.
- Prop-firm sanity on any winner: standalone MaxDD at deploy risk should leave the combined portfolio ≤6% total; worst trade ≪ 1.2% (Striking) and ≪ 2% (risk/idea); largest single win ≪ 60% of phase target.
- Report in Spanish: the set block first, reasons after, one honest caveat, next action last.

## Principios para la comunidad

- **El criterio es siempre el mismo, sin importar quien lo corra:** probabilidad fuera-de-muestra, puertas duras, meseta sobre pico. Cada trader genera y optimiza SU propio XML — la skill garantiza que todos elijan con la misma calidad de criterio, no el mismo set.
- Si el resultado parece "poco rentable" comparado con el pase de mas profit, ese es el punto: el de mas profit casi siempre es curve-fit. La skill elige el que tiene mas probabilidad de repetirse en vivo.
- Esto es analisis estadistico sobre backtest, NO garantia de resultados futuros. Los edges se degradan; valida siempre con backtest antes de arriesgar capital.
Herramienta educativa de PoPey Academy. El trading con apalancamiento implica riesgo de perdida.
