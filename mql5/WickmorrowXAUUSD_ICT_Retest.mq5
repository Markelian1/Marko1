// @polsia:user-owned
//+------------------------------------------------------------------+
//| Wickmorrow XAUUSD ICT Retest                                     |
//| Separate, provisional Strategy Tester hypothesis.                 |
//|                                                                  |
//| Operational definitions:                                         |
//| - FVG: a three-bar gap between the first and third candle ranges. |
//| - IFVG: an FVG invalidated past its far edge; its zone flips side. |
//| - OB: nearest opposing candle before an MSS break; range/body is  |
//|   configurable. Its invalidation flips it into a breaker block.  |
//| - CISD: close/wick crosses the open of the nearest prior opposite |
//|   candle, measured against the preceding candle.                  |
//| - Suspension block: configurable pre-displacement candle chosen  |
//|   when a three-bar FVG forms.                                     |
//| - MSS: close/wick breaks a selected confirmed swing high/low.     |
//| - MSS+FVG: same-direction MSS and FVG within a configurable window.|
//|                                                                  |
//| Entries require matching MSS + CISD within the confirmation       |
//| window, then an armed retest of IFVG, breaker, OB or suspension   |
//| block. Plain FVG / MSS+FVG zones are plotted but are not entries. |
//+------------------------------------------------------------------+
#property copyright "Wickmorrow"
#property version   "1.00"
#property description "Provisional XAUUSD ICT concepts and confirmed-zone retest EA"

#include <Trade/Trade.mqh>

enum ENUM_BREAK_RULE
  {
   BREAK_BY_CLOSE = 0,
   BREAK_BY_WICK = 1
  };

enum ENUM_SWING_PICK
  {
   SWING_MOST_RECENT_CONFIRMED = 0,
   SWING_EXTREME_IN_LOOKBACK = 1
  };

enum ENUM_SUSPENSION_PICK
  {
   SB_PRE_DISPLACEMENT_CANDLE = 0,
   SB_NEAREST_OPPOSITE_CANDLE = 1
  };

enum ENUM_ZONE_PRICE_RANGE
  {
   ZONE_FULL_CANDLE = 0,
   ZONE_CANDLE_BODY = 1
  };

enum ENUM_POSITION_SIZING
  {
   SIZE_FIXED_LOTS = 0,
   SIZE_RISK_PERCENT = 1
  };

enum ENUM_ZONE_KIND
  {
   ZONE_FVG = 0,
   ZONE_IFVG = 1,
   ZONE_ORDER_BLOCK = 2,
   ZONE_BREAKER = 3,
   ZONE_SUSPENSION = 4
  };

input string             InpTradeSymbol = "XAUUSD";                   // Must match chart symbol exactly
input ENUM_TIMEFRAMES    InpSignalTimeframe = PERIOD_M5;               // Structure and signal timeframe
input ENUM_BREAK_RULE    InpStructureBreakRule = BREAK_BY_CLOSE;      // MSS and CISD trigger rule
input ENUM_BREAK_RULE    InpZoneInvalidationRule = BREAK_BY_CLOSE;    // Close-through or wick-through distal edge
input ENUM_SWING_PICK    InpSwingSelection = SWING_MOST_RECENT_CONFIRMED;
input int                InpSwingLeftBars = 2;                         // Older bars required around a pivot
input int                InpSwingRightBars = 2;                        // Newer closed bars required to confirm a pivot
input int                InpStructureLookbackBars = 80;
input int                InpCISDLookbackBars = 12;
input int                InpOrderBlockSearchBars = 12;
input int                InpConfirmationWindowBars = 12;              // Max separation between matching MSS/CISD
input int                InpMSSFVGWindowBars = 6;                     // Max separation for MSS+FVG plot
input ENUM_SUSPENSION_PICK InpSuspensionIdentification = SB_PRE_DISPLACEMENT_CANDLE;
input ENUM_ZONE_PRICE_RANGE InpZonePriceRange = ZONE_FULL_CANDLE;    // Full candle or body for OB / suspension zones
input int                InpHistoryBarsToPlot = 500;                   // Closed bars replayed for chart annotations
input int                InpMaxTrackedZones = 300;
input int                InpZoneExtensionBars = 80;

input ENUM_POSITION_SIZING InpPositionSizing = SIZE_FIXED_LOTS;      // Provisional tester default: fixed 0.10 lots
input double             InpFixedLots = 0.10;                          // PROVISIONAL tester baseline from existing EA
input double             InpRiskPercent = 1.0;                          // Used only in risk-percent mode
input int                InpStopLossPoints = 500;                       // PROVISIONAL tester baseline; broker points
input double             InpTakeProfitRiskMultiple = 2.0;               // PROVISIONAL rule: TP = 2R (twice stop distance)
input int                InpMaxTradesPerDay = 1;                        // Server-time day; counts entry positions
input ulong              InpMagicNumber = 7052027;                     // Distinct from breakout EA magic 7052026
input uint               InpDeviationPoints = 20;

struct SZone
  {
   int      id;
   int      kind;
   int      direction; // +1 bullish, -1 bearish
   double   low;
   double   high;
   datetime created;
   bool     invalidated;
   bool     armed;
  };

CTrade trade;
SZone g_zones[];
datetime g_lastBarTime = 0;
datetime g_lastMssTime = 0;
datetime g_lastCisdTime = 0;
int g_lastMssDirection = 0;
int g_lastCisdDirection = 0;
int g_objectSerial = 0;
string g_objectPrefix = "WickmorrowICT_";

string ZoneKindName(const int kind)
  {
   if(kind == ZONE_FVG) return "FVG";
   if(kind == ZONE_IFVG) return "IFVG";
   if(kind == ZONE_ORDER_BLOCK) return "Order block";
   if(kind == ZONE_BREAKER) return "Breaker block";
   if(kind == ZONE_SUSPENSION) return "Suspension block";
   return "Zone";
  }

color ZoneColor(const int kind, const int direction, const bool invalidated)
  {
   if(invalidated) return clrDimGray;
   if(kind == ZONE_IFVG) return direction > 0 ? clrDeepSkyBlue : clrTomato;
   if(kind == ZONE_ORDER_BLOCK) return direction > 0 ? clrSeaGreen : clrIndianRed;
   if(kind == ZONE_BREAKER) return direction > 0 ? clrDodgerBlue : clrOrangeRed;
   if(kind == ZONE_SUSPENSION) return direction > 0 ? clrMediumSeaGreen : clrSalmon;
   return direction > 0 ? clrSlateGray : clrDarkSlateGray;
  }

datetime ZoneRightEdge()
  {
   int seconds = PeriodSeconds(InpSignalTimeframe);
   if(seconds <= 0) seconds = PeriodSeconds(_Period);
   if(seconds <= 0) seconds = 60;
   return TimeCurrent() + (datetime)(seconds * InpZoneExtensionBars);
  }

void DrawZone(const int index)
  {
   if(index < 0 || index >= ArraySize(g_zones)) return;
   SZone zone = g_zones[index];
   string base = g_objectPrefix + "zone_" + IntegerToString(zone.id);
   string rectangle = base + "_box";
   string label = base + "_label";
   datetime rightEdge = ZoneRightEdge();
   color zoneColor = ZoneColor(zone.kind, zone.direction, zone.invalidated);

   if(ObjectFind(0, rectangle) < 0)
      ObjectCreate(0, rectangle, OBJ_RECTANGLE, 0, zone.created, zone.high, rightEdge, zone.low);
   else
     {
      ObjectMove(0, rectangle, 0, zone.created, zone.high);
      ObjectMove(0, rectangle, 1, rightEdge, zone.low);
     }
   ObjectSetInteger(0, rectangle, OBJPROP_COLOR, zoneColor);
   ObjectSetInteger(0, rectangle, OBJPROP_FILL, true);
   ObjectSetInteger(0, rectangle, OBJPROP_BACK, true);
   ObjectSetInteger(0, rectangle, OBJPROP_STYLE, zone.invalidated ? STYLE_DOT : STYLE_SOLID);
   ObjectSetInteger(0, rectangle, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, rectangle, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, rectangle, OBJPROP_HIDDEN, true);

   if(ObjectFind(0, label) < 0)
      ObjectCreate(0, label, OBJ_TEXT, 0, zone.created, zone.high);
   else
      ObjectMove(0, label, 0, zone.created, zone.high);
   string side = zone.direction > 0 ? " bullish" : " bearish";
   string state = zone.invalidated ? " (invalidated)" : "";
   ObjectSetString(0, label, OBJPROP_TEXT, ZoneKindName(zone.kind) + side + state);
   ObjectSetInteger(0, label, OBJPROP_COLOR, zoneColor);
   ObjectSetInteger(0, label, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, label, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, label, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, label, OBJPROP_HIDDEN, true);
  }

void DrawMarker(const string label, const datetime when, const double price, const int direction, const color markerColor)
  {
   g_objectSerial++;
   string name = g_objectPrefix + "marker_" + IntegerToString(g_objectSerial);
   if(!ObjectCreate(0, name, OBJ_ARROW, 0, when, price)) return;
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, direction > 0 ? 233 : 234);
   ObjectSetInteger(0, name, OBJPROP_COLOR, markerColor);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

   g_objectSerial++;
   string textName = g_objectPrefix + "text_" + IntegerToString(g_objectSerial);
   double offset = 10.0 * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double textPrice = direction > 0 ? price - offset : price + offset;
   if(ObjectCreate(0, textName, OBJ_TEXT, 0, when, textPrice))
     {
      ObjectSetString(0, textName, OBJPROP_TEXT, label);
      ObjectSetInteger(0, textName, OBJPROP_COLOR, markerColor);
      ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, textName, OBJPROP_ANCHOR, direction > 0 ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, textName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, textName, OBJPROP_HIDDEN, true);
     }
  }

void DrawMSSLine(const datetime swingTime, const datetime breakTime, const double level, const int direction)
  {
   g_objectSerial++;
   string name = g_objectPrefix + "mss_level_" + IntegerToString(g_objectSerial);
   if(!ObjectCreate(0, name, OBJ_TREND, 0, swingTime, level, breakTime, level)) return;
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_COLOR, direction > 0 ? clrLimeGreen : clrRed);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

void AddZone(const int kind, const int direction, const double lowPrice, const double highPrice, const datetime created)
  {
   if(lowPrice <= 0.0 || highPrice <= lowPrice || direction == 0) return;
   int maximum = InpMaxTrackedZones < 20 ? 20 : InpMaxTrackedZones;
   int count = ArraySize(g_zones);
   if(count >= maximum)
     {
      string oldBase = g_objectPrefix + "zone_" + IntegerToString(g_zones[0].id);
      ObjectDelete(0, oldBase + "_box");
      ObjectDelete(0, oldBase + "_label");
      for(int i = 1; i < count; i++) g_zones[i - 1] = g_zones[i];
      ArrayResize(g_zones, count - 1);
     }
   int index = ArraySize(g_zones);
   if(ArrayResize(g_zones, index + 1) != index + 1) return;
   g_objectSerial++;
   g_zones[index].id = g_objectSerial;
   g_zones[index].kind = kind;
   g_zones[index].direction = direction;
   g_zones[index].low = lowPrice;
   g_zones[index].high = highPrice;
   g_zones[index].created = created;
   g_zones[index].invalidated = false;
   g_zones[index].armed = false;
   DrawZone(index);
  }

bool BreakAbove(const MqlRates &bar, const double level, const ENUM_BREAK_RULE rule)
  {
   return rule == BREAK_BY_WICK ? bar.high > level : bar.close > level;
  }

bool BreakBelow(const MqlRates &bar, const double level, const ENUM_BREAK_RULE rule)
  {
   return rule == BREAK_BY_WICK ? bar.low < level : bar.close < level;
  }

bool IsSwingPivot(const MqlRates &rates[], const int count, const int index, const bool highPivot)
  {
   if(index - InpSwingRightBars < 1 || index + InpSwingLeftBars >= count) return false;
   double candidate = highPivot ? rates[index].high : rates[index].low;
   for(int step = 1; step <= InpSwingRightBars; step++)
     {
      double newer = highPivot ? rates[index - step].high : rates[index - step].low;
      if(highPivot ? candidate <= newer : candidate >= newer) return false;
     }
   for(int step = 1; step <= InpSwingLeftBars; step++)
     {
      double older = highPivot ? rates[index + step].high : rates[index + step].low;
      if(highPivot ? candidate < older : candidate > older) return false;
     }
   return true;
  }

bool FindSwing(const MqlRates &rates[], const int count, const int signalShift, const bool highPivot,
               double &level, datetime &swingTime)
  {
   int first = signalShift + InpSwingRightBars + 1;
   int last = signalShift + InpStructureLookbackBars;
   if(last > count - InpSwingLeftBars - 1) last = count - InpSwingLeftBars - 1;
   bool found = false;
   double selected = highPivot ? -DBL_MAX : DBL_MAX;
   int selectedIndex = -1;
   for(int index = first; index <= last; index++)
     {
      if(!IsSwingPivot(rates, count, index, highPivot)) continue;
      if(InpSwingSelection == SWING_MOST_RECENT_CONFIRMED)
        {
         selectedIndex = index;
         found = true;
         break;
        }
      double candidate = highPivot ? rates[index].high : rates[index].low;
      if(!found || (highPivot ? candidate > selected : candidate < selected))
        {
         selected = candidate;
         selectedIndex = index;
         found = true;
        }
     }
   if(!found || selectedIndex < 0) return false;
   level = highPivot ? rates[selectedIndex].high : rates[selectedIndex].low;
   swingTime = rates[selectedIndex].time;
   return true;
  }

int DetectMSS(const MqlRates &rates[], const int count, const int shift, double &brokenLevel, datetime &swingTime)
  {
   if(shift + 1 >= count) return 0;
   double highLevel = 0.0;
   double lowLevel = 0.0;
   datetime highTime = 0;
   datetime lowTime = 0;
   bool haveHigh = FindSwing(rates, count, shift, true, highLevel, highTime);
   bool haveLow = FindSwing(rates, count, shift, false, lowLevel, lowTime);
   bool bullish = haveHigh && BreakAbove(rates[shift], highLevel, InpStructureBreakRule) &&
                  !BreakAbove(rates[shift + 1], highLevel, InpStructureBreakRule);
   bool bearish = haveLow && BreakBelow(rates[shift], lowLevel, InpStructureBreakRule) &&
                  !BreakBelow(rates[shift + 1], lowLevel, InpStructureBreakRule);
   if(bullish == bearish) return 0;
   if(bullish)
     {
      brokenLevel = highLevel;
      swingTime = highTime;
      return 1;
     }
   brokenLevel = lowLevel;
   swingTime = lowTime;
   return -1;
  }

int DetectCISD(const MqlRates &rates[], const int count, const int shift, double &referenceOpen)
  {
   if(shift + 1 >= count) return 0;
   bool bullishCandle = rates[shift].close > rates[shift].open;
   bool bearishCandle = rates[shift].close < rates[shift].open;
   int last = shift + InpCISDLookbackBars;
   if(last > count - 1) last = count - 1;
   for(int index = shift + 1; index <= last; index++)
     {
      bool opposite = bullishCandle ? rates[index].close < rates[index].open :
                      bearishCandle ? rates[index].close > rates[index].open : false;
      if(!opposite) continue;
      double trigger = rates[index].open;
      bool nowCrossed = bullishCandle ? BreakAbove(rates[shift], trigger, InpStructureBreakRule) :
                        bearishCandle ? BreakBelow(rates[shift], trigger, InpStructureBreakRule) : false;
      bool wasNotCrossed = bullishCandle ? !BreakAbove(rates[shift + 1], trigger, InpStructureBreakRule) :
                           bearishCandle ? !BreakBelow(rates[shift + 1], trigger, InpStructureBreakRule) : false;
      if(nowCrossed && wasNotCrossed)
        {
         referenceOpen = trigger;
         return bullishCandle ? 1 : -1;
        }
      return 0;
     }
   return 0;
  }

void GetZoneBounds(const MqlRates &bar, double &lowPrice, double &highPrice)
  {
   if(InpZonePriceRange == ZONE_CANDLE_BODY)
     {
      lowPrice = MathMin(bar.open, bar.close);
      highPrice = MathMax(bar.open, bar.close);
     }
   else
     {
      lowPrice = bar.low;
      highPrice = bar.high;
     }
  }

int FindOpposingCandle(const MqlRates &rates[], const int count, const int shift, const int direction, const int searchBars)
  {
   int last = shift + searchBars;
   if(last > count - 1) last = count - 1;
   for(int index = shift + 1; index <= last; index++)
     {
      bool bearish = rates[index].close < rates[index].open;
      bool bullish = rates[index].close > rates[index].open;
      if((direction > 0 && bearish) || (direction < 0 && bullish)) return index;
     }
   return -1;
  }

void CreateOrderBlock(const MqlRates &rates[], const int count, const int shift, const int direction)
  {
   int index = FindOpposingCandle(rates, count, shift, direction, InpOrderBlockSearchBars);
   if(index < 0) return;
   double lowPrice = 0.0;
   double highPrice = 0.0;
   GetZoneBounds(rates[index], lowPrice, highPrice);
   AddZone(ZONE_ORDER_BLOCK, direction, lowPrice, highPrice, rates[index].time);
  }

void CreateSuspensionBlock(const MqlRates &rates[], const int count, const int shift, const int direction)
  {
   int index = shift + 2; // Candle before the FVG's displacement candle.
   if(InpSuspensionIdentification == SB_NEAREST_OPPOSITE_CANDLE)
     {
      index = FindOpposingCandle(rates, count, shift + 1, direction, InpOrderBlockSearchBars);
      if(index < 0) return;
     }
   if(index >= count) return;
   double lowPrice = 0.0;
   double highPrice = 0.0;
   GetZoneBounds(rates[index], lowPrice, highPrice);
   AddZone(ZONE_SUSPENSION, direction, lowPrice, highPrice, rates[index].time);
  }

void UpdateZones(const MqlRates &bar)
  {
   int initialCount = ArraySize(g_zones);
   for(int index = initialCount - 1; index >= 0; index--)
     {
      if(g_zones[index].invalidated) continue;
      SZone zone = g_zones[index];
      bool breached = false;
      if(zone.direction > 0)
         breached = InpZoneInvalidationRule == BREAK_BY_WICK ? bar.low < zone.low : bar.close < zone.low;
      else
         breached = InpZoneInvalidationRule == BREAK_BY_WICK ? bar.high > zone.high : bar.close > zone.high;
      if(!breached) continue;

      g_zones[index].invalidated = true;
      g_zones[index].armed = false;
      DrawZone(index);
      if(zone.kind == ZONE_FVG)
         AddZone(ZONE_IFVG, -zone.direction, zone.low, zone.high, bar.time);
      else if(zone.kind == ZONE_ORDER_BLOCK)
         AddZone(ZONE_BREAKER, -zone.direction, zone.low, zone.high, bar.time);
     }
  }

bool BarsWithin(const datetime first, const datetime second, const int bars)
  {
   int seconds = PeriodSeconds(InpSignalTimeframe);
   if(seconds <= 0) return false;
   return MathAbs((double)(first - second)) <= (double)(seconds * bars);
  }

void PlotCompositeMSSFVG(const datetime when, const double price, const int direction)
  {
   DrawMarker("MSS+FVG", when, price, direction, clrGold);
  }

void ProcessBar(const MqlRates &rates[], const int count, const int shift)
  {
   if(shift < 1 || shift + 3 >= count) return;
   MqlRates bar = rates[shift];
   UpdateZones(bar);

   double mssLevel = 0.0;
   datetime swingTime = 0;
   int mssDirection = DetectMSS(rates, count, shift, mssLevel, swingTime);
   if(mssDirection != 0)
     {
      g_lastMssDirection = mssDirection;
      g_lastMssTime = bar.time;
      double markerPrice = mssDirection > 0 ? bar.low : bar.high;
      DrawMarker(mssDirection > 0 ? "MSS bullish" : "MSS bearish", bar.time, markerPrice, mssDirection,
                 mssDirection > 0 ? clrLimeGreen : clrRed);
      DrawMSSLine(swingTime, bar.time, mssLevel, mssDirection);
      CreateOrderBlock(rates, count, shift, mssDirection);
     }

   double cisdReference = 0.0;
   int cisdDirection = DetectCISD(rates, count, shift, cisdReference);
   if(cisdDirection != 0)
     {
      g_lastCisdDirection = cisdDirection;
      g_lastCisdTime = bar.time;
      double markerPrice = cisdDirection > 0 ? bar.low : bar.high;
      DrawMarker(cisdDirection > 0 ? "CISD bullish" : "CISD bearish", bar.time, markerPrice, cisdDirection,
                 cisdDirection > 0 ? clrAqua : clrMagenta);
     }

   int fvgDirection = 0;
   double fvgLow = 0.0;
   double fvgHigh = 0.0;
   if(rates[shift + 2].high < bar.low)
     {
      fvgDirection = 1;
      fvgLow = rates[shift + 2].high;
      fvgHigh = bar.low;
     }
   else if(rates[shift + 2].low > bar.high)
     {
      fvgDirection = -1;
      fvgLow = bar.high;
      fvgHigh = rates[shift + 2].low;
     }
   if(fvgDirection != 0)
     {
      AddZone(ZONE_FVG, fvgDirection, fvgLow, fvgHigh, bar.time);
      CreateSuspensionBlock(rates, count, shift, fvgDirection);
      if(g_lastMssDirection == fvgDirection && BarsWithin(g_lastMssTime, bar.time, InpMSSFVGWindowBars))
         PlotCompositeMSSFVG(bar.time, fvgDirection > 0 ? bar.low : bar.high, fvgDirection);
     }
  }

int ConfirmedTradeDirection(datetime &confirmationTime)
  {
   confirmationTime = 0;
   if(g_lastMssDirection == 0 || g_lastCisdDirection == 0 ||
      g_lastMssDirection != g_lastCisdDirection ||
      !BarsWithin(g_lastMssTime, g_lastCisdTime, InpConfirmationWindowBars)) return 0;
   confirmationTime = g_lastMssTime > g_lastCisdTime ? g_lastMssTime : g_lastCisdTime;
   return g_lastMssDirection;
  }

bool IsEntryZone(const int kind)
  {
   return kind == ZONE_IFVG || kind == ZONE_BREAKER || kind == ZONE_ORDER_BLOCK || kind == ZONE_SUSPENSION;
  }

bool HasOpenPosition()
  {
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      ulong ticket = PositionGetTicket(index);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) return true;
     }
   return false;
  }

int TradesOpenedToday()
  {
   MqlDateTime today;
   if(!TimeToStruct(TimeCurrent(), today)) return 0;
   today.hour = 0;
   today.min = 0;
   today.sec = 0;
   datetime dayStart = StructToTime(today);
   if(!HistorySelect(dayStart, TimeCurrent())) return 0;
   ulong positions[];
   int uniquePositions = 0;
   int deals = HistoryDealsTotal();
   for(int index = 0; index < deals; index++)
     {
      ulong ticket = HistoryDealGetTicket(index);
      if(ticket == 0) continue;
      if((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber ||
         HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) continue;
      ulong positionId = (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      bool seen = false;
      for(int prior = 0; prior < uniquePositions; prior++)
         if(positions[prior] == positionId) { seen = true; break; }
      if(seen) continue;
      if(ArrayResize(positions, uniquePositions + 1) != uniquePositions + 1) continue;
      positions[uniquePositions++] = positionId;
     }
   return uniquePositions;
  }

int VolumeDigits()
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   for(int digits = 0; digits <= 8; digits++)
      if(MathAbs(step - NormalizeDouble(step, digits)) < 1e-10) return digits;
   return 2;
  }

double CalculateVolume()
  {
   double minimum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maximum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(minimum <= 0.0 || maximum < minimum || step <= 0.0) return 0.0;
   double rawLots = InpFixedLots;
   if(InpPositionSizing == SIZE_RISK_PERCENT)
     {
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double stopDistance = InpStopLossPoints * point;
      if(tickSize <= 0.0 || tickValue <= 0.0 || point <= 0.0 || stopDistance <= 0.0) return 0.0;
      double lossPerLot = (stopDistance / tickSize) * tickValue;
      if(lossPerLot <= 0.0) return 0.0;
      rawLots = AccountInfoDouble(ACCOUNT_BALANCE) * (InpRiskPercent / 100.0) / lossPerLot;
     }
   if(rawLots < minimum || rawLots > maximum) return 0.0;
   double aligned = MathFloor((rawLots + 1e-10) / step) * step;
   if(aligned < minimum) return 0.0;
   return NormalizeDouble(aligned, VolumeDigits());
  }

bool IsSuccessfulTrade()
  {
   uint result = trade.ResultRetcode();
   return result == TRADE_RETCODE_DONE || result == TRADE_RETCODE_DONE_PARTIAL || result == TRADE_RETCODE_PLACED;
  }

void TryEntry()
  {
   if(HasOpenPosition() || InpMaxTradesPerDay <= 0 || TradesOpenedToday() >= InpMaxTradesPerDay) return;
   datetime confirmationTime = 0;
   int direction = ConfirmedTradeDirection(confirmationTime);
   if(direction == 0) return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   datetime currentBarTime = iTime(_Symbol, InpSignalTimeframe, 0);
   if(currentBarTime <= confirmationTime ||
      !BarsWithin(confirmationTime, currentBarTime, InpConfirmationWindowBars)) return;

   int selected = -1;
   for(int index = ArraySize(g_zones) - 1; index >= 0; index--)
     {
      if(g_zones[index].invalidated || !IsEntryZone(g_zones[index].kind) ||
         g_zones[index].direction != direction || g_zones[index].created >= currentBarTime) continue;
      if(direction > 0 && tick.ask > g_zones[index].high) g_zones[index].armed = true;
      if(direction < 0 && tick.bid < g_zones[index].low) g_zones[index].armed = true;
      bool retest = direction > 0 ? tick.ask >= g_zones[index].low && tick.ask <= g_zones[index].high :
                    tick.bid >= g_zones[index].low && tick.bid <= g_zones[index].high;
      if(g_zones[index].armed && retest) { selected = index; break; }
     }
   if(selected < 0) return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   long minimumStop = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(point <= 0.0 || InpStopLossPoints < minimumStop) return;
   double volume = CalculateVolume();
   if(volume <= 0.0)
     {
      Print("No entry: calculated volume is outside the symbol's minimum, maximum or volume step.");
      return;
     }
   double stopDistance = InpStopLossPoints * point;
   double targetDistance = stopDistance * InpTakeProfitRiskMultiple;
   double price = direction > 0 ? tick.ask : tick.bid;
   double stopLoss = NormalizeDouble(direction > 0 ? price - stopDistance : price + stopDistance, digits);
   double takeProfit = NormalizeDouble(direction > 0 ? price + targetDistance : price - targetDistance, digits);
   string comment = ZoneKindName(g_zones[selected].kind) + (direction > 0 ? " retest buy" : " retest sell");
   bool submitted = direction > 0 ? trade.Buy(volume, _Symbol, 0.0, stopLoss, takeProfit, comment) :
                    trade.Sell(volume, _Symbol, 0.0, stopLoss, takeProfit, comment);
   if(submitted && IsSuccessfulTrade())
     {
      g_zones[selected].armed = false;
      PrintFormat("Provisional retest order opened: %s, %.2f lots, SL %.*f, TP %.*f.",
                  comment, volume, digits, stopLoss, digits, takeProfit);
     }
   else
      PrintFormat("Retest order was not executed. Trade retcode: %u.", trade.ResultRetcode());
  }

bool ValidateInputs()
  {
   if(_Symbol != InpTradeSymbol)
     {
      PrintFormat("Attach to %s; current chart symbol is %s.", InpTradeSymbol, _Symbol);
      return false;
     }
   if(InpSwingLeftBars < 1 || InpSwingRightBars < 1 || InpStructureLookbackBars < 10 ||
      InpCISDLookbackBars < 1 || InpOrderBlockSearchBars < 1 || InpConfirmationWindowBars < 1 ||
      InpMSSFVGWindowBars < 1 || InpHistoryBarsToPlot < 50 || InpMaxTrackedZones < 20 ||
      InpZoneExtensionBars < 1)
     {
      Print("Invalid structure, history, or plotting input; bar windows must be positive and lookbacks large enough.");
      return false;
     }
   if(InpStopLossPoints <= 0 || InpTakeProfitRiskMultiple <= 0.0 || InpMaxTradesPerDay < 1 ||
      InpMagicNumber == 0 || InpFixedLots <= 0.0 || InpRiskPercent <= 0.0)
     {
      Print("Invalid risk input: stop, TP multiple, sizing values, daily cap and magic number must be positive.");
      return false;
     }
   return true;
  }

void ReplayHistory()
  {
   int extra = InpStructureLookbackBars + InpOrderBlockSearchBars + InpCISDLookbackBars +
               InpSwingLeftBars + InpSwingRightBars + 10;
   int requested = InpHistoryBarsToPlot + extra;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, InpSignalTimeframe, 0, requested, rates);
   if(copied < extra + 4)
     {
      PrintFormat("Waiting for more %s history; copied %d bars.", EnumToString(InpSignalTimeframe), copied);
      return;
     }
   int oldestShift = copied - 4;
   if(oldestShift > InpHistoryBarsToPlot) oldestShift = InpHistoryBarsToPlot;
   for(int shift = oldestShift; shift >= 1; shift--)
      ProcessBar(rates, copied, shift);
   ChartRedraw();
  }

int OnInit()
  {
   if(!ValidateInputs()) return INIT_PARAMETERS_INCORRECT;
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   if(!trade.SetTypeFillingBySymbol(_Symbol))
     {
      Print("Could not select a supported filling mode for this symbol.");
      return INIT_FAILED;
     }
   ReplayHistory();
   g_lastBarTime = iTime(_Symbol, InpSignalTimeframe, 0);
   Print("Provisional ICT retest EA initialized. No profitability is implied by its defaults or rules.");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, g_objectPrefix);
  }

void OnTick()
  {
   datetime currentBarTime = iTime(_Symbol, InpSignalTimeframe, 0);
   if(currentBarTime > 0 && currentBarTime != g_lastBarTime)
     {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int required = InpStructureLookbackBars + InpOrderBlockSearchBars + InpCISDLookbackBars +
                     InpSwingLeftBars + InpSwingRightBars + 8;
      int copied = CopyRates(_Symbol, InpSignalTimeframe, 0, required, rates);
      if(copied > 4)
        {
         ProcessBar(rates, copied, 1);
         g_lastBarTime = currentBarTime;
         ChartRedraw();
        }
     }
   TryEntry();
  }
