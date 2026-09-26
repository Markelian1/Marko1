//+------------------------------------------------------------------+
//|                          XAUUSD_NY_OpenRangeBreakout_v14.mq5     |
//|   New York Opening-Range Breakout (ORB) for XAUUSD (gold spot)   |
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
#property version   "1.40"
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
input double InpLotSize         = 0.10;  // Lot size per trade (used when risk % = 0)
input double InpRiskPercent     = 0.0;   // Risk per trade (% of equity, 0 = fixed lot)
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

input group "=== Drawing ==="
input bool   InpDrawBox         = true;  // Draw opening range box

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

//====================== HELPERS =====================================

//--- Is the current server time inside the opening-range window?
bool InRangeWindow(const MqlDateTime &t)
{
   int nowMin   = t.hour * 60 + t.min;
   int openMin  = InpSessionOpenHour * 60 + InpSessionOpenMin;
   int rangeEnd = openMin + MathMax(InpRangeMinutes, 1);
   return (nowMin >= openMin && nowMin < rangeEnd);
}

//--- Is it after the last allowed entry time?
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

   PrintFormat("XAUUSD NY ORB v1.4 initialised | range %d min | R target %.2f | lots %.2f | risk %.2f%% | minRange %d pts | maxRange %.2f | last entry %d:%02d",
               InpRangeMinutes, InpRrTarget, InpLotSize, InpRiskPercent,
               InpMinRangePoints, InpMaxRangePrice,
               InpLastEntryHour, InpLastEntryMinute);
   return INIT_SUCCEEDED;
}

//====================== DEINIT ======================================
void OnDeinit(const int reason)
{
   if(g_boxName != "" && ObjectFind(0, g_boxName) >= 0)
      ObjectDelete(0, g_boxName);
}

//====================== TICK ========================================
void OnTick()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);

   //---------------------------------------------------------------
   //  1) New session -> reset state, drop stale orders/boxes
   //---------------------------------------------------------------
   if(NewSession(t))
   {
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
         PrintFormat("NY OR frozen: %.2f - %.2f (width %.2f)",
                     g_rangeLow, g_rangeHigh, g_rangeHigh - g_rangeLow);
         DrawRangeBox(iTime(_Symbol, PERIOD_M1, 0), TimeCurrent(),
                      g_rangeHigh, g_rangeLow);
      }
   }

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
      return;
   }

   //---------------------------------------------------------------
   //  5) One breakout entry per session -- evaluated ONCE per M1 bar,
   //     on the CLOSED candle, not on every tick.
   //---------------------------------------------------------------
   if(!g_rangeFrozen || g_traded) return;

   int dirNow;
   if(CountMyPositions(dirNow) > 0) { g_traded = true; return; }

   // --- no new entries after the last entry time ---
   if(PastLastEntry(t)) { g_traded = true; return; }

   // --- day-of-week filter ---
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(InpSkipFriday && dt.day_of_week == 5) { g_traded = true; return; }
   if(InpSkipMonday && dt.day_of_week == 1) { g_traded = true; return; }

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
      if(width < (double)InpMinRangePoints * point) return;
   }

   // --- maximum range filter (skip wide / volatile sessions) ---
   if(InpMaxRangePrice > 0.0 && width > InpMaxRangePrice)
   {
      PrintFormat("Session skipped: range %.2f > max %.2f", width, InpMaxRangePrice);
      g_traded = true;
      return;
   }

   // --- one evaluation per new M1 bar ---
   datetime barTime = iTime(_Symbol, PERIOD_M1, 0);
   if(barTime == g_lastBarTime) return;
   g_lastBarTime = barTime;

   if(g_attempts >= MathMax(InpMaxAttempts, 1)) { g_traded = true; return; }

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
         g_traded = true;
         return;
      }

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
         g_traded = true;
         return;
      }

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

   if(armed) g_traded = true;

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
//+------------------------------------------------------------------+
