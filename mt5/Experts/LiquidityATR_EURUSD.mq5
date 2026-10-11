//+------------------------------------------------------------------+
//|                                        LiquidityATR_EURUSD.mq5   |
//| Liquidity-window range EA with ATR stops (breakout or sweep).    |
//| Input names follow the LPX layout so the lpx-set-analyzer skill  |
//| reads its optimization XML directly. This is NOT the LPX EA.     |
//+------------------------------------------------------------------+
#property copyright "Marko1"
#property version   "1.00"
#property description "Range between LiquidityHour2:Min2 and LiquidityHour1:Min1 (server time)."
#property description "EntryMode 0 = breakout with stop orders, 1 = sweep-reversal on candle close."
#property description "SL = ATR x ATR_Mult, TP = SL x ATR_RR, lot from RiskPercent. One trade per day."

#include <Trade/Trade.mqh>

input group "Risk"
input double RiskPercent     = 0.5;   // Risk per trade, % of balance
input group "ATR stops"
input int    ATR_Period      = 16;    // ATR period
input double ATR_Mult        = 2.6;   // SL distance = ATR x ATR_Mult
input double ATR_RR          = 2.4;   // TP distance = SL x ATR_RR
input group "Liquidity window (server time)"
input int    LiquidityHour1  = 14;    // Range end / entries start: hour
input int    LiquidityMin1   = 20;    // Range end / entries start: minute
input int    LiquidityHour2  = 14;    // Range start: hour (-1 = only the last candle)
input int    LiquidityMin2   = 10;    // Range start: minute
input int    EntryWindowMin  = 120;   // Minutes after range end in which entries are allowed
input int    EntryMode       = 0;     // 0 = breakout, 1 = sweep-reversal
input int    BufferPoints    = 0;     // Breakout buffer beyond the range, points
input group "Filters"
input bool   TradeFriday     = true;  // Allow new trades on Friday
input bool   UseNewsFilter   = false; // Skip high-impact news of both currencies (live only, not in tester)
input int    NewsMinutes     = 30;    // News blackout, +/- minutes
input int    MaxSpreadPoints = 0;     // Max spread to enter, points (0 = off)
input group "Exits"
input bool   CloseAtTime     = true;  // Close open trade and pending orders at the time below
input int    CloseHour       = 22;    // Close hour (server)
input int    CloseMin        = 45;    // Close minute (server)
input group "General"
input long   MagicNumber     = 500500;

CTrade   trade;
int      atrHandle   = INVALID_HANDLE;
datetime g_day       = 0;
bool     g_rangeReady = false;
bool     g_traded     = false;
bool     g_ordersPlaced = false;
double   g_hi = 0, g_lo = 0;
datetime g_lastBar = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   if(RiskPercent <= 0 || ATR_Period < 1 || ATR_Mult <= 0 || ATR_RR <= 0 || EntryWindowMin < 1)
      return INIT_PARAMETERS_INCORRECT;
   if(LiquidityHour1 < 0 || LiquidityHour1 > 23 || LiquidityMin1 < 0 || LiquidityMin1 > 59 ||
      LiquidityHour2 < -1 || LiquidityHour2 > 23 || LiquidityMin2 < 0 || LiquidityMin2 > 59 ||
      EntryMode < 0 || EntryMode > 1)
      return INIT_PARAMETERS_INCORRECT;
   if(CloseAtTime && CloseHour * 60 + CloseMin <= LiquidityHour1 * 60 + LiquidityMin1)
      return INIT_PARAMETERS_INCORRECT;   // exit time must come after the entry time

   atrHandle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   if(atrHandle == INVALID_HANDLE)
      return INIT_FAILED;
   trade.SetExpertMagicNumber((ulong)MagicNumber);
   trade.SetDeviationInPoints(20);
   trade.SetTypeFillingBySymbol(_Symbol);
   if(UseNewsFilter && MQLInfoInteger(MQL_TESTER))
      Print("News filter is not available in the Strategy Tester - this run trades without it.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime now = TimeCurrent();
   datetime day = (datetime)((long)now - (long)now % 86400);
   if(day != g_day)
   {
      g_day = day;
      g_rangeReady = false;
      g_ordersPlaced = false;
      g_traded = TradedToday(day);
   }

   if(CloseAtTime && now >= day + CloseHour * 3600 + CloseMin * 60)
   {
      CloseAll();
      DeletePendings();
      return;
   }

   if(HasPosition())
   {
      g_traded = true;
      DeletePendings();            // one trade per day: cancel the opposite stop order
      return;
   }
   if(g_traded)
      return;

   datetime tEnd  = day + LiquidityHour1 * 3600 + LiquidityMin1 * 60;
   datetime tStop = tEnd + EntryWindowMin * 60;
   if(now < tEnd)
      return;
   if(now >= tStop)
   {
      DeletePendings();
      return;
   }
   if(!TradeFriday && Dow(now) == 5)
      return;
   if(!g_rangeReady)
   {
      if(!BuildRange(day, tEnd))
         return;                   // no bars yet (or holiday) - retry on the next tick
      g_rangeReady = true;
   }
   if(NewsBlocked())
   {
      DeletePendings();
      g_ordersPlaced = false;
      return;
   }

   if(EntryMode == 0)
      PlaceBreakout();
   else
      CheckSweep(tEnd);
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) == MagicNumber &&
      HistoryDealGetString(trans.deal, DEAL_SYMBOL) == _Symbol &&
      HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
      g_traded = true;
}

//+------------------------------------------------------------------+
//| Range = candles from LiquidityHour2:Min2 up to LiquidityHour1:Min1|
//| If the start is -1 or not before the end: only the last candle.   |
//+------------------------------------------------------------------+
bool BuildRange(datetime day, datetime tEnd)
{
   datetime tStart = (LiquidityHour2 < 0) ? tEnd : day + LiquidityHour2 * 3600 + LiquidityMin2 * 60;
   if(tStart >= tEnd)
      tStart = tEnd - PeriodSeconds(PERIOD_CURRENT);
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_CURRENT, tStart, tEnd - 1, r);
   if(n <= 0)
      return false;
   g_hi = r[0].high;
   g_lo = r[0].low;
   for(int i = 1; i < n; i++)
   {
      g_hi = MathMax(g_hi, r[i].high);
      g_lo = MathMin(g_lo, r[i].low);
   }
   return g_hi > g_lo;
}

void PlaceBreakout()
{
   if(g_ordersPlaced)
      return;
   if(HasPending())
   {
      g_ordersPlaced = true;      // restarted with orders already working
      return;
   }
   if(!SpreadOK())
      return;
   double atr = ATR();
   if(atr <= 0)
      return;
   double sl = atr * ATR_Mult, tp = sl * ATR_RR;
   double lots = LotsFor(sl);
   g_ordersPlaced = true;
   if(lots <= 0)
      return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minDist = (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) + 1) * _Point;
   double buyPx  = Norm(g_hi + BufferPoints * _Point);
   double sellPx = Norm(g_lo - BufferPoints * _Point);
   // a side whose level is already behind price is skipped (no chasing)
   if(buyPx > ask + minDist &&
      !trade.BuyStop(lots, buyPx, _Symbol, Norm(buyPx - sl), Norm(buyPx + tp), ORDER_TIME_GTC, 0, "LiqATR BO"))
      Report("BuyStop");
   if(sellPx < bid - minDist &&
      !trade.SellStop(lots, sellPx, _Symbol, Norm(sellPx + sl), Norm(sellPx - tp), ORDER_TIME_GTC, 0, "LiqATR BO"))
      Report("SellStop");
}

void CheckSweep(datetime tEnd)
{
   datetime bt = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(bt == g_lastBar)
      return;
   g_lastBar = bt;
   MqlRates r[];
   if(CopyRates(_Symbol, PERIOD_CURRENT, 1, 1, r) != 1 || r[0].time < tEnd)
      return;                      // only candles formed after the range count
   bool upSweep = r[0].high > g_hi && r[0].close < g_hi;   // took the highs, closed back inside
   bool dnSweep = r[0].low < g_lo && r[0].close > g_lo;    // took the lows, closed back inside
   if(upSweep == dnSweep || !SpreadOK())
      return;
   double atr = ATR();
   if(atr <= 0)
      return;
   double sl = atr * ATR_Mult, tp = sl * ATR_RR;
   double lots = LotsFor(sl);
   if(lots <= 0)
      return;
   if(upSweep)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(!trade.Sell(lots, _Symbol, bid, Norm(bid + sl), Norm(bid - tp), "LiqATR SW"))
         Report("Sell");
   }
   else
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(!trade.Buy(lots, _Symbol, ask, Norm(ask - sl), Norm(ask + tp), "LiqATR SW"))
         Report("Buy");
   }
}

//+------------------------------------------------------------------+
void Report(string op)
{
   PrintFormat("%s failed: %u %s", op, trade.ResultRetcode(), trade.ResultRetcodeDescription());
}

double ATR()
{
   double b[];
   if(CopyBuffer(atrHandle, 0, 1, 1, b) != 1)
      return 0;
   return b[0];
}

double LotsFor(double slDist)
{
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0)
      tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0 || tickValue <= 0 || slDist <= 0)
      return 0;
   double risk       = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
   double lossPerLot = slDist / tickSize * tickValue;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0)
      step = vmin;
   double lots = MathFloor(risk / lossPerLot / step) * step;
   if(lots < vmin)
   {
      PrintFormat("Lot %.4f is below the broker minimum %.2f - trade skipped (raise RiskPercent or balance).", lots, vmin);
      return 0;
   }
   int digits = (int)MathMax(0, MathCeil(-MathLog10(step) - 1e-9));
   return NormalizeDouble(MathMin(lots, vmax), digits);
}

double Norm(double price)
{
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts > 0)
      price = MathRound(price / ts) * ts;
   return NormalizeDouble(price, _Digits);
}

bool SpreadOK()
{
   return MaxSpreadPoints <= 0 || SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= MaxSpreadPoints;
}

bool NewsBlocked()
{
   if(!UseNewsFilter || MQLInfoInteger(MQL_TESTER))
      return false;
   datetime now = TimeTradeServer();
   string ccy[2];
   ccy[0] = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);     // EUR on EURUSD
   ccy[1] = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);   // USD on EURUSD
   for(int c = 0; c < 2; c++)
   {
      MqlCalendarValue vals[];
      if(CalendarValueHistory(vals, now - NewsMinutes * 60, now + NewsMinutes * 60, NULL, ccy[c]) <= 0)
         continue;
      for(int i = 0; i < ArraySize(vals); i++)
      {
         MqlCalendarEvent ev;
         if(CalendarEventById(vals[i].event_id, ev) && ev.importance == CALENDAR_IMPORTANCE_HIGH)
            return true;
      }
   }
   return false;
}

int Dow(datetime t)
{
   MqlDateTime s;
   TimeToStruct(t, s);
   return s.day_of_week;
}

bool HasPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return true;
   }
   return false;
}

bool HasPending()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i);
      if(t != 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == MagicNumber)
         return true;
   }
   return false;
}

void CloseAll()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         if(!trade.PositionClose(t))
            Report("PositionClose");
   }
}

void DeletePendings()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i);
      if(t != 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == MagicNumber)
         if(!trade.OrderDelete(t))
            Report("OrderDelete");
   }
}

bool TradedToday(datetime day)
{
   if(!HistorySelect(day, TimeCurrent() + 60))
      return false;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong d = HistoryDealGetTicket(i);
      if(d != 0 && HistoryDealGetInteger(d, DEAL_MAGIC) == MagicNumber &&
         HistoryDealGetString(d, DEAL_SYMBOL) == _Symbol &&
         HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN)
         return true;
   }
   return false;
}
//+------------------------------------------------------------------+
