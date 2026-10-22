# XAUUSD ICT Retest EA

`WickmorrowXAUUSD_ICT_Retest.mq5` is a separate Expert Advisor. It does not replace or modify `WickmorrowXAUUSDBreakout.mq5`.

## Rule summary

- Direction is eligible only when the most recent MSS and CISD point the same way and occur within the configured confirmation window.
- An order can trigger only after price first moves away from, then retests, a same-direction IFVG, breaker block, order block, or suspension block. Plain FVG and MSS+FVG annotations do not qualify as entry zones.
- MSS uses a confirmed pivot and a close or wick break. Swing selection can use the latest confirmed pivot or the extreme pivot in the lookback.
- CISD is the close or wick crossing the open of the nearest prior opposite-color candle, with the prior candle required to have not crossed that level.
- A three-candle FVG is the gap between the first and third candle ranges. An FVG invalidated beyond its far edge flips direction and is plotted as an IFVG.
- An order block is the nearest opposite-color candle before an MSS break. Its invalidation flips it into a breaker block. Suspension blocks are selected from the candle before the FVG displacement candle or the nearest opposite-color candle, depending on the input.
- Zone invalidation can use a candle close or a wick through the zone's distal edge. OB and suspension zone bounds can use the full candle or its body.

These are explicit, testable operational definitions for concepts that can be interpreted differently. They are a proposed hypothesis, not a claim that the strategy is profitable.

## Provisional Strategy Tester defaults

The defaults are provisional test settings based on the existing breakout EA's 0.10-lot / 500-point-stop baseline:

- Symbol: `XAUUSD`; signal timeframe: M5.
- Fixed volume: 0.10 lots.
- Stop loss: 500 symbol points.
- Take profit: 2R, meaning twice the configured stop distance.
- Maximum entries: one per server-time day.
- Position sizing can instead use a configurable balance-risk percentage.

The meaning of a point depends on the broker's XAUUSD quote precision. These defaults and the entry rules are not validated performance results.

## Load and run a test

1. In MetaTrader 5 desktop, choose **File → Open Data Folder**.
2. Copy `WickmorrowXAUUSD_ICT_Retest.mq5` into `MQL5/Experts/` in that data folder.
3. Open the file in MetaEditor and press **F7** to compile. The compiled EA should appear under **Navigator → Expert Advisors**.
4. In MT5, open **View → Strategy Tester** (or press **Ctrl+R**), select this EA, choose the broker's exact XAUUSD symbol and M5 timeframe, set a date range with available history, and choose **Every tick based on real ticks**.
5. Start with the provisional defaults, enable visual mode if you want to inspect the plotted annotations and retests, then run the test. Review the trade list and chart to confirm that direction required matching MSS/CISD, entries followed an eligible-zone retest, and stops/targets and the daily cap match the inputs.

If the broker names gold with a suffix, set `InpTradeSymbol` to that exact symbol before compiling or running. This repository does not include a Strategy Tester report or claim that a test has been run.
