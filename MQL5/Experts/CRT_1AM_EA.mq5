//+------------------------------------------------------------------+
//|                                                   CRT_1AM_EA.mq5 |
//|        Time-based CRT (1AM / 5AM / 9AM New York H4 candle)       |
//+------------------------------------------------------------------+
//
// Rules taken from "How to trade the 1AM CRT" and "Time & Price":
//
//   1. HTF bias first (daily draw on liquidity). Here: the daily trend
//      (previous daily close above / below its 50-day average), and
//      premium / discount of the time-based range: sell in premium, buy
//      in discount.
//   2. Time-based range = the H4 candle(s) before the CRT candle.
//      1AM candle -> 5PM + 9PM candles (CBDR / Asia range)
//      5AM candle -> 1AM candle,   9AM candle -> 5AM candle
//   3. The CRT candle sweeps the range high or low (turtle soup) and
//      comes back inside.
//   4. OHLC / OLHC: sell above the CRT candle's opening price, buy below.
//   5. Key time: 2:00-4:00 AM New York for the 1AM candle.
//   6. Entry model #1: the candle that dug above the high (below the low)
//      is the order block; when a later candle closes through it (engulfs
//      it), enter. Entry timeframe M30 by default (tested better than M15
//      on 2020-2026 XAUUSD data), M15 as an option.
//   7. SL beyond the sweep extreme, TP at 1:2 / 1:3 RR (or the other side
//      of the range = short-term draw on liquidity).
//
// All times are New York time. InpNYOffset converts them to server time
// (most MT5 brokers: server = New York + 7 hours all year).
//
// Not implemented: SMT divergence (needs a second symbol) and H4 order
// block / FVG key levels (approximated by the premium/discount filter).
//+------------------------------------------------------------------+
#property copyright "Marko"
#property version   "1.02"
#property description "Time-based CRT: the 1AM (5AM / 9AM) New York H4 candle sweeps the"
#property description "prior range at key time; M30 / M15 order block entry. Built for XAUUSD."

#include <Trade/Trade.mqh>


// ============================================================================
// ENUMS
// ============================================================================

enum ENUM_CRT_BIAS
{
   BIAS_NONE       = 0, // Off (both directions)
   BIAS_D1_CRT     = 1, // Active daily CRT only (no trade without one)
   BIAS_PREV_DAY   = 2, // Direction of the previous daily candle
   BIAS_D1_OR_PREV = 3, // Daily CRT, else the previous daily candle
   BIAS_TREND      = 4  // Daily trend: previous close vs its N-day average
};

enum ENUM_CRT_PD
{
   PD_OFF      = 0, // Off
   PD_RANGE    = 1, // Half of the time-based range (Asia range for 1AM)
   PD_PREV_DAY = 2  // Half of the previous day's range
};

// Why a signal was not traded (counted for the funnel report).
enum ENUM_REJECT
{
   REJ_SIGNALS_ONLY = 0,
   REJ_KEY_TIME,
   REJ_BIAS,
   REJ_POSITION,
   REJ_MAX_TRADES,
   REJ_SPREAD,
   REJ_OHLC,
   REJ_PD,
   REJ_SL_SIDE,
   REJ_SL_SMALL,
   REJ_RR,
   REJ_LOTS,
   REJ_ORDER,
   REJ_STALE
};
#define REJECTS 14   // number of ENUM_REJECT values

enum ENUM_CRT_TP
{
   TP_RR    = 0, // Fixed reward:risk (1:2 / 1:3)
   TP_RANGE = 1  // Other side of the time-based range (short-term DOL)
};


// ============================================================================
// INPUTS
// ============================================================================

input group "1. MODEL (New York time)"
input bool InpTradeEnabled = true;  // Place trades (false = signals only)
input int  InpNYOffset     = 7;     // Server time minus New York time (hours)
input ENUM_TIMEFRAMES InpEntryTF = PERIOD_M30; // Entry / order-block timeframe (M5, M15, M30)
input bool InpModel1AM     = true;  // 1AM candle (range = 5PM + 9PM candles)
input int  InpKT1From      = 200;   // 1AM key time from (HHMM)
input int  InpKT1To        = 400;   // 1AM key time to (HHMM)
input bool InpModel5AM     = true;  // 5AM candle (range = 1AM candle)
input int  InpKT5From      = 500;   // 5AM key time from (HHMM)
input int  InpKT5To        = 700;   // 5AM key time to (HHMM)
input bool InpModel9AM     = true;  // 9AM candle (range = 5AM candle)
input int  InpKT9From      = 930;   // 9AM key time from (HHMM)
input int  InpKT9To        = 1100;  // 9AM key time to (HHMM)

input group "2. BIAS / PREMIUM-DISCOUNT"
input ENUM_CRT_BIAS InpBias     = BIAS_TREND;      // Higher-timeframe bias
input int           InpTrendDays = 50;             // Days in the trend average (bias = daily trend)
input ENUM_CRT_PD   InpPremDisc = PD_RANGE;        // Premium/discount (sell above / buy below the middle)
input bool          InpOHLC     = true;            // Sell only above / buy only below the CRT candle open

input group "3. RISK / EXIT"
input double InpRiskPercent  = 0.5;    // Risk per trade (% of balance)
input double InpMaxLots      = 5.0;    // Max lots per trade (safety cap)
input ENUM_CRT_TP InpTPMode   = TP_RR;  // Take profit
input double InpRR           = 2.0;    // Reward:risk (TP = fixed RR)
input double InpMinRR        = 1.5;    // Min reward:risk (TP = range side)
input double InpSLBuffer     = 0.30;   // SL buffer beyond the sweep (price units, XAUUSD = $)
input int    InpExitHHMM     = 1200;   // Close open trades at (HHMM New York, 0 = off)
input int    InpMaxTradesDay = 1;      // Max trades per day
input ulong  InpMagic        = 660100; // Magic number

input group "4. COST FILTERS"
input double InpMinSL        = 1.00;   // Min SL distance (price units, 0 = off)
input double InpMinSLSpreadX = 4.0;    // Min SL distance as a multiple of the spread (0 = off)
input double InpMaxSpread    = 0.50;   // Max spread (price units, 0 = off)
input int    InpSlippagePts  = 30;     // Max slippage (points)

input group "5. DISPLAY"
input bool InpShowPanel = true;  // Show status panel
input bool InpDraw      = true;  // Draw ranges, sweeps and entries
input bool InpVerbose   = true;  // Print setups to the journal

input group "6. OPTIMIZATION"
input int  InpOptMinTrades = 30; // Min trades for the "Custom max" score


// ============================================================================
// STRUCTS / GLOBALS
// ============================================================================

#define MODELS  3
#define OBJ_PFX "CRT1AM_"

struct ModelDay
{
   datetime key;         // CRT candle start (New York time)
   bool     ok;          // range and open available
   bool     done;        // traded (or finished) for this candle
   int      allowDir;    // 0 = none, 1 = buy, 2 = sell, 3 = both
   double   rngHigh;
   double   rngLow;
   double   crtOpen;
   double   pdMid;       // previous day's midpoint (premium above, discount below)
   bool     sweptHigh;
   double   sweepHigh;
   double   obSellLow;   // low of the candle that dug above the high
   datetime obSellTime;
   bool     sweptLow;
   double   sweepLow;
   double   obBuyHigh;   // high of the candle that dug below the low
   datetime obBuyTime;
   string   status;
};

struct D1Engine
{
   bool     hasParent;
   int      state;       // 0 wait, 1 bull CRT active, 2 bear CRT active
   double   ph;
   double   pl;
   double   target;
   datetime lastBarTime;
};

struct TradeRisk
{
   ulong  posId;
   double riskMoney;
   double commission;
};

CTrade    g_trade;
ModelDay  g_md[MODELS];
D1Engine  g_d1;
TradeRisk g_risk[];

int       g_mHour[MODELS]   = {1, 5, 9};   // CRT candle start (NY hour)
int       g_mRange[MODELS]  = {2, 1, 1};   // H4 candles in the time-based range
string    g_mName[MODELS]   = {"1AM", "5AM", "9AM"};
bool      g_mOn[MODELS];
int       g_mFrom[MODELS];
int       g_mTo[MODELS];

datetime  g_lastBar    = 0;          // open time of the entry-TF bar being formed
ENUM_TIMEFRAMES g_tf   = PERIOD_M30;
int       g_tfSec      = 1800;
bool      g_ready     = false;
bool      g_silent    = false;
bool      g_noChart   = false;
string    g_lastSkip  = "-";

// Funnel: how many CRT candles, sweeps and order-block breaks there were
// and why the signals were not traded.
int       g_fCandles = 0, g_fNoData = 0, g_fNoBias = 0;
int       g_fHighSweeps = 0, g_fLowSweeps = 0, g_fBreaks = 0, g_fTrades = 0;
int       g_rej[REJECTS];
string    g_rejName[REJECTS] = {"signals only", "key time", "against bias", "position open", "max trades",
                                "spread", "OHLC", "premium/discount", "SL side", "SL too small", "RR",
                                "lot size", "order failed", "stale"};
long      g_objSeq    = 0;

int       g_stN = 0, g_stWin = 0, g_stSL = 0, g_stTP = 0, g_stOther = 0;
double    g_stWinR = 0.0, g_stLossR = 0.0, g_stWorstR = 0.0;
double    g_stSLR = 0.0, g_stTPR = 0.0, g_stOtherR = 0.0;

void SetPlannedRisk(ulong posId, double riskMoney);


// ============================================================================
// HELPERS
// ============================================================================

void Log(string msg)
{
   if(!g_silent)
      Print(msg);
}

datetime ToNY(datetime server)     { return server - InpNYOffset * 3600; }
datetime ToServer(datetime ny)     { return ny + InpNYOffset * 3600; }
datetime DayStart(datetime t)      { return (datetime)((long)t - (long)t % 86400); }
int      MinuteOfDay(datetime t)   { return (int)(((long)t % 86400) / 60); }
int      HHMMToMin(int hhmm)       { return (hhmm / 100) * 60 + hhmm % 100; }

string NYText(datetime ny)
{
   MqlDateTime d;
   TimeToStruct(ny, d);
   return StringFormat("%02d/%02d %02d:%02d NY", d.day, d.mon, d.hour, d.min);
}

string PriceText(double p) { return p <= 0.0 ? "-" : DoubleToString(p, _Digits); }

double NormPrice(double p)
{
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0.0)
      ts = _Point;
   return NormalizeDouble(MathRound(p / ts) * ts, _Digits);
}

double NormalizeLots(double lots)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0)
      step = 0.01;

   lots = MathFloor(lots / step + 1e-9) * step;
   if(lots < vmin - 1e-9)
      return 0.0;
   if(vmax > 0.0 && lots > vmax)
      lots = vmax;
   if(InpMaxLots > 0.0 && lots > InpMaxLots)
      lots = MathFloor(InpMaxLots / step + 1e-9) * step;

   int digits = 0;
   double s = step;
   while(digits < 8 && MathAbs(s - MathRound(s)) > 1e-9)
   {
      s *= 10.0;
      digits++;
   }
   return NormalizeDouble(lots, digits);
}

double CalcLots(int dir, double entry, double sl)
{
   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double pnl = 0.0;
   ENUM_ORDER_TYPE type = dir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(type, _Symbol, 1.0, entry, sl, pnl) || pnl >= 0.0)
      return 0.0;
   return NormalizeLots(riskMoney / -pnl);
}

bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
   }
   return false;
}

// Trades opened since the start of the current New York day.
int TradesToday()
{
   datetime now      = TimeCurrent();
   datetime dayStart = ToServer(DayStart(ToNY(now)));
   if(!HistorySelect(dayStart, now + 60))
      return 0;

   int cnt   = 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0)
         continue;
      if(HistoryDealGetString(t, DEAL_SYMBOL) != _Symbol)
         continue;
      if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagic)
         continue;
      if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;
      cnt++;
   }
   return cnt;
}

void Skip(int why, string reason)
{
   g_rej[why]++;
   g_lastSkip = reason;
   Log("SKIP: " + reason);
}

string FunnelText()
{
   return StringFormat("CRT candles %d | no data %d | no bias %d | high sweeps %d | low sweeps %d | OB breaks %d | trades %d",
                       g_fCandles, g_fNoData, g_fNoBias, g_fHighSweeps, g_fLowSweeps, g_fBreaks, g_fTrades);
}

string RejectText()
{
   string s = "";
   for(int i = 0; i < REJECTS; i++)
      if(g_rej[i] > 0)
         s += (s == "" ? "" : " | ") + g_rejName[i] + " " + IntegerToString(g_rej[i]);
   return s == "" ? "none" : s;
}


// ============================================================================
// DRAWING
// ============================================================================

bool DrawingOn() { return InpDraw && !g_silent && !g_noChart; }

string NewObjName(string tag)
{
   g_objSeq++;
   return OBJ_PFX + tag + "_" + IntegerToString(g_objSeq);
}

void DrawLabel(datetime t, double price, string text, color clr, bool above)
{
   if(!DrawingOn() || price <= 0.0)
      return;
   string name = NewObjName("T");
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price))
      return;
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, above ? ANCHOR_LOWER : ANCHOR_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawLevel(datetime t1, datetime t2, double price, color clr, ENUM_LINE_STYLE style)
{
   if(!DrawingOn() || price <= 0.0)
      return;
   string name = NewObjName("L");
   if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price))
      return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawBox(datetime t1, datetime t2, double p1, double p2, color clr)
{
   if(!DrawingOn())
      return;
   string name = NewObjName("B");
   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2))
      return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}


// ============================================================================
// DAILY CRT (bias)
// ============================================================================

void D1Parent(const MqlRates &r)
{
   g_d1.hasParent = true;
   g_d1.ph        = r.high;
   g_d1.pl        = r.low;
   g_d1.target    = 0.0;
   g_d1.state     = 0;
}

// Same rules as the CRT engine of CRT_MTF_EA: parent -> sweep -> close back
// inside -> CRT active until the target is hit or it is invalidated.
void D1Step(const MqlRates &r)
{
   if(!g_d1.hasParent)
   {
      D1Parent(r);
      return;
   }

   if(g_d1.state == 0)
   {
      bool sweptLow  = r.low  <= g_d1.pl;
      bool sweptHigh = r.high >= g_d1.ph;
      if(r.close > g_d1.ph || r.close < g_d1.pl || (sweptLow && sweptHigh))
         D1Parent(r);
      else if(sweptLow)
      {
         g_d1.state  = 1;
         g_d1.target = g_d1.ph;
      }
      else if(sweptHigh)
      {
         g_d1.state  = 2;
         g_d1.target = g_d1.pl;
      }
      return;
   }

   bool bull = g_d1.state == 1;
   if((bull && r.high >= g_d1.target) || (!bull && r.low <= g_d1.target))
      D1Parent(r);
   else if((bull && r.close < g_d1.pl) || (!bull && r.close > g_d1.ph))
      D1Parent(r);
}

// Feed every daily bar that has closed and not been processed yet.
bool D1Update()
{
   MqlRates r[];
   int n;
   if(g_d1.lastBarTime == 0)
      n = CopyRates(_Symbol, PERIOD_D1, 1, 300, r);
   else
   {
      datetime lastOpen = iTime(_Symbol, PERIOD_D1, 1);
      if(lastOpen <= g_d1.lastBarTime)
         return true;
      n = CopyRates(_Symbol, PERIOD_D1, g_d1.lastBarTime + 1, lastOpen, r);
   }
   if(n <= 0)
      return false;

   for(int i = 0; i < n; i++)
   {
      if(r[i].time <= g_d1.lastBarTime)
         continue;
      D1Step(r[i]);
      g_d1.lastBarTime = r[i].time;
   }
   return true;
}

string D1Text()
{
   return g_d1.state == 1 ? "BULL CRT" : g_d1.state == 2 ? "BEAR CRT" : "NO CRT";
}


// ============================================================================
// MODEL
// ============================================================================

void ResetModelDay(int m, datetime key)
{
   g_md[m].key        = key;
   g_md[m].ok         = false;
   g_md[m].done       = false;
   g_md[m].allowDir   = 0;
   g_md[m].rngHigh    = 0.0;
   g_md[m].rngLow     = 0.0;
   g_md[m].crtOpen    = 0.0;
   g_md[m].pdMid      = 0.0;
   g_md[m].sweptHigh  = false;
   g_md[m].sweepHigh  = 0.0;
   g_md[m].obSellLow  = 0.0;
   g_md[m].obSellTime = 0;
   g_md[m].sweptLow   = false;
   g_md[m].sweepLow   = 0.0;
   g_md[m].obBuyHigh  = 0.0;
   g_md[m].obBuyTime  = 0;
   g_md[m].status     = "waiting";
}

// First entry-TF bar of a CRT candle: build the time-based range, read the
// candle's open, the previous day's range and the higher-timeframe bias.
void InitModelDay(int m, datetime crtNY)
{
   ResetModelDay(m, crtNY);
   g_fCandles++;

   datetime crtSrv   = ToServer(crtNY);
   datetime rngStart = crtSrv - g_mRange[m] * 4 * 3600;

   MqlRates rr[];
   int n = CopyRates(_Symbol, g_tf, rngStart, crtSrv - 1, rr);
   if(n < 2)
   {
      g_md[m].status = "no range data";
      g_fNoData++;
      return;
   }
   double hi = rr[0].high;
   double lo = rr[0].low;
   for(int i = 1; i < n; i++)
   {
      hi = MathMax(hi, rr[i].high);
      lo = MathMin(lo, rr[i].low);
   }

   MqlRates oc[];
   if(CopyRates(_Symbol, g_tf, crtSrv, crtSrv + 3600, oc) <= 0)
   {
      g_md[m].status = "no open";
      g_fNoData++;
      return;
   }

   // dd[k-1] = the day that contains the CRT candle, dd[k-2] = previous day,
   // dd[0..k-2] = the days of the trend average.
   MqlRates dd[];
   int need = MathMax(2, InpTrendDays + 1);
   int k    = CopyRates(_Symbol, PERIOD_D1, crtSrv, need, dd);
   if(k < 2 || (InpBias == BIAS_TREND && k < need))
   {
      g_md[m].status = "no daily data";
      g_fNoData++;
      return;
   }

   g_md[m].rngHigh = hi;
   g_md[m].rngLow  = lo;
   g_md[m].crtOpen = oc[0].open;
   MqlRates prev = dd[k - 2];
   g_md[m].pdMid   = InpPremDisc == PD_PREV_DAY ? (prev.high + prev.low) / 2.0 : (hi + lo) / 2.0;

   int prevDir = prev.close > prev.open ? 1 : prev.close < prev.open ? 2 : 0;
   if(InpBias == BIAS_NONE)
      g_md[m].allowDir = 3;
   else if(InpBias == BIAS_D1_CRT)
      g_md[m].allowDir = g_d1.state;                 // 0 none, 1 buy, 2 sell
   else if(InpBias == BIAS_PREV_DAY)
      g_md[m].allowDir = prevDir;
   else if(InpBias == BIAS_D1_OR_PREV)
      g_md[m].allowDir = g_d1.state != 0 ? g_d1.state : prevDir;
   else
   {
      double sum = 0.0;
      for(int j = 0; j < k - 1; j++)
         sum += dd[j].close;
      double avg = sum / (k - 1);
      g_md[m].allowDir = prev.close > avg ? 1 : prev.close < avg ? 2 : 0;
   }

   g_md[m].ok     = true;
   g_md[m].status = g_md[m].allowDir == 0 ? "no bias today" : "watching sweep";
   if(g_md[m].allowDir == 0)
      g_fNoBias++;

   DrawBox(rngStart, crtSrv, lo, hi, clrDarkSlateGray);
   DrawLevel(crtSrv, crtSrv + 4 * 3600, g_md[m].crtOpen, clrGold, STYLE_DOT);
   DrawLevel(crtSrv, crtSrv + 4 * 3600, hi, clrTomato, STYLE_SOLID);
   DrawLevel(crtSrv, crtSrv + 4 * 3600, lo, clrMediumSeaGreen, STYLE_SOLID);

   if(InpVerbose)
      Log(StringFormat("[%s] %s range %s - %s | open %s | prev-day mid %s | bias %s",
                       g_mName[m], NYText(crtNY), PriceText(lo), PriceText(hi),
                       PriceText(g_md[m].crtOpen), PriceText(g_md[m].pdMid),
                       g_md[m].allowDir == 1 ? "BUY" : g_md[m].allowDir == 2 ? "SELL" :
                       g_md[m].allowDir == 3 ? "BOTH" : "NONE"));
}

bool InKeyTime(int m, datetime ny)
{
   int t = MinuteOfDay(ny);
   return t >= HHMMToMin(g_mFrom[m]) && t < HHMMToMin(g_mTo[m]);
}

// Checks the filters and sends the order. dir 1 = buy, 2 = sell.
bool TryEnter(int m, int dir, datetime sigNY, double extreme)
{
   string tag = g_mName[m] + (dir == 1 ? " BUY" : " SELL");

   if(!InpTradeEnabled)
   {
      Skip(REJ_SIGNALS_ONLY, tag + ": signals only");
      return false;
   }
   if(!InKeyTime(m, sigNY))
   {
      Skip(REJ_KEY_TIME, tag + ": outside key time " + NYText(sigNY));
      return false;
   }
   if((g_md[m].allowDir & dir) == 0)
   {
      Skip(REJ_BIAS, tag + ": against HTF bias");
      return false;
   }
   if(HasOpenPosition())
   {
      Skip(REJ_POSITION, tag + ": position already open");
      return false;
   }
   if(InpMaxTradesDay > 0 && TradesToday() >= InpMaxTradesDay)
   {
      Skip(REJ_MAX_TRADES, tag + ": max trades today");
      return false;
   }

   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;
   double entry  = dir == 1 ? ask : bid;

   if(InpMaxSpread > 0.0 && spread > InpMaxSpread)
   {
      Skip(REJ_SPREAD, tag + ": spread " + DoubleToString(spread, _Digits));
      return false;
   }
   // OHLC: sell above the CRT candle's open, buy below it.
   if(InpOHLC && ((dir == 2 && bid < g_md[m].crtOpen) || (dir == 1 && ask > g_md[m].crtOpen)))
   {
      Skip(REJ_OHLC, tag + ": wrong side of the CRT open");
      return false;
   }
   // Premium / discount: sell above / buy below the middle of the range (or previous day).
   if(InpPremDisc != PD_OFF && ((dir == 2 && bid < g_md[m].pdMid) || (dir == 1 && ask > g_md[m].pdMid)))
   {
      Skip(REJ_PD, tag + (dir == 2 ? ": not in premium" : ": not in discount"));
      return false;
   }

   double sl   = NormPrice(dir == 1 ? extreme - InpSLBuffer : extreme + InpSLBuffer);
   double risk = dir == 1 ? entry - sl : sl - entry;
   if(risk <= 0.0)
   {
      Skip(REJ_SL_SIDE, tag + ": SL on the wrong side");
      return false;
   }
   double minRisk = MathMax(InpMinSL, InpMinSLSpreadX * spread);
   double minDist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(risk < minRisk || risk < minDist)
   {
      Skip(REJ_SL_SMALL, StringFormat("%s: SL %s too small", tag, DoubleToString(risk, _Digits)));
      return false;
   }

   double tp;
   if(InpTPMode == TP_RR)
      tp = dir == 1 ? entry + InpRR * risk : entry - InpRR * risk;
   else
   {
      tp = dir == 1 ? g_md[m].rngHigh : g_md[m].rngLow;
      double reward = dir == 1 ? tp - entry : entry - tp;
      if(reward <= 0.0 || reward / risk < InpMinRR)
      {
         Skip(REJ_RR, StringFormat("%s: RR %.2f < %.2f", tag, reward / risk, InpMinRR));
         return false;
      }
   }
   tp = NormPrice(tp);

   double lots = CalcLots(dir, entry, sl);
   if(lots <= 0.0)
   {
      Skip(REJ_LOTS, tag + ": lot size below broker minimum");
      return false;
   }

   string cmt = "CRT " + g_mName[m];
   bool ok = dir == 1 ? g_trade.Buy(lots, _Symbol, entry, sl, tp, cmt)
                      : g_trade.Sell(lots, _Symbol, entry, sl, tp, cmt);
   uint rc = g_trade.ResultRetcode();
   if(!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_PLACED))
   {
      Skip(REJ_ORDER, StringFormat("%s: order failed %u %s", tag, rc, g_trade.ResultRetcodeDescription()));
      return false;
   }

   // Planned risk at the real fill, for the R accounting.
   double fill = g_trade.ResultPrice() > 0.0 ? g_trade.ResultPrice() : entry;
   double pnlAtSl = 0.0;
   if(OrderCalcProfit(dir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lots, fill, sl, pnlAtSl) && pnlAtSl < 0.0)
      SetPlannedRisk(g_trade.ResultOrder(), -pnlAtSl);

   g_lastSkip = "-";
   g_fTrades++;
   Log(StringFormat("%s %s lots | entry %s  SL %s  TP %s | range %s-%s | %s",
                    tag, DoubleToString(lots, 2), PriceText(entry), PriceText(sl), PriceText(tp),
                    PriceText(g_md[m].rngLow), PriceText(g_md[m].rngHigh), NYText(sigNY)));
   DrawLabel(TimeCurrent(), entry, tag, dir == 1 ? clrAqua : clrMagenta, dir == 2);
   return true;
}

// One closed entry-TF bar through the model.
void ModelStep(int m, const MqlRates &b, bool latest)
{
   datetime ny    = ToNY(b.time);
   datetime crtNY = DayStart(ny) + g_mHour[m] * 3600;
   if(ny < crtNY || ny >= crtNY + 4 * 3600)
      return;   // only inside the CRT candle

   if(g_md[m].key != crtNY)
      InitModelDay(m, crtNY);
   if(!g_md[m].ok || g_md[m].done || g_md[m].allowDir == 0)
      return;

   // ------------------------------------------------------------------
   // Model #1: a later candle closes through the order block (the candle
   // that dug above the high / below the low) and back inside the range.
   // Checked before the sweep update, so an engulfing candle that also
   // makes a new extreme still counts; its extreme goes into the SL.
   // ------------------------------------------------------------------
   bool sellSig = g_md[m].sweptHigh && b.time > g_md[m].obSellTime &&
                  b.close < g_md[m].obSellLow && b.close < g_md[m].rngHigh;
   bool buySig  = g_md[m].sweptLow && b.time > g_md[m].obBuyTime &&
                  b.close > g_md[m].obBuyHigh && b.close > g_md[m].rngLow;

   datetime sigNY = ny + g_tfSec;   // the signal is known at the bar close
   for(int k = 0; k < 2; k++)
   {
      int  dir = k == 0 ? 2 : 1;
      bool sig = k == 0 ? sellSig : buySig;
      if(!sig)
         continue;

      g_fBreaks++;
      if(InpVerbose)
         Log(StringFormat("[%s] %s OB break at %s", g_mName[m], dir == 2 ? "SELL" : "BUY", NYText(sigNY)));

      double extreme = dir == 2 ? MathMax(g_md[m].sweepHigh, b.high) : MathMin(g_md[m].sweepLow, b.low);
      bool entered = false;
      if(latest)
         entered = TryEnter(m, dir, sigNY, extreme);
      else
         Skip(REJ_STALE, g_mName[m] + ": stale signal");

      // This order block is used up either way; a new sweep extreme makes a new one.
      if(dir == 2)
         g_md[m].obSellTime = D'3000.01.01';
      else
         g_md[m].obBuyTime = D'3000.01.01';

      if(entered)
      {
         g_md[m].done   = true;
         g_md[m].status = "traded";
         return;
      }
   }

   // ------------------------------------------------------------------
   // Sweep of the range high: the candle with the highest high is the
   // sell order block. Mirror image for the low.
   // ------------------------------------------------------------------
   if(b.high > g_md[m].rngHigh && (!g_md[m].sweptHigh || b.high > g_md[m].sweepHigh))
   {
      if(!g_md[m].sweptHigh)
      {
         g_fHighSweeps++;
         DrawLabel(b.time, b.high, g_mName[m] + " sweep", clrOrange, true);
      }
      g_md[m].sweptHigh  = true;
      g_md[m].sweepHigh  = b.high;
      g_md[m].obSellLow  = b.low;
      g_md[m].obSellTime = b.time;
      g_md[m].status     = "high swept, waiting for OB break";
   }
   if(b.low < g_md[m].rngLow && (!g_md[m].sweptLow || b.low < g_md[m].sweepLow))
   {
      if(!g_md[m].sweptLow)
      {
         g_fLowSweeps++;
         DrawLabel(b.time, b.low, g_mName[m] + " sweep", clrOrange, false);
      }
      g_md[m].sweptLow  = true;
      g_md[m].sweepLow  = b.low;
      g_md[m].obBuyHigh = b.high;
      g_md[m].obBuyTime = b.time;
      g_md[m].status    = "low swept, waiting for OB break";
   }
}

// Closes positions opened before the latest exit time (InpExitHHMM New York).
void CloseAtExitTime()
{
   if(InpExitHHMM <= 0)
      return;
   datetime nowNY  = ToNY(TimeCurrent());
   datetime exitNY = DayStart(nowNY) + HHMMToMin(InpExitHHMM) * 60;
   if(nowNY < exitNY)
      exitNY -= 86400;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(ToNY((datetime)PositionGetInteger(POSITION_TIME)) >= exitNY)
         continue;
      if(g_trade.PositionClose(ticket))
         Log("CLOSE: exit time " + NYText(nowNY));
   }
}


// ============================================================================
// TRADE ACCOUNTING (realised R per trade)
// ============================================================================

int FindRisk(ulong posId)
{
   for(int i = ArraySize(g_risk) - 1; i >= 0; i--)
      if(g_risk[i].posId == posId)
         return i;
   return -1;
}

int AddRisk(ulong posId)
{
   int n = ArraySize(g_risk);
   ArrayResize(g_risk, n + 1, 16);
   g_risk[n].posId      = posId;
   g_risk[n].riskMoney  = 0.0;
   g_risk[n].commission = 0.0;
   return n;
}

void SetPlannedRisk(ulong posId, double riskMoney)
{
   int i = FindRisk(posId);
   if(i < 0)
      i = AddRisk(posId);
   g_risk[i].riskMoney = riskMoney;
}

void RemoveRisk(int i)
{
   int n = ArraySize(g_risk);
   for(int k = i; k < n - 1; k++)
      g_risk[k] = g_risk[k + 1];
   ArrayResize(g_risk, n - 1);
}

void PrintTradeSummary()
{
   Print("CRT 1AM FUNNEL: " + FunnelText());
   Print("CRT 1AM REJECTED: " + RejectText());
   if(g_stN == 0)
   {
      Print("CRT 1AM SUMMARY: no closed trades");
      return;
   }
   int losses = g_stN - g_stWin;
   Print(StringFormat("CRT 1AM SUMMARY: %d trades | win %.1f%% | avg win %+.2fR | avg loss %+.2fR | worst %+.2fR | total %+.1fR",
                      g_stN, 100.0 * g_stWin / g_stN,
                      g_stWin > 0 ? g_stWinR / g_stWin : 0.0,
                      losses > 0 ? g_stLossR / losses : 0.0,
                      g_stWorstR, g_stWinR + g_stLossR));
   Print(StringFormat("CRT 1AM SUMMARY by exit: SL %d x %+.2fR | TP %d x %+.2fR | time/EA close %d x %+.2fR",
                      g_stSL, g_stSL > 0 ? g_stSLR / g_stSL : 0.0,
                      g_stTP, g_stTP > 0 ? g_stTPR / g_stTP : 0.0,
                      g_stOther, g_stOther > 0 ? g_stOtherR / g_stOther : 0.0));
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;
   if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic)
      return;

   ulong posId    = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   long  dealType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   int   i        = FindRisk(posId);

   if(dealType == DEAL_ENTRY_IN)
   {
      if(i < 0)
         i = AddRisk(posId);
      g_risk[i].commission += HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
      return;
   }
   if(dealType != DEAL_ENTRY_OUT && dealType != DEAL_ENTRY_OUT_BY)
      return;
   if(i < 0 || g_risk[i].riskMoney <= 0.0)
      return;

   double money = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                  HistoryDealGetDouble(trans.deal, DEAL_COMMISSION) +
                  HistoryDealGetDouble(trans.deal, DEAL_SWAP) +
                  g_risk[i].commission;
   double r      = money / g_risk[i].riskMoney;
   long   reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   RemoveRisk(i);

   g_stN++;
   if(r > 0.0)
   {
      g_stWin++;
      g_stWinR += r;
   }
   else
      g_stLossR += r;
   g_stWorstR = MathMin(g_stWorstR, r);

   if(reason == DEAL_REASON_SL)
   {
      g_stSL++;
      g_stSLR += r;
   }
   else if(reason == DEAL_REASON_TP)
   {
      g_stTP++;
      g_stTPR += r;
   }
   else
   {
      g_stOther++;
      g_stOtherR += r;
   }

   Log(StringFormat("CLOSE pos %s | %+.2fR", IntegerToString((long)posId), r));
}

double OnTester()
{
   double trades = TesterStatistics(STAT_TRADES);
   if(trades < InpOptMinTrades)
      return 0.0;
   return TesterStatistics(STAT_PROFIT_FACTOR);
}


// ============================================================================
// PANEL
// ============================================================================

void UpdatePanel()
{
   if(!InpShowPanel || g_silent || g_noChart)
      return;

   datetime nowNY = ToNY(TimeCurrent());
   string s = "CRT 1AM EA v1.02  |  " + _Symbol + "  |  " + (InpTradeEnabled ? "TRADING ON" : "SIGNALS ONLY") +
              "  |  New York time " + NYText(nowNY) + "  (server - " + IntegerToString(InpNYOffset) + "h)";
   s += "\nDaily CRT bias: " + D1Text() + "  |  last skip: " + g_lastSkip;
   s += "\n" + FunnelText() + "\nRejected: " + RejectText();

   for(int m = 0; m < MODELS; m++)
   {
      if(!g_mOn[m])
         continue;
      s += StringFormat("\n\n[%s]  key time %02d:%02d-%02d:%02d  |  %s",
                        g_mName[m], g_mFrom[m] / 100, g_mFrom[m] % 100, g_mTo[m] / 100, g_mTo[m] % 100,
                        g_md[m].key > 0 ? NYText(g_md[m].key) + ": " + g_md[m].status : "waiting for the candle");
      if(g_md[m].ok)
         s += "\nrange " + PriceText(g_md[m].rngLow) + " - " + PriceText(g_md[m].rngHigh) +
              "   open " + PriceText(g_md[m].crtOpen) + "   prev-day mid " + PriceText(g_md[m].pdMid) +
              "   bias " + (g_md[m].allowDir == 1 ? "BUY" : g_md[m].allowDir == 2 ? "SELL" :
                            g_md[m].allowDir == 3 ? "BOTH" : "NONE");
   }
   Comment(s);
}


// ============================================================================
// EVENT HANDLERS
// ============================================================================

bool ValidHHMM(int v) { return v >= 0 && v <= 2359 && v % 100 < 60; }

int OnInit()
{
   if(InpNYOffset < -12 || InpNYOffset > 14 || InpRiskPercent <= 0.0 || InpRiskPercent > 10.0 ||
      !ValidHHMM(InpKT1From) || !ValidHHMM(InpKT1To) || !ValidHHMM(InpKT5From) || !ValidHHMM(InpKT5To) ||
      !ValidHHMM(InpKT9From) || !ValidHHMM(InpKT9To) || !ValidHHMM(InpExitHHMM))
   {
      Print("Invalid inputs");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpEntryTF != PERIOD_M5 && InpEntryTF != PERIOD_M15 && InpEntryTF != PERIOD_M30)
   {
      Print("Entry timeframe must be M5, M15 or M30");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpBias == BIAS_TREND && (InpTrendDays < 2 || InpTrendDays > 250))
   {
      Print("Trend days must be 2-250");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(!InpModel1AM && !InpModel5AM && !InpModel9AM)
   {
      Print("Enable at least one model");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_tf    = InpEntryTF;
   g_tfSec = PeriodSeconds(g_tf);

   g_mOn[0] = InpModel1AM;  g_mFrom[0] = InpKT1From;  g_mTo[0] = InpKT1To;
   g_mOn[1] = InpModel5AM;  g_mFrom[1] = InpKT5From;  g_mTo[1] = InpKT5To;
   g_mOn[2] = InpModel9AM;  g_mFrom[2] = InpKT9From;  g_mTo[2] = InpKT9To;
   for(int m = 0; m < MODELS; m++)
      ResetModelDay(m, 0);
   ArrayInitialize(g_rej, 0);
   g_fCandles = g_fNoData = g_fNoBias = g_fHighSweeps = g_fLowSweeps = g_fBreaks = g_fTrades = 0;

   g_silent  = (bool)MQLInfoInteger(MQL_OPTIMIZATION);
   g_noChart = (bool)MQLInfoInteger(MQL_TESTER) && !(bool)MQLInfoInteger(MQL_VISUAL_MODE);

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints((ulong)InpSlippagePts);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   g_d1.hasParent   = false;
   g_d1.state       = 0;
   g_d1.lastBarTime = 0;
   ArrayResize(g_risk, 0);

   if(!g_silent && !g_noChart)
      ObjectsDeleteAll(0, OBJ_PFX);

   Log(StringFormat("CRT 1AM EA v1.02 | entry %s | models %s%s%s | NY offset %d | bias %s (%d days) | prem/disc %s | OHLC %s | TP %s | exit %04d NY",
                    EnumToString(g_tf), InpModel1AM ? "1AM " : "", InpModel5AM ? "5AM " : "", InpModel9AM ? "9AM " : "",
                    InpNYOffset, EnumToString(InpBias), InpTrendDays, EnumToString(InpPremDisc), InpOHLC ? "on" : "off",
                    InpTPMode == TP_RR ? StringFormat("1:%.1f", InpRR) : "range side", InpExitHHMM));

   if(!MQLInfoInteger(MQL_TESTER))
      Log("Server time " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES) + " = New York " +
          NYText(ToNY(TimeCurrent())) + ". If New York time is wrong, change InpNYOffset.");

   g_ready = D1Update();
   g_lastBar = iTime(_Symbol, g_tf, 0);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   PrintTradeSummary();
   Comment("");
   if(!MQLInfoInteger(MQL_TESTER))
      ObjectsDeleteAll(0, OBJ_PFX);
}

void OnTick()
{
   if(!g_ready)
   {
      g_ready = D1Update();
      if(!g_ready)
         return;
   }

   CloseAtExitTime();

   // Everything else runs once per closed entry-TF bar.
   datetime barOpen = iTime(_Symbol, g_tf, 0);
   if(barOpen <= 0 || barOpen == g_lastBar)
      return;
   if(g_lastBar == 0)
   {
      g_lastBar = barOpen;
      return;
   }

   MqlRates bars[];
   int n = CopyRates(_Symbol, g_tf, g_lastBar, barOpen - 1, bars);
   g_lastBar = barOpen;
   if(n <= 0)
      return;

   D1Update();

   for(int i = 0; i < n; i++)
      for(int m = 0; m < MODELS; m++)
         if(g_mOn[m])
            ModelStep(m, bars[i], i == n - 1);

   UpdatePanel();
}
//+------------------------------------------------------------------+
