// @polsia:user-owned
//+------------------------------------------------------------------+
//| Wickmorrow XAUUSD Breakout                                       |
//| Forms one server-time intraday range per day and trades the first |
//| post-range breakout with a fixed volume and stop-loss distance.   |
//+------------------------------------------------------------------+
#property copyright "Wickmorrow"
#property version   "1.00"
#property description "Daily XAUUSD range breakout Expert Advisor"

#include <Trade/Trade.mqh>

input string InpTradeSymbol       = "XAUUSD"; // Chart/symbol to trade
input int    InpRangeStartHour    = 8;        // Range start, server hour [0..23]
input int    InpRangeEndHour      = 10;       // Range end, server hour [1..23]
input double InpFixedLotSize      = 0.10;     // Fixed order volume
input int    InpStopLossPoints    = 500;      // Stop-loss distance in points
input ulong  InpMagicNumber       = 7052026;  // EA position identifier
input uint   InpDeviationPoints   = 20;       // Maximum market-order deviation

CTrade trade;

int    g_periodDayKey = -1;
bool   g_rangeBuilding = false;
bool   g_rangeComplete = false;
bool   g_tradeTaken = false;
double g_rangeHigh = 0.0;
double g_rangeLow = 0.0;

// Strategy Tester scenario (manual):
// Symbol = XAUUSD, timeframe = M1, model = Every tick based on real ticks.
// Use a date with prices covering 08:00-10:00 server time and these inputs:
// RangeStartHour=8, RangeEndHour=10, FixedLotSize=0.10,
// StopLossPoints=500. Confirm that the recorded high/low are formed only in
// [08:00, 10:00), no order exists before 10:00, and the first post-10:00
// breakout order has volume 0.10 and an SL 500 points from its entry price.

int DateKey(const MqlDateTime &date)
{
   return date.year * 10000 + date.mon * 100 + date.day;
}

bool IsVolumeAligned()
{
   const double volumeMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double volumeMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   const double volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if (volumeMin <= 0.0 || volumeMax < volumeMin || volumeStep <= 0.0)
      return false;
   if (InpFixedLotSize < volumeMin || InpFixedLotSize > volumeMax)
      return false;

   const double stepCount = InpFixedLotSize / volumeStep;
   return MathAbs(stepCount - MathRound(stepCount)) <= 1e-6;
}

bool ValidateInputs()
{
   if (_Symbol != InpTradeSymbol)
   {
      PrintFormat("Invalid symbol: attach this EA to %s, current symbol is %s.", InpTradeSymbol, _Symbol);
      return false;
   }
   if (InpRangeStartHour < 0 || InpRangeStartHour > 23 ||
       InpRangeEndHour < 1 || InpRangeEndHour > 23 ||
       InpRangeStartHour >= InpRangeEndHour)
   {
      Print("Invalid range hours: start and end must define a same-day window with start < end.");
      return false;
   }
   if (InpFixedLotSize <= 0.0 || !IsVolumeAligned())
   {
      Print("Invalid fixed lot size: it must be positive and aligned to the symbol volume limits/step.");
      return false;
   }
   if (InpStopLossPoints <= 0)
   {
      Print("Invalid stop loss: InpStopLossPoints must be greater than zero.");
      return false;
   }

   const long minimumStopPoints = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if (InpStopLossPoints < minimumStopPoints)
   {
      PrintFormat("Invalid stop loss: %d points is below the symbol minimum of %d points.",
                  InpStopLossPoints, minimumStopPoints);
      return false;
   }
   if (InpMagicNumber == 0)
   {
      Print("Invalid magic number: it must be non-zero.");
      return false;
   }
   return true;
}

void ResetTradingPeriod(const int dayKey)
{
   g_periodDayKey = dayKey;
   g_rangeBuilding = false;
   g_rangeComplete = false;
   g_tradeTaken = false;
   g_rangeHigh = 0.0;
   g_rangeLow = 0.0;
}

bool HasOpenPosition()
{
   for (int index = PositionsTotal() - 1; index >= 0; index--)
   {
      const ulong ticket = PositionGetTicket(index);
      if (ticket == 0)
         continue;
      if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
          (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         return true;
   }
   return false;
}

void UpdateRange(const MqlTick &tick, const MqlDateTime &now)
{
   const int dayKey = DateKey(now);
   if (dayKey != g_periodDayKey)
      ResetTradingPeriod(dayKey);

   const int currentMinutes = now.hour * 60 + now.min;
   const int rangeStartMinutes = InpRangeStartHour * 60;
   const int rangeEndMinutes = InpRangeEndHour * 60;

   if (currentMinutes < rangeStartMinutes)
      return;

   if (currentMinutes >= rangeEndMinutes)
   {
      if (g_rangeBuilding && !g_rangeComplete)
         g_rangeComplete = g_rangeHigh >= g_rangeLow && g_rangeLow > 0.0;
      return;
   }

   if (g_rangeComplete)
      return;

   const double rangePrice = tick.bid;
   if (rangePrice <= 0.0)
      return;

   if (!g_rangeBuilding)
   {
      g_rangeHigh = rangePrice;
      g_rangeLow = rangePrice;
      g_rangeBuilding = true;
      return;
   }

   g_rangeHigh = MathMax(g_rangeHigh, rangePrice);
   g_rangeLow = MathMin(g_rangeLow, rangePrice);
}

bool IsSuccessfulTrade()
{
   const uint retcode = trade.ResultRetcode();
   return retcode == TRADE_RETCODE_DONE ||
          retcode == TRADE_RETCODE_DONE_PARTIAL ||
          retcode == TRADE_RETCODE_PLACED;
}

void TryBreakout(const MqlTick &tick)
{
   if (!g_rangeComplete || g_tradeTaken || HasOpenPosition())
      return;

   const double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if (point <= 0.0)
      return;

   const double stopDistance = InpStopLossPoints * point;
   const int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if (tick.ask > g_rangeHigh)
   {
      const double stopLoss = NormalizeDouble(tick.ask - stopDistance, digits);
      if (trade.Buy(InpFixedLotSize, _Symbol, 0.0, stopLoss, 0.0,
                    "Wickmorrow XAUUSD range breakout buy") && IsSuccessfulTrade())
      {
         g_tradeTaken = true;
         PrintFormat("Long breakout entered at %.5f with %.2f lots and SL %.5f.",
                     tick.ask, InpFixedLotSize, stopLoss);
      }
      else
      {
         PrintFormat("Long breakout was not executed. Trade retcode: %u.", trade.ResultRetcode());
      }
      return;
   }

   if (tick.bid < g_rangeLow)
   {
      const double stopLoss = NormalizeDouble(tick.bid + stopDistance, digits);
      if (trade.Sell(InpFixedLotSize, _Symbol, 0.0, stopLoss, 0.0,
                     "Wickmorrow XAUUSD range breakout sell") && IsSuccessfulTrade())
      {
         g_tradeTaken = true;
         PrintFormat("Short breakout entered at %.5f with %.2f lots and SL %.5f.",
                     tick.bid, InpFixedLotSize, stopLoss);
      }
      else
      {
         PrintFormat("Short breakout was not executed. Trade retcode: %u.", trade.ResultRetcode());
      }
   }
}

int OnInit()
{
   if (!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   if (!trade.SetTypeFillingBySymbol(_Symbol))
   {
      Print("Unable to select a supported order filling mode for the symbol.");
      return INIT_FAILED;
   }

   PrintFormat("Wickmorrow breakout EA initialized for %s. Range: %02d:00-%02d:00 server time.",
               _Symbol, InpRangeStartHour, InpRangeEndHour);
   return INIT_SUCCEEDED;
}

void OnTick()
{
   MqlTick tick;
   if (!SymbolInfoTick(_Symbol, tick))
      return;

   MqlDateTime now;
   if (!TimeToStruct(TimeCurrent(), now))
      return;

   UpdateRange(tick, now);
   TryBreakout(tick);
}
