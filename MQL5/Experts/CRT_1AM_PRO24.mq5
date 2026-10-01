//+------------------------------------------------------------------+
//|                                                CRT_1AM_PRO24.mq5 |
//|      24-hour CRT: setups in every New York H4 candle, no clock   |
//+------------------------------------------------------------------+
//
// The 24-hour sibling of CRT_1AM_EA. Same setup, but no fixed hours:
//
//   - every H4 candle of the day (1AM, 5AM, 9AM, 1PM, 5PM, 9PM New York)
//     is a CRT candle; the range is the candle(s) before it (Asia range
//     for the 1AM candle)
//   - the candle sweeps the range high or low; when a later M15 candle
//     closes through the candle that made the sweep (order block) and
//     back inside the range, the EA waits up to 4 hours for price to come
//     back to the order-block level (retest) and enters there; a new
//     sweep extreme first cancels the setup (v1.02; market entry at the
//     break is still an option)
//   - v1.03, more entries: one position per H4 candle (each candle has
//     its own magic number, so a 5AM trade can open while the 1AM trade
//     is still running), a new setup in the same candle after a trade
//     closes, and optionally the PDF Selective model (key times, M30,
//     market entry) as a second strategy with magic +10
//   - daily trend bias (previous close vs its 50-day average) and
//     premium / discount of the range
//   - SL beyond the sweep, TP 1:2, trade closed after 8 hours if still open
//   - Friday close (weekend gap protection) can be switched off
//   - journal: every closed trade is written to Common/Files/
//     CRT_PRO24_journal.csv with its context, how far it went for and
//     against (in R) and a short description of the win or loss
//
// Tested on FP Trading XAUUSD 2023.01-2026.09 (simulation, 0.5% risk):
//   v1.03 defaults (per candle + re-entry + Selective): ~1120 trades,
//   PF 1.32, +161%, max DD 8.6%, up to 3 positions open at once
//   v1.02 (one position, retest): 922 trades, PF 1.29, +107%, max DD 9.8%
//   v1.01 (one position, market): 1226 trades, PF 1.17, +71%, max DD 11.1%
//+------------------------------------------------------------------+
#property copyright "Marko"
#property version   "1.03"
#property description "CRT PRO24: the CRT_1AM_EA setup in every H4 candle, 24 hours, no fixed hours."

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
   REJ_STALE,
   REJ_FRIDAY,
   REJ_NEWS
};
#define REJECTS 16   // number of ENUM_REJECT values

enum ENUM_CRT_ENTRY
{
   ENTRY_MARKET = 0, // Market order at the order-block break
   ENTRY_RETEST = 1  // Limit at the order-block level (retest)
};

enum ENUM_CRT_TP
{
   TP_RR    = 0, // Fixed reward:risk (1:2 / 1:3)
   TP_RANGE = 1  // Other side of the time-based range (short-term DOL)
};


// ============================================================================
// INPUTS
// ============================================================================

input group "1. SETUP (New York time)"
input bool InpTradeEnabled = true;  // Place trades (false = signals only)
input int  InpNYOffset     = 7;     // Server time minus New York time (hours)
input ENUM_TIMEFRAMES InpEntryTF = PERIOD_M15; // Entry / order-block timeframe (M5, M15, M30)
input bool InpPerCandle    = true;  // One position per H4 candle (more entries, several trades open)
input bool InpReentry      = true;  // New setup in the same candle after a trade closes
input bool InpAddSelective = true;  // Also trade the PDF Selective model (key times, M30, magic +10)

input group "2. BIAS / PREMIUM-DISCOUNT"
input ENUM_CRT_BIAS InpBias     = BIAS_TREND;      // Higher-timeframe bias
input int           InpTrendDays = 50;             // Days in the trend average (bias = daily trend)
input ENUM_CRT_PD   InpPremDisc = PD_RANGE;        // Premium/discount (sell above / buy below the middle)

input ENUM_CRT_ENTRY InpEntryType  = ENTRY_RETEST; // Entry
input int            InpRetestHours = 4;            // Retest: how long to wait for price to come back (hours)

input group "3. RISK / EXIT"
input double InpRiskPercent  = 0.5;    // Risk per trade (% of balance)
input double InpMaxLots      = 5.0;    // Max lots per trade (safety cap)
input ENUM_CRT_TP InpTPMode   = TP_RR;  // Take profit
input double InpRR           = 2.0;    // Reward:risk (TP = fixed RR)
input double InpMinRR        = 1.5;    // Min reward:risk (TP = range side)
input double InpSLBuffer     = 0.30;   // SL buffer beyond the sweep (price units, XAUUSD = $)
input int    InpMaxHoldHours = 8;      // Close a trade after this many hours (0 = off)
input int    InpMaxTradesDay = 5;      // Max trades per day (one position at a time)
input int    InpFridayClose  = 1600;   // Friday: close trades at (HHMM NY), no new trades 4h before (0 = off)
input ulong  InpMagic        = 770100; // Magic number (different from CRT_1AM_EA)

input group "4. COST FILTERS"
input double InpMinSL        = 1.00;   // Min SL distance (price units, 0 = off)
input double InpMinSLSpreadX = 4.0;    // Min SL distance as a multiple of the spread (0 = off)
input double InpMaxSpread    = 0.50;   // Max spread (price units, 0 = off)
input int    InpSlippagePts  = 30;     // Max slippage (points)

input group "5. DISPLAY"
input bool InpShowPanel = true;  // Show status panel
input bool InpDraw      = true;  // Draw ranges, sweeps and entries
input bool InpVerbose   = true;  // Print setups to the journal
input bool InpJournal   = true;  // Write every trade with a description to Common\Files\CRT_PRO24_journal.csv

input group "6. OPTIMIZATION"
input int  InpOptMinTrades = 30; // Min trades for the "Custom max" score


// ============================================================================
// STRUCTS / GLOBALS
// ============================================================================

#define MODELS  6
#define OBJ_PFX "CRT24_"

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
   double   prevClose;   // previous daily close
   double   trendAvg;    // its N-day average (trend)
   double   atr;         // average daily range of the last 14 days
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

#define SLOTS 2

// One strategy configuration (Active, Selective or Custom) with its own
// magic number, entry timeframe, candles, exits and positions.
struct Slot
{
   bool            on;
   string          name;
   ulong           magic;
   ENUM_TIMEFRAMES tf;
   int             tfSec;
   bool            ohlc;
   int             exitHHMM;
   int             maxHoldSec;
   int             maxDay;
   bool            newsPause;    // not used in PRO24
   bool            retest;       // retest limit entry (else market at the break)
   bool            perCandle;    // own magic (base + candle) and position per H4 candle
   bool            reentry;      // keep watching the candle after a trade
   datetime        lastBar;      // open time of the entry-TF bar being formed
   bool            mOn[MODELS];
   int             mFrom[MODELS];
   int             mTo[MODELS];
   int             trades;       // closed trades and their R, for the summary
   double          totalR;
};

CTrade    g_trade;
Slot      g_slot[SLOTS];
ModelDay  g_md[SLOTS][MODELS];
D1Engine  g_d1;
TradeRisk g_risk[];

int       g_mHour[MODELS]   = {1, 5, 9, 13, 17, 21};   // CRT candle start (NY hour)
int       g_mRange[MODELS]  = {2, 1, 1, 1, 1, 1};      // H4 candles in the time-based range
string    g_mName[MODELS]   = {"1AM", "5AM", "9AM", "1PM", "5PM", "9PM"};

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
                                "lot size", "order failed", "stale", "Friday", "news hours"};
long      g_objSeq    = 0;

int       g_stN = 0, g_stWin = 0, g_stSL = 0, g_stTP = 0, g_stOther = 0;
double    g_stWinR = 0.0, g_stLossR = 0.0, g_stWorstR = 0.0;
double    g_stSLR = 0.0, g_stTPR = 0.0, g_stOtherR = 0.0;

void   SetPlannedRisk(ulong posId, double riskMoney);
bool   TryEnter(int s, int m, int dir, datetime sigNY, double extreme);

// Retest: one waiting limit (virtual: the EA sends a market order when
// price touches the level).
struct Pending
{
   bool     on;
   int      s;
   int      m;
   int      dir;
   double   level;     // order-block level to come back to
   double   extreme;   // sweep extreme (SL side); beyond it the setup is gone
   datetime sigNY;
   datetime expires;  // server time
};
Pending g_pend[SLOTS][MODELS];
int     g_rtPlaced = 0, g_rtFilled = 0, g_rtExpired = 0, g_rtInvalid = 0;
void   JournalOpen(ulong posId, int s, int m, int dir, double entry, double sl, double tp, double extreme, double spread);
string SlotTitle(int s);


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

// Slot that owns a magic number, -1 if none.
int SlotOf(ulong magic)
{
   for(int s = 0; s < SLOTS; s++)
   {
      if(!g_slot[s].on)
         continue;
      if(g_slot[s].perCandle ? (magic >= g_slot[s].magic && magic < g_slot[s].magic + MODELS) : magic == g_slot[s].magic)
         return s;
   }
   return -1;
}

// Magic number of a slot's candle model.
ulong MagicOf(int s, int m) { return g_slot[s].perCandle ? g_slot[s].magic + (ulong)m : g_slot[s].magic; }

bool HasOpenPosition(ulong magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == magic)
         return true;
   }
   return false;
}

// Trades opened since the start of the current New York day.
int TradesToday(ulong magic)
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
      if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != magic)
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

void ResetModelDay(int s, int m, datetime key)
{
   g_md[s][m].key        = key;
   g_md[s][m].ok         = false;
   g_md[s][m].done       = false;
   g_md[s][m].allowDir   = 0;
   g_md[s][m].rngHigh    = 0.0;
   g_md[s][m].rngLow     = 0.0;
   g_md[s][m].crtOpen    = 0.0;
   g_md[s][m].pdMid      = 0.0;
   g_md[s][m].sweptHigh  = false;
   g_md[s][m].sweepHigh  = 0.0;
   g_md[s][m].obSellLow  = 0.0;
   g_md[s][m].obSellTime = 0;
   g_md[s][m].sweptLow   = false;
   g_md[s][m].sweepLow   = 0.0;
   g_md[s][m].obBuyHigh  = 0.0;
   g_md[s][m].obBuyTime  = 0;
   g_md[s][m].prevClose  = 0.0;
   g_md[s][m].trendAvg   = 0.0;
   g_md[s][m].atr        = 0.0;
   g_md[s][m].status     = "waiting";
}

// First entry-TF bar of a CRT candle: build the time-based range, read the
// candle's open, the previous day's range and the higher-timeframe bias.
void InitModelDay(int s, int m, datetime crtNY)
{
   ResetModelDay(s, m, crtNY);
   g_fCandles++;

   datetime crtSrv   = ToServer(crtNY);
   datetime rngStart = crtSrv - g_mRange[m] * 4 * 3600;

   MqlRates rr[];
   int n = CopyRates(_Symbol, g_slot[s].tf, rngStart, crtSrv - 1, rr);
   if(n < 2)
   {
      g_md[s][m].status = "no range data";
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
   if(CopyRates(_Symbol, g_slot[s].tf, crtSrv, crtSrv + 4 * 3600 - 1, oc) <= 0)   // 5PM opens after the daily break
   {
      g_md[s][m].status = "no open";
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
      g_md[s][m].status = "no daily data";
      g_fNoData++;
      return;
   }

   g_md[s][m].rngHigh = hi;
   g_md[s][m].rngLow  = lo;
   g_md[s][m].crtOpen = oc[0].open;
   MqlRates prev = dd[k - 2];
   g_md[s][m].pdMid   = InpPremDisc == PD_PREV_DAY ? (prev.high + prev.low) / 2.0 : (hi + lo) / 2.0;

   double closeSum = 0.0, rangeSum = 0.0;
   int    rangeN   = 0;
   for(int j = 0; j < k - 1; j++)
   {
      closeSum += dd[j].close;
      if(j >= k - 15)
      {
         rangeSum += dd[j].high - dd[j].low;
         rangeN++;
      }
   }
   g_md[s][m].prevClose = prev.close;
   g_md[s][m].trendAvg  = closeSum / (k - 1);
   g_md[s][m].atr       = rangeN > 0 ? rangeSum / rangeN : 0.0;

   int prevDir = prev.close > prev.open ? 1 : prev.close < prev.open ? 2 : 0;
   if(InpBias == BIAS_NONE)
      g_md[s][m].allowDir = 3;
   else if(InpBias == BIAS_D1_CRT)
      g_md[s][m].allowDir = g_d1.state;                 // 0 none, 1 buy, 2 sell
   else if(InpBias == BIAS_PREV_DAY)
      g_md[s][m].allowDir = prevDir;
   else if(InpBias == BIAS_D1_OR_PREV)
      g_md[s][m].allowDir = g_d1.state != 0 ? g_d1.state : prevDir;
   else
   {
      double sum = 0.0;
      for(int j = 0; j < k - 1; j++)
         sum += dd[j].close;
      double avg = sum / (k - 1);
      g_md[s][m].allowDir = prev.close > avg ? 1 : prev.close < avg ? 2 : 0;
   }

   g_md[s][m].ok     = true;
   g_md[s][m].status = g_md[s][m].allowDir == 0 ? "no bias today" : "watching sweep";
   if(g_md[s][m].allowDir == 0)
      g_fNoBias++;

   DrawBox(rngStart, crtSrv, lo, hi, clrDarkSlateGray);
   DrawLevel(crtSrv, crtSrv + 4 * 3600, g_md[s][m].crtOpen, clrGold, STYLE_DOT);
   DrawLevel(crtSrv, crtSrv + 4 * 3600, hi, clrTomato, STYLE_SOLID);
   DrawLevel(crtSrv, crtSrv + 4 * 3600, lo, clrMediumSeaGreen, STYLE_SOLID);

   if(InpVerbose)
      Log(StringFormat("[%s%s] %s range %s - %s | open %s | prev-day mid %s | bias %s",
                       g_slot[s].name, g_mName[m], NYText(crtNY), PriceText(lo), PriceText(hi),
                       PriceText(g_md[s][m].crtOpen), PriceText(g_md[s][m].pdMid),
                       g_md[s][m].allowDir == 1 ? "BUY" : g_md[s][m].allowDir == 2 ? "SELL" :
                       g_md[s][m].allowDir == 3 ? "BOTH" : "NONE"));
}

// Friday (New York) and at or after hhmm.
bool FridayAfter(datetime ny, int hhmm)
{
   MqlDateTime d;
   TimeToStruct(ny, d);
   return d.day_of_week == 5 && MinuteOfDay(ny) >= HHMMToMin(hhmm);
}

bool InKeyTime(int s, int m, datetime ny)
{
   if(g_slot[s].mFrom[m] < 0)
      return true;          // any time inside the candle
   int t = MinuteOfDay(ny);
   return t >= HHMMToMin(g_slot[s].mFrom[m]) && t < HHMMToMin(g_slot[s].mTo[m]);
}

// Checks the filters and sends the order. dir 1 = buy, 2 = sell.
bool TryEnter(int s, int m, int dir, datetime sigNY, double extreme)
{
   string tag = g_slot[s].name + g_mName[m] + (dir == 1 ? " BUY" : " SELL");

   if(!InpTradeEnabled)
   {
      Skip(REJ_SIGNALS_ONLY, tag + ": signals only");
      return false;
   }
   if(!InKeyTime(s, m, sigNY))
   {
      Skip(REJ_KEY_TIME, tag + ": outside key time " + NYText(sigNY));
      return false;
   }
   if((g_md[s][m].allowDir & dir) == 0)
   {
      Skip(REJ_BIAS, tag + ": against HTF bias");
      return false;
   }
   if(HasOpenPosition(MagicOf(s, m)))
   {
      Skip(REJ_POSITION, tag + ": position already open");
      return false;
   }
   if(InpFridayClose > 0 && FridayAfter(ToNY(TimeCurrent()), MathMax(0, InpFridayClose - 400)))
   {
      Skip(REJ_FRIDAY, tag + ": too close to the Friday close");
      return false;
   }
   if(g_slot[s].maxDay > 0 && TradesToday(MagicOf(s, m)) >= g_slot[s].maxDay)
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
   if(g_slot[s].ohlc && ((dir == 2 && bid < g_md[s][m].crtOpen) || (dir == 1 && ask > g_md[s][m].crtOpen)))
   {
      Skip(REJ_OHLC, tag + ": wrong side of the CRT open");
      return false;
   }
   // Premium / discount: sell above / buy below the middle of the range (or previous day).
   if(InpPremDisc != PD_OFF && ((dir == 2 && bid < g_md[s][m].pdMid) || (dir == 1 && ask > g_md[s][m].pdMid)))
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
      tp = dir == 1 ? g_md[s][m].rngHigh : g_md[s][m].rngLow;
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

   string cmt = "CRT24 " + g_mName[m];
   g_trade.SetExpertMagicNumber(MagicOf(s, m));
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
   JournalOpen(g_trade.ResultOrder(), s, m, dir, fill, sl, tp, extreme, spread);

   g_lastSkip = "-";
   g_fTrades++;
   Log(StringFormat("%s %s lots | entry %s  SL %s  TP %s | range %s-%s | %s",
                    tag, DoubleToString(lots, 2), PriceText(entry), PriceText(sl), PriceText(tp),
                    PriceText(g_md[s][m].rngLow), PriceText(g_md[s][m].rngHigh), NYText(sigNY)));
   DrawLabel(TimeCurrent(), entry, tag, dir == 1 ? clrAqua : clrMagenta, dir == 2);
   return true;
}

bool AnyPending(int s)
{
   for(int m = 0; m < MODELS; m++)
      if(g_pend[s][m].on)
         return true;
   return false;
}

// Fill, cancel or expire one waiting retest.
void PendingOne(int s, int m)
{
   if(!g_pend[s][m].on)
      return;
   if(g_md[s][m].done || HasOpenPosition(MagicOf(s, m)))
   {
      g_pend[s][m].on = false;
      return;
   }
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(TimeCurrent() > g_pend[s][m].expires)
   {
      g_pend[s][m].on = false;
      g_rtExpired++;
      g_md[s][m].status = "retest expired";
      return;
   }
   if((g_pend[s][m].dir == 2 && ask > g_pend[s][m].extreme) || (g_pend[s][m].dir == 1 && bid < g_pend[s][m].extreme))
   {
      g_pend[s][m].on = false;
      g_rtInvalid++;
      g_md[s][m].status = "retest cancelled: new sweep extreme";
      return;
   }
   bool touched = g_pend[s][m].dir == 2 ? bid >= g_pend[s][m].level : ask <= g_pend[s][m].level;
   if(!touched)
      return;
   g_pend[s][m].on = false;
   if(TryEnter(s, m, g_pend[s][m].dir, g_pend[s][m].sigNY, g_pend[s][m].extreme))
   {
      g_rtFilled++;
      g_md[s][m].done   = !g_slot[s].reentry;
      g_md[s][m].status = "traded (retest)";
   }
}

// Every tick: all waiting retests.
void PendingCheck()
{
   for(int s = 0; s < SLOTS; s++)
      for(int m = 0; m < MODELS; m++)
         PendingOne(s, m);
}

// One closed entry-TF bar through the model.
void ModelStep(int s, int m, const MqlRates &b, bool latest)
{
   datetime ny   = ToNY(b.time);
   long     into = ((long)ny - g_mHour[m] * 3600) % 86400;   // time since the candle start
   if(into < 0)
      into += 86400;
   if(into >= 4 * 3600)
      return;   // only inside the CRT candle
   datetime crtNY = (datetime)((long)ny - into);

   if(g_md[s][m].key != crtNY)
      InitModelDay(s, m, crtNY);
   if(!g_md[s][m].ok || g_md[s][m].done || g_md[s][m].allowDir == 0)
      return;

   // ------------------------------------------------------------------
   // Model #1: a later candle closes through the order block (the candle
   // that dug above the high / below the low) and back inside the range.
   // Checked before the sweep update, so an engulfing candle that also
   // makes a new extreme still counts; its extreme goes into the SL.
   // ------------------------------------------------------------------
   bool sellSig = g_md[s][m].sweptHigh && b.time > g_md[s][m].obSellTime &&
                  b.close < g_md[s][m].obSellLow && b.close < g_md[s][m].rngHigh;
   bool buySig  = g_md[s][m].sweptLow && b.time > g_md[s][m].obBuyTime &&
                  b.close > g_md[s][m].obBuyHigh && b.close > g_md[s][m].rngLow;

   datetime sigNY = ny + g_slot[s].tfSec;   // the signal is known at the bar close
   for(int k = 0; k < 2; k++)
   {
      int  dir = k == 0 ? 2 : 1;
      bool sig = k == 0 ? sellSig : buySig;
      if(!sig)
         continue;

      g_fBreaks++;
      if(InpVerbose)
         Log(StringFormat("[%s%s] %s OB break at %s", g_slot[s].name, g_mName[m], dir == 2 ? "SELL" : "BUY", NYText(sigNY)));

      double extreme = dir == 2 ? MathMax(g_md[s][m].sweepHigh, b.high) : MathMin(g_md[s][m].sweepLow, b.low);
      bool entered = false;
      if(!latest)
         Skip(REJ_STALE, g_slot[s].name + g_mName[m] + ": stale signal");
      else if(g_slot[s].retest)
      {
         // Wait for price to come back to the broken order-block level.
         bool busy = g_pend[s][m].on || HasOpenPosition(MagicOf(s, m)) || (!g_slot[s].perCandle && AnyPending(s));
         if(!busy)
         {
            g_pend[s][m].on      = true;
            g_pend[s][m].s       = s;
            g_pend[s][m].m       = m;
            g_pend[s][m].dir     = dir;
            g_pend[s][m].level   = dir == 2 ? g_md[s][m].obSellLow : g_md[s][m].obBuyHigh;
            g_pend[s][m].extreme = extreme;
            g_pend[s][m].sigNY   = sigNY;
            g_pend[s][m].expires = TimeCurrent() + InpRetestHours * 3600;
            g_rtPlaced++;
            g_md[s][m].status = StringFormat("waiting for retest of %s", PriceText(g_pend[s][m].level));
            Log(StringFormat("[%s] %s retest limit %s (SL side %s), valid %dh", g_mName[m], dir == 2 ? "SELL" : "BUY",
                             PriceText(g_pend[s][m].level), PriceText(extreme), InpRetestHours));
         }
      }
      else
         entered = TryEnter(s, m, dir, sigNY, extreme);

      // This order block is used up either way; a new sweep extreme makes a new one.
      if(dir == 2)
         g_md[s][m].obSellTime = D'3000.01.01';
      else
         g_md[s][m].obBuyTime = D'3000.01.01';

      if(entered)
      {
         g_md[s][m].done   = !g_slot[s].reentry;
         g_md[s][m].status = "traded";
         return;
      }
   }

   // ------------------------------------------------------------------
   // Sweep of the range high: the candle with the highest high is the
   // sell order block. Mirror image for the low.
   // ------------------------------------------------------------------
   if(b.high > g_md[s][m].rngHigh && (!g_md[s][m].sweptHigh || b.high > g_md[s][m].sweepHigh))
   {
      if(!g_md[s][m].sweptHigh)
      {
         g_fHighSweeps++;
         DrawLabel(b.time, b.high, g_slot[s].name + g_mName[m] + " sweep", clrOrange, true);
      }
      g_md[s][m].sweptHigh  = true;
      g_md[s][m].sweepHigh  = b.high;
      g_md[s][m].obSellLow  = b.low;
      g_md[s][m].obSellTime = b.time;
      g_md[s][m].status     = "high swept, waiting for OB break";
   }
   if(b.low < g_md[s][m].rngLow && (!g_md[s][m].sweptLow || b.low < g_md[s][m].sweepLow))
   {
      if(!g_md[s][m].sweptLow)
      {
         g_fLowSweeps++;
         DrawLabel(b.time, b.low, g_slot[s].name + g_mName[m] + " sweep", clrOrange, false);
      }
      g_md[s][m].sweptLow  = true;
      g_md[s][m].sweepLow  = b.low;
      g_md[s][m].obBuyHigh = b.high;
      g_md[s][m].obBuyTime = b.time;
      g_md[s][m].status    = "low swept, waiting for OB break";
   }
}

// Closes positions opened before the latest daily exit time of their slot
// (New York), held longer than the slot's max hold time, or on Friday.
void CloseAtExitTime()
{
   datetime now    = TimeCurrent();
   datetime nowNY  = ToNY(now);
   bool     friday = InpFridayClose > 0 && FridayAfter(nowNY, InpFridayClose);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      int s = SlotOf((ulong)PositionGetInteger(POSITION_MAGIC));
      if(s < 0)
         continue;

      datetime opened  = (datetime)PositionGetInteger(POSITION_TIME);
      bool     byClock = false;
      if(g_slot[s].exitHHMM > 0)
      {
         datetime exitNY = DayStart(nowNY) + HHMMToMin(g_slot[s].exitHHMM) * 60;
         if(nowNY < exitNY)
            exitNY -= 86400;
         byClock = ToNY(opened) < exitNY;
      }
      bool byHold = g_slot[s].maxHoldSec > 0 && now - opened >= g_slot[s].maxHoldSec;
      if(!byClock && !byHold && !friday)
         continue;
      g_trade.SetExpertMagicNumber((ulong)PositionGetInteger(POSITION_MAGIC));
      if(g_trade.PositionClose(ticket))
         Log(g_slot[s].name + (friday ? "CLOSE: Friday close " : byHold ? "CLOSE: max hold time " : "CLOSE: exit time ") + NYText(nowNY));
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
   Print("CRT PRO24 FUNNEL: " + FunnelText());
   Print("CRT PRO24 REJECTED: " + RejectText());
   if(g_slot[0].retest)
      Print(StringFormat("CRT PRO24 RETEST: placed %d | filled %d | expired %d | cancelled (new extreme) %d",
                         g_rtPlaced, g_rtFilled, g_rtExpired, g_rtInvalid));
   if(g_stN == 0)
   {
      Print("CRT PRO24 SUMMARY: no closed trades");
      return;
   }
   int losses = g_stN - g_stWin;
   Print(StringFormat("CRT PRO24 SUMMARY: %d trades | win %.1f%% | avg win %+.2fR | avg loss %+.2fR | worst %+.2fR | total %+.1fR",
                      g_stN, 100.0 * g_stWin / g_stN,
                      g_stWin > 0 ? g_stWinR / g_stWin : 0.0,
                      losses > 0 ? g_stLossR / losses : 0.0,
                      g_stWorstR, g_stWinR + g_stLossR));
   string bySlot = "";
   for(int s = 0; s < SLOTS; s++)
      if(g_slot[s].on)
         bySlot += StringFormat("%s%s %d trades %+.1fR", bySlot == "" ? "" : " | ", SlotTitle(s), g_slot[s].trades, g_slot[s].totalR);
   Print("CRT PRO24 SUMMARY by mode: " + bySlot);
   Print(StringFormat("CRT PRO24 SUMMARY by exit: SL %d x %+.2fR | TP %d x %+.2fR | time/EA close %d x %+.2fR",
                      g_stSL, g_stSL > 0 ? g_stSLR / g_stSL : 0.0,
                      g_stTP, g_stTP > 0 ? g_stTPR / g_stTP : 0.0,
                      g_stOther, g_stOther > 0 ? g_stOtherR / g_stOther : 0.0));
}

// ============================================================================
// TRADE JOURNAL (CSV with a description of every trade)
// ============================================================================

#define JOURNAL_FILE "CRT_PRO24_journal.csv"

struct JournalRec
{
   ulong    posId;
   datetime tIn;
   int      model;
   int      dir;
   double   entry;
   double   sl;
   double   tp;
   double   risk;
   double   rngLow;
   double   rngHigh;
   double   extreme;
   double   trendPct;
   double   atr;
   double   spread;
   double   mfe;      // best excursion so far (R)
   double   mae;      // worst excursion so far (R)
};

JournalRec g_jr[];
int        g_jFile  = INVALID_HANDLE;
int        g_jCount = 0;
string     g_dayName[7] = {"e diel", "e hene", "e marte", "e merkure", "e enjte", "e premte", "e shtune"};

string F2(double v) { return DoubleToString(v, 2); }

// Tester: a new file per run. Live / demo: append to the existing file.
void JournalStart()
{
   if(!InpJournal || g_silent)
      return;
   bool tester = (bool)MQLInfoInteger(MQL_TESTER);
   int  flags  = FILE_CSV | FILE_ANSI | FILE_COMMON | FILE_WRITE;
   if(!tester)
      flags |= FILE_READ | FILE_SHARE_READ;
   g_jFile = FileOpen(JOURNAL_FILE, flags, ',');
   if(g_jFile == INVALID_HANDLE)
   {
      Print("Journal: cannot open ", JOURNAL_FILE, ", error ", GetLastError());
      return;
   }
   FileSeek(g_jFile, 0, SEEK_END);
   if(FileSize(g_jFile) == 0)
      FileWrite(g_jFile, "nr", "hyrja (server)", "hyrja (NY)", "dita", "qiriri H4", "drejtimi", "entry", "SL", "TP",
                "SL $", "rezultati R", "dalja", "minuta", "max ne favor R", "max kunder R", "range low", "range high",
                "sweep", "sweep pertej range $", "hyrja ne range %", "trendi % nga mesatarja", "SL / ATR ditore",
                "spread", "lloji", "pershkrimi");
}

void JournalStop()
{
   if(g_jFile == INVALID_HANDLE)
      return;
   FileClose(g_jFile);
   g_jFile = INVALID_HANDLE;
   Print("CRT PRO24 JOURNAL: ", g_jCount, " trades -> ",
         TerminalInfoString(TERMINAL_COMMONDATA_PATH), "\\Files\\", JOURNAL_FILE);
}

void JournalOpen(ulong posId, int s, int m, int dir, double entry, double sl, double tp, double extreme, double spread)
{
   if(g_jFile == INVALID_HANDLE)
      return;
   int n = ArraySize(g_jr);
   ArrayResize(g_jr, n + 1, 16);
   g_jr[n].posId    = posId;
   g_jr[n].tIn      = TimeCurrent();
   g_jr[n].model    = m;
   g_jr[n].dir      = dir;
   g_jr[n].entry    = entry;
   g_jr[n].sl       = sl;
   g_jr[n].tp       = tp;
   g_jr[n].risk     = MathAbs(entry - sl);
   g_jr[n].rngLow   = g_md[s][m].rngLow;
   g_jr[n].rngHigh  = g_md[s][m].rngHigh;
   g_jr[n].extreme  = extreme;
   g_jr[n].trendPct = g_md[s][m].trendAvg > 0.0 ?
                      (g_md[s][m].prevClose - g_md[s][m].trendAvg) / g_md[s][m].trendAvg * 100.0 : 0.0;
   g_jr[n].atr      = g_md[s][m].atr;
   g_jr[n].spread   = spread;
   g_jr[n].mfe      = 0.0;
   g_jr[n].mae      = 0.0;
}

// Best and worst excursion of the open trades, every tick.
void JournalTrack()
{
   int n = ArraySize(g_jr);
   if(n == 0)
      return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   for(int i = 0; i < n; i++)
   {
      if(g_jr[i].risk <= 0.0)
         continue;
      double x = g_jr[i].dir == 1 ? (bid - g_jr[i].entry) / g_jr[i].risk : (g_jr[i].entry - ask) / g_jr[i].risk;
      g_jr[i].mfe = MathMax(g_jr[i].mfe, x);
      g_jr[i].mae = MathMin(g_jr[i].mae, x);
   }
}

string LossText(string kind)
{
   if(kind == "L1") return "kthim i menjehershem: cmimi shkoi kunder menjehere (sweep-i vazhdoi)";
   if(kind == "L2") return "pa drejtim: nuk shkoi kurre ne favor";
   if(kind == "L3") return "levizje e vogel ne favor (+0.3R deri +1R) pastaj SL";
   if(kind == "L4") return "fitim i humbur: arriti te pakten +1R pastaj u kthye ne SL";
   if(kind == "L5") return "mbyllje me kohe ne humbje (8 ore ose e premte)";
   if(kind == "W1") return "fitim: preku TP";
   return "mbyllje me kohe ne fitim";
}

void JournalClose(ulong posId, double r, long reason)
{
   int i = -1;
   for(int k = ArraySize(g_jr) - 1; k >= 0; k--)
      if(g_jr[k].posId == posId)
      {
         i = k;
         break;
      }
   if(i < 0)
      return;
   JournalRec j = g_jr[i];
   int n = ArraySize(g_jr);
   for(int k = i; k < n - 1; k++)
      g_jr[k] = g_jr[k + 1];
   ArrayResize(g_jr, n - 1);
   if(g_jFile == INVALID_HANDLE)
      return;

   datetime tOut    = TimeCurrent();
   double   minutes = (double)(tOut - j.tIn) / 60.0;
   string   kind;
   if(reason == DEAL_REASON_TP)
      kind = "W1";
   else if(reason == DEAL_REASON_SL)
      kind = j.mfe >= 1.0 ? "L4" : j.mfe >= 0.3 ? "L3" : minutes <= 60.0 ? "L1" : "L2";
   else
      kind = r > 0.0 ? "W2" : "L5";

   // context tags
   datetime    ny = ToNY(j.tIn);
   MqlDateTime d;
   TimeToStruct(ny, d);
   double rng   = j.rngHigh - j.rngLow;
   double depth = j.dir == 2 ? j.extreme - j.rngHigh : j.rngLow - j.extreme;
   double pos   = rng > 0.0 ? (j.entry - j.rngLow) / rng : 0.5;
   string tags  = "";
   if(j.model == 5)
      tags += " / qiri 9PM (Asia)";
   if(j.model == 4)
      tags += " / qiri 5PM (pas mbylljes ditore)";
   if(d.hour == 8 || d.hour == 9)
      tags += " / ora e lajmeve 8-10 NY";
   if(d.day_of_week == 5)
      tags += " / e premte";
   if(MathAbs(j.trendPct) < 0.5)
      tags += " / trend i dobet (<0.5% nga mesatarja)";
   if(j.atr > 0.0 && j.risk > 0.30 * j.atr)
      tags += " / SL i madh (>30% e ATR ditore)";
   if(j.atr > 0.0 && j.risk < 0.10 * j.atr)
      tags += " / SL i vogel (<10% e ATR ditore)";
   if(rng > 0.0 && depth > 0.5 * rng)
      tags += " / sweep i thelle (>50% e range-it)";
   if(j.spread > 0.35)
      tags += " / spread i larte (>0.35)";
   if((j.dir == 2 && pos < 0.6) || (j.dir == 1 && pos > 0.4))
      tags += " / hyrje afer mesit te range-it";

   string side = j.dir == 1 ? "BUY" : "SELL";
   string desc = g_mName[j.model] + " " + side + ": " + LossText(kind);
   if(kind == "L4")
      desc += StringFormat(" (maksimumi +%.1fR)", j.mfe);
   if(kind == "L1" || kind == "L2" || kind == "L3" || kind == "L4")
      desc += StringFormat("; SL pas %.0f min", minutes);
   if(kind == "L5" || kind == "W2")
      desc += StringFormat("; %+.2fR pas %.1f oresh", r, minutes / 60.0);
   if(tags != "")
      desc += " |" + StringSubstr(tags, 2);

   g_jCount++;
   FileWrite(g_jFile, IntegerToString(g_jCount), TimeToString(j.tIn, TIME_DATE | TIME_MINUTES),
             TimeToString(ny, TIME_DATE | TIME_MINUTES), g_dayName[d.day_of_week], g_mName[j.model], side,
             F2(j.entry), F2(j.sl), F2(j.tp), F2(j.risk), F2(r),
             reason == DEAL_REASON_SL ? "SL" : reason == DEAL_REASON_TP ? "TP" : "kohe",
             IntegerToString((int)MathRound(minutes)), F2(j.mfe), F2(j.mae), F2(j.rngLow), F2(j.rngHigh),
             F2(j.extreme), F2(depth), IntegerToString((int)MathRound(pos * 100.0)), F2(j.trendPct),
             j.atr > 0.0 ? F2(j.risk / j.atr) : "", F2(j.spread), kind, desc);
   if(!MQLInfoInteger(MQL_TESTER))
      FileFlush(g_jFile);
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;
   int slot = SlotOf((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC));
   if(slot < 0)
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
   JournalClose(posId, r, reason);

   g_slot[slot].trades++;
   g_slot[slot].totalR += r;
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
   string s = "CRT PRO24 v1.03  |  " + _Symbol + "  |  " + (InpTradeEnabled ? "TRADING ON" : "SIGNALS ONLY") +
              "  |  New York time " + NYText(nowNY) + "  (server - " + IntegerToString(InpNYOffset) + "h)";
   s += "\nDaily CRT bias: " + D1Text() + "  |  last skip: " + g_lastSkip;
   s += "\n" + FunnelText() + "\nRejected: " + RejectText();
   for(int k = 0; k < SLOTS; k++)
      for(int m = 0; m < MODELS; m++)
         if(g_pend[k][m].on)
            s += StringFormat("\nWaiting retest: %s %s at %s (until %s)", g_mName[m], g_pend[k][m].dir == 2 ? "SELL" : "BUY",
                              PriceText(g_pend[k][m].level), TimeToString(g_pend[k][m].expires, TIME_DATE | TIME_MINUTES));

   for(int k = 0; k < SLOTS; k++)
   {
      if(!g_slot[k].on)
         continue;
      s += StringFormat("\n\n=== %s (%s, magic %s) ===", SlotTitle(k), EnumToString(g_slot[k].tf), IntegerToString((long)g_slot[k].magic));
      for(int m = 0; m < MODELS; m++)
      {
         if(!g_slot[k].mOn[m])
            continue;
         string key = g_slot[k].mFrom[m] < 0 ? "whole candle" :
                      StringFormat("%02d:%02d-%02d:%02d", g_slot[k].mFrom[m] / 100, g_slot[k].mFrom[m] % 100,
                                   g_slot[k].mTo[m] / 100, g_slot[k].mTo[m] % 100);
         s += StringFormat("\n[%s]  %s  |  %s", g_mName[m], key,
                           g_md[k][m].key > 0 ? NYText(g_md[k][m].key) + ": " + g_md[k][m].status : "waiting for the candle");
      }
   }
   Comment(s);
}


// ============================================================================
// EVENT HANDLERS
// ============================================================================

bool ValidHHMM(int v) { return v >= 0 && v <= 2359 && v % 100 < 60; }

string SlotTitle(int s) { return s == 0 ? "PRO24" : "Selective"; }

void SetModel(int s, int m, bool on, int from, int to)
{
   g_slot[s].mOn[m]   = on;
   g_slot[s].mFrom[m] = from;
   g_slot[s].mTo[m]   = to;
}

// Every H4 candle of the day, signal anywhere inside the candle.
void SetPro24(int s)
{
   g_slot[s].on = true;  g_slot[s].name = "";  g_slot[s].magic = InpMagic;
   g_slot[s].tf = InpEntryTF;  g_slot[s].ohlc = false;  g_slot[s].newsPause = false;
   g_slot[s].exitHHMM = 0;  g_slot[s].maxHoldSec = InpMaxHoldHours * 3600;  g_slot[s].maxDay = InpMaxTradesDay;
   g_slot[s].retest = InpEntryType == ENTRY_RETEST;  g_slot[s].perCandle = InpPerCandle;  g_slot[s].reentry = InpReentry;
   for(int m = 0; m < MODELS; m++)
      SetModel(s, m, true, -1, -1);
}

// The PDF model of CRT_1AM_EA (Selective): 1AM 2-4, 5AM 5-7, 9AM 9:30-11 NY,
// M30 order-block break, OHLC rule, market entry, out at 12:00 NY, 1 a day.
void SetSelective(int s)
{
   g_slot[s].on = true;  g_slot[s].name = "S ";  g_slot[s].magic = InpMagic + 10;
   g_slot[s].tf = PERIOD_M30;  g_slot[s].ohlc = true;  g_slot[s].newsPause = false;
   g_slot[s].exitHHMM = 1200;  g_slot[s].maxHoldSec = 0;  g_slot[s].maxDay = 1;
   g_slot[s].retest = false;  g_slot[s].perCandle = false;  g_slot[s].reentry = false;
   for(int m = 0; m < MODELS; m++)
      SetModel(s, m, false, -1, -1);
   SetModel(s, 0, true, 200, 400);
   SetModel(s, 1, true, 500, 700);
   SetModel(s, 2, true, 930, 1100);
}

int OnInit()
{
   if(InpNYOffset < -12 || InpNYOffset > 14 || InpRiskPercent <= 0.0 || InpRiskPercent > 10.0 ||
      !ValidHHMM(InpFridayClose) || InpMaxHoldHours < 0 || InpMaxTradesDay < 0 || InpRetestHours < 1)
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
   g_slot[1].on = false;
   SetPro24(0);
   if(InpAddSelective)
      SetSelective(1);
   for(int k = 0; k < SLOTS; k++)
   {
      g_slot[k].tfSec   = PeriodSeconds(g_slot[k].tf);
      g_slot[k].lastBar = 0;
      g_slot[k].trades  = 0;
      g_slot[k].totalR  = 0.0;
      for(int m = 0; m < MODELS; m++)
         ResetModelDay(k, m, 0);
   }
   ArrayInitialize(g_rej, 0);
   g_fCandles = g_fNoData = g_fNoBias = g_fHighSweeps = g_fLowSweeps = g_fBreaks = g_fTrades = 0;
   for(int k = 0; k < SLOTS; k++)
      for(int m = 0; m < MODELS; m++)
         g_pend[k][m].on = false;
   g_rtPlaced = g_rtFilled = g_rtExpired = g_rtInvalid = 0;

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

   for(int k = 0; k < SLOTS; k++)
   {
      if(!g_slot[k].on)
         continue;
      string models = "";
      for(int m = 0; m < MODELS; m++)
         if(g_slot[k].mOn[m])
            models += g_mName[m] + " ";
      Log(StringFormat("CRT PRO24 v1.03 | %s | magic %s | entry %s | models %s| OHLC %s | exit %04d NY | max hold %dh | max %d/day",
                       SlotTitle(k), IntegerToString((long)g_slot[k].magic), EnumToString(g_slot[k].tf), models,
                       g_slot[k].ohlc ? "on" : "off", g_slot[k].exitHHMM, g_slot[k].maxHoldSec / 3600, g_slot[k].maxDay));
   }
   Log(StringFormat("CRT PRO24 v1.03 | NY offset %d | bias %s (%d days) | prem/disc %s | TP %s | Friday close %04d NY",
                    InpNYOffset, EnumToString(InpBias), InpTrendDays, EnumToString(InpPremDisc),
                    InpTPMode == TP_RR ? StringFormat("1:%.1f", InpRR) : "range side", InpFridayClose));

   if(!MQLInfoInteger(MQL_TESTER))
      Log("Server time " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES) + " = New York " +
          NYText(ToNY(TimeCurrent())) + ". If New York time is wrong, change InpNYOffset.");

   ArrayResize(g_jr, 0);
   g_jCount = 0;
   JournalStart();

   g_ready = D1Update();
   for(int k = 0; k < SLOTS; k++)
      if(g_slot[k].on)
         g_slot[k].lastBar = iTime(_Symbol, g_slot[k].tf, 0);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   PrintTradeSummary();
   JournalStop();
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

   JournalTrack();
   CloseAtExitTime();

   // Everything else runs once per closed entry-TF bar of each slot.
   bool newBar = false;
   for(int k = 0; k < SLOTS; k++)
   {
      if(!g_slot[k].on)
         continue;
      datetime barOpen = iTime(_Symbol, g_slot[k].tf, 0);
      if(barOpen <= 0 || barOpen == g_slot[k].lastBar)
         continue;
      if(g_slot[k].lastBar == 0)
      {
         g_slot[k].lastBar = barOpen;
         continue;
      }

      MqlRates bars[];
      int n = CopyRates(_Symbol, g_slot[k].tf, g_slot[k].lastBar, barOpen - 1, bars);
      g_slot[k].lastBar = barOpen;
      if(n <= 0)
         continue;

      if(!newBar)
         D1Update();
      newBar = true;

      for(int i = 0; i < n; i++)
         for(int m = 0; m < MODELS; m++)
            if(g_slot[k].mOn[m])
               ModelStep(k, m, bars[i], i == n - 1);
   }
   PendingCheck();
   if(!newBar)
      return;

   UpdatePanel();
}
//+------------------------------------------------------------------+
