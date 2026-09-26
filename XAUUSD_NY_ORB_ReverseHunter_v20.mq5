//+------------------------------------------------------------------+
//|                          XAUUSD_NY_ORB_ReverseHunter_v20.mq5     |
//|   New York Opening-Range "Reverse Hunter" for XAUUSD (gold spot) |
//|                                                                  |
//|   v2.0 -- trade the FAILED breakout, both directions:            |
//|     + The EA always follows a virtual breakout: the first M1     |
//|       close beyond the NY opening range (no filters), SL at the  |
//|       far side, TP rr x width beyond the range. When that        |
//|       breakout is stopped out, the EA enters once the other way. |
//|       2020-2026 journals: the breakout alone was ~0R out of      |
//|       sample, the reversal after it +44R with half the drawdown. |
//|     + InpTradeBreakout (default false) also trades the breakout  |
//|       itself with the trend / range filters, as in v1.9.         |
//|     + Risk sizing on by default (0.5% of equity per trade).      |
//|                                                                  |
//|   v1.9 -- reversal module (both directions):                     |
//|     + When the session's breakout trade is stopped out, enter    |
//|       once in the OPPOSITE direction (failed short -> long,      |
//|       failed long -> short): SL at the far side of the range,    |
//|       TP rr_target x width beyond the range, like a breakout.    |
//|       No trend filter on the reversal: it is a counter-signal.   |
//|     + Journal: trades.csv gets a "module" column (BREAKOUT /     |
//|       REVERSAL); sessions.csv gets a shadow reversal (rv_*)      |
//|       after every stopped-out shadow breakout.                   |
//|                                                                  |
//|   v1.8 -- analysis journal (trading logic identical to v1.7):    |
//|     + Writes two CSV files to Terminal\Common\Files during a     |
//|       single backtest (not during optimization):                 |
//|       <prefix>_sessions.csv -- one row per session: range, median|
//|         ratio, daily SMA distance, the filter decision, and a    |
//|         "shadow" trade: the unfiltered breakout the EA would     |
//|         take, followed to TP / SL / session flatten.             |
//|       <prefix>_trades.csv -- one row per real trade: entry, exit,|
//|         reason, P/L, result in R, MFE / MAE in R, context.       |
//|     + Optional breakeven: InpBreakevenR > 0 moves the SL to the  |
//|       entry once a trade is that many R in profit (default off). |
//|                                                                  |
//|   v1.7 -- trend filter:                                          |
//|     + With InpTrendDays > 0, longs only when the last closed M1  |
//|       candle is above the daily SMA(InpTrendDays) of the last    |
//|       completed day, shorts only below it. A breakout against    |
//|       the trend consumes the session (no chasing the other side).|
//|       In 2024 most losses came from shorts against gold's uptrend.|
//|                                                                  |
//|   v1.6 -- range band:                                            |
//|     + InpMinRangeRatio also skips sessions NARROWER than that    |
//|       multiple of the median (very quiet opens lacked follow-    |
//|       through in the 2025-2026 MT5 tests).                       |
//|     + Defaults set to the tested band: 0.7x .. 1.0x median.      |
//|                                                                  |
//|   v1.5 -- relative range filter:                                 |
//|     + Skip sessions whose opening range is wider than            |
//|       InpMaxRangeRatio x the median range of the previous        |
//|       InpAvgDays sessions. Adapts as gold's price and volatility |
//|       change, unlike the fixed-dollar filter. While fewer than   |
//|       InpAvgDays sessions are recorded, the filter stands down   |
//|       from trading (warm-up).                                    |
//|                                                                  |
//|   v1.4 -- changes vs v1.0 (logic otherwise identical):           |
//|     + Max range filter: skip sessions whose opening range is     |
//|       wider than InpMaxRangePrice (price units, e.g. 15.0 = $15).|
//|     + Last entry time: no new entries after InpLastEntryHour:Min.|
//|     + Optional risk sizing: InpRiskPercent > 0 sizes the lot so  |
//|       the stop costs that % of equity (0 = fixed InpLotSize).    |
//|                                                                  |
//|     Range  = first N minutes of the NY session (RTH open, ET).   |
//|     Entry  = stop order at range high (long) / range low (short).|
//|     Stop   = opposite side of the range.                         |
//|     Target = rr_target x R, where R = range width.               |
//|     One trade per session; flat at the session close.            |
//|                                                                  |
//|   Backtest on XAUUSD, any chart TF <= range length in minutes.   |
//+------------------------------------------------------------------+
#property copyright "Roboquant AI"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>

//====================== INPUTS ======================================
input group "=== Session clock (broker server time) ==="
input int    InpSessionOpenHour = 16;    // NY RTH open hour (server time, 16 = 09:30 ET @ GMT+3)
input int    InpSessionOpenMin  = 30;    // NY RTH open minute
input int    InpRangeMinutes    = 30;    // Opening range length (min)
input int    InpLastEntryHour   = 18;    // Last entry hour (server time, 18 = 11:30 ET @ GMT+3)
input int    InpLastEntryMinute = 30;    // Last entry minute
input int    InpFlatHour        = 23;    // Flatten hour (server time, 23 = 16:00 ET @ GMT+3)
input int    InpFlatMinute      = 0;     // Flatten minute

input group "=== Trade economics ==="
input double InpRrTarget        = 2.0;   // Target (R multiple)
input double InpBreakevenR      = 0.0;   // Move SL to entry after +X R in profit (0 = off)
input double InpLotSize         = 0.10;  // Lot size per trade (used when risk % = 0)
input double InpRiskPercent     = 0.5;   // Risk per trade (% of equity, 0 = fixed lot)
input double InpMaxLots         = 1.00;  // Max lots (risk sizing cap)
input bool   InpAllowLong       = true;  // Allow longs
input bool   InpAllowShort      = true;  // Allow shorts

input group "=== Execution ==="
input int    InpMagic           = 20260926; // Magic number
input ulong  InpSlippagePoints  = 30;    // Max deviation (points)
input int    InpMaxAttempts     = 3;     // Max order attempts per session
input bool   InpRequireClose    = true;  // LONG/SHORT only on CLOSE beyond range

input group "=== Filters (optional, 0 = off) ==="
input int    InpMinRangePoints  = 0;     // Min range height (points, 0 = off)
input double InpMaxRangePrice   = 0.0;   // Max range height (price, 15.0 = $15 on gold, 0 = off)
input int    InpMaxSpreadPoints = 0;     // Max spread (points, 0 = off)
input bool   InpSkipFriday      = false; // Skip Friday
input bool   InpSkipMonday      = false; // Skip Monday

input group "=== Relative range filter (0 = off) ==="
input double InpMaxRangeRatio   = 0.0;   // Max range vs median of last N days (1.5 = 150%, 0 = off)
input double InpMinRangeRatio   = 0.5;   // Min range vs median of last N days (0.7 = 70%, 0 = off)
input int    InpAvgDays         = 20;    // N days for the median range

input group "=== Trend filter (0 = off) ==="
input int    InpTrendDays       = 50;    // Trend SMA on D1 (days, 0 = off)

input group "=== Drawing ==="
input bool   InpDrawBox         = true;  // Draw opening range box

input group "=== Journal (CSV for analysis) ==="
input bool   InpWriteJournal    = true;  // Write session + trade CSV files (single backtests only)
input string InpJournalPrefix   = "ORB"; // File name prefix (Terminal\Common\Files)

input group "=== Modules ==="
input bool   InpTradeBreakout   = false; // Also trade the breakout itself (false = watch only)
input bool   InpUseReversal     = true;  // Enter the opposite way once the breakout is stopped out
input int    InpRevLastHour     = 20;    // Last reversal entry hour (server time, 20 = 13:00 ET @ GMT+3)
input int    InpRevLastMinute   = 0;     // Last reversal entry minute

//====================== GLOBALS =====================================
CTrade  trade;

int      g_day         = -1;   // current session day-of-year + year marker
int      g_dayOfYear   = -1;
int      g_year        = -1;
double   g_rangeHigh   = 0.0;
double   g_rangeLow    = 0.0;
bool     g_haveRange   = false;
bool     g_rangeFrozen = false;
bool     g_traded      = false;

ulong    g_buyStopTicket  = 0;
ulong    g_sellStopTicket = 0;

// --- per-bar evaluation gate + order-attempt guard ---
datetime g_lastBarTime = 0;
int      g_attempts    = 0;

string   g_boxName     = "";

// --- daily SMA handle for the trend filter ---
int      g_trendHandle = INVALID_HANDLE;

// --- opening-range history (ring buffer) for the relative filter ---
double   g_rangeHist[];
int      g_histCount   = 0;
int      g_histPos     = 0;
double   g_medRange    = 0.0;  // median of PREVIOUS sessions, set at freeze (0 = warming up)

// --- journal (CSV) ---
bool     g_journal        = false;
int      g_sessFile       = INVALID_HANDLE;
int      g_tradeFile      = INVALID_HANDLE;
int      g_journalSma     = INVALID_HANDLE;  // SMA(50) D1 for logging when the trend filter is off

// session row being collected (written at the flatten time)
bool     g_sessOpen       = false;
string   g_sessDecision   = "";
datetime g_sessDate       = 0;
double   g_sessMedian     = 0.0;
double   g_sessSma        = 0.0;
double   g_sessPxVsSma    = 0.0;   // % distance of price from the daily SMA at the freeze
double   g_sessHi         = 0.0;   // highest bid after the range froze
double   g_sessLo         = 0.0;   // lowest bid after the range froze

// shadow trade: the unfiltered breakout the EA WOULD take, on every session
int      g_shDir          = 0;     // 0 none, 1 long, -1 short
bool     g_shActive       = false;
bool     g_shDone         = false;
datetime g_shTime         = 0;
datetime g_shBarTime      = 0;
double   g_shEntry        = 0.0;
double   g_shSL           = 0.0;
double   g_shTP           = 0.0;
double   g_shExit         = 0.0;
double   g_shMfe          = 0.0;
double   g_shMae          = 0.0;
bool     g_shHit1R        = false; // reached +1R before the exit
bool     g_shBack1R       = false; // came back to the entry after reaching +1R
string   g_shOutcome      = "";

// real trade being followed
bool     g_inTrade        = false;
int      g_trDir          = 0;
datetime g_trOpenTime     = 0;
double   g_trEntry        = 0.0;
double   g_trSL           = 0.0;
double   g_trTP           = 0.0;
double   g_trLots         = 0.0;
double   g_trInCost       = 0.0;   // commission charged on the entry deal
double   g_trMfe          = 0.0;
double   g_trMae          = 0.0;
double   g_trWidth        = 0.0;
double   g_trMedian       = 0.0;
double   g_trSma          = 0.0;
double   g_trPxVsSma      = 0.0;
double   g_pendSL         = 0.0;   // SL / TP of the last order sent (fallback for the journal)
double   g_pendTP         = 0.0;
string   g_pendModule     = "BREAKOUT";  // module of the last order sent
string   g_trModule       = "BREAKOUT";  // module of the open trade (journal)

// --- reversal module (works with or without the journal) ---
int      g_revPending     = 0;     // +1 buy / -1 sell requested after a stopped-out breakout
bool     g_revDone        = false; // one reversal per session
string   g_openModule     = "";    // module of the position currently open

// shadow reversal: after the shadow breakout is stopped out (journal)
int      g_rvDir          = 0;
bool     g_rvActive       = false;
bool     g_rvDone         = false;
datetime g_rvTime         = 0;
double   g_rvEntry        = 0.0;
double   g_rvSL           = 0.0;
double   g_rvTP           = 0.0;
double   g_rvExit         = 0.0;
double   g_rvMfe          = 0.0;
double   g_rvMae          = 0.0;
string   g_rvOutcome      = "";

// virtual breakout: followed on every session, journal or not; its stop-out
// triggers the reversal (same rules as the journal's shadow breakout)
int      g_vbDir          = 0;
bool     g_vbActive       = false;
bool     g_vbDone         = false;
datetime g_vbBarTime      = 0;
double   g_vbSL           = 0.0;
double   g_vbTP           = 0.0;

//====================== HELPERS =====================================

//--- Median of the recorded opening ranges (0 until N sessions are stored)
double MedianRange()
{
   int n = ArraySize(g_rangeHist);
   if(n < 1 || g_histCount < n) return 0.0;

   double tmp[];
   ArrayCopy(tmp, g_rangeHist, 0, 0, n);
   ArraySort(tmp);
   if(n % 2 == 1) return tmp[n / 2];
   return (tmp[n / 2 - 1] + tmp[n / 2]) / 2.0;
}

//--- Record one session's opening-range width
void PushRange(const double width)
{
   int n = ArraySize(g_rangeHist);
   if(n < 1) return;
   g_rangeHist[g_histPos] = width;
   g_histPos = (g_histPos + 1) % n;
   if(g_histCount < n) g_histCount++;
}

//--- Is the current server time inside the opening-range window?
bool InRangeWindow(const MqlDateTime &t)
{
   int nowMin   = t.hour * 60 + t.min;
   int openMin  = InpSessionOpenHour * 60 + InpSessionOpenMin;
   int rangeEnd = openMin + MathMax(InpRangeMinutes, 1);
   return (nowMin >= openMin && nowMin < rangeEnd);
}

//--- Is it after the last allowed entry time?
bool PastRevLastEntry(const MqlDateTime &t)
{
   int nowMin  = t.hour * 60 + t.min;
   int lastMin = InpRevLastHour * 60 + InpRevLastMinute;
   return (nowMin > lastMin);
}

bool PastLastEntry(const MqlDateTime &t)
{
   int nowMin   = t.hour * 60 + t.min;
   int lastMin  = InpLastEntryHour * 60 + InpLastEntryMinute;
   return (nowMin > lastMin);
}

//--- Is it at/after the flatten time?
bool AtFlattenTime(const MqlDateTime &t)
{
   int nowMin   = t.hour * 60 + t.min;
   int flatMin  = InpFlatHour * 60 + InpFlatMinute;
   return (nowMin >= flatMin);
}

//--- New session detection (resets per-day state)
bool NewSession(const MqlDateTime &t)
{
   if(t.day_of_year != g_dayOfYear || t.year != g_year)
   {
      g_dayOfYear = t.day_of_year;
      g_year      = t.year;
      return true;
   }
   return false;
}

//--- Lot size for a trade from entry to stop.
//    Fixed InpLotSize when InpRiskPercent = 0; otherwise the lot whose
//    stop loss costs InpRiskPercent of equity, capped at InpMaxLots.
//    Returns 0 when even the minimum lot would risk more than the budget.
double CalcLots(const double entry, const double stop)
{
   if(InpRiskPercent <= 0.0) return InpLotSize;

   double dist      = MathAbs(entry - stop);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double volStep   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double volMin    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volMax    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(dist <= 0.0 || tickSize <= 0.0 || tickValue <= 0.0 || volStep <= 0.0)
      return 0.0;

   double lossPerLot = dist / tickSize * tickValue;
   double budget     = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0;
   double lots       = MathFloor(budget / lossPerLot / volStep) * volStep;
   lots = MathMin(lots, MathMin(volMax, InpMaxLots));
   if(lots < volMin) return 0.0;

   int volDigits = (int)MathMax(0.0, MathCeil(-MathLog10(volStep)));
   return NormalizeDouble(lots, volDigits);
}

//--- Count our open positions and their net direction
int CountMyPositions(int &direction)
{
   direction = 0;
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      count++;
      long type = PositionGetInteger(POSITION_TYPE);
      if(type == POSITION_TYPE_BUY)  direction += 1;
      if(type == POSITION_TYPE_SELL) direction -= 1;
   }
   return count;
}

//--- Delete our pending stop orders
void DeletePendingStops()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;

      long type = OrderGetInteger(ORDER_TYPE);
      if(type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP)
         trade.OrderDelete(ticket);
   }
   g_buyStopTicket  = 0;
   g_sellStopTicket = 0;
}

//--- Close everything we own on this symbol
void FlattenAll()
{
   DeletePendingStops();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      trade.PositionClose(ticket);
   }
}

//--- Draw / update the opening-range box
void DrawRangeBox(const datetime tStart, const datetime tEnd,
                  const double hi, const double lo)
{
   if(!InpDrawBox) return;

   if(g_boxName == "")
      g_boxName = StringFormat("ORB_%s_%d", _Symbol, InpMagic);

   if(ObjectFind(0, g_boxName) < 0)
   {
      ObjectCreate(0, g_boxName, OBJ_RECTANGLE, 0, tStart, hi, tStart, lo);
      ObjectSetInteger(0, g_boxName, OBJPROP_COLOR, clrRoyalBlue);
      ObjectSetInteger(0, g_boxName, OBJPROP_FILL, true);
      ObjectSetInteger(0, g_boxName, OBJPROP_BACK, true);
      ObjectSetInteger(0, g_boxName, OBJPROP_SELECTABLE, false);
   }
   // grow/refresh the box with the live range
   ObjectSetInteger(0, g_boxName, OBJPROP_TIME, 0, tStart);
   ObjectSetDouble (0, g_boxName, OBJPROP_PRICE, 0, hi);
   ObjectSetInteger(0, g_boxName, OBJPROP_TIME, 1, tEnd);
   ObjectSetDouble (0, g_boxName, OBJPROP_PRICE, 1, lo);
}

//====================== BREAKEVEN ===================================

//--- Move the SL of our open positions to the entry once they are
//    InpBreakevenR x the initial risk in profit. Stateless: a position
//    whose SL already sits at/beyond the entry is left alone.
void ApplyBreakeven(const double bid, const double ask)
{
   if(InpBreakevenR <= 0.0) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      long   type = PositionGetInteger(POSITION_TYPE);
      if(sl <= 0.0) continue;

      if(type == POSITION_TYPE_BUY && sl < open)
      {
         double risk = open - sl;
         if(bid - open >= InpBreakevenR * risk && trade.PositionModify(ticket, open, tp))
            PrintFormat("Breakeven: LONG SL moved to entry %.2f", open);
      }
      else if(type == POSITION_TYPE_SELL && sl > open)
      {
         double risk = sl - open;
         if(open - ask >= InpBreakevenR * risk && trade.PositionModify(ticket, open, tp))
            PrintFormat("Breakeven: SHORT SL moved to entry %.2f", open);
      }
   }
}

//====================== JOURNAL =====================================

string WeekdayName(const datetime when)
{
   MqlDateTime d;
   TimeToStruct(when, d);
   string names[] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
   return names[d.day_of_week];
}

string Px(const double v)   { return DoubleToString(v, _Digits); }
string Num(const double v)  { return DoubleToString(v, 3); }

//--- Daily SMA of the last completed day (trend handle, or the journal's own SMA(50))
double JournalSmaValue()
{
   int handle = (g_trendHandle != INVALID_HANDLE) ? g_trendHandle : g_journalSma;
   if(handle == INVALID_HANDLE) return 0.0;
   double sma[1];
   if(CopyBuffer(handle, 0, 1, 1, sma) != 1) return 0.0;
   return sma[0];
}

//--- Open both CSV files (single backtests only) and write the headers
void JournalOpen()
{
   g_journal = InpWriteJournal && !(bool)MQLInfoInteger(MQL_OPTIMIZATION);
   if(!g_journal) return;

   if(g_trendHandle == INVALID_HANDLE)
      g_journalSma = iMA(_Symbol, PERIOD_D1, 50, 0, MODE_SMA, PRICE_CLOSE);

   string sessName  = InpJournalPrefix + "_sessions.csv";
   string tradeName = InpJournalPrefix + "_trades.csv";
   g_sessFile  = FileOpen(sessName,  FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
   g_tradeFile = FileOpen(tradeName, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
   if(g_sessFile == INVALID_HANDLE || g_tradeFile == INVALID_HANDLE)
   {
      PrintFormat("Journal disabled: could not open %s / %s (error %d)",
                  sessName, tradeName, GetLastError());
      if(g_sessFile  != INVALID_HANDLE) FileClose(g_sessFile);
      if(g_tradeFile != INVALID_HANDLE) FileClose(g_tradeFile);
      g_sessFile  = INVALID_HANDLE;
      g_tradeFile = INVALID_HANDLE;
      g_journal   = false;
      return;
   }

   FileWrite(g_sessFile,
             "date", "weekday", "range_low", "range_high", "width", "median", "ratio",
             "sma_d1", "px_vs_sma_pct", "decision",
             "sh_dir", "sh_time", "sh_entry", "sh_sl", "sh_tp", "sh_exit", "sh_outcome",
             "sh_R", "sh_mfe_R", "sh_mae_R", "sh_hit_1R", "sh_back_to_entry_after_1R",
             "high_after_range", "low_after_range",
             "rv_dir", "rv_time", "rv_entry", "rv_sl", "rv_tp", "rv_exit", "rv_outcome",
             "rv_R", "rv_mfe_R", "rv_mae_R");
   FileWrite(g_tradeFile,
             "open_time", "close_time", "dir", "lots", "entry", "sl", "tp", "exit",
             "exit_reason", "profit_usd", "risk_price", "result_R", "mfe_R", "mae_R",
             "minutes", "range_width", "median", "ratio", "sma_d1", "px_vs_sma_pct",
             "hour", "weekday", "module");
}

//--- Start collecting the session row at the moment the range freezes
void SessionStart()
{
   if(!g_journal) return;

   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double last = iClose(_Symbol, PERIOD_M1, 1);

   g_sessOpen     = true;
   g_sessDecision = InpTradeBreakout ? "NO_BREAKOUT" : "WATCH_ONLY";
   g_sessDate     = TimeCurrent();
   g_sessMedian   = g_medRange;
   g_sessSma      = JournalSmaValue();
   g_sessPxVsSma  = (g_sessSma > 0.0 && last > 0.0) ? (last - g_sessSma) / g_sessSma * 100.0 : 0.0;
   g_sessHi       = bid;
   g_sessLo       = bid;

   g_shDir     = 0;
   g_shActive  = false;
   g_shDone    = false;
   g_shTime    = 0;
   g_shBarTime = 0;
   g_shEntry   = 0.0;
   g_shSL      = 0.0;
   g_shTP      = 0.0;
   g_shExit    = 0.0;
   g_shMfe     = 0.0;
   g_shMae     = 0.0;
   g_shHit1R   = false;
   g_shBack1R  = false;
   g_shOutcome = "";

   g_rvDir     = 0;
   g_rvActive  = false;
   g_rvDone    = false;
   g_rvTime    = 0;
   g_rvEntry   = 0.0;
   g_rvSL      = 0.0;
   g_rvTP      = 0.0;
   g_rvExit    = 0.0;
   g_rvMfe     = 0.0;
   g_rvMae     = 0.0;
   g_rvOutcome = "";
}

//--- Record why the session did (not) trade; the last decision wins
void SetDecision(const string decision)
{
   if(g_journal && g_sessOpen) g_sessDecision = decision;
}

void ShadowClose(const double price, const string outcome)
{
   g_shExit    = price;
   g_shOutcome = outcome;
   g_shActive  = false;
   g_shDone    = true;
}

void RevShadowClose(const double price, const string outcome)
{
   g_rvExit    = price;
   g_rvOutcome = outcome;
   g_rvActive  = false;
   g_rvDone    = true;
}

//--- Open the shadow reversal right after the shadow breakout is stopped out
void RevShadowOpen(const MqlDateTime &t, const double bid, const double ask)
{
   if(g_rvDone || g_rvActive) return;
   g_rvDone = true;                      // one attempt per session
   if(PastRevLastEntry(t)) return;

   double width = g_rangeHigh - g_rangeLow;
   if(width <= 0.0) return;

   if(g_shDir == -1)                     // failed short -> reversal long
   {
      g_rvEntry = ask;
      g_rvSL    = g_rangeLow;
      g_rvTP    = g_rangeHigh + InpRrTarget * width;
      if(g_rvEntry <= g_rvSL || g_rvTP <= g_rvEntry) return;
      g_rvDir   = 1;
   }
   else if(g_shDir == 1)                 // failed long -> reversal short
   {
      g_rvEntry = bid;
      g_rvSL    = g_rangeHigh;
      g_rvTP    = g_rangeLow - InpRrTarget * width;
      if(g_rvEntry >= g_rvSL || g_rvTP >= g_rvEntry) return;
      g_rvDir   = -1;
   }
   else return;

   g_rvDone   = false;
   g_rvActive = true;
   g_rvTime   = TimeCurrent();
}

//--- Follow the shadow reversal to TP / SL
void RevShadowUpdate(const double bid, const double ask)
{
   if(!g_rvActive) return;
   double px  = (g_rvDir == 1) ? bid : ask;
   double fav = (g_rvDir == 1) ? px - g_rvEntry : g_rvEntry - px;
   if(fav > g_rvMfe)  g_rvMfe = fav;
   if(-fav > g_rvMae) g_rvMae = -fav;

   if(g_rvDir == 1)
   {
      if(bid <= g_rvSL)      RevShadowClose(g_rvSL, "SL");
      else if(bid >= g_rvTP) RevShadowClose(g_rvTP, "TP");
   }
   else
   {
      if(ask >= g_rvSL)      RevShadowClose(g_rvSL, "SL");
      else if(ask <= g_rvTP) RevShadowClose(g_rvTP, "TP");
   }
}

//--- Follow the shadow trade (unfiltered breakout, same entry/SL/TP rules)
void ShadowUpdate(const MqlDateTime &t, const double bid, const double ask)
{
   if(!g_journal || !g_sessOpen) return;

   if(bid > g_sessHi) g_sessHi = bid;
   if(bid < g_sessLo) g_sessLo = bid;

   RevShadowUpdate(bid, ask);

   if(g_shActive)
   {
      double risk = MathAbs(g_shEntry - g_shSL);
      double px   = (g_shDir == 1) ? bid : ask;       // the side that closes the trade
      double fav  = (g_shDir == 1) ? px - g_shEntry : g_shEntry - px;
      if(fav > g_shMfe)  g_shMfe = fav;
      if(-fav > g_shMae) g_shMae = -fav;
      if(risk > 0.0 && g_shMfe >= risk) g_shHit1R = true;
      if(g_shHit1R && fav <= 0.0)       g_shBack1R = true;

      if(g_shDir == 1)
      {
         if(bid <= g_shSL)      ShadowClose(g_shSL, "SL");
         else if(bid >= g_shTP) ShadowClose(g_shTP, "TP");
      }
      else
      {
         if(ask >= g_shSL)      ShadowClose(g_shSL, "SL");
         else if(ask <= g_shTP) ShadowClose(g_shTP, "TP");
      }
      if(g_shOutcome == "SL") RevShadowOpen(t, bid, ask);
      return;
   }

   if(g_shDone || PastLastEntry(t)) return;

   // one evaluation per new M1 bar, on the closed candle (same rule as the EA)
   datetime barTime = iTime(_Symbol, PERIOD_M1, 0);
   if(barTime == g_shBarTime) return;
   g_shBarTime = barTime;

   double closed = iClose(_Symbol, PERIOD_M1, 1);
   double width  = g_rangeHigh - g_rangeLow;
   if(closed <= 0.0 || width <= 0.0) return;

   if(closed > g_rangeHigh)
   {
      g_shDir   = 1;
      g_shEntry = ask;
      g_shSL    = g_rangeLow;
      g_shTP    = g_rangeHigh + InpRrTarget * width;
   }
   else if(closed < g_rangeLow)
   {
      g_shDir   = -1;
      g_shEntry = bid;
      g_shSL    = g_rangeHigh;
      g_shTP    = g_rangeLow - InpRrTarget * width;
   }
   else return;

   g_shActive = true;
   g_shTime   = TimeCurrent();
}

//--- Write the collected session row (at the flatten time or when the day ends)
void SessionWrite()
{
   if(!g_journal || !g_sessOpen) return;

   if(g_shActive)
   {
      double px = (g_shDir == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                 : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      ShadowClose(px, "FLAT");
   }
   if(g_rvActive)
   {
      double px = (g_rvDir == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                 : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      RevShadowClose(px, "FLAT");
   }

   double width = g_rangeHigh - g_rangeLow;
   double ratio = (g_sessMedian > 0.0) ? width / g_sessMedian : 0.0;
   double risk  = MathAbs(g_shEntry - g_shSL);
   double shR   = (g_shDir != 0 && risk > 0.0) ? g_shDir * (g_shExit - g_shEntry) / risk : 0.0;
   double mfeR  = (risk > 0.0) ? g_shMfe / risk : 0.0;
   double maeR  = (risk > 0.0) ? g_shMae / risk : 0.0;

   double rvRisk = MathAbs(g_rvEntry - g_rvSL);
   double rvR    = (g_rvDir != 0 && rvRisk > 0.0) ? g_rvDir * (g_rvExit - g_rvEntry) / rvRisk : 0.0;
   double rvMfeR = (rvRisk > 0.0) ? g_rvMfe / rvRisk : 0.0;
   double rvMaeR = (rvRisk > 0.0) ? g_rvMae / rvRisk : 0.0;

   FileWrite(g_sessFile,
             TimeToString(g_sessDate, TIME_DATE), WeekdayName(g_sessDate),
             Px(g_rangeLow), Px(g_rangeHigh), Px(width), Px(g_sessMedian), Num(ratio),
             Px(g_sessSma), Num(g_sessPxVsSma), g_sessDecision,
             (g_shDir == 1 ? "LONG" : (g_shDir == -1 ? "SHORT" : "-")),
             (g_shDir != 0 ? TimeToString(g_shTime, TIME_DATE | TIME_MINUTES) : "-"),
             Px(g_shEntry), Px(g_shSL), Px(g_shTP), Px(g_shExit),
             (g_shDir != 0 ? g_shOutcome : "-"),
             Num(shR), Num(mfeR), Num(maeR),
             (g_shHit1R ? "1" : "0"), (g_shBack1R ? "1" : "0"),
             Px(g_sessHi), Px(g_sessLo),
             (g_rvDir == 1 ? "LONG" : (g_rvDir == -1 ? "SHORT" : "-")),
             (g_rvDir != 0 ? TimeToString(g_rvTime, TIME_DATE | TIME_MINUTES) : "-"),
             Px(g_rvEntry), Px(g_rvSL), Px(g_rvTP), Px(g_rvExit),
             (g_rvDir != 0 ? g_rvOutcome : "-"),
             Num(rvR), Num(rvMfeR), Num(rvMaeR));
   g_sessOpen = false;
}

//--- Track the excursion of the real open trade
void TradeTrack(const double bid, const double ask)
{
   if(!g_journal || !g_inTrade) return;
   double px  = (g_trDir == 1) ? bid : ask;
   double fav = (g_trDir == 1) ? px - g_trEntry : g_trEntry - px;
   if(fav > g_trMfe)  g_trMfe = fav;
   if(-fav > g_trMae) g_trMae = -fav;
}

void JournalClose()
{
   if(!g_journal) return;
   SessionWrite();
   if(g_sessFile  != INVALID_HANDLE) FileClose(g_sessFile);
   if(g_tradeFile != INVALID_HANDLE) FileClose(g_tradeFile);
   g_sessFile  = INVALID_HANDLE;
   g_tradeFile = INVALID_HANDLE;
   if(g_journalSma != INVALID_HANDLE) IndicatorRelease(g_journalSma);
   g_journalSma = INVALID_HANDLE;
   PrintFormat("Journal written: %s_sessions.csv and %s_trades.csv in Terminal\\Common\\Files",
               InpJournalPrefix, InpJournalPrefix);
   g_journal = false;
}

//====================== VIRTUAL BREAKOUT ============================

//--- Follow the first M1 close beyond the frozen range (no filters) to its
//    TP or SL. A stop-out requests the reversal in the opposite direction.
void VirtualBreakoutUpdate(const MqlDateTime &t, const double bid, const double ask)
{
   if(!g_rangeFrozen || g_vbDone) return;

   if(g_vbActive)
   {
      bool stopped = false;
      if(g_vbDir == 1)
      {
         if(bid <= g_vbSL)      stopped = true;
         else if(bid >= g_vbTP) g_vbDone = true;
      }
      else
      {
         if(ask >= g_vbSL)      stopped = true;
         else if(ask <= g_vbTP) g_vbDone = true;
      }
      if(stopped)
      {
         g_vbDone = true;
         if(InpUseReversal && !g_revDone)
         {
            g_revPending = -g_vbDir;
            PrintFormat("Breakout %s failed at %.2f -> reversal %s requested",
                        (g_vbDir == 1 ? "LONG" : "SHORT"), g_vbSL,
                        (g_vbDir == 1 ? "SHORT" : "LONG"));
         }
      }
      if(g_vbDone) g_vbActive = false;
      return;
   }

   if(PastLastEntry(t)) { g_vbDone = true; return; }

   // one evaluation per new M1 bar, on the closed candle
   datetime barTime = iTime(_Symbol, PERIOD_M1, 0);
   if(barTime == g_vbBarTime) return;
   g_vbBarTime = barTime;

   double closed = iClose(_Symbol, PERIOD_M1, 1);
   double width  = g_rangeHigh - g_rangeLow;
   if(closed <= 0.0 || width <= 0.0) return;

   if(closed > g_rangeHigh)
   {
      g_vbDir = 1;
      g_vbSL  = g_rangeLow;
      g_vbTP  = g_rangeHigh + InpRrTarget * width;
   }
   else if(closed < g_rangeLow)
   {
      g_vbDir = -1;
      g_vbSL  = g_rangeHigh;
      g_vbTP  = g_rangeLow - InpRrTarget * width;
   }
   else return;

   g_vbActive = true;
}

//====================== REVERSAL ====================================

//--- Enter once in the opposite direction after the breakout trade was
//    stopped out: SL at the far side of the range, TP like a breakout.
void ExecuteReversal(const MqlDateTime &t)
{
   int dir = g_revPending;

   if(!InpUseReversal || g_revDone || !g_rangeFrozen || PastRevLastEntry(t))
   {
      g_revPending = 0;
      g_revDone    = true;
      return;
   }

   int dirNow;
   if(CountMyPositions(dirNow) > 0) return;   // wait until the stopped trade is gone

   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double width = g_rangeHigh - g_rangeLow;
   if(ask <= 0.0 || bid <= 0.0 || width <= 0.0) return;

   // one attempt per session, whatever happens next
   g_revPending = 0;
   g_revDone    = true;

   if(dir == 1)
   {
      double sl = g_rangeLow;
      double tp = g_rangeHigh + InpRrTarget * width;
      if(ask <= sl || tp <= ask) { Print("Reversal LONG skipped: price outside the range levels."); return; }
      double lots = CalcLots(ask, sl);
      if(lots <= 0.0) { Print("Reversal LONG skipped: risk budget."); return; }
      g_pendModule = "REVERSAL";
      g_pendSL     = sl;
      g_pendTP     = tp;
      if(trade.Buy(lots, _Symbol, 0.0, sl, tp, "ORB rev long"))
         PrintFormat("REVERSAL LONG @ %.2f x%.2f | stop %.2f | target %.2f (range %.2f-%.2f)",
                     ask, lots, sl, tp, g_rangeLow, g_rangeHigh);
      else
         PrintFormat("REVERSAL LONG rejected retcode=%d", trade.ResultRetcode());
   }
   else if(dir == -1)
   {
      double sl = g_rangeHigh;
      double tp = g_rangeLow - InpRrTarget * width;
      if(bid >= sl || tp >= bid) { Print("Reversal SHORT skipped: price outside the range levels."); return; }
      double lots = CalcLots(bid, sl);
      if(lots <= 0.0) { Print("Reversal SHORT skipped: risk budget."); return; }
      g_pendModule = "REVERSAL";
      g_pendSL     = sl;
      g_pendTP     = tp;
      if(trade.Sell(lots, _Symbol, 0.0, sl, tp, "ORB rev short"))
         PrintFormat("REVERSAL SHORT @ %.2f x%.2f | stop %.2f | target %.2f (range %.2f-%.2f)",
                     bid, lots, sl, tp, g_rangeLow, g_rangeHigh);
      else
         PrintFormat("REVERSAL SHORT rejected retcode=%d", trade.ResultRetcode());
   }
}

//====================== INIT ========================================
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);

   if(InpRangeMinutes < 1)
   {
      Print("Opening-range length must be >= 1 minute.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpRrTarget <= 0.0)
   {
      Print("R multiple must be > 0.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpLotSize <= 0.0)
   {
      Print("Lot size must be > 0.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpRiskPercent < 0.0 || InpMaxLots <= 0.0)
   {
      Print("Risk % must be >= 0 and max lots > 0.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpMaxRangePrice < 0.0)
   {
      Print("Max range must be >= 0 (0 = off).");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpMaxRangeRatio < 0.0 || InpMinRangeRatio < 0.0 || InpAvgDays < 5)
   {
      Print("Range ratios must be >= 0 (0 = off) and median days >= 5.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpMaxRangeRatio > 0.0 && InpMinRangeRatio >= InpMaxRangeRatio)
   {
      Print("Min range ratio must be below the max range ratio.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpTrendDays < 0)
   {
      Print("Trend SMA days must be >= 0 (0 = off).");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpRevLastHour < 0 || InpRevLastHour > 23 || InpRevLastMinute < 0 || InpRevLastMinute > 59)
   {
      Print("Reversal last entry time must be a valid hour/minute.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpBreakevenR < 0.0)
   {
      Print("Breakeven R must be >= 0 (0 = off).");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_trendHandle = INVALID_HANDLE;
   if(InpTrendDays > 0)
   {
      g_trendHandle = iMA(_Symbol, PERIOD_D1, InpTrendDays, 0, MODE_SMA, PRICE_CLOSE);
      if(g_trendHandle == INVALID_HANDLE)
      {
         PrintFormat("Trend SMA(%d) on D1 could not be created.", InpTrendDays);
         return INIT_FAILED;
      }
   }

   ArrayResize(g_rangeHist, InpAvgDays);
   ArrayInitialize(g_rangeHist, 0.0);
   g_histCount = 0;
   g_histPos   = 0;
   g_medRange  = 0.0;

   // Reset per-run state so a fresh backtest starts clean.
   g_dayOfYear   = -1;
   g_year        = -1;
   g_rangeHigh   = 0.0;
   g_rangeLow    = 0.0;
   g_haveRange   = false;
   g_rangeFrozen = false;
   g_traded      = false;
   g_boxName     = "";
   g_lastBarTime = 0;
   g_attempts    = 0;
   g_inTrade     = false;
   g_sessOpen    = false;

   JournalOpen();

   PrintFormat("XAUUSD NY ORB Reverse Hunter v2.0 initialised | breakout trades %s | reversal %s (until %d:%02d) | range %d min | R target %.2f | breakeven %.2fR | lots %.2f | risk %.2f%% | minRange %d pts | maxRange %.2f | band %.2f-%.2f x %d-day median | trend SMA %d D1 | last entry %d:%02d | journal %s",
               (InpTradeBreakout ? "on" : "watch only"),
               (InpUseReversal ? "on" : "off"), InpRevLastHour, InpRevLastMinute,
               InpRangeMinutes, InpRrTarget, InpBreakevenR, InpLotSize, InpRiskPercent,
               InpMinRangePoints, InpMaxRangePrice,
               InpMinRangeRatio, InpMaxRangeRatio, InpAvgDays,
               InpTrendDays,
               InpLastEntryHour, InpLastEntryMinute,
               (g_journal ? "on" : "off"));
   return INIT_SUCCEEDED;
}

//====================== DEINIT ======================================
void OnDeinit(const int reason)
{
   JournalClose();
   if(g_trendHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_trendHandle);
      g_trendHandle = INVALID_HANDLE;
   }
   if(g_boxName != "" && ObjectFind(0, g_boxName) >= 0)
      ObjectDelete(0, g_boxName);
}

//====================== TICK ========================================
void OnTick()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);

   double tickBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tickAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   ApplyBreakeven(tickBid, tickAsk);
   TradeTrack(tickBid, tickAsk);

   //---------------------------------------------------------------
   //  1) New session -> reset state, drop stale orders/boxes
   //---------------------------------------------------------------
   if(NewSession(t))
   {
      SessionWrite();   // previous session ended without reaching the flatten time
      DeletePendingStops();
      // a position carried over the day boundary is closed at the
      // prior session's flatten time, so nothing should survive here
      g_rangeHigh   = 0.0;
      g_rangeLow    = 0.0;
      g_haveRange   = false;
      g_rangeFrozen = false;
      g_traded      = false;
      g_lastBarTime = 0;
      g_attempts    = 0;
      g_medRange    = 0.0;
      g_revPending  = 0;
      g_revDone     = false;
      g_vbDir       = 0;
      g_vbActive    = false;
      g_vbDone      = false;
      g_vbBarTime   = 0;
   }

   //---------------------------------------------------------------
   //  2) Build the opening range from the bars inside the window
   //---------------------------------------------------------------
   if(InRangeWindow(t))
   {
      double hi = iHigh(_Symbol, PERIOD_M1, 0);
      double lo = iLow (_Symbol, PERIOD_M1, 0);

      if(hi > 0.0 && lo > 0.0)
      {
         if(g_haveRange)
         {
            if(hi > g_rangeHigh) g_rangeHigh = hi;
            if(lo < g_rangeLow)  g_rangeLow  = lo;
         }
         else
         {
            g_rangeHigh = hi;
            g_rangeLow  = lo;
            g_haveRange = true;
         }

         // keep the box visible/updated while the range is building
         DrawRangeBox(iTime(_Symbol, PERIOD_M1, 0), TimeCurrent(),
                      g_rangeHigh, g_rangeLow);
      }
   }

   //---------------------------------------------------------------
   //  3) Freeze the range once the window closes
   //---------------------------------------------------------------
   if(!g_rangeFrozen && !InRangeWindow(t) && g_haveRange)
   {
      int nowMin   = t.hour * 60 + t.min;
      int openMin  = InpSessionOpenHour * 60 + InpSessionOpenMin;
      int rangeEnd = openMin + MathMax(InpRangeMinutes, 1);
      if(nowMin >= rangeEnd)
      {
         g_rangeFrozen = true;

         // median of the PREVIOUS sessions first, then record today's width
         double frozenWidth = g_rangeHigh - g_rangeLow;
         g_medRange = MedianRange();
         PushRange(frozenWidth);
         SessionStart();

         PrintFormat("NY OR frozen: %.2f - %.2f (width %.2f, %d-day median %.2f)",
                     g_rangeLow, g_rangeHigh, frozenWidth, InpAvgDays, g_medRange);
         DrawRangeBox(iTime(_Symbol, PERIOD_M1, 0), TimeCurrent(),
                      g_rangeHigh, g_rangeLow);
      }
   }

   // follow the unfiltered "shadow" breakout for the journal
   ShadowUpdate(t, tickBid, tickAsk);

   // follow the virtual breakout whose failure triggers the reversal
   if(!AtFlattenTime(t)) VirtualBreakoutUpdate(t, tickBid, tickAsk);

   //---------------------------------------------------------------
   //  4) Flatten at the session close
   //---------------------------------------------------------------
   if(AtFlattenTime(t))
   {
      int dir;
      if(CountMyPositions(dir) > 0)
      {
         FlattenAll();
         Print("Session flatten -- position closed.");
      }
      DeletePendingStops();
      SessionWrite();
      return;
   }

   //---------------------------------------------------------------
   //  5) One breakout entry per session -- evaluated ONCE per M1 bar,
   //     on the CLOSED candle, not on every tick.
   //---------------------------------------------------------------
   // --- reversal module: runs after the breakout trade was stopped out ---
   if(g_revPending != 0) ExecuteReversal(t);

   // watch-only mode: the breakout is followed virtually, never traded
   if(!InpTradeBreakout) return;

   if(!g_rangeFrozen || g_traded) return;

   int dirNow;
   if(CountMyPositions(dirNow) > 0) { g_traded = true; return; }

   // --- no new entries after the last entry time ---
   if(PastLastEntry(t)) { g_traded = true; return; }

   // --- day-of-week filter ---
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(InpSkipFriday && dt.day_of_week == 5) { SetDecision("SKIP_WEEKDAY"); g_traded = true; return; }
   if(InpSkipMonday && dt.day_of_week == 1) { SetDecision("SKIP_WEEKDAY"); g_traded = true; return; }

   // --- spread guard ---
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0) return;

   if(InpMaxSpreadPoints > 0)
   {
      double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double spreadP = (ask - bid) / point;
      if(spreadP > (double)InpMaxSpreadPoints) return;
   }

   double width = g_rangeHigh - g_rangeLow;
   if(width <= 0.0) return;

   // --- minimum range filter (skip dead/compressed sessions) ---
   if(InpMinRangePoints > 0)
   {
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      if(width < (double)InpMinRangePoints * point) { SetDecision("SKIP_MIN_POINTS"); return; }
   }

   // --- maximum range filter (skip wide / volatile sessions) ---
   if(InpMaxRangePrice > 0.0 && width > InpMaxRangePrice)
   {
      PrintFormat("Session skipped: range %.2f > max %.2f", width, InpMaxRangePrice);
      SetDecision("SKIP_MAX_PRICE");
      g_traded = true;
      return;
   }

   // --- relative range band (skip sessions wider or narrower than usual) ---
   if(InpMaxRangeRatio > 0.0 || InpMinRangeRatio > 0.0)
   {
      if(g_medRange <= 0.0)
      {
         PrintFormat("Session skipped: range median warming up (%d/%d days)",
                     g_histCount, InpAvgDays);
         SetDecision("SKIP_WARMUP");
         g_traded = true;
         return;
      }
      if(InpMaxRangeRatio > 0.0 && width > InpMaxRangeRatio * g_medRange)
      {
         PrintFormat("Session skipped: range %.2f > %.2f x median %.2f",
                     width, InpMaxRangeRatio, g_medRange);
         SetDecision("SKIP_WIDE");
         g_traded = true;
         return;
      }
      if(InpMinRangeRatio > 0.0 && width < InpMinRangeRatio * g_medRange)
      {
         PrintFormat("Session skipped: range %.2f < %.2f x median %.2f",
                     width, InpMinRangeRatio, g_medRange);
         SetDecision("SKIP_NARROW");
         g_traded = true;
         return;
      }
   }

   // --- one evaluation per new M1 bar ---
   datetime barTime = iTime(_Symbol, PERIOD_M1, 0);
   if(barTime == g_lastBarTime) return;
   g_lastBarTime = barTime;

   if(g_attempts >= MathMax(InpMaxAttempts, 1)) { SetDecision("ORDER_FAILED"); g_traded = true; return; }

   double closedClose = iClose(_Symbol, PERIOD_M1, 1);  // last CLOSED candle
   if(closedClose <= 0.0) return;

   double longEntry  = g_rangeHigh;
   double longStop   = g_rangeLow;
   double longTarget = longEntry + InpRrTarget * width;

   double shortEntry  = g_rangeLow;
   double shortStop   = g_rangeHigh;
   double shortTarget = shortEntry - InpRrTarget * width;

   // Breakout test: on the CLOSED candle, or live on bid/ask if disabled.
   bool longBreak  = InpRequireClose ? (closedClose > longEntry)  : (bid >= longEntry);
   bool shortBreak = InpRequireClose ? (closedClose < shortEntry) : (ask <= shortEntry);

   // --- trend filter: trade only with the daily trend ---
   if(InpTrendDays > 0 && (longBreak || shortBreak))
   {
      double sma[1];
      if(CopyBuffer(g_trendHandle, 0, 1, 1, sma) != 1) return;   // daily SMA not ready yet
      if(longBreak  && closedClose <= sma[0]) longBreak  = false;
      if(shortBreak && closedClose >= sma[0]) shortBreak = false;
      if(!longBreak && !shortBreak)
      {
         // The range is consumed: no chasing the other side later.
         PrintFormat("Breakout against the trend skipped (close %.2f, SMA %.2f)",
                     closedClose, sma[0]);
         SetDecision("SKIP_TREND");
         g_traded = true;
         return;
      }
   }

   bool armed = false;

   // ---- LONG ----
   // If price is ALREADY beyond the level, a BuyStop would be rejected
   // (INVALID_STOPS) -- enter at market instead. Otherwise arm the stop.
   if(InpAllowLong && longBreak)
   {
      double lots = CalcLots(MathMax(ask, longEntry), longStop);
      if(lots <= 0.0)
      {
         PrintFormat("LONG skipped: min lot risks more than %.2f%% of equity", InpRiskPercent);
         SetDecision("SKIP_RISK");
         g_traded = true;
         return;
      }

      g_pendModule = "BREAKOUT";
      g_pendSL = longStop;
      g_pendTP = longTarget;
      if(ask >= longEntry)
      {
         if(trade.Buy(lots, _Symbol, 0.0, longStop, longTarget, "ORB long"))
         {
            armed = true;
            PrintFormat("LONG breakout MARKET @ %.2f x%.2f | stop %.2f | target %.2f (range %.2f-%.2f)",
                        ask, lots, longStop, longTarget, g_rangeLow, g_rangeHigh);
         }
         else
         {
            g_attempts++;
            PrintFormat("LONG market rejected retcode=%d (attempt %d/%d)",
                        trade.ResultRetcode(), g_attempts, InpMaxAttempts);
         }
      }
      else if(trade.BuyStop(lots, longEntry, _Symbol, longStop, longTarget,
                            ORDER_TIME_GTC, 0, "ORB long"))
      {
         armed = true;
         PrintFormat("LONG breakout armed @ %.2f x%.2f | stop %.2f | target %.2f (range %.2f-%.2f)",
                     longEntry, lots, longStop, longTarget, g_rangeLow, g_rangeHigh);
      }
      else
      {
         g_attempts++;
         PrintFormat("LONG BuyStop rejected retcode=%d (attempt %d/%d)",
                     trade.ResultRetcode(), g_attempts, InpMaxAttempts);
      }
   }

   // ---- SHORT ----
   if(!armed && InpAllowShort && shortBreak)
   {
      double lots = CalcLots(MathMin(bid, shortEntry), shortStop);
      if(lots <= 0.0)
      {
         PrintFormat("SHORT skipped: min lot risks more than %.2f%% of equity", InpRiskPercent);
         SetDecision("SKIP_RISK");
         g_traded = true;
         return;
      }

      g_pendModule = "BREAKOUT";
      g_pendSL = shortStop;
      g_pendTP = shortTarget;
      if(bid <= shortEntry)
      {
         if(trade.Sell(lots, _Symbol, 0.0, shortStop, shortTarget, "ORB short"))
         {
            armed = true;
            PrintFormat("SHORT breakout MARKET @ %.2f x%.2f | stop %.2f | target %.2f (range %.2f-%.2f)",
                        bid, lots, shortStop, shortTarget, g_rangeLow, g_rangeHigh);
         }
         else
         {
            g_attempts++;
            PrintFormat("SHORT market rejected retcode=%d (attempt %d/%d)",
                        trade.ResultRetcode(), g_attempts, InpMaxAttempts);
         }
      }
      else if(trade.SellStop(lots, shortEntry, _Symbol, shortStop, shortTarget,
                             ORDER_TIME_GTC, 0, "ORB short"))
      {
         armed = true;
         PrintFormat("SHORT breakout armed @ %.2f x%.2f | stop %.2f | target %.2f (range %.2f-%.2f)",
                     shortEntry, lots, shortStop, shortTarget, g_rangeLow, g_rangeHigh);
      }
      else
      {
         g_attempts++;
         PrintFormat("SHORT SellStop rejected retcode=%d (attempt %d/%d)",
                     trade.ResultRetcode(), g_attempts, InpMaxAttempts);
      }
   }

   if(armed)
   {
      g_traded = true;
      SetDecision((longBreak && InpAllowLong) ? "LONG" : "SHORT");
   }

   //---------------------------------------------------------------
   //  6) Housekeeping -- nothing else should be alive
   //---------------------------------------------------------------
   int dirFinal;
   if(CountMyPositions(dirFinal) > 0)
   {
      // position open -> pending stop orders are no longer wanted
      DeletePendingStops();
   }
}

//====================== BAR CLOSE (box redraw) ======================
void OnTrade()
{
   // keep the box aligned to the frozen range once the window ends
   if(InpDrawBox && g_rangeFrozen && g_haveRange && g_boxName != "")
   {
      datetime tStart = iTime(_Symbol, PERIOD_M1, 0);
      DrawRangeBox(tStart, TimeCurrent(), g_rangeHigh, g_rangeLow);
   }
}

//====================== TRADE EVENTS (reversal + journal) ===========
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic) return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

   // ---- module of the position just opened (the reversal itself is
   //      triggered by the virtual breakout, see VirtualBreakoutUpdate) ----
   if(entry == DEAL_ENTRY_IN)
      g_openModule = g_pendModule;

   if(!g_journal) return;

   // ---- position opened: remember the entry and its context ----
   if(entry == DEAL_ENTRY_IN)
   {
      g_trModule   = g_openModule;
      g_inTrade    = true;
      g_trDir      = (HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY) ? 1 : -1;
      g_trOpenTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
      g_trEntry    = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
      g_trLots     = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
      g_trInCost   = HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
      g_trSL       = g_pendSL;
      g_trTP       = g_pendTP;
      ulong posId  = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
      if(PositionSelectByTicket(posId))
      {
         if(PositionGetDouble(POSITION_SL) > 0.0) g_trSL = PositionGetDouble(POSITION_SL);
         if(PositionGetDouble(POSITION_TP) > 0.0) g_trTP = PositionGetDouble(POSITION_TP);
      }
      g_trMfe      = 0.0;
      g_trMae      = 0.0;
      g_trWidth    = g_rangeHigh - g_rangeLow;
      g_trMedian   = g_sessMedian;
      g_trSma      = g_sessSma;
      g_trPxVsSma  = g_sessPxVsSma;
      return;
   }

   // ---- position closed: write the trade row ----
   if((entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY) && g_inTrade)
   {
      double   exitPx    = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
      datetime closeTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
      double   profit    = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                         + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION)
                         + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                         + g_trInCost;
      long     reason    = HistoryDealGetInteger(trans.deal, DEAL_REASON);
      string   why       = (reason == DEAL_REASON_SL) ? "SL" :
                           (reason == DEAL_REASON_TP) ? "TP" : "CLOSE";

      double risk  = MathAbs(g_trEntry - g_trSL);
      double resR  = (risk > 0.0) ? g_trDir * (exitPx - g_trEntry) / risk : 0.0;
      double mfeR  = (risk > 0.0) ? g_trMfe / risk : 0.0;
      double maeR  = (risk > 0.0) ? g_trMae / risk : 0.0;
      double ratio = (g_trMedian > 0.0) ? g_trWidth / g_trMedian : 0.0;

      MqlDateTime o;
      TimeToStruct(g_trOpenTime, o);

      FileWrite(g_tradeFile,
                TimeToString(g_trOpenTime, TIME_DATE | TIME_MINUTES),
                TimeToString(closeTime, TIME_DATE | TIME_MINUTES),
                (g_trDir == 1 ? "LONG" : "SHORT"),
                DoubleToString(g_trLots, 2),
                Px(g_trEntry), Px(g_trSL), Px(g_trTP), Px(exitPx),
                why, DoubleToString(profit, 2), Px(risk),
                Num(resR), Num(mfeR), Num(maeR),
                IntegerToString((long)((closeTime - g_trOpenTime) / 60)),
                Px(g_trWidth), Px(g_trMedian), Num(ratio),
                Px(g_trSma), Num(g_trPxVsSma),
                IntegerToString(o.hour), WeekdayName(g_trOpenTime), g_trModule);
      g_inTrade = false;
   }
}
//+------------------------------------------------------------------+
