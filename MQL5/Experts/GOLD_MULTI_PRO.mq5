//+------------------------------------------------------------------+
//|                                               GOLD_MULTI_PRO.mq5 |
//|   XAUUSD multi-strategy EA: six tested setups, no fixed hours,   |
//|   every trade written with the analysis that opened it           |
//+------------------------------------------------------------------+
//
// Built from a search of 844 strategy configurations (28 families: trend,
// mean reversion, breakouts, price action, ICT) on FP Trading XAUUSD
// 2020-2026: chosen in 2020.04-2023.06, judged in 2023.07-2026.09, the
// survivors checked on M15 and M5 prices and added only when they made
// the whole portfolio better in 2020-22, 2022-24 and 2024-26
// (backtest/strategy_search.py, backtest/gold_multi_pro.py).
// Each setup has its own magic number and one position at a time:
//
//   1. CRT H4 (magic +0..+5): every New York H4 candle. The range of the
//      candle(s) before it is swept (stops taken), an M15 candle closes
//      back through the order block, a limit waits for the retest. Daily
//      trend, premium / discount, range tick-volume filter. TP 2R, 8h.
//   2. Daily CRT (+20): the same on the 17:00-17:00 NY daily candle, M30
//      order block, 8h retest, 24h hold.
//   3. Inside day (+30): yesterday stayed inside the day before; the first
//      M30 close beyond it in the trend direction. SL other side, TP 2R.
//   4. Displacement (+40): an H4 candle of 2.5x ATR or more; enter in its
//      direction (large orders keep pushing). SL 1.5 ATR, TP 2R, 72h.
//   5. Bollinger pullback (+50): in the daily trend an H4 close outside the
//      Bollinger band and back inside; target the middle band, 72h.
//   6. CCI pullback (+60): in the daily trend CCI(20) H4 turns back over
//      -100 (under +100); out when it reaches the other extreme, 72h.
//
// Every trade is printed and written to Common/Files/
// GOLD_MULTI_PRO_journal.csv with the reason it was opened (the setup,
// the levels, the daily trend, volatility and volume) and, when it
// closes, how it ended. The chart label of each entry shows the reason
// as a tooltip; the panel shows the live market reading of every setup.
//
// Tested and not used (no edge in both periods, or only gold's uptrend):
// MA crosses, Donchian / Bollinger / Keltner breakouts, Supertrend, MACD,
// ADX, Parabolic SAR, Ichimoku, Heikin-Ashi, TSMOM, RSI(2), z-score,
// Stochastic, N-bar reversals, pivots, NR4/NR7, squeeze, previous day /
// week breakouts, engulfing / pin / outside bars, intraday fair value gaps
// (PF 1.3 on M30 bars was a bar-order artefact: 0.9-1.0 on M5 prices),
// swing failures, Fibonacci 61.8% pullbacks.
//
// Risk: 0.1% per trade, daily loss limit 0.3%, max drawdown stop 3.5%,
// Friday close 16:00 NY. Simulation 2020.04-2026.09 at 0.1%: about 2440
// trades, +38%, max DD 2.0% (setups 1-3 alone: +28%, max DD 2.3%).
// No setup wins every trade; the stop loss keeps a wrong idea small.
//
// v1.00 in MT5 (2023.01-2026.09, 0.1%): 1576 trades, PF 1.31, +27.4%, max DD 1.9%.
// v1.01: every closed trade is drawn like a position tool (risk box, target
//   box, line to the exit, result) and, in the visual tester or live, saved
//   as a PNG screenshot (InpShots); the journal gets the position id and the
//   screenshot names. Tested and not used: buying only when the previous
//   day, the range candle, H4 EMA 20/50 or the last 24h also point up. A
//   CRT buy comes after the range was sold and its low swept; those trades
//   are most of the profit (filters cut 40-80% of it, PF unchanged).
//+------------------------------------------------------------------+
#property copyright "Marko"
#property version   "1.01"
#property description "GOLD MULTI PRO: six tested XAUUSD setups (CRT H4, daily CRT, inside day, displacement, Bollinger and CCI pullbacks), every trade with its reason."

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
   REJ_NEWS,
   REJ_DAYLOSS
};
#define REJECTS 17   // number of ENUM_REJECT values

enum ENUM_SHOTS
{
   SHOTS_OFF    = 0, // Off
   SHOTS_CLOSE  = 1, // Every trade, when it closes (entry, SL, TP and exit drawn)
   SHOTS_BOTH   = 2, // Every trade, when it opens and when it closes
   SHOTS_LOSSES = 3  // Only losing trades, when they close
};

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
input ENUM_TIMEFRAMES InpEntryTF = PERIOD_M15; // CRT H4: entry / order-block timeframe (M5, M15, M30)
input bool InpPerCandle    = true;  // CRT H4: one position per H4 candle
input bool InpReentry      = true;  // CRT: new setup in the same candle after a trade closes
input double InpMinRangeVol = 0.7;  // CRT H4: trade a candle only if its range had this x the average H4 tick volume (0 = off)

input group "1b. STRATEGIES (each with its own magic number)"
input bool InpCRTH4        = true;  // 1. CRT H4: sweep of the previous H4 range, order block, retest (magic +0..+5)
input bool InpDailyCRT     = true;  // 2. Daily CRT: the same on the daily candle (magic +20)
input bool InpInsideDay    = true;  // 3. Inside day breakout with the daily trend (magic +30)
input bool InpDisplacement = true;  // 4. Displacement: H4 candle >= 2.5 ATR, enter in its direction (magic +40)
input bool InpBBPullback   = true;  // 5. Bollinger pullback in the daily trend, target the middle band (magic +50)
input bool InpCCIPullback  = true;  // 6. CCI(20) H4 pullback in the daily trend (magic +60)

input group "2. BIAS / PREMIUM-DISCOUNT"
input ENUM_CRT_BIAS InpBias     = BIAS_TREND;      // Higher-timeframe bias
input int           InpTrendDays = 50;             // Days in the trend average (bias = daily trend)
input ENUM_CRT_PD   InpPremDisc = PD_RANGE;        // Premium/discount (sell above / buy below the middle)

input ENUM_CRT_ENTRY InpEntryType  = ENTRY_RETEST; // Entry
input int            InpRetestHours = 4;            // Retest: how long to wait for price to come back (hours)

input group "3. RISK / EXIT"
input double InpRiskPercent  = 0.1;    // Risk per trade (% of balance)
input double InpMaxLots      = 5.0;    // Max lots per trade (safety cap)
input ENUM_CRT_TP InpTPMode   = TP_RR;  // Take profit
input double InpRR           = 2.0;    // Reward:risk (TP = fixed RR)
input double InpMinRR        = 1.5;    // Min reward:risk (TP = range side)
input double InpSLBuffer     = 0.30;   // SL buffer beyond the sweep (price units, XAUUSD = $)
input int    InpMaxHoldHours = 8;      // Close a trade after this many hours (0 = off)
input int    InpMaxTradesDay = 5;      // Max trades per day (one position at a time)
input int    InpFridayClose  = 1600;   // Friday: close trades at (HHMM NY), no new trades 4h before (0 = off)
input double InpDailyLossPct = 0.3;    // Daily loss limit: no new trades after losing this % in a NY day (0 = off)
input double InpMaxDDPct     = 3.5;    // Max drawdown: close all and stop when equity is this % below its peak (0 = off)
input bool   InpResetDDStop  = false;  // Restart after a max-drawdown stop (the peak becomes the current equity)
input ulong  InpMagic        = 880100; // Base magic number (setups use +0..+60)

input group "4. COST FILTERS"
input double InpMinSL        = 1.00;   // Min SL distance (price units, 0 = off)
input double InpMinSLSpreadX = 4.0;    // Min SL distance as a multiple of the spread (0 = off)
input double InpMaxSpread    = 0.50;   // Max spread (price units, 0 = off)
input int    InpSlippagePts  = 30;     // Max slippage (points)

input group "5. DISPLAY"
input bool InpShowPanel = true;  // Show status panel
input bool InpDraw      = true;  // Draw ranges, sweeps and entries
input bool InpVerbose   = true;  // Print setups to the journal
input bool InpJournal   = true;  // Write every trade with its reason to Common\Files\GOLD_MULTI_PRO_journal.csv
input ENUM_SHOTS InpShots = SHOTS_CLOSE; // Chart screenshot of every trade (visual tester or live), MQL5\Files\GOLD_MULTI_PRO_shots
input int  InpShotWidth  = 1600; // Screenshot width (pixels)
input int  InpShotHeight = 900;  // Screenshot height (pixels)

input group "6. OPTIMIZATION"
input int  InpOptMinTrades = 30; // Min trades for the "Custom max" score


// ============================================================================
// STRUCTS / GLOBALS
// ============================================================================

#define MODELS  6
#define OBJ_PFX "GMP_"

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

#define SLOTS 4   // 0 CRT H4, 1 (unused), 2 Daily CRT, 3 Inside day

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
   bool            newsPause;    // not used
   bool            retest;       // retest limit entry (else market at the break)
   bool            perCandle;    // own magic (base + candle) and position per H4 candle
   bool            reentry;      // keep watching the candle after a trade
   datetime        lastBar;      // open time of the entry-TF bar being formed
   int             candleSec;    // CRT candle length (4h, 24h for the daily CRT)
   int             candleHour;   // NY start hour of a single daily candle (-1 = the six H4 candles)
   int             retestSec;    // how long a retest limit waits
   bool            pd;           // premium/discount filter
   double          slBuffer;     // SL beyond the sweep extreme
   bool            inside;       // inside-day breakout (no CRT candles)
   double          minRangeVol;  // min tick volume of the range vs the average candle (0 = off)
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

int    CandleHour(int s, int m)   { return g_slot[s].candleHour >= 0 ? g_slot[s].candleHour : g_mHour[m]; }
int    RangeCandles(int s, int m) { return g_slot[s].candleHour >= 0 ? 1 : g_mRange[m]; }
string ModelName(int s, int m)    { return g_slot[s].inside ? "INSIDE" : g_slot[s].candleHour >= 0 ? "D1" : g_mName[m]; }

bool      g_ready     = false;
bool      g_silent    = false;
bool      g_noChart   = false;
string    g_lastSkip  = "-";
bool      g_ddStopped = false;   // max drawdown reached: no trading until reset
double    g_eqPeak    = 0.0;     // highest equity seen (persisted in a terminal global variable)
string    g_gvPeak    = "";
string    g_gvStop    = "";
datetime  g_ddPanel   = 0;       // last panel refresh while stopped

// Funnel: how many CRT candles, sweeps and order-block breaks there were
// and why the signals were not traded.
int       g_fCandles = 0, g_fNoData = 0, g_fNoBias = 0, g_fQuiet = 0;
int       g_fHighSweeps = 0, g_fLowSweeps = 0, g_fBreaks = 0, g_fTrades = 0;
int       g_rej[REJECTS];
string    g_rejName[REJECTS] = {"signals only", "key time", "against bias", "position open", "max trades",
                                "spread", "OHLC", "premium/discount", "SL side", "SL too small", "RR",
                                "lot size", "order failed", "stale", "Friday", "news hours",
                                "daily loss limit"};
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
void   JournalOpen(ulong posId, int s, int m, int dir, double entry, double sl, double tp, double extreme, double spread, string why);
string SlotTitle(int s);
int    XOf(ulong magic);
void   ShotAtOpen(ulong posId, string tag, double sl, double tp);
string MarketContext();

// H4 indicator setups (4. displacement, 5. Bollinger pullback, 6. CCI pullback)
#define XMODS 3
string   g_xName[XMODS]   = {"DISPLACEMENT", "BB PULLBACK", "CCI PULLBACK"};
string   g_xStatus[XMODS];
int      g_xSignals[XMODS];
int      g_xOpened[XMODS];
int      g_xTrades[XMODS];
double   g_xR[XMODS];
datetime g_xLastBar = 0;


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

bool IsMine(ulong magic) { return SlotOf(magic) >= 0 || XOf(magic) >= 0; }

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

// Today's (New York day) realised result of this EA's trades, in money.
double TodayResult()
{
   datetime now      = TimeCurrent();
   datetime dayStart = ToServer(DayStart(ToNY(now)));
   if(!HistorySelect(dayStart, now + 60))
      return 0.0;

   double sum   = 0.0;
   int    total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0)
         continue;
      if(HistoryDealGetString(t, DEAL_SYMBOL) != _Symbol)
         continue;
      if(!IsMine((ulong)HistoryDealGetInteger(t, DEAL_MAGIC)))
         continue;
      sum += HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_COMMISSION) +
             HistoryDealGetDouble(t, DEAL_SWAP);
   }
   return sum;
}

// True once today's closed trades lost InpDailyLossPct of the day's starting balance.
bool DayLossHit()
{
   if(InpDailyLossPct <= 0.0)
      return false;
   double today    = TodayResult();
   double startBal = AccountInfoDouble(ACCOUNT_BALANCE) - today;
   return startBal > 0.0 && today <= -InpDailyLossPct / 100.0 * startBal;
}

void Skip(int why, string reason)
{
   g_rej[why]++;
   g_lastSkip = reason;
   Log("SKIP: " + reason);
}

string FunnelText()
{
   return StringFormat("CRT candles %d | no data %d | quiet range %d | no bias %d | high sweeps %d | low sweeps %d | OB breaks %d | trades %d",
                       g_fCandles, g_fNoData, g_fQuiet, g_fNoBias, g_fHighSweeps, g_fLowSweeps, g_fBreaks, g_fTrades);
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

void DrawLabel(datetime t, double price, string text, color clr, bool above, string tip = "")
{
   if(!DrawingOn() || price <= 0.0)
      return;
   string name = NewObjName("T");
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price))
      return;
   if(tip != "")
      ObjectSetString(0, name, OBJPROP_TOOLTIP, StringSubstr(tip, 0, 1000));
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
   datetime rngStart = crtSrv - RangeCandles(s, m) * g_slot[s].candleSec;

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
   if(CopyRates(_Symbol, g_slot[s].tf, crtSrv, crtSrv + g_slot[s].candleSec - 1, oc) <= 0)   // 5PM opens after the daily break
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

   // Liquidity of the range: a sweep only means something when the range was
   // built with real volume. Tick volume per candle of the range vs the
   // average candle of the last 5 days (quiet Asia ranges fall out here).
   if(g_slot[s].minRangeVol > 0.0)
   {
      long   rv[], av[];
      int    nr = CopyTickVolume(_Symbol, g_slot[s].tf, rngStart, crtSrv - 1, rv);
      int    na = CopyTickVolume(_Symbol, g_slot[s].tf, crtSrv - 5 * 86400, crtSrv - 1, av);
      double sr = 0.0, sa = 0.0;
      for(int i = 0; i < nr; i++)
         sr += (double)rv[i];
      for(int i = 0; i < na; i++)
         sa += (double)av[i];
      double avgCandle = sa / (5.0 * 86400.0 / g_slot[s].candleSec);
      double ratio     = avgCandle > 0.0 ? sr / RangeCandles(s, m) / avgCandle : 1.0;
      if(ratio < g_slot[s].minRangeVol)
      {
         g_md[s][m].status = StringFormat("quiet range: volume %.2f x average", ratio);
         g_fQuiet++;
         if(InpVerbose)
            Log(StringFormat("[%s%s] %s quiet range (volume %.2f x average), not traded",
                             g_slot[s].name, ModelName(s, m), NYText(crtNY), ratio));
         return;
      }
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
   DrawLevel(crtSrv, crtSrv + g_slot[s].candleSec, g_md[s][m].crtOpen, clrGold, STYLE_DOT);
   DrawLevel(crtSrv, crtSrv + g_slot[s].candleSec, hi, clrTomato, STYLE_SOLID);
   DrawLevel(crtSrv, crtSrv + g_slot[s].candleSec, lo, clrMediumSeaGreen, STYLE_SOLID);

   if(InpVerbose)
      Log(StringFormat("[%s%s] %s range %s - %s | open %s | prev-day mid %s | bias %s",
                       g_slot[s].name, ModelName(s, m), NYText(crtNY), PriceText(lo), PriceText(hi),
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

// ============================================================================
// MARKET ANALYSIS (the reasons written with every trade and on the panel)
// ============================================================================

// Daily trend: yesterday's close vs the average of the last InpTrendDays
// closes. 1 up, 2 down, 0 unknown; pct = distance from the average in %.
int DailyTrend(double &pct)
{
   pct = 0.0;
   MqlRates d[];
   int n = CopyRates(_Symbol, PERIOD_D1, 1, InpTrendDays, d);
   if(n < InpTrendDays)
      return 0;
   double sum = 0.0;
   for(int i = 0; i < n; i++)
      sum += d[i].close;
   double avg = sum / n;
   double c   = d[n - 1].close;
   pct = avg > 0.0 ? (c - avg) / avg * 100.0 : 0.0;
   return c > avg ? 1 : c < avg ? 2 : 0;
}

string TrendText(int t) { return t == 1 ? "LART" : t == 2 ? "POSHTE" : "pa trend"; }

// Trend, volatility (daily ATR 14 vs the last 60 days) and the volume of the
// last H4 candle (vs the 30 before it), in one line.
string MarketContext()
{
   double pct;
   int    tr = DailyTrend(pct);
   string s  = StringFormat("trend ditor %s (%+.1f%% nga SMA%d)", TrendText(tr), pct, InpTrendDays);
   MqlRates d[];
   int n = CopyRates(_Symbol, PERIOD_D1, 1, 74, d);
   if(n >= 74)
   {
      double a14 = 0.0, a60 = 0.0;
      for(int i = n - 14; i < n; i++)
         a14 += d[i].high - d[i].low;
      for(int i = n - 74; i < n - 14; i++)
         a60 += d[i].high - d[i].low;
      a14 /= 14.0;
      a60 /= 60.0;
      double ratio = a60 > 0.0 ? a14 / a60 : 1.0;
      s += StringFormat(" | volatiliteti %s (ATR ditor %.1f$ = %.1fx mesatarja 60 dite)",
                        ratio > 1.3 ? "i larte" : ratio < 0.7 ? "i ulet" : "normal", a14, ratio);
   }
   MqlRates h[];
   int nh = CopyRates(_Symbol, PERIOD_H4, 1, 31, h);
   if(nh >= 31)
   {
      double sv = 0.0;
      for(int i = 0; i < nh - 1; i++)
         sv += (double)h[i].tick_volume;
      double vr = sv > 0.0 ? (double)h[nh - 1].tick_volume / (sv / (nh - 1)) : 1.0;
      s += StringFormat(" | volumi i qiririt te fundit H4 %.1fx mesatarja", vr);
   }
   return s;
}

string TfName(ENUM_TIMEFRAMES tf) { return StringSubstr(EnumToString(tf), 7); }

// Why a CRT / inside-day trade was opened.
string CRTReason(int s, int m, int dir, double entry, double extreme)
{
   double lo  = g_md[s][m].rngLow;
   double hi  = g_md[s][m].rngHigh;
   double rng = hi - lo;
   double pct = g_md[s][m].trendAvg > 0.0 ? (g_md[s][m].prevClose - g_md[s][m].trendAvg) / g_md[s][m].trendAvg * 100.0 : 0.0;
   if(g_slot[s].inside)
      return StringFormat("INSIDE DAY: dita e djeshme (%s - %s) qendroi brenda dites para saj, tregu mblodhi energji; "
                          "nje mbyllje M30 %s %s ne drejtim te trendit ditor %s (%+.1f%%) = breakout; SL ne anen tjeter te dites, TP %.1fR",
                          PriceText(lo), PriceText(hi), dir == 1 ? "mbi" : "nen", PriceText(dir == 1 ? hi : lo),
                          TrendText(dir), pct, InpRR);
   double pos   = rng > 0.0 ? (entry - lo) / rng * 100.0 : 50.0;
   string cname = g_slot[s].candleHour >= 0 ? "CRT DITOR" : "CRT H4 " + g_mName[m];
   return StringFormat("%s: range-i i kohes %s - %s u fshi %s deri %s (u moren stop-et pertej tij); "
                       "nje qiri %s u mbyll perseri pertej order block-ut = kthim (likuiditeti u perdor per te shkuar ne anen tjeter); "
                       "hyrje %s; trend ditor %s (%+.1f%%); hyrja ne %.0f%% te range-it (%s); SL pertej sweep-it, TP %.1fR",
                       cname, PriceText(lo), PriceText(hi), dir == 2 ? "lart" : "poshte", PriceText(extreme), TfName(g_slot[s].tf),
                       g_slot[s].retest ? "ne retest te order block-ut" : "me treg", TrendText(dir), pct, pos,
                       dir == 2 ? "zone premium, shitje" : "zone discount, blerje", InpRR);
}

// Checks the filters and sends the order. dir 1 = buy, 2 = sell.
bool TryEnter(int s, int m, int dir, datetime sigNY, double extreme)
{
   string tag = g_slot[s].name + ModelName(s, m) + (dir == 1 ? " BUY" : " SELL");

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
   if(DayLossHit())
   {
      Skip(REJ_DAYLOSS, tag + ": daily loss limit reached");
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
   if(g_slot[s].pd && InpPremDisc != PD_OFF && ((dir == 2 && bid < g_md[s][m].pdMid) || (dir == 1 && ask > g_md[s][m].pdMid)))
   {
      Skip(REJ_PD, tag + (dir == 2 ? ": not in premium" : ": not in discount"));
      return false;
   }

   double sl   = NormPrice(dir == 1 ? extreme - g_slot[s].slBuffer : extreme + g_slot[s].slBuffer);
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

   string cmt = "GMP " + g_slot[s].name + ModelName(s, m);
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
   string why = CRTReason(s, m, dir, fill, extreme) + " | " + MarketContext();
   JournalOpen(g_trade.ResultOrder(), s, m, dir, fill, sl, tp, extreme, spread, why);

   g_lastSkip = "-";
   g_fTrades++;
   Log(StringFormat("%s %s lots | entry %s  SL %s  TP %s | range %s-%s | %s",
                    tag, DoubleToString(lots, 2), PriceText(entry), PriceText(sl), PriceText(tp),
                    PriceText(g_md[s][m].rngLow), PriceText(g_md[s][m].rngHigh), NYText(sigNY)));
   Log("ARSYEJA: " + why);
   DrawLabel(TimeCurrent(), entry, tag, dir == 1 ? clrAqua : clrMagenta, dir == 2, why);
   ShotAtOpen(g_trade.ResultOrder(), tag, sl, tp);
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
   long     into = ((long)ny - CandleHour(s, m) * 3600) % 86400;   // time since the candle start
   if(into < 0)
      into += 86400;
   if(into >= g_slot[s].candleSec)
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
         Log(StringFormat("[%s%s] %s OB break at %s", g_slot[s].name, ModelName(s, m), dir == 2 ? "SELL" : "BUY", NYText(sigNY)));

      double extreme = dir == 2 ? MathMax(g_md[s][m].sweepHigh, b.high) : MathMin(g_md[s][m].sweepLow, b.low);
      bool entered = false;
      if(!latest)
         Skip(REJ_STALE, g_slot[s].name + ModelName(s, m) + ": stale signal");
      else if(g_slot[s].retest)
      {
         // Wait for price to come back to the broken order-block level.
         // v1.06: a setup against the trend is dropped here; its limit
         // would be refused at the fill anyway and blocked the candle.
         bool busy = g_pend[s][m].on || HasOpenPosition(MagicOf(s, m)) || (!g_slot[s].perCandle && AnyPending(s));
         if((g_md[s][m].allowDir & dir) == 0)
            Skip(REJ_BIAS, g_slot[s].name + ModelName(s, m) + (dir == 1 ? " BUY" : " SELL") + ": against HTF bias");
         else if(!busy)
         {
            g_pend[s][m].on      = true;
            g_pend[s][m].s       = s;
            g_pend[s][m].m       = m;
            g_pend[s][m].dir     = dir;
            g_pend[s][m].level   = dir == 2 ? g_md[s][m].obSellLow : g_md[s][m].obBuyHigh;
            g_pend[s][m].extreme = extreme;
            g_pend[s][m].sigNY   = sigNY;
            g_pend[s][m].expires = TimeCurrent() + g_slot[s].retestSec;
            g_rtPlaced++;
            g_md[s][m].status = StringFormat("waiting for retest of %s", PriceText(g_pend[s][m].level));
            Log(StringFormat("[%s%s] %s retest limit %s (SL side %s), valid %dh", g_slot[s].name, ModelName(s, m), dir == 2 ? "SELL" : "BUY",
                             PriceText(g_pend[s][m].level), PriceText(extreme), g_slot[s].retestSec / 3600));
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
         DrawLabel(b.time, b.high, g_slot[s].name + ModelName(s, m) + " sweep", clrOrange, true);
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
         DrawLabel(b.time, b.low, g_slot[s].name + ModelName(s, m) + " sweep", clrOrange, false);
      }
      g_md[s][m].sweptLow  = true;
      g_md[s][m].sweepLow  = b.low;
      g_md[s][m].obBuyHigh = b.high;
      g_md[s][m].obBuyTime = b.time;
      g_md[s][m].status    = "low swept, waiting for OB break";
   }
}

// ============================================================================
// INSIDE DAY BREAKOUT
// Yesterday (server day) stayed inside the day before it. Today, the first
// M30 close beyond yesterday's high (daily trend up) or low (trend down)
// enters at market; SL at the other side of yesterday, TP at InpRR, out
// after 24 hours. One try per inside day.
// ============================================================================

void InsideInit(int s, datetime day)
{
   ResetModelDay(s, 0, day);
   MqlRates dd[];
   int k = CopyRates(_Symbol, PERIOD_D1, day, InpTrendDays + 2, dd);
   int y = k > 0 && dd[k - 1].time >= day ? k - 2 : k - 1;      // yesterday
   if(y < InpTrendDays || y < 1)
   {
      g_md[s][0].status = "no daily data";
      return;
   }
   MqlRates yd = dd[y], pp = dd[y - 1];
   g_md[s][0].rngHigh = yd.high;
   g_md[s][0].rngLow  = yd.low;
   if(!(yd.high < pp.high && yd.low > pp.low))
   {
      g_md[s][0].status = "yesterday was not an inside day";
      return;
   }
   // trend: yesterday's close vs the average of the InpTrendDays closes up to yesterday
   double sum = 0.0, rangeSum = 0.0;
   int    rangeN = 0;
   for(int j = y - InpTrendDays + 1; j <= y; j++)
   {
      sum += dd[j].close;
      if(j > y - 14)
      {
         rangeSum += dd[j].high - dd[j].low;
         rangeN++;
      }
   }
   double avg = sum / InpTrendDays;
   g_md[s][0].prevClose = yd.close;
   g_md[s][0].trendAvg  = avg;
   g_md[s][0].atr       = rangeN > 0 ? rangeSum / rangeN : 0.0;
   g_md[s][0].pdMid     = (yd.high + yd.low) / 2.0;
   g_md[s][0].allowDir  = yd.close > avg ? 1 : yd.close < avg ? 2 : 0;
   g_md[s][0].ok        = true;
   g_md[s][0].status    = g_md[s][0].allowDir == 1 ? "inside day: waiting for a close above " + PriceText(yd.high) :
                          g_md[s][0].allowDir == 2 ? "inside day: waiting for a close below " + PriceText(yd.low) : "inside day, no trend";
   DrawLevel(day, day + 86400, yd.high, clrTomato, STYLE_DASH);
   DrawLevel(day, day + 86400, yd.low, clrMediumSeaGreen, STYLE_DASH);
   if(InpVerbose)
      Log(StringFormat("[%sINSIDE] %s inside day %s - %s | trend %s", g_slot[s].name, TimeToString(day, TIME_DATE),
                       PriceText(yd.low), PriceText(yd.high), g_md[s][0].allowDir == 1 ? "UP" : g_md[s][0].allowDir == 2 ? "DOWN" : "NONE"));
}

// One closed M30 bar through the inside-day module.
void InsideStep(int s, const MqlRates &b, bool latest)
{
   datetime day = DayStart(b.time);   // server day
   if(g_md[s][0].key != day)
      InsideInit(s, day);
   if(!g_md[s][0].ok || g_md[s][0].done || g_md[s][0].allowDir == 0)
      return;
   int dir = g_md[s][0].allowDir == 1 && b.close > g_md[s][0].rngHigh ? 1 :
             g_md[s][0].allowDir == 2 && b.close < g_md[s][0].rngLow  ? 2 : 0;
   if(dir == 0)
      return;
   g_md[s][0].done = true;            // only the first break of the day counts
   if(!latest)
   {
      Skip(REJ_STALE, g_slot[s].name + "INSIDE: stale signal");
      return;
   }
   double extreme = dir == 1 ? g_md[s][0].rngLow : g_md[s][0].rngHigh;
   bool   ok      = TryEnter(s, 0, dir, ToNY(b.time) + g_slot[s].tfSec, extreme);
   g_md[s][0].status = ok ? "traded" : "break not traded: " + g_lastSkip;
}

// ============================================================================
// H4 INDICATOR SETUPS (4. displacement, 5. Bollinger pullback, 6. CCI pullback)
// Evaluated once per closed H4 bar; market entry at the next bar's open.
// The indicators are computed here from the bars (Wilder ATR 14, SMA / SD
// 20, CCI 20) so they match backtest/strategy_search.py exactly.
// ============================================================================

ulong XMagic(int x) { return InpMagic + 40 + 10 * (ulong)x; }
bool  XOn(int x)    { return x == 0 ? InpDisplacement : x == 1 ? InpBBPullback : InpCCIPullback; }

int XOf(ulong magic)
{
   for(int x = 0; x < XMODS; x++)
      if(magic == XMagic(x))
         return x;
   return -1;
}

// Wilder ATR(14) of every bar (index 0 = oldest).
void XAtr(const MqlRates &r[], int n, double &atr[])
{
   ArrayResize(atr, n);
   ArrayInitialize(atr, 0.0);
   double sum = 0.0;
   for(int i = 0; i < n; i++)
   {
      double tr = r[i].high - r[i].low;
      if(i > 0)
         tr = MathMax(tr, MathMax(MathAbs(r[i].high - r[i - 1].close), MathAbs(r[i].low - r[i - 1].close)));
      if(i < 14)
      {
         sum += tr;
         if(i == 13)
            atr[i] = sum / 14.0;
      }
      else
         atr[i] = atr[i - 1] + (tr - atr[i - 1]) / 14.0;
   }
}

double XSma(const MqlRates &r[], int k, int p)
{
   double sum = 0.0;
   for(int i = k - p + 1; i <= k; i++)
      sum += r[i].close;
   return sum / p;
}

double XSd(const MqlRates &r[], int k, int p)
{
   double m = XSma(r, k, p), sum = 0.0;
   for(int i = k - p + 1; i <= k; i++)
      sum += (r[i].close - m) * (r[i].close - m);
   return MathSqrt(sum / p);
}

double XCci(const MqlRates &r[], int k, int p)
{
   double m = 0.0;
   for(int i = k - p + 1; i <= k; i++)
      m += (r[i].high + r[i].low + r[i].close) / 3.0;
   m /= p;
   double md = 0.0;
   for(int i = k - p + 1; i <= k; i++)
      md += MathAbs((r[i].high + r[i].low + r[i].close) / 3.0 - m);
   md /= p;
   double tp = (r[k].high + r[k].low + r[k].close) / 3.0;
   return md > 0.0 ? (tp - m) / (0.015 * md) : 0.0;
}

// Market order for an H4 setup. tp: rr > 0 = rr x risk, else tpPrice (0 = none).
bool XEnter(int x, int dir, double slRaw, double tpPrice, double rr, string why)
{
   string tag = g_xName[x] + (dir == 1 ? " BUY" : " SELL");
   g_xSignals[x]++;
   if(!InpTradeEnabled)
   {
      Skip(REJ_SIGNALS_ONLY, tag + ": signals only");
      return false;
   }
   if(HasOpenPosition(XMagic(x)))
   {
      Skip(REJ_POSITION, tag + ": position already open");
      return false;
   }
   if(InpFridayClose > 0 && FridayAfter(ToNY(TimeCurrent()), MathMax(0, InpFridayClose - 400)))
   {
      Skip(REJ_FRIDAY, tag + ": too close to the Friday close");
      return false;
   }
   if(DayLossHit())
   {
      Skip(REJ_DAYLOSS, tag + ": daily loss limit reached");
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
   double sl   = NormPrice(slRaw);
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
   double tp = 0.0;
   if(rr > 0.0)
      tp = dir == 1 ? entry + rr * risk : entry - rr * risk;
   else if(tpPrice > 0.0)
   {
      tp = tpPrice;
      if((dir == 1 && tp <= entry) || (dir == 2 && tp >= entry))
      {
         Skip(REJ_RR, tag + ": target already reached");
         return false;
      }
   }
   if(tp > 0.0)
      tp = NormPrice(tp);
   double lots = CalcLots(dir, entry, sl);
   if(lots <= 0.0)
   {
      Skip(REJ_LOTS, tag + ": lot size below broker minimum");
      return false;
   }
   g_trade.SetExpertMagicNumber(XMagic(x));
   bool ok = dir == 1 ? g_trade.Buy(lots, _Symbol, entry, sl, tp, "GMP " + g_xName[x])
                      : g_trade.Sell(lots, _Symbol, entry, sl, tp, "GMP " + g_xName[x]);
   uint rc = g_trade.ResultRetcode();
   if(!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_PLACED))
   {
      Skip(REJ_ORDER, StringFormat("%s: order failed %u %s", tag, rc, g_trade.ResultRetcodeDescription()));
      return false;
   }
   double fill = g_trade.ResultPrice() > 0.0 ? g_trade.ResultPrice() : entry;
   double pnlAtSl = 0.0;
   if(OrderCalcProfit(dir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lots, fill, sl, pnlAtSl) && pnlAtSl < 0.0)
      SetPlannedRisk(g_trade.ResultOrder(), -pnlAtSl);
   string full = why + " | " + MarketContext();
   JournalOpen(g_trade.ResultOrder(), -1 - x, 0, dir, fill, sl, tp, 0.0, spread, full);
   g_xOpened[x]++;
   g_lastSkip = "-";
   Log(StringFormat("%s %s lots | entry %s  SL %s  TP %s", tag, DoubleToString(lots, 2), PriceText(fill), PriceText(sl),
                    tp > 0.0 ? PriceText(tp) : "signal"));
   Log("ARSYEJA: " + full);
   DrawLabel(TimeCurrent(), fill, tag, dir == 1 ? clrAqua : clrMagenta, dir == 2, full);
   ShotAtOpen(g_trade.ResultOrder(), tag, sl, tp);
   return true;
}

// Once per new H4 bar: CCI exits, then the three setups on the bar that just closed.
void XStep()
{
   if(!XOn(0) && !XOn(1) && !XOn(2))
      return;
   datetime bar0 = iTime(_Symbol, PERIOD_H4, 0);
   if(bar0 <= 0 || bar0 == g_xLastBar)
      return;
   bool first = g_xLastBar == 0;      // the bar closed before the EA started: no entry
   g_xLastBar = bar0;

   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_H4, 1, 300, r);
   if(n < 60)
      return;
   int    k = n - 1;                    // the H4 bar that just closed
   double atr[];
   XAtr(r, n, atr);
   double a     = atr[k];
   double aPrev = atr[k - 1];
   double cciK  = XCci(r, k, 20), cciP = XCci(r, k - 1, 20);
   double mid   = XSma(r, k, 20), sd = XSd(r, k, 20);
   double midP  = XSma(r, k - 1, 20), sdP = XSd(r, k - 1, 20);
   double upK = mid + 2.0 * sd, loK = mid - 2.0 * sd, upP = midP + 2.0 * sdP, loP = midP - 2.0 * sdP;
   double rngAtr = aPrev > 0.0 ? (r[k].high - r[k].low) / aPrev : 0.0;
   double pct;
   int    trend = DailyTrend(pct);

   // 6. CCI pullback is over when CCI reaches the other extreme
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol || (ulong)PositionGetInteger(POSITION_MAGIC) != XMagic(2))
         continue;
      bool buy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      if((buy && cciK > 100.0) || (!buy && cciK < -100.0))
      {
         g_trade.SetExpertMagicNumber(XMagic(2));
         if(g_trade.PositionClose(ticket))
            Log(StringFormat("CCI PULLBACK CLOSE: CCI %.0f arriti ekstremin tjeter, pullback-u mbaroi", cciK));
      }
   }

   // 4. Displacement: a candle of 2.5 ATR or more, both directions
   if(XOn(0))
   {
      g_xStatus[0] = StringFormat("qiriri i fundit H4 %.1fx ATR (sinjal nga 2.5x)", rngAtr);
      if(!first && rngAtr >= 2.5)
      {
         int    dir = r[k].close > r[k].open ? 1 : 2;
         double sl  = dir == 1 ? r[k].close - 1.5 * a : r[k].close + 1.5 * a;
         string why = StringFormat("DISPLACEMENT: qiriri H4 %s - %s levizi %.1f$ = %.1fx ATR (%s): urdhra te medhenj hyne ne treg "
                                   "dhe zakonisht vazhdojne; hyrje ne drejtimin e tij, SL 1.5 ATR (%.1f$), TP 2R, maksimumi 72 ore",
                                   TimeToString(r[k].time, TIME_DATE | TIME_MINUTES), TimeToString(r[k].time + 4 * 3600, TIME_MINUTES),
                                   r[k].high - r[k].low, rngAtr, dir == 1 ? "bullish" : "bearish", 1.5 * a);
         XEnter(0, dir, sl, 0.0, 2.0, why);
      }
   }

   // 5. Bollinger pullback: an H4 close outside the band and back inside, with the daily trend
   if(XOn(1))
   {
      int dir = r[k - 1].close < loP && r[k].close > loK ? 1 : r[k - 1].close > upP && r[k].close < upK ? 2 : 0;
      double bpos = upK > loK ? (r[k].close - loK) / (upK - loK) * 100.0 : 50.0;
      g_xStatus[1] = StringFormat("cmimi ne %.0f%% te Bollinger (0 = banda poshte, 100 = lart), trend %s", bpos, TrendText(trend));
      if(!first && dir != 0)
      {
         if(dir != trend)
            Skip(REJ_BIAS, g_xName[1] + (dir == 1 ? " BUY" : " SELL") + ": against the daily trend");
         else
         {
            double lo3 = MathMin(r[k].low, MathMin(r[k - 1].low, r[k - 2].low));
            double hi3 = MathMax(r[k].high, MathMax(r[k - 1].high, r[k - 2].high));
            double sl  = dir == 1 ? lo3 - 0.3 * a : hi3 + 0.3 * a;
            string why = StringFormat("BOLLINGER PULLBACK: trendi ditor %s (%+.1f%%); qiriri H4 i meparshem u mbyll %s bandes Bollinger (%s) "
                                      "dhe ky u mbyll perseri brenda (%s) = pullback i tepruar qe po kthehet; TP mesi i Bollinger %s, "
                                      "SL %s 3 qirinjve te fundit",
                                      TrendText(trend), pct, dir == 1 ? "nen" : "mbi", PriceText(dir == 1 ? loP : upP),
                                      PriceText(r[k].close), PriceText(mid), dir == 1 ? "nen" : "mbi");
            XEnter(1, dir, sl, mid, 0.0, why);
         }
      }
   }

   // 6. CCI pullback: CCI(20) back over -100 (under +100), with the daily trend
   if(XOn(2))
   {
      int dir = cciP < -100.0 && cciK >= -100.0 ? 1 : cciP > 100.0 && cciK <= 100.0 ? 2 : 0;
      g_xStatus[2] = StringFormat("CCI(20) H4 %.0f (blerje kur kthehet mbi -100 ne trend lart), trend %s", cciK, TrendText(trend));
      if(!first && dir != 0)
      {
         if(dir != trend)
            Skip(REJ_BIAS, g_xName[2] + (dir == 1 ? " BUY" : " SELL") + ": against the daily trend");
         else
         {
            double sl  = dir == 1 ? r[k].close - 2.0 * a : r[k].close + 2.0 * a;
            string why = StringFormat("CCI PULLBACK: trendi ditor %s (%+.1f%%); CCI(20) H4 nga %.0f u kthye ne %.0f, %s = pullback-u "
                                      "kunder trendit mbaroi; dalje kur CCI arrin %s, SL mbrojtes 2 ATR (%.1f$), maksimumi 72 ore",
                                      TrendText(trend), pct, cciP, cciK, dir == 1 ? "mbi -100" : "nen +100",
                                      dir == 1 ? "+100" : "-100", 2.0 * a);
            XEnter(2, dir, sl, 0.0, 0.0, why);
         }
      }
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
      ulong mg = (ulong)PositionGetInteger(POSITION_MAGIC);
      int   s  = SlotOf(mg);
      int   x  = s < 0 ? XOf(mg) : -1;
      if(s < 0 && x < 0)
         continue;

      datetime opened  = (datetime)PositionGetInteger(POSITION_TIME);
      bool     byClock = false;
      if(s >= 0 && g_slot[s].exitHHMM > 0)
      {
         datetime exitNY = DayStart(nowNY) + HHMMToMin(g_slot[s].exitHHMM) * 60;
         if(nowNY < exitNY)
            exitNY -= 86400;
         byClock = ToNY(opened) < exitNY;
      }
      int  hold   = s >= 0 ? g_slot[s].maxHoldSec : 72 * 3600;
      bool byHold = hold > 0 && now - opened >= hold;
      if(!byClock && !byHold && !friday)
         continue;
      g_trade.SetExpertMagicNumber(mg);
      if(g_trade.PositionClose(ticket))
         Log((s >= 0 ? g_slot[s].name : g_xName[x] + " ") + (friday ? "CLOSE: Friday close " : byHold ? "CLOSE: max hold time " : "CLOSE: exit time ") + NYText(nowNY));
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

// ============================================================================
// MAX DRAWDOWN STOP
// Equity is compared with its highest value. At InpMaxDDPct below it the EA
// closes its positions, drops its retest orders and stops trading until it
// is restarted with InpResetDDStop = true. Outside the tester the peak and
// the stop survive a terminal restart (terminal global variables).
// ============================================================================

void DDInit()
{
   g_ddStopped = false;
   g_eqPeak    = AccountInfoDouble(ACCOUNT_EQUITY);
   if(InpMaxDDPct <= 0.0 || MQLInfoInteger(MQL_TESTER))
      return;
   string base = "GMP_" + _Symbol + "_" + IntegerToString((long)InpMagic);
   g_gvPeak = base + "_peak";
   g_gvStop = base + "_ddstop";
   if(InpResetDDStop)
   {
      GlobalVariableDel(g_gvStop);
      GlobalVariableSet(g_gvPeak, g_eqPeak);
      Log(StringFormat("MAX DD: stop reset, peak = equity %.2f. Set InpResetDDStop back to false.", g_eqPeak));
      return;
   }
   if(GlobalVariableCheck(g_gvPeak))
      g_eqPeak = MathMax(g_eqPeak, GlobalVariableGet(g_gvPeak));
   else
      GlobalVariableSet(g_gvPeak, g_eqPeak);
   if(GlobalVariableCheck(g_gvStop))
   {
      g_ddStopped = true;
      Log("MAX DD: the EA was stopped by the max drawdown limit. Restart it with InpResetDDStop = true.");
   }
}

// Closes this EA's positions on this symbol; returns how many could not be closed.
int CloseAllMine()
{
   int left = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(!IsMine((ulong)PositionGetInteger(POSITION_MAGIC)))
         continue;
      g_trade.SetExpertMagicNumber((ulong)PositionGetInteger(POSITION_MAGIC));
      if(!g_trade.PositionClose(ticket))
         left++;
   }
   return left;
}

// True while the EA is stopped by the max drawdown limit.
bool DDCheck()
{
   if(InpMaxDDPct <= 0.0)
      return false;
   if(!g_ddStopped)
   {
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq > g_eqPeak)
      {
         if(g_gvPeak != "" && eq > g_eqPeak * 1.0001)
            GlobalVariableSet(g_gvPeak, eq);
         g_eqPeak = eq;
      }
      if(g_eqPeak <= 0.0 || eq > g_eqPeak * (1.0 - InpMaxDDPct / 100.0))
         return false;
      g_ddStopped = true;
      if(g_gvStop != "")
         GlobalVariableSet(g_gvStop, (double)TimeCurrent());
      for(int k = 0; k < SLOTS; k++)
         for(int m = 0; m < MODELS; m++)
            g_pend[k][m].on = false;
      g_lastSkip = "max drawdown stop";
      Log(StringFormat("MAX DD: equity %.2f is %.2f%% below its peak %.2f (limit %.1f%%). Closing all and stopping. Restart with InpResetDDStop = true.",
                       eq, 100.0 * (1.0 - eq / g_eqPeak), g_eqPeak, InpMaxDDPct));
   }
   CloseAllMine();   // again on later ticks if a close failed
   return true;
}

void PrintTradeSummary()
{
   Print("GOLD MULTI FUNNEL: " + FunnelText());
   Print("GOLD MULTI REJECTED: " + RejectText());
   string xs = "";
   for(int x = 0; x < XMODS; x++)
      if(XOn(x))
         xs += StringFormat("%s%s signals %d, opened %d", xs == "" ? "" : " | ", g_xName[x], g_xSignals[x], g_xOpened[x]);
   if(xs != "")
      Print("GOLD MULTI H4 SETUPS: " + xs);
   if(InpMaxDDPct > 0.0)
      Print(StringFormat("GOLD MULTI MAX DD STOP (%.1f%%): %s", InpMaxDDPct,
                         g_ddStopped ? "TRIGGERED, the EA stopped trading" : "not reached"));
   if(g_slot[0].retest)
      Print(StringFormat("GOLD MULTI RETEST: placed %d | filled %d | expired %d | cancelled (new extreme) %d",
                         g_rtPlaced, g_rtFilled, g_rtExpired, g_rtInvalid));
   if(g_stN == 0)
   {
      Print("GOLD MULTI SUMMARY: no closed trades");
      return;
   }
   int losses = g_stN - g_stWin;
   Print(StringFormat("GOLD MULTI SUMMARY: %d trades | win %.1f%% | avg win %+.2fR | avg loss %+.2fR | worst %+.2fR | total %+.1fR",
                      g_stN, 100.0 * g_stWin / g_stN,
                      g_stWin > 0 ? g_stWinR / g_stWin : 0.0,
                      losses > 0 ? g_stLossR / losses : 0.0,
                      g_stWorstR, g_stWinR + g_stLossR));
   string bySlot = "";
   for(int s = 0; s < SLOTS; s++)
      if(g_slot[s].on)
         bySlot += StringFormat("%s%s %d trades %+.1fR", bySlot == "" ? "" : " | ", SlotTitle(s), g_slot[s].trades, g_slot[s].totalR);
   for(int x = 0; x < XMODS; x++)
      if(XOn(x))
         bySlot += StringFormat("%s%s %d trades %+.1fR", bySlot == "" ? "" : " | ", g_xName[x], g_xTrades[x], g_xR[x]);
   Print("GOLD MULTI SUMMARY by mode: " + bySlot);
   Print(StringFormat("GOLD MULTI SUMMARY by exit: SL %d x %+.2fR | TP %d x %+.2fR | time/EA close %d x %+.2fR",
                      g_stSL, g_stSL > 0 ? g_stSLR / g_stSL : 0.0,
                      g_stTP, g_stTP > 0 ? g_stTPR / g_stTP : 0.0,
                      g_stOther, g_stOther > 0 ? g_stOtherR / g_stOther : 0.0));
}

// ============================================================================
// SCREENSHOTS (visual tester and live): the chart of every trade as a PNG in
// MQL5\Files\GOLD_MULTI_PRO_shots (in the tester: Tester\Agent-...\MQL5\Files)
// ============================================================================

bool ShotsOn() { return InpShots != SHOTS_OFF && !g_silent && !g_noChart; }

string SafeName(string v)
{
   StringReplace(v, " ", "_");
   StringReplace(v, ":", "-");
   StringReplace(v, "/", "-");
   return v;
}

// Zooms out until the bars since `from` fit, takes the screenshot, restores the zoom.
string Shot(datetime from, string tag)
{
   if(!ShotsOn())
      return "";
   long scale0 = ChartGetInteger(0, CHART_SCALE);
   int  need   = (int)((TimeCurrent() - from) / PeriodSeconds(_Period)) + 30;
   ChartSetInteger(0, CHART_AUTOSCROLL, true);
   for(int sc = (int)scale0; sc >= 0; sc--)
   {
      ChartSetInteger(0, CHART_SCALE, sc);
      ChartNavigate(0, CHART_END, 0);
      ChartRedraw(0);
      if(ChartGetInteger(0, CHART_WIDTH_IN_BARS) >= need)
         break;
   }
   string name = "GOLD_MULTI_PRO_shots\\" + SafeName(TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES) + "_" + tag) + ".png";
   bool ok = ChartScreenShot(0, name, InpShotWidth, InpShotHeight, ALIGN_RIGHT);
   ChartSetInteger(0, CHART_SCALE, scale0);
   ChartRedraw(0);
   if(!ok)
   {
      Log("Screenshot failed: " + name + ", error " + IntegerToString(GetLastError()));
      return "";
   }
   return name;
}

// The trade on the chart like a position tool: risk box (entry to SL), target
// box (entry to TP), a line from the entry to the exit and the result.
void DrawTrade(datetime tIn, datetime tOut, int dir, double entry, double sl, double tp, double exitPrice, double r, string text)
{
   if(!DrawingOn())
      return;
   datetime t2 = tOut > tIn ? tOut : tIn + PeriodSeconds(_Period);
   DrawBox(tIn, t2, entry, sl, C'90,25,25');
   if(tp > 0.0)
      DrawBox(tIn, t2, entry, tp, C'20,70,35');
   if(exitPrice > 0.0)
   {
      string name = NewObjName("X");
      if(ObjectCreate(0, name, OBJ_TREND, 0, tIn, entry, t2, exitPrice))
      {
         ObjectSetInteger(0, name, OBJPROP_COLOR, r > 0.0 ? clrLime : clrRed);
         ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      }
      DrawLabel(t2, exitPrice, text, r > 0.0 ? clrLime : clrRed, dir == 1 ? r > 0.0 : r <= 0.0);
   }
}


// ============================================================================
// TRADE JOURNAL (CSV with a description of every trade)
// ============================================================================

#define JOURNAL_FILE "GOLD_MULTI_PRO_journal.csv"

struct JournalRec
{
   ulong    posId;
   datetime tIn;
   int      slot;     // CRT slot, or -1 - x for the H4 setups
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
   string   why;      // the analysis that opened the trade
   string   shotOpen; // screenshot at the entry ("" = none)
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
      FileWrite(g_jFile, "nr", "hyrja (server)", "hyrja (NY)", "dita", "strategjia", "drejtimi", "entry", "SL", "TP",
                "SL $", "rezultati R", "dalja", "minuta", "max ne favor R", "max kunder R", "range low", "range high",
                "sweep", "sweep pertej range $", "hyrja ne range %", "trendi % nga mesatarja", "SL / ATR ditore",
                "spread", "lloji", "pershkrimi", "arsyeja e hyrjes (analiza)", "pozicioni", "foto hyrja", "foto dalja");
}

void JournalStop()
{
   if(g_jFile == INVALID_HANDLE)
      return;
   FileClose(g_jFile);
   g_jFile = INVALID_HANDLE;
   Print("GOLD MULTI JOURNAL: ", g_jCount, " trades -> ",
         TerminalInfoString(TERMINAL_COMMONDATA_PATH), "\\Files\\", JOURNAL_FILE);
}

void JournalOpen(ulong posId, int s, int m, int dir, double entry, double sl, double tp, double extreme, double spread, string why)
{
   if(g_jFile == INVALID_HANDLE)
      return;
   int n = ArraySize(g_jr);
   ArrayResize(g_jr, n + 1, 16);
   g_jr[n].posId    = posId;
   g_jr[n].tIn      = TimeCurrent();
   g_jr[n].slot     = s;
   g_jr[n].model    = m;
   g_jr[n].dir      = dir;
   g_jr[n].entry    = entry;
   g_jr[n].sl       = sl;
   g_jr[n].tp       = tp;
   g_jr[n].risk     = MathAbs(entry - sl);
   g_jr[n].extreme  = extreme;
   g_jr[n].spread   = spread;
   g_jr[n].why      = why;
   g_jr[n].shotOpen = "";
   if(s >= 0)
   {
      g_jr[n].rngLow   = g_md[s][m].rngLow;
      g_jr[n].rngHigh  = g_md[s][m].rngHigh;
      g_jr[n].trendPct = g_md[s][m].trendAvg > 0.0 ?
                         (g_md[s][m].prevClose - g_md[s][m].trendAvg) / g_md[s][m].trendAvg * 100.0 : 0.0;
      g_jr[n].atr      = g_md[s][m].atr;
   }
   else
   {
      double pct = 0.0;
      DailyTrend(pct);
      g_jr[n].rngLow   = 0.0;
      g_jr[n].rngHigh  = 0.0;
      g_jr[n].trendPct = pct;
      g_jr[n].atr      = 0.0;
   }
   g_jr[n].mfe      = 0.0;
   g_jr[n].mae      = 0.0;
}

// Entry screenshot (SHOTS_BOTH) with the SL / TP boxes of the new trade.
void ShotAtOpen(ulong posId, string tag, double sl, double tp)
{
   if(InpShots != SHOTS_BOTH || !ShotsOn())
      return;
   int i = ArraySize(g_jr) - 1;
   if(i < 0 || g_jr[i].posId != posId)
      return;
   datetime t = TimeCurrent();
   DrawBox(t, t + 4 * PeriodSeconds(_Period), g_jr[i].entry, sl, C'90,25,25');
   if(tp > 0.0)
      DrawBox(t, t + 4 * PeriodSeconds(_Period), g_jr[i].entry, tp, C'20,70,35');
   g_jr[i].shotOpen = Shot(t - 60 * PeriodSeconds(_Period), "pos" + IntegerToString((long)posId) + "_" + tag + "_open");
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
   if(kind == "L5") return "mbyllje me kohe ose me sinjal ne humbje";
   if(kind == "W1") return "fitim: preku TP";
   return "mbyllje me kohe ose me sinjal ne fitim";
}

void JournalClose(ulong posId, double r, long reason, double exitPrice)
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
   if(j.slot == 0 && j.model == 5)
      tags += " / qiri 9PM (Asia)";
   if(j.slot == 0 && j.model == 4)
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
   if(rng > 0.0 && ((j.dir == 2 && pos < 0.6) || (j.dir == 1 && pos > 0.4)))
      tags += " / hyrje afer mesit te range-it";

   string side = j.dir == 1 ? "BUY" : "SELL";
   string strat = j.slot >= 0 ? g_slot[j.slot].name + ModelName(j.slot, j.model) : g_xName[-1 - j.slot];
   string desc  = strat + " " + side + ": " + LossText(kind);
   if(kind == "L4")
      desc += StringFormat(" (maksimumi +%.1fR)", j.mfe);
   if(kind == "L1" || kind == "L2" || kind == "L3" || kind == "L4")
      desc += StringFormat("; SL pas %.0f min", minutes);
   if(kind == "L5" || kind == "W2")
      desc += StringFormat("; %+.2fR pas %.1f oresh", r, minutes / 60.0);
   if(tags != "")
      desc += " |" + StringSubstr(tags, 2);

   string exitTxt = reason == DEAL_REASON_SL ? "SL" : reason == DEAL_REASON_TP ? "TP" : "kohe/sinjal";
   DrawTrade(j.tIn, tOut, j.dir, j.entry, j.sl, j.tp, exitPrice, r, StringFormat("%s %+.2fR %s", strat, r, exitTxt));
   string shot = "";
   if(InpShots == SHOTS_CLOSE || InpShots == SHOTS_BOTH || (InpShots == SHOTS_LOSSES && r < 0.0))
      shot = Shot(j.tIn - 40 * PeriodSeconds(_Period),
                  "pos" + IntegerToString((long)posId) + "_" + strat + "_" + side + StringFormat("_%+.1fR_", r) + exitTxt);
   string why = j.why;
   StringReplace(why, ",", ";");          // the file is comma separated
   g_jCount++;
   FileWrite(g_jFile, IntegerToString(g_jCount), TimeToString(j.tIn, TIME_DATE | TIME_MINUTES),
             TimeToString(ny, TIME_DATE | TIME_MINUTES), g_dayName[d.day_of_week], strat, side,
             F2(j.entry), F2(j.sl), F2(j.tp), F2(j.risk), F2(r),
             reason == DEAL_REASON_SL ? "SL" : reason == DEAL_REASON_TP ? "TP" : "kohe",
             IntegerToString((int)MathRound(minutes)), F2(j.mfe), F2(j.mae), F2(j.rngLow), F2(j.rngHigh),
             F2(j.extreme), F2(depth), IntegerToString((int)MathRound(pos * 100.0)), F2(j.trendPct),
             j.atr > 0.0 ? F2(j.risk / j.atr) : "", F2(j.spread), kind, desc, why,
             IntegerToString((long)posId), j.shotOpen, shot);
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
   ulong dmg  = (ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   int   slot = SlotOf(dmg);
   int   xm   = slot < 0 ? XOf(dmg) : -1;
   if(slot < 0 && xm < 0)
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
   JournalClose(posId, r, reason, HistoryDealGetDouble(trans.deal, DEAL_PRICE));

   if(slot >= 0)
   {
      g_slot[slot].trades++;
      g_slot[slot].totalR += r;
   }
   else
   {
      g_xTrades[xm]++;
      g_xR[xm] += r;
   }
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
   string s = "GOLD MULTI PRO v1.01  |  " + _Symbol + "  |  " +
              (g_ddStopped ? "STOPPED: MAX DRAWDOWN (restart with InpResetDDStop = true)" : InpTradeEnabled ? "TRADING ON" : "SIGNALS ONLY") +
              "  |  New York time " + NYText(nowNY) + "  (server - " + IntegerToString(InpNYOffset) + "h)";
   s += "\nDaily CRT bias: " + D1Text() + "  |  last skip: " + g_lastSkip;
   if(InpMaxDDPct > 0.0 && g_eqPeak > 0.0)
      s += StringFormat("\nDrawdown %.2f%% of max %.1f%%  (equity peak %.2f)",
                        100.0 * (1.0 - AccountInfoDouble(ACCOUNT_EQUITY) / g_eqPeak), InpMaxDDPct, g_eqPeak);
   s += "\nANALIZA: " + MarketContext();
   for(int x = 0; x < XMODS; x++)
      if(XOn(x))
         s += StringFormat("\n[%s]  %s%s", g_xName[x], g_xStatus[x], HasOpenPosition(XMagic(x)) ? "  |  POZICION I HAPUR" : "");
   s += "\n" + FunnelText() + "\nRejected: " + RejectText();
   for(int k = 0; k < SLOTS; k++)
      for(int m = 0; m < MODELS; m++)
         if(g_pend[k][m].on)
            s += StringFormat("\nWaiting retest: %s%s %s at %s (until %s)", g_slot[k].name, ModelName(k, m), g_pend[k][m].dir == 2 ? "SELL" : "BUY",
                              PriceText(g_pend[k][m].level), TimeToString(g_pend[k][m].expires, TIME_DATE | TIME_MINUTES));

   for(int k = 0; k < SLOTS; k++)
   {
      if(!g_slot[k].on)
         continue;
      s += StringFormat("\n\n=== %s (%s, magic %s) ===", SlotTitle(k), EnumToString(g_slot[k].tf), IntegerToString((long)g_slot[k].magic));
      if(g_slot[k].inside)
         s += "\n[INSIDE]  " + (g_md[k][0].key > 0 ? TimeToString(g_md[k][0].key, TIME_DATE) + ": " + g_md[k][0].status : "waiting for the day");
      for(int m = 0; m < MODELS; m++)
      {
         if(!g_slot[k].mOn[m])
            continue;
         string key = g_slot[k].mFrom[m] < 0 ? "whole candle" :
                      StringFormat("%02d:%02d-%02d:%02d", g_slot[k].mFrom[m] / 100, g_slot[k].mFrom[m] % 100,
                                   g_slot[k].mTo[m] / 100, g_slot[k].mTo[m] % 100);
         s += StringFormat("\n[%s]  %s  |  %s", ModelName(k, m), key,
                           g_md[k][m].key > 0 ? NYText(g_md[k][m].key) + ": " + g_md[k][m].status : "waiting for the candle");
      }
   }
   Comment(s);
}


// ============================================================================
// EVENT HANDLERS
// ============================================================================

bool ValidHHMM(int v) { return v >= 0 && v <= 2359 && v % 100 < 60; }

string SlotTitle(int s) { return s == 0 ? "CRT H4" : s == 2 ? "Daily CRT" : s == 3 ? "Inside day" : "-"; }

void SetModel(int s, int m, bool on, int from, int to)
{
   g_slot[s].mOn[m]   = on;
   g_slot[s].mFrom[m] = from;
   g_slot[s].mTo[m]   = to;
}

// Every H4 candle of the day, signal anywhere inside the candle.
void SetPro24(int s)
{
   g_slot[s].on = true;  g_slot[s].name = "CRT ";  g_slot[s].magic = InpMagic;
   g_slot[s].tf = InpEntryTF;  g_slot[s].ohlc = false;  g_slot[s].newsPause = false;
   g_slot[s].exitHHMM = 0;  g_slot[s].maxHoldSec = InpMaxHoldHours * 3600;  g_slot[s].maxDay = InpMaxTradesDay;
   g_slot[s].retest = InpEntryType == ENTRY_RETEST;  g_slot[s].perCandle = InpPerCandle;  g_slot[s].reentry = InpReentry;
   g_slot[s].candleSec = 4 * 3600;  g_slot[s].candleHour = -1;  g_slot[s].retestSec = InpRetestHours * 3600;
   g_slot[s].pd = true;  g_slot[s].slBuffer = InpSLBuffer;  g_slot[s].inside = false;
   g_slot[s].minRangeVol = InpMinRangeVol;
   for(int m = 0; m < MODELS; m++)
      SetModel(s, m, true, -1, -1);
}

// The CRT H4 setup on the daily candle (17:00-17:00 NY): range = previous
// day, M30 order-block break, retest up to 8 hours, out after 24 hours.
void SetDailyCRT(int s)
{
   g_slot[s].on = true;  g_slot[s].name = "D ";  g_slot[s].magic = InpMagic + 20;
   g_slot[s].tf = PERIOD_M30;  g_slot[s].ohlc = false;  g_slot[s].newsPause = false;
   g_slot[s].exitHHMM = 0;  g_slot[s].maxHoldSec = 24 * 3600;  g_slot[s].maxDay = InpMaxTradesDay;
   g_slot[s].retest = true;  g_slot[s].perCandle = false;  g_slot[s].reentry = InpReentry;
   g_slot[s].candleSec = 86400;  g_slot[s].candleHour = 17;  g_slot[s].retestSec = 8 * 3600;
   g_slot[s].pd = true;  g_slot[s].slBuffer = InpSLBuffer;  g_slot[s].inside = false;
   g_slot[s].minRangeVol = 0.0;
   for(int m = 0; m < MODELS; m++)
      SetModel(s, m, m == 0, -1, -1);
}

// Inside day breakout in the daily trend (see InsideStep).
void SetInsideDay(int s)
{
   g_slot[s].on = true;  g_slot[s].name = "I ";  g_slot[s].magic = InpMagic + 30;
   g_slot[s].tf = PERIOD_M30;  g_slot[s].ohlc = false;  g_slot[s].newsPause = false;
   g_slot[s].exitHHMM = 0;  g_slot[s].maxHoldSec = 24 * 3600;  g_slot[s].maxDay = 0;
   g_slot[s].retest = false;  g_slot[s].perCandle = false;  g_slot[s].reentry = false;
   g_slot[s].candleSec = 86400;  g_slot[s].candleHour = -1;  g_slot[s].retestSec = 0;
   g_slot[s].pd = false;  g_slot[s].slBuffer = 0.0;  g_slot[s].inside = true;
   g_slot[s].minRangeVol = 0.0;
   for(int m = 0; m < MODELS; m++)
      SetModel(s, m, false, -1, -1);
}

int OnInit()
{
   if(InpNYOffset < -12 || InpNYOffset > 14 || InpRiskPercent <= 0.0 || InpRiskPercent > 10.0 ||
      !ValidHHMM(InpFridayClose) || InpMaxHoldHours < 0 || InpMaxTradesDay < 0 || InpRetestHours < 1 ||
      InpDailyLossPct < 0.0 || InpMaxDDPct < 0.0 || InpMaxDDPct >= 100.0 || InpMinRangeVol < 0.0)
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
   for(int k = 0; k < SLOTS; k++)
      g_slot[k].on = false;
   if(InpCRTH4)
      SetPro24(0);
   if(InpDailyCRT)
      SetDailyCRT(2);
   if(InpInsideDay)
      SetInsideDay(3);
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
   g_fCandles = g_fNoData = g_fQuiet = g_fNoBias = g_fHighSweeps = g_fLowSweeps = g_fBreaks = g_fTrades = 0;
   for(int k = 0; k < SLOTS; k++)
      for(int m = 0; m < MODELS; m++)
         g_pend[k][m].on = false;
   g_rtPlaced = g_rtFilled = g_rtExpired = g_rtInvalid = 0;
   for(int x = 0; x < XMODS; x++)
   {
      g_xStatus[x]  = "pret mbylljen e qiririt te ardhshem H4";
      g_xSignals[x] = 0;
      g_xOpened[x]  = 0;
      g_xTrades[x]  = 0;
      g_xR[x]       = 0.0;
   }
   g_xLastBar = 0;

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
            models += ModelName(k, m) + " ";
      Log(StringFormat("GOLD MULTI PRO v1.01 | %s | magic %s | entry %s | models %s| OHLC %s | exit %04d NY | max hold %dh | max %d/day",
                       SlotTitle(k), IntegerToString((long)g_slot[k].magic), EnumToString(g_slot[k].tf), models,
                       g_slot[k].ohlc ? "on" : "off", g_slot[k].exitHHMM, g_slot[k].maxHoldSec / 3600, g_slot[k].maxDay));
   }
   string xl = "";
   for(int x = 0; x < XMODS; x++)
      if(XOn(x))
         xl += StringFormat("%s (magic %s)  ", g_xName[x], IntegerToString((long)XMagic(x)));
   if(xl != "")
      Log("GOLD MULTI PRO v1.01 | H4 setups: " + xl);
   Log(StringFormat("GOLD MULTI PRO v1.01 | NY offset %d | bias %s (%d days) | prem/disc %s | TP %s | Friday close %04d NY",
                    InpNYOffset, EnumToString(InpBias), InpTrendDays, EnumToString(InpPremDisc),
                    InpTPMode == TP_RR ? StringFormat("1:%.1f", InpRR) : "range side", InpFridayClose));

   if(!MQLInfoInteger(MQL_TESTER))
      Log("Server time " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES) + " = New York " +
          NYText(ToNY(TimeCurrent())) + ". If New York time is wrong, change InpNYOffset.");

   ArrayResize(g_jr, 0);
   g_jCount = 0;
   JournalStart();
   DDInit();
   if(ShotsOn())
      Log("Screenshots: " + TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\GOLD_MULTI_PRO_shots");
   else if(InpShots != SHOTS_OFF && MQLInfoInteger(MQL_TESTER))
      Log("Screenshots need the visual mode of the Strategy Tester (Visual mode with the display of charts).");

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
   if(DDCheck())
   {
      if(TimeCurrent() - g_ddPanel >= 60)
      {
         g_ddPanel = TimeCurrent();
         UpdatePanel();
      }
      return;
   }
   CloseAtExitTime();
   XStep();

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
      {
         for(int m = 0; m < MODELS; m++)
            if(g_slot[k].mOn[m])
               ModelStep(k, m, bars[i], i == n - 1);
         if(g_slot[k].inside)
            InsideStep(k, bars[i], i == n - 1);
      }
   }
   PendingCheck();
   if(!newBar)
      return;

   UpdatePanel();
}
//+------------------------------------------------------------------+
