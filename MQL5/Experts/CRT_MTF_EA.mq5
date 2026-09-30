//+------------------------------------------------------------------+
//|                                                   CRT_MTF_EA.mq5 |
//|                 CRT MTF EVENT ENGINE - Expert Advisor for MT5    |
//+------------------------------------------------------------------+
//
// Port of the TradingView scripts
//   "CRT MTF EVENT ENGINE v8 - 5M FINAL - NO 1M"   (default entry mode)
//   "CRT MTF EVENT ENGINE v5 + v6 1M MICRO ENGINE" (optional entry mode)
//
// FLOW
//   1W / 1D / 4H / 1H / 30M / 15M / 5M CRT engines (closed bars only)
//         |
//   5M CRT CONFIRMED  (parent -> sweep -> close back inside)
//         |
//   v8 (default): MARKET ENTRY at the 5M CRT close
//                 SL beyond the C2 sweep wick, TP at the 5M CRT target
//   optional:     1M SWEEP -> 1M MSS -> 1M FVG -> 1M FVG RETEST -> ENTRY
//   The entry CRT timeframe is an input (M5 default, up to H4).
//
// v1.20 COST / QUALITY FILTERS (the v1.10 5M test lost ~48% in 5 weeks:
// stops of $0.3-$1 on gold paid most of the risk to the spread)
//   - min SL distance, absolute and as a multiple of the spread
//   - min sweep depth beyond the parent range (% of the range)
//   - session filter on by default (10:00-20:00 server time)
//
// v1.25 DEFAULTS = best family of the 2023-2026 optimizations
//   M15 CRT entries only in the direction of an active D1 CRT.
//   In-sample 2023-01..2025-06: PF ~0.87 (306 trades) - still losing.
//   Forward   2025-07..2026-09: PF ~1.40 (~185 trades).
//   Every M15/H1 + H4/D1 same-direction variant lost in-sample and won
//   forward, so the edge depends on the market regime: demo first.
//
// FIXES VS THE PINE VERSION
//   - 50% rule: by default the entry retires once price has already
//     travelled halfway TOWARD the target (the v5 rule is selectable).
//   - Events come straight from the engine: no "!= na" comparisons.
//   - 5M engine runs on closed M5 bars, without the extra 1-bar lag
//     of request.security(...)[1] on a 5M chart.
//   - 1M history is rolling (not wiped at every new CRT), so a sweep
//     can happen on the very first 1M bar after the CRT.
//   - Separate sweep / MSS lookbacks (MSS lookback was unused).
//   - Target and 50% are checked on every closed 1M bar, so no entry
//     is taken after the move is already done.
//   - Only closed 1M bars are used: no intrabar repaint.
//   - Ledger records TARGET / INVALID with the CRT levels they closed.
//
// Defaults are tuned for XAUUSD (prices in $).
//+------------------------------------------------------------------+
#property copyright "Marko"
#property version   "1.25"
#property description "Multi-timeframe CRT engine (W1..M5). Enters on the 5M (or higher) CRT,"
#property description "or optionally on a 1M sweep -> MSS -> FVG -> retest. Tuned for XAUUSD."

#include <Trade/Trade.mqh>


// ============================================================================
// EVENT CODES (same numbering as the Pine script)
// ============================================================================

#define EV_NONE       0
#define EV_PARENT     1
#define EV_BULL       2
#define EV_BEAR       3
#define EV_MID        4
#define EV_TARGET     5
#define EV_INVALID    6
#define EV_EXPANSION  7
#define EV_DOUBLE     8


// ============================================================================
// MICRO STATES
// ============================================================================

#define MICRO_IDLE    0
#define MICRO_WAIT    1
#define MICRO_SWEEP   2
#define MICRO_MSS     3
#define MICRO_FVG     4
#define MICRO_DONE    5

#define ENG_COUNT     7
#define IDX_M5        6
#define OBJ_PFX       "CRTEA_"


// ============================================================================
// ENUMS
// ============================================================================

enum ENUM_MID_RULE
{
   MID_TOWARD_TARGET = 0, // Retire when price reaches 50% toward target
   MID_ORIGINAL_V5   = 1, // Original v5 rule (bull: low<=50%, bear: high>=50%)
   MID_OFF           = 2  // Never retire at 50%
};

enum ENUM_ENTRY_MODE
{
   ENTRY_MICRO_1M  = 0, // 1M micro: sweep -> MSS -> FVG -> retest
   ENTRY_CRT_CLOSE = 1  // CRT only (v8): market entry at CRT confirmation
};

enum ENUM_SL_MODE
{
   SL_MICRO_SWEEP = 0, // Beyond the 1M sweep extreme
   SL_CRT_SWEEP   = 1, // Beyond the 5M CRT sweep wick (C2)
   SL_FVG         = 2  // Beyond the far edge of the 1M FVG
};

enum ENUM_TP_MODE
{
   TP_CRT_TARGET = 0, // 5M CRT target (other side of the parent range)
   TP_R_MULTIPLE = 1  // Fixed R multiple
};

enum ENUM_RISK_MODE
{
   RISK_PERCENT    = 0, // % of balance lost at SL
   RISK_FIXED_LOTS = 1  // Fixed lots
};

enum ENUM_BIAS_MODE
{
   BIAS_OFF         = 0, // Off
   BIAS_NOT_AGAINST = 1, // Block trades against an active HTF CRT
   BIAS_SAME_DIR    = 2  // Require an active HTF CRT in the same direction
};


// ============================================================================
// INPUTS
// ============================================================================

input group "TRADING"
input bool            InpTradeEnabled  = true;           // Place trades (false = signals only)
input ENUM_ENTRY_MODE InpEntryMode     = ENTRY_CRT_CLOSE; // Entry mode
input ENUM_TIMEFRAMES InpEntryTF       = PERIOD_M15;     // CRT entry timeframe (M5/M15/M30/H1/H4)
input bool            InpCloseOnInvalid = true;          // Close the trade when its entry CRT is invalidated
input ulong           InpMagic         = 550100;         // Magic number
input ENUM_RISK_MODE  InpRiskMode      = RISK_PERCENT;   // Position sizing
input double          InpRiskPercent   = 0.5;            // Risk per trade (% of balance)
input double          InpFixedLots     = 0.01;           // Fixed lots
input double          InpMaxLots       = 5.0;            // Max lots per trade (safety cap)
input ENUM_SL_MODE    InpSLMode        = SL_MICRO_SWEEP; // Stop loss placement (1M mode; 5M mode uses the C2 wick)
input double          InpSLBuffer      = 0.30;           // SL buffer (price units, XAUUSD = $)
input ENUM_TP_MODE    InpTPMode        = TP_CRT_TARGET;  // Take profit
input double          InpRMultiple     = 2.0;            // R multiple (when TP = R multiple)
input double          InpMinRR         = 1.0;            // Min reward:risk to take a trade (0 = off)
input double          InpBreakEvenR    = 0.0;            // Move SL to entry at +R (0 = off)
input int             InpMaxTradesDay  = 3;              // Max trades per day (0 = no limit)
input double          InpMaxSpread     = 0.50;           // Max spread (price units, 0 = off)
input int             InpSlippagePts   = 30;             // Max slippage (points)

input group "QUALITY / COST FILTERS"
input double InpMinSL         = 1.00;  // Min SL distance (price units, XAUUSD = $, 0 = off)
input double InpMinSLSpreadX  = 4.0;   // Min SL distance as a multiple of the spread (0 = off)
input double InpMinSweepPct   = 10.0;  // Min sweep beyond the parent range (% of range, 0 = off)

input group "SESSION (server time)"
input bool InpUseSession     = true;  // Only enter inside the session
input int  InpSessStartHour  = 10;    // Session start hour
input int  InpSessStartMin   = 0;     // Session start minute
input int  InpSessEndHour    = 20;    // Session end hour
input int  InpSessEndMin     = 0;     // Session end minute
input bool InpCloseOutside   = false; // Close positions outside the session

input group "HTF BIAS"
input ENUM_BIAS_MODE  InpBiasMode = BIAS_SAME_DIR; // HTF bias filter
input ENUM_TIMEFRAMES InpBiasTF   = PERIOD_D1;     // HTF bias timeframe (W1/D1/H4/H1/M30/M15)

input group "CRT ENGINE"
input ENUM_MID_RULE InpMidRule    = MID_TOWARD_TARGET; // 50% midpoint rule
input int           InpWarmupBars = 300;               // Warm-up bars per timeframe

input group "1M MICRO ENGINE"
input int  InpSweepLookback   = 3;    // Liquidity sweep lookback (1M bars)
input int  InpMssLookback     = 3;    // MSS lookback (1M bars)
input int  InpMicroMaxBars    = 15;   // Max 1M bars after the 5M CRT
input int  InpMinFvgTicks     = 1;    // Min FVG size (ticks)
input bool InpCancelOnFvgFail = true; // Cancel when a 1M bar closes through the FVG

input group "DISPLAY / LOG"
input bool InpShowPanel   = true;  // Show MTF panel + ledger (chart comment)
input int  InpLedgerMax   = 100;   // Max ledger events kept
input int  InpLedgerRows  = 10;    // Visible ledger rows
input bool InpDraw        = true;  // Draw 5M CRT levels and 1M events
input bool InpVerbose     = true;  // Print 1M micro events to the journal
input bool InpLedgerCSV   = false; // Write the ledger to MQL5/Files/CRT_ledger_<symbol>.csv
input bool InpAlertPopup  = false; // Popup alerts
input bool InpAlertPush   = false; // Push notifications

input group "OPTIMIZATION"
input int  InpOptMinTrades = 30;   // Min trades for the "Custom max" score (fewer = score 0)


// ============================================================================
// STRUCTS
// ============================================================================

struct CRTEngine
{
   ENUM_TIMEFRAMES tf;
   bool            hasParent;
   int             state;          // 0 = wait, 1 = bull active, 2 = bear active
   int             id;
   double          ph;
   double          pl;
   double          mid;
   double          target;
   double          sweepExtreme;   // wick extreme of the sweep candle (C2)
   datetime        parentTime;
   datetime        sweepTime;
   datetime        confirmTime;
   bool            entryOpen;
   int             lastEvent;
   int             lastEventDir;
   datetime        lastEventTime;
   datetime        lastBarTime;    // open time of the last processed closed bar
};

struct LedgerEvent
{
   ENUM_TIMEFRAMES tf;
   int             id;
   int             ev;
   int             dir;
   int             state;
   datetime        evTime;
   datetime        parentTime;
   datetime        sweepTime;
   double          ph;
   double          pl;
   double          mid;
   double          target;
   bool            entryOpen;
};

struct MicroEngine
{
   int      state;
   int      dir;
   int      crtId;
   int      bars;
   double   crtPH;
   double   crtPL;
   double   crtMid;
   double   crtTarget;
   double   crtSweep;
   double   sweepPrice;
   datetime sweepTime;
   double   mssPrice;
   datetime mssTime;
   double   fvgTop;
   double   fvgBottom;
   datetime fvgTime;
   double   entryPrice;
   datetime entryTime;
   datetime lastEventTime;
};


// ============================================================================
// GLOBALS
// ============================================================================

ENUM_TIMEFRAMES g_tfs[ENG_COUNT] = {PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M30, PERIOD_M15, PERIOD_M5};

CTrade      g_trade;
CRTEngine   g_eng[ENG_COUNT];
LedgerEvent g_ledger[];
MicroEngine g_micro;
string      g_microEvent = "IDLE";

double      g_hHigh[];            // rolling closed 1M history, oldest first
double      g_hLow[];
int         g_histMax    = 5;

datetime    g_lastM1Time = 0;     // open time of the last processed closed 1M bar
datetime    g_lastM1Open = 0;     // open time of the forming 1M bar at the last update
bool        g_ready      = false;
bool        g_warmup     = false;
bool        g_silent     = false; // optimization: no prints, drawings or panel
bool        g_noChart    = false; // non-visual tester: no drawings or panel
int         g_biasIdx    = -1;
int         g_csv        = INVALID_HANDLE;
int         g_drawnCrtId = -1;
long        g_objSeq     = 0;
string      g_lastSkip   = "-";
int         g_tradeCrtId = -1;    // entry-CRT id of the last trade opened
int         g_entryIdx   = IDX_M5; // engine that produces entries

// Per-trade accounting: planned risk vs realised result, in R.
struct TradeRisk
{
   ulong  posId;
   double riskMoney;    // money lost if the stop fills exactly at its price
   double commission;   // entry-side commission
};

TradeRisk g_risk[];
int       g_stN      = 0;
int       g_stWin    = 0;
int       g_stSL     = 0;
int       g_stTP     = 0;
int       g_stOther  = 0;
double    g_stWinR   = 0.0;
double    g_stLossR  = 0.0;
double    g_stWorstR = 0.0;
double    g_stSLR    = 0.0;
double    g_stTPR    = 0.0;
double    g_stOtherR = 0.0;

void SetPlannedRisk(ulong posId, double riskMoney);   // defined in TRADE ACCOUNTING


// ============================================================================
// TEXT HELPERS
// ============================================================================

string TfName(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_W1:  return "1W";
      case PERIOD_D1:  return "1D";
      case PERIOD_H4:  return "4H";
      case PERIOD_H1:  return "1H";
      case PERIOD_M30: return "30M";
      case PERIOD_M15: return "15M";
      case PERIOD_M5:  return "5M";
      case PERIOD_M1:  return "1M";
      default:         break;
   }
   return EnumToString(tf);
}

string EventText(int ev)
{
   switch(ev)
   {
      case EV_PARENT:    return "PARENT";
      case EV_BULL:      return "BULL CRT";
      case EV_BEAR:      return "BEAR CRT";
      case EV_MID:       return "MIDPOINT";
      case EV_TARGET:    return "TARGET HIT";
      case EV_INVALID:   return "INVALIDATED";
      case EV_EXPANSION: return "EXPANSION";
      case EV_DOUBLE:    return "DOUBLE SWEEP";
      default:           break;
   }
   return "-";
}

string StateText(int state)
{
   return state == 1 ? "BULL ACTIVE" : state == 2 ? "BEAR ACTIVE" : "WAIT";
}

string EntryText(int state, bool entryOpen)
{
   return state == 0 ? "NO ENTRY" : entryOpen ? "OPEN" : "RETIRED";
}

string DirText(int dir)
{
   return dir == 1 ? "BULL" : dir == 2 ? "BEAR" : "-";
}

string MicroStateText(int s)
{
   switch(s)
   {
      case MICRO_IDLE:  return "IDLE";
      case MICRO_WAIT:  return "WAIT SWEEP";
      case MICRO_SWEEP: return "SWEEP FOUND";
      case MICRO_MSS:   return "MSS CONFIRMED";
      case MICRO_FVG:   return "FVG FOUND";
      case MICRO_DONE:  return "DONE";
      default:          break;
   }
   return "-";
}

string TimeText(datetime t)
{
   if(t <= 0)
      return "-";
   MqlDateTime d;
   TimeToStruct(t, d);
   return StringFormat("%02d/%02d %02d:%02d", d.day, d.mon, d.hour, d.min);
}

string PriceText(double p)
{
   return p <= 0.0 ? "-" : DoubleToString(p, _Digits);
}

void Log(string msg)
{
   if(!g_silent)
      Print(msg);
}

void Notify(string msg)
{
   if(g_warmup || g_silent || MQLInfoInteger(MQL_TESTER))
      return;
   if(InpAlertPopup)
      Alert(msg);
   if(InpAlertPush)
      SendNotification(msg);
}


// ============================================================================
// CRT ENGINE
// ============================================================================

void ResetEngine(CRTEngine &e, ENUM_TIMEFRAMES tf)
{
   e.tf            = tf;
   e.hasParent     = false;
   e.state         = 0;
   e.id            = 0;
   e.ph            = 0.0;
   e.pl            = 0.0;
   e.mid           = 0.0;
   e.target        = 0.0;
   e.sweepExtreme  = 0.0;
   e.parentTime    = 0;
   e.sweepTime     = 0;
   e.confirmTime   = 0;
   e.entryOpen     = false;
   e.lastEvent     = EV_NONE;
   e.lastEventDir  = 0;
   e.lastEventTime = 0;
   e.lastBarTime   = 0;
}

// The candle becomes the new parent range.
void SetParent(CRTEngine &e, const MqlRates &r)
{
   e.hasParent    = true;
   e.ph           = r.high;
   e.pl           = r.low;
   e.mid          = (r.high + r.low) / 2.0;
   e.target       = 0.0;
   e.sweepExtreme = 0.0;
   e.parentTime   = r.time;
   e.sweepTime    = 0;
   e.confirmTime  = 0;
   e.state        = 0;
   e.entryOpen    = false;
   e.id++;
}

// 50% rule. TOWARD_TARGET retires the entry once half of the move to the
// target is done (bull: high >= 50%, bear: low <= 50%).
bool MidRetire(const CRTEngine &e, double hi, double lo)
{
   if(InpMidRule == MID_OFF)
      return false;

   if(e.state == 1)
      return InpMidRule == MID_TOWARD_TARGET ? hi >= e.mid : lo <= e.mid;

   if(e.state == 2)
      return InpMidRule == MID_TOWARD_TARGET ? lo <= e.mid : hi >= e.mid;

   return false;
}

// Runs one closed candle through the engine. Returns the event code and
// fills 'le' when an event happened.
int EngineStep(CRTEngine &e, const MqlRates &r, LedgerEvent &le)
{
   CRTEngine prev = e;
   int ev  = EV_NONE;
   int dir = 0;
   datetime tClose = r.time + PeriodSeconds(e.tf);

   // =========================================================================
   // INITIAL PARENT
   // =========================================================================
   if(!e.hasParent)
   {
      SetParent(e, r);
      ev = EV_PARENT;
   }

   // =========================================================================
   // NO ACTIVE CRT
   // =========================================================================
   else if(e.state == 0)
   {
      bool sweptLow  = r.low  <= e.pl;
      bool sweptHigh = r.high >= e.ph;
      bool closeOut  = r.close > e.ph || r.close < e.pl;

      // EXPANSION
      if(closeOut)
      {
         SetParent(e, r);
         ev = EV_EXPANSION;
      }
      // DOUBLE SWEEP
      else if(sweptLow && sweptHigh)
      {
         SetParent(e, r);
         ev = EV_DOUBLE;
      }
      // BULLISH CRT: low swept + close back inside
      else if(sweptLow)
      {
         e.state        = 1;
         e.target       = e.ph;
         e.mid          = (e.ph + e.pl) / 2.0;
         e.sweepTime    = r.time;
         e.sweepExtreme = r.low;
         e.confirmTime  = tClose;
         e.entryOpen    = true;
         e.id++;
         ev  = EV_BULL;
         dir = 1;
      }
      // BEARISH CRT: high swept + close back inside
      else if(sweptHigh)
      {
         e.state        = 2;
         e.target       = e.pl;
         e.mid          = (e.ph + e.pl) / 2.0;
         e.sweepTime    = r.time;
         e.sweepExtreme = r.high;
         e.confirmTime  = tClose;
         e.entryOpen    = true;
         e.id++;
         ev  = EV_BEAR;
         dir = 2;
      }
   }

   // =========================================================================
   // CRT ACTIVE
   // =========================================================================
   else
   {
      bool bull      = (e.state == 1);
      bool targetHit = bull ? r.high >= e.target : r.low <= e.target;
      bool invalid   = bull ? r.close < e.pl : r.close > e.ph;

      dir = e.state;

      if(targetHit)
      {
         SetParent(e, r);
         ev = EV_TARGET;
      }
      else if(invalid)
      {
         SetParent(e, r);
         ev = EV_INVALID;
      }
      else if(e.entryOpen && MidRetire(e, r.high, r.low))
      {
         e.entryOpen = false;
         ev = EV_MID;
      }
   }

   if(ev == EV_NONE)
      return EV_NONE;

   e.lastEvent     = ev;
   e.lastEventDir  = dir;
   e.lastEventTime = tClose;

   // TARGET / INVALID reset the engine: record the CRT that just closed.
   bool usePrev = (ev == EV_TARGET || ev == EV_INVALID);

   le.tf         = e.tf;
   le.ev         = ev;
   le.dir        = dir;
   le.evTime     = tClose;
   le.id         = usePrev ? prev.id         : e.id;
   le.state      = usePrev ? prev.state      : e.state;
   le.parentTime = usePrev ? prev.parentTime : e.parentTime;
   le.sweepTime  = usePrev ? prev.sweepTime  : e.sweepTime;
   le.ph         = usePrev ? prev.ph         : e.ph;
   le.pl         = usePrev ? prev.pl         : e.pl;
   le.mid        = usePrev ? prev.mid        : e.mid;
   le.target     = usePrev ? prev.target     : e.target;
   le.entryOpen  = usePrev ? false           : e.entryOpen;

   return ev;
}


// ============================================================================
// EVENT LEDGER
// ============================================================================

void TrimLedger()
{
   int n    = ArraySize(g_ledger);
   int keep = (int)MathMax(InpLedgerMax, 1);
   if(n <= keep)
      return;

   int drop = n - keep;
   for(int i = 0; i < keep; i++)
      g_ledger[i] = g_ledger[i + drop];
   ArrayResize(g_ledger, keep);
}

void AddLedger(const LedgerEvent &le)
{
   int n = ArraySize(g_ledger);
   ArrayResize(g_ledger, n + 1, 256);
   g_ledger[n] = le;

   // During warm-up every timeframe is replayed separately: keep all events,
   // sort them by time once warm-up is done, then trim.
   if(!g_warmup)
      TrimLedger();
}

// Stable insertion sort by event time.
void SortLedger()
{
   int n = ArraySize(g_ledger);
   for(int i = 1; i < n; i++)
   {
      LedgerEvent x = g_ledger[i];
      int j = i - 1;
      while(j >= 0 && g_ledger[j].evTime > x.evTime)
      {
         g_ledger[j + 1] = g_ledger[j];
         j--;
      }
      g_ledger[j + 1] = x;
   }
}

void OpenCsv()
{
   string fn = "CRT_ledger_" + _Symbol + ".csv";
   g_csv = FileOpen(fn, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ, ';');
   if(g_csv == INVALID_HANDLE)
   {
      Log("Cannot open " + fn + ", error " + IntegerToString(GetLastError()));
      return;
   }

   if(FileSize(g_csv) == 0)
      FileWrite(g_csv, "event_time", "tf", "id", "event", "dir", "parent_time", "sweep_time",
                "parent_high", "parent_low", "midpoint", "target", "entry");
   FileSeek(g_csv, 0, SEEK_END);
}

void WriteCsv(const LedgerEvent &le)
{
   if(g_csv == INVALID_HANDLE)
      return;

   FileWrite(g_csv,
             TimeToString(le.evTime, TIME_DATE | TIME_MINUTES),
             TfName(le.tf),
             le.id,
             EventText(le.ev),
             DirText(le.dir),
             TimeToString(le.parentTime, TIME_DATE | TIME_MINUTES),
             le.sweepTime > 0 ? TimeToString(le.sweepTime, TIME_DATE | TIME_MINUTES) : "",
             DoubleToString(le.ph, _Digits),
             DoubleToString(le.pl, _Digits),
             DoubleToString(le.mid, _Digits),
             le.target > 0.0 ? DoubleToString(le.target, _Digits) : "",
             EntryText(le.state, le.entryOpen));
   FileFlush(g_csv);
}


// ============================================================================
// DRAWING
// ============================================================================

bool DrawingOn()
{
   return InpDraw && !g_silent && !g_noChart;
}

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
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 7);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, above ? ANCHOR_LOWER : ANCHOR_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawSegment(string name, datetime t1, datetime t2, double price, color clr, int width, ENUM_LINE_STYLE style)
{
   if(!DrawingOn() || price <= 0.0)
      return;

   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price))
         return;
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   else
   {
      ObjectMove(0, name, 0, t1, price);
      ObjectMove(0, name, 1, t2, price);
   }
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

string CrtLineName(int id, string part)
{
   return OBJ_PFX + "C5_" + IntegerToString(id) + "_" + part;
}

void DrawCrtLevels(const CRTEngine &e, datetime tEnd)
{
   if(!DrawingOn())
      return;

   color tc = e.state == 1 ? clrLime : clrRed;
   DrawSegment(CrtLineName(e.id, "PH"),  e.parentTime,  tEnd, e.ph,     clrTomato,         1, STYLE_SOLID);
   DrawSegment(CrtLineName(e.id, "PL"),  e.parentTime,  tEnd, e.pl,     clrMediumSeaGreen, 1, STYLE_SOLID);
   DrawSegment(CrtLineName(e.id, "MID"), e.parentTime,  tEnd, e.mid,    clrGold,           1, STYLE_DOT);
   DrawSegment(CrtLineName(e.id, "TGT"), e.confirmTime, tEnd, e.target, tc,                2, STYLE_SOLID);
}

// Stop the lines of a finished CRT at the event time.
void FreezeCrtLines(int id, datetime tEnd)
{
   if(!DrawingOn())
      return;

   string parts[4] = {"PH", "PL", "MID", "TGT"};
   for(int i = 0; i < 4; i++)
   {
      string n = CrtLineName(id, parts[i]);
      if(ObjectFind(0, n) >= 0)
         ObjectMove(0, n, 1, tEnd, ObjectGetDouble(0, n, OBJPROP_PRICE, 1));
   }
}

void ExtendActiveDrawings()
{
   if(!DrawingOn() || g_drawnCrtId < 0)
      return;

   if(g_eng[g_entryIdx].state != 0 && g_eng[g_entryIdx].id == g_drawnCrtId)
      DrawCrtLevels(g_eng[g_entryIdx], TimeCurrent());
   else
      g_drawnCrtId = -1;
}


// ============================================================================
// TRADING HELPERS
// ============================================================================

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
   if(InpRiskMode == RISK_FIXED_LOTS)
      return NormalizeLots(MathMax(InpFixedLots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)));

   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double pnl = 0.0;
   ENUM_ORDER_TYPE type = dir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   // Money lost by 1 lot from entry to SL (includes contract size and tick value).
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

int TradesToday()
{
   datetime now      = TimeCurrent();
   datetime dayStart = (datetime)((long)now - (long)now % 86400);
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

bool InSession(datetime t)
{
   if(!InpUseSession)
      return true;

   MqlDateTime d;
   TimeToStruct(t, d);
   int m = d.hour * 60 + d.min;
   int s = InpSessStartHour * 60 + InpSessStartMin;
   int e = InpSessEndHour * 60 + InpSessEndMin;

   if(s == e)
      return true;
   if(s < e)
      return m >= s && m < e;
   return m >= s || m < e;   // session crosses midnight
}

void Skip(string reason)
{
   g_lastSkip = reason;
   Log("SKIP: " + reason);
}

bool CanOpen(int dir, string &reason)
{
   if(!InpTradeEnabled)
   {
      reason = "SIGNALS ONLY";
      return false;
   }
   if(!InSession(TimeCurrent()))
   {
      reason = "OUTSIDE SESSION";
      return false;
   }
   if(HasOpenPosition())
   {
      reason = "POSITION ALREADY OPEN";
      return false;
   }
   if(InpMaxTradesDay > 0 && TradesToday() >= InpMaxTradesDay)
   {
      reason = "MAX TRADES TODAY";
      return false;
   }
   if(InpMaxSpread > 0.0)
   {
      double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(spread > InpMaxSpread)
      {
         reason = "SPREAD " + DoubleToString(spread, _Digits);
         return false;
      }
   }
   if(InpBiasMode != BIAS_OFF && g_biasIdx >= 0)
   {
      int bs = g_eng[g_biasIdx].state;
      if(InpBiasMode == BIAS_NOT_AGAINST && bs != 0 && bs != dir)
      {
         reason = TfName(InpBiasTF) + " CRT AGAINST";
         return false;
      }
      if(InpBiasMode == BIAS_SAME_DIR && bs != dir)
      {
         reason = "NO " + TfName(InpBiasTF) + " CRT IN SAME DIRECTION";
         return false;
      }
   }
   return true;
}

// Market entry. slRef is the structure level the stop goes beyond;
// crtTarget is the 5M CRT target (used when TP = CRT target).
void ExecuteSignal(int dir, double slRef, double crtTarget, int crtId, string tag)
{
   string reason = "";
   if(!CanOpen(dir, reason))
   {
      Skip(reason);
      return;
   }

   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = dir == 1 ? ask : bid;
   if(entry <= 0.0 || slRef <= 0.0)
   {
      Skip("NO PRICE");
      return;
   }

   double sl   = NormPrice(dir == 1 ? slRef - InpSLBuffer : slRef + InpSLBuffer);
   double risk = dir == 1 ? entry - sl : sl - entry;
   if(risk <= 0.0)
   {
      Skip("SL ON THE WRONG SIDE OF PRICE");
      return;
   }

   // A stop only a few spreads wide pays most of the risk to the spread:
   // skip setups whose stop is too small for the costs.
   double minRisk = MathMax(InpMinSL, InpMinSLSpreadX * (ask - bid));
   if(risk < minRisk)
   {
      Skip(StringFormat("SL %s < MIN %s", DoubleToString(risk, _Digits), DoubleToString(minRisk, _Digits)));
      return;
   }

   double minDist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(risk < minDist)
   {
      Skip("SL TOO CLOSE");
      return;
   }

   double tp = InpTPMode == TP_CRT_TARGET ? crtTarget
             : dir == 1 ? entry + InpRMultiple * risk : entry - InpRMultiple * risk;
   tp = NormPrice(tp);

   double reward = dir == 1 ? tp - entry : entry - tp;
   if(reward <= 0.0)
   {
      Skip("TARGET ALREADY PASSED");
      return;
   }
   if(reward < minDist)
   {
      Skip("TP TOO CLOSE");
      return;
   }

   double rr = reward / risk;
   if(InpMinRR > 0.0 && rr < InpMinRR)
   {
      Skip(StringFormat("RR %.2f < %.2f", rr, InpMinRR));
      return;
   }

   double lots = CalcLots(dir, entry, sl);
   if(lots <= 0.0)
   {
      Skip("LOT SIZE BELOW BROKER MINIMUM");
      return;
   }

   string cmt = StringFormat("CRT %s #%d", tag, crtId);
   bool ok = dir == 1 ? g_trade.Buy(lots, _Symbol, entry, sl, tp, cmt)
                      : g_trade.Sell(lots, _Symbol, entry, sl, tp, cmt);
   uint rc = g_trade.ResultRetcode();
   if(!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_PLACED))
   {
      Skip(StringFormat("ORDER FAILED %u %s", rc, g_trade.ResultRetcodeDescription()));
      return;
   }

   g_lastSkip   = "-";
   g_tradeCrtId = crtId;

   // Planned risk at the real fill price: every exit is later measured against it.
   double fill = g_trade.ResultPrice() > 0.0 ? g_trade.ResultPrice() : entry;
   double pnlAtSl = 0.0;
   ENUM_ORDER_TYPE otype = dir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(OrderCalcProfit(otype, _Symbol, lots, fill, sl, pnlAtSl) && pnlAtSl < 0.0)
      SetPlannedRisk(g_trade.ResultOrder(), -pnlAtSl);
   string msg = StringFormat("%s %s %s lots | entry %s  SL %s  TP %s | RR %.2f | CRT #%d",
                             dir == 1 ? "BUY" : "SELL", tag, DoubleToString(lots, 2),
                             PriceText(entry), PriceText(sl), PriceText(tp), rr, crtId);
   Log(msg);
   Notify(_Symbol + " " + msg);
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

string DealReasonText(long reason)
{
   if(reason == DEAL_REASON_SL)
      return "SL";
   if(reason == DEAL_REASON_TP)
      return "TP";
   if(reason == DEAL_REASON_SO)
      return "STOP OUT";
   return "EA CLOSE";
}

void PrintTradeSummary()
{
   if(g_stN == 0)
   {
      Print("CRT SUMMARY: no closed trades");
      return;
   }
   int losses = g_stN - g_stWin;
   Print(StringFormat("CRT SUMMARY: %d trades | win %.1f%% | avg win %+.2fR | avg loss %+.2fR | worst %+.2fR | total %+.1fR",
                      g_stN, 100.0 * g_stWin / g_stN,
                      g_stWin > 0 ? g_stWinR / g_stWin : 0.0,
                      losses > 0 ? g_stLossR / losses : 0.0,
                      g_stWorstR, g_stWinR + g_stLossR));
   Print(StringFormat("CRT SUMMARY by exit: SL %d x %+.2fR | TP %d x %+.2fR | EA close %d x %+.2fR   (an exact stop fill is -1.00R)",
                      g_stSL, g_stSL > 0 ? g_stSLR / g_stSL : 0.0,
                      g_stTP, g_stTP > 0 ? g_stTPR / g_stTP : 0.0,
                      g_stOther, g_stOther > 0 ? g_stOtherR / g_stOther : 0.0));
}

void CloseOurPositions(string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(g_trade.PositionClose(ticket))
         Log("CLOSE: " + reason);
   }
}

void ManagePositions()
{
   bool closeOutside = InpUseSession && InpCloseOutside && !InSession(TimeCurrent());
   if(InpBreakEvenR <= 0.0 && !closeOutside)
      return;

   double minDist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      if(closeOutside)
      {
         g_trade.PositionClose(ticket);
         continue;
      }

      long   type = PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      if(sl <= 0.0)
         continue;

      if(type == POSITION_TYPE_BUY)
      {
         if(sl >= open)
            continue;   // already at break-even
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(bid - open >= InpBreakEvenR * (open - sl) && bid - open > minDist)
            g_trade.PositionModify(ticket, NormPrice(open), tp);
      }
      else if(type == POSITION_TYPE_SELL)
      {
         if(sl <= open)
            continue;
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(open - ask >= InpBreakEvenR * (sl - open) && open - ask > minDist)
            g_trade.PositionModify(ticket, NormPrice(open), tp);
      }
   }
}


// ============================================================================
// 1M MICRO ENGINE
// ============================================================================

void ResetMicro()
{
   g_micro.state         = MICRO_IDLE;
   g_micro.dir           = 0;
   g_micro.crtId         = -1;
   g_micro.bars          = 0;
   g_micro.crtPH         = 0.0;
   g_micro.crtPL         = 0.0;
   g_micro.crtMid        = 0.0;
   g_micro.crtTarget     = 0.0;
   g_micro.crtSweep      = 0.0;
   g_micro.sweepPrice    = 0.0;
   g_micro.sweepTime     = 0;
   g_micro.mssPrice      = 0.0;
   g_micro.mssTime       = 0;
   g_micro.fvgTop        = 0.0;
   g_micro.fvgBottom     = 0.0;
   g_micro.fvgTime       = 0;
   g_micro.entryPrice    = 0.0;
   g_micro.entryTime     = 0;
   g_micro.lastEventTime = 0;
   g_microEvent          = "IDLE";
}

void MicroMark(string text, datetime t, double price, color clr, bool above)
{
   g_microEvent          = text;
   g_micro.lastEventTime = t;
   DrawLabel(t, price, "1M " + text, clr, above);
   if(InpVerbose)
      Log(StringFormat("[1M] CRT #%d %s | %s @ %s", g_micro.crtId, DirText(g_micro.dir), text, TimeText(t)));
}

bool MicroActive()
{
   return g_micro.state >= MICRO_WAIT && g_micro.state <= MICRO_FVG;
}

// A new 5M CRT starts a completely new 1M micro sequence.
void ArmMicro(const CRTEngine &e)
{
   ResetMicro();
   g_micro.state     = MICRO_WAIT;
   g_micro.dir       = e.state;
   g_micro.crtId     = e.id;
   g_micro.crtPH     = e.ph;
   g_micro.crtPL     = e.pl;
   g_micro.crtMid    = e.mid;
   g_micro.crtTarget = e.target;
   g_micro.crtSweep  = e.sweepExtreme;
   MicroMark("CRT CONFIRMED", e.confirmTime, 0.0, clrWhite, true);
}

void CancelMicro(string reason, datetime t)
{
   if(!MicroActive())
      return;
   g_micro.state = MICRO_DONE;
   MicroMark(reason, t, 0.0, clrGray, true);
}

double MaxLast(const double &a[], int n)
{
   int sz   = ArraySize(a);
   int from = (int)MathMax(0, sz - n);
   double m = -DBL_MAX;
   for(int i = from; i < sz; i++)
      if(a[i] > m)
         m = a[i];
   return m;
}

double MinLast(const double &a[], int n)
{
   int sz   = ArraySize(a);
   int from = (int)MathMax(0, sz - n);
   double m = DBL_MAX;
   for(int i = from; i < sz; i++)
      if(a[i] < m)
         m = a[i];
   return m;
}

void PushHistory(double h, double l)
{
   int sz = ArraySize(g_hHigh);
   if(sz < g_histMax)
   {
      ArrayResize(g_hHigh, sz + 1);
      ArrayResize(g_hLow, sz + 1);
      g_hHigh[sz] = h;
      g_hLow[sz]  = l;
      return;
   }
   for(int i = 1; i < sz; i++)
   {
      g_hHigh[i - 1] = g_hHigh[i];
      g_hLow[i - 1]  = g_hLow[i];
   }
   g_hHigh[sz - 1] = h;
   g_hLow[sz - 1]  = l;
}

double MicroSlRef()
{
   if(InpSLMode == SL_CRT_SWEEP)
      return g_micro.crtSweep;
   if(InpSLMode == SL_FVG)
      return g_micro.dir == 1 ? g_micro.fvgBottom : g_micro.fvgTop;
   return g_micro.sweepPrice;
}

// Processes one closed 1M bar. The history arrays hold the bars BEFORE b.
void MicroStep(const MqlRates &b, bool latest)
{
   if(!MicroActive())
      return;

   int d  = g_micro.dir;
   int hs = ArraySize(g_hHigh);
   g_micro.bars++;

   // ------------------------------------------------------------------------
   // GUARDS: the 5M move must not be done yet.
   // ------------------------------------------------------------------------
   bool targetHit = d == 1 ? b.high >= g_micro.crtTarget : b.low <= g_micro.crtTarget;
   if(targetHit)
   {
      CancelMicro("TARGET BEFORE ENTRY", b.time);
      return;
   }

   if(InpMidRule == MID_TOWARD_TARGET)
   {
      bool midHit = d == 1 ? b.high >= g_micro.crtMid : b.low <= g_micro.crtMid;
      if(midHit)
      {
         CancelMicro("50% REACHED BEFORE ENTRY", b.time);
         return;
      }
   }

   switch(g_micro.state)
   {
      // ======================================================================
      // LOOK FOR LIQUIDITY SWEEP
      // ======================================================================
      case MICRO_WAIT:
      {
         if(hs < InpSweepLookback)
            break;

         double prevLow  = MinLast(g_hLow, InpSweepLookback);
         double prevHigh = MaxLast(g_hHigh, InpSweepLookback);

         // Bullish: low takes the recent lows and closes back above them.
         if(d == 1 && b.low <= prevLow && b.close > prevLow)
         {
            g_micro.state      = MICRO_SWEEP;
            g_micro.sweepPrice = b.low;
            g_micro.sweepTime  = b.time;
            MicroMark("LOW SWEEP", b.time, b.low, clrLime, false);
         }
         // Bearish: high takes the recent highs and closes back below them.
         else if(d == 2 && b.high >= prevHigh && b.close < prevHigh)
         {
            g_micro.state      = MICRO_SWEEP;
            g_micro.sweepPrice = b.high;
            g_micro.sweepTime  = b.time;
            MicroMark("HIGH SWEEP", b.time, b.high, clrRed, true);
         }
         break;
      }

      // ======================================================================
      // LOOK FOR MSS
      // ======================================================================
      case MICRO_SWEEP:
      {
         // Keep the stop reference at the deepest point of the sweep.
         if(d == 1 && b.low < g_micro.sweepPrice)
            g_micro.sweepPrice = b.low;
         if(d == 2 && b.high > g_micro.sweepPrice)
            g_micro.sweepPrice = b.high;

         if(hs < InpMssLookback)
            break;

         double refHigh = MaxLast(g_hHigh, InpMssLookback);
         double refLow  = MinLast(g_hLow, InpMssLookback);

         if(d == 1 && b.close > refHigh)
         {
            g_micro.state    = MICRO_MSS;
            g_micro.mssPrice = b.close;
            g_micro.mssTime  = b.time;
            MicroMark("BULL MSS", b.time, b.low, clrLime, false);
         }
         else if(d == 2 && b.close < refLow)
         {
            g_micro.state    = MICRO_MSS;
            g_micro.mssPrice = b.close;
            g_micro.mssTime  = b.time;
            MicroMark("BEAR MSS", b.time, b.high, clrRed, true);
         }
         break;
      }

      // ======================================================================
      // LOOK FOR FVG (candles i-2, i-1, i)
      // ======================================================================
      case MICRO_MSS:
      {
         if(hs < 2)
            break;

         double high2  = g_hHigh[hs - 2];
         double low2   = g_hLow[hs - 2];
         double tick   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double minGap = InpMinFvgTicks * (tick > 0.0 ? tick : _Point);

         // Bullish FVG: current low above the high two candles back.
         if(d == 1 && b.low - high2 >= minGap)
         {
            g_micro.state     = MICRO_FVG;
            g_micro.fvgBottom = high2;
            g_micro.fvgTop    = b.low;
            g_micro.fvgTime   = b.time;
            DrawBox(b.time - 120, b.time + 600, g_micro.fvgBottom, g_micro.fvgTop, clrDarkGreen);
            MicroMark("BULL FVG", b.time, g_micro.fvgBottom, clrLime, false);
         }
         // Bearish FVG: current high below the low two candles back.
         else if(d == 2 && low2 - b.high >= minGap)
         {
            g_micro.state     = MICRO_FVG;
            g_micro.fvgTop    = low2;
            g_micro.fvgBottom = b.high;
            g_micro.fvgTime   = b.time;
            DrawBox(b.time - 120, b.time + 600, g_micro.fvgBottom, g_micro.fvgTop, clrMaroon);
            MicroMark("BEAR FVG", b.time, g_micro.fvgTop, clrRed, true);
         }
         break;
      }

      // ======================================================================
      // LOOK FOR FVG RETEST
      // ======================================================================
      case MICRO_FVG:
      {
         bool failed = d == 1 ? b.close < g_micro.fvgBottom : b.close > g_micro.fvgTop;
         if(InpCancelOnFvgFail && failed)
         {
            CancelMicro("FVG FAILED", b.time);
            return;
         }

         // Price trades back into the gap and closes on the right side of it.
         bool retest = d == 1 ? (b.low <= g_micro.fvgTop && b.close >= g_micro.fvgBottom)
                              : (b.high >= g_micro.fvgBottom && b.close <= g_micro.fvgTop);
         if(!retest)
            break;

         g_micro.state      = MICRO_DONE;
         g_micro.entryPrice = b.close;
         g_micro.entryTime  = b.time;

         if(d == 1)
            MicroMark("BUY ENTRY", b.time, b.low, clrAqua, false);
         else
            MicroMark("SELL ENTRY", b.time, b.high, clrMagenta, true);

         if(latest)
            ExecuteSignal(d, MicroSlRef(), g_micro.crtTarget, g_micro.crtId, "1M");
         else
            Skip("STALE SIGNAL (catch-up bar)");
         return;
      }

      default:
         break;
   }

   // ------------------------------------------------------------------------
   // MICRO TIMEOUT
   // ------------------------------------------------------------------------
   if(MicroActive() && g_micro.bars >= InpMicroMaxBars)
      CancelMicro("MICRO EXPIRED", b.time);
}


// ============================================================================
// ENGINE EVENTS
// ============================================================================

// Sweep depth beyond the parent range, as a share of the range.
bool SweepDeepEnough(const CRTEngine &e)
{
   if(InpMinSweepPct <= 0.0)
      return true;

   double range = e.ph - e.pl;
   if(range <= 0.0)
      return false;

   double depth = e.state == 1 ? e.pl - e.sweepExtreme : e.sweepExtreme - e.ph;
   return depth >= range * InpMinSweepPct / 100.0;
}

void OnEngineEvent(int k, int ev, const LedgerEvent &le, const MqlRates &bar, bool latest)
{
   AddLedger(le);
   if(g_warmup)
      return;

   WriteCsv(le);

   if(k != g_entryIdx)
      return;

   string tfTxt = TfName(g_eng[k].tf);

   switch(ev)
   {
      case EV_BULL:
      case EV_BEAR:
      {
         int d = ev == EV_BULL ? 1 : 2;
         DrawLabel(bar.time, d == 1 ? bar.low : bar.high, tfTxt + " " + EventText(ev), d == 1 ? clrLime : clrRed, d == 2);
         g_drawnCrtId = g_eng[k].id;
         DrawCrtLevels(g_eng[k], le.evTime);
         Notify(StringFormat("%s %s %s confirmed | target %s", _Symbol, tfTxt, EventText(ev), PriceText(le.target)));

         // A sweep of a few cents is noise, not a liquidity grab.
         if(!SweepDeepEnough(g_eng[k]))
         {
            Skip(StringFormat("SHALLOW SWEEP (CRT #%d)", g_eng[k].id));
            break;
         }

         if(InpEntryMode == ENTRY_MICRO_1M)
            ArmMicro(g_eng[k]);
         else if(latest)
            ExecuteSignal(d, g_eng[k].sweepExtreme, g_eng[k].target, g_eng[k].id, tfTxt);
         else
            Skip("STALE SIGNAL (catch-up bar)");
         break;
      }

      case EV_TARGET:
      case EV_INVALID:
      case EV_MID:
      {
         color c = ev == EV_TARGET ? clrDodgerBlue : ev == EV_INVALID ? clrOrange : clrSilver;
         DrawLabel(bar.time, le.dir == 1 ? bar.high : bar.low, tfTxt + " " + EventText(ev), c, le.dir == 1);

         if(le.id == g_micro.crtId)
            CancelMicro(tfTxt + " " + EventText(ev), le.evTime);

         // The setup behind the open trade is dead: get out at market.
         if(ev == EV_INVALID && InpCloseOnInvalid && le.id == g_tradeCrtId)
            CloseOurPositions(StringFormat("%s CRT #%d INVALIDATED", tfTxt, le.id));

         if(ev != EV_MID && le.id == g_drawnCrtId)
         {
            FreezeCrtLines(le.id, le.evTime);
            g_drawnCrtId = -1;
         }
         break;
      }

      default:
         break;
   }
}

// Copies the bars of 'tf' that opened after 'after' and are closed by 'closedBy'.
int CopyClosedBars(ENUM_TIMEFRAMES tf, datetime after, datetime closedBy, MqlRates &out[])
{
   ArrayFree(out);
   datetime lastOpen = closedBy - PeriodSeconds(tf);
   if(lastOpen <= after)
      return 0;
   return CopyRates(_Symbol, tf, after + 1, lastOpen, out);
}

void AdvanceEngine(int k, datetime closedBy, bool latest)
{
   MqlRates r[];
   int n = CopyClosedBars(g_eng[k].tf, g_eng[k].lastBarTime, closedBy, r);
   for(int j = 0; j < n; j++)
   {
      if(r[j].time <= g_eng[k].lastBarTime)
         continue;

      LedgerEvent le;
      int ev = EngineStep(g_eng[k], r[j], le);
      g_eng[k].lastBarTime = r[j].time;
      if(ev != EV_NONE)
         OnEngineEvent(k, ev, le, r[j], latest && j == n - 1);
   }
}

void AdvanceAll(datetime closedBy, bool latest)
{
   for(int k = 0; k < ENG_COUNT; k++)
      AdvanceEngine(k, closedBy, latest);
}

// Replays every new closed 1M bar in order. Before each 1M bar the engines
// get every higher-timeframe bar that closed before that 1M bar opened.
void ProcessNewBars(datetime m1Open)
{
   MqlRates m1[];
   int n = CopyClosedBars(PERIOD_M1, g_lastM1Time, m1Open, m1);
   if(n < 0)
      return;   // 1M data not ready: engines wait so the order stays intact

   for(int i = 0; i < n; i++)
   {
      if(m1[i].time <= g_lastM1Time)
         continue;
      AdvanceAll(m1[i].time, false);
      MicroStep(m1[i], i == n - 1);
      PushHistory(m1[i].high, m1[i].low);
      g_lastM1Time = m1[i].time;
   }

   // Bars that closed right now (e.g. the 5M bar ending at this minute).
   AdvanceAll(m1Open, true);
}


// ============================================================================
// WARM-UP
// ============================================================================

bool InitEngines()
{
   // Rolling 1M history.
   MqlRates m1[];
   int got = CopyRates(_Symbol, PERIOD_M1, 1, g_histMax, m1);
   if(got < g_histMax)
      return false;

   ArrayResize(g_hHigh, 0);
   ArrayResize(g_hLow, 0);
   for(int i = 0; i < got; i++)
      PushHistory(m1[i].high, m1[i].low);
   g_lastM1Time = m1[got - 1].time;
   datetime closedBy = g_lastM1Time + 60;

   // Replay recent history through every CRT engine.
   ArrayResize(g_ledger, 0);
   g_warmup = true;
   bool ok  = true;

   for(int k = 0; k < ENG_COUNT; k++)
   {
      ResetEngine(g_eng[k], g_tfs[k]);

      int want = (int)MathMin(InpWarmupBars, Bars(_Symbol, g_tfs[k]) - 1);
      if(want > 0)
      {
         MqlRates r[];
         int c = CopyRates(_Symbol, g_tfs[k], 1, want, r);
         if(c < 0)
         {
            ok = false;   // not synchronized yet
            break;
         }

         for(int j = 0; j < c; j++)
         {
            if(r[j].time + PeriodSeconds(g_tfs[k]) > closedBy)
               break;

            LedgerEvent le;
            int ev = EngineStep(g_eng[k], r[j], le);
            g_eng[k].lastBarTime = r[j].time;
            if(ev != EV_NONE)
               OnEngineEvent(k, ev, le, r[j], false);
         }
      }

      // Short history (e.g. W1 at the start of a test): start from the
      // forming bar instead of replaying everything since 1970.
      if(g_eng[k].lastBarTime == 0)
      {
         datetime cur = iTime(_Symbol, g_tfs[k], 0);
         if(cur <= 0)
         {
            ok = false;
            break;
         }
         g_eng[k].lastBarTime = cur - 1;
      }
   }

   g_warmup = false;

   if(!ok)
   {
      ArrayResize(g_ledger, 0);
      return false;   // history not loaded yet: retried on the next tick
   }

   SortLedger();
   TrimLedger();
   ResetMicro();
   g_lastM1Open = iTime(_Symbol, PERIOD_M1, 0);

   Log(StringFormat("CRT MTF EA ready on %s | %d warm-up events | entry engine: %s",
                    _Symbol, ArraySize(g_ledger), StateText(g_eng[g_entryIdx].state)));
   return true;
}


// ============================================================================
// PANEL
// ============================================================================

void UpdatePanel()
{
   if(!InpShowPanel || g_silent || g_noChart)
      return;

   string s = "CRT MTF EA v1.25  |  " + _Symbol + "  |  magic " + IntegerToString((long)InpMagic) +
              "  |  " + (InpTradeEnabled ? "TRADING ON" : "SIGNALS ONLY") +
              "  |  entry: " + TfName(InpEntryTF) + (InpEntryMode == ENTRY_MICRO_1M ? " CRT + 1M MICRO" : " CRT CLOSE");

   s += "\n\nTF      ID       CRT             LAST EVENT       ENTRY        TARGET        50%";
   for(int i = 0; i < ENG_COUNT; i++)
   {
      bool active = g_eng[i].state != 0;
      s += StringFormat("\n%-7s %-8d %-15s %-16s %-12s %-13s %s",
                        TfName(g_eng[i].tf),
                        g_eng[i].id,
                        StateText(g_eng[i].state),
                        EventText(g_eng[i].lastEvent),
                        EntryText(g_eng[i].state, g_eng[i].entryOpen),
                        active ? PriceText(g_eng[i].target) : "-",
                        active ? PriceText(g_eng[i].mid) : "-");
   }

   s += StringFormat("\n\n1M MICRO  |  CRT #%d %s  |  %s  |  last: %s @ %s  |  bars %d/%d",
                     g_micro.crtId, DirText(g_micro.dir), MicroStateText(g_micro.state),
                     g_microEvent, TimeText(g_micro.lastEventTime), g_micro.bars, InpMicroMaxBars);
   s += "\nSweep " + PriceText(g_micro.sweepPrice) +
        "   MSS " + PriceText(g_micro.mssPrice) +
        "   FVG " + (g_micro.fvgTop > 0.0 ? PriceText(g_micro.fvgBottom) + " - " + PriceText(g_micro.fvgTop) : "-") +
        "   Entry " + PriceText(g_micro.entryPrice);

   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   string sessTxt = !InpUseSession ? "OFF (24h)"
                  : StringFormat("%s %02d:%02d-%02d:%02d", InSession(TimeCurrent()) ? "IN" : "OUT",
                                 InpSessStartHour, InpSessStartMin, InpSessEndHour, InpSessEndMin);
   s += StringFormat("\nTrades today %d/%s  |  spread %s  |  session %s  |  last skip: %s",
                     TradesToday(), InpMaxTradesDay > 0 ? IntegerToString(InpMaxTradesDay) : "NO LIMIT",
                     DoubleToString(spread, _Digits), sessTxt, g_lastSkip);

   s += "\n\nEVENT LEDGER (newest first)";
   int n    = ArraySize(g_ledger);
   int rows = (int)MathMin(InpLedgerRows, n);
   for(int r = 0; r < rows; r++)
   {
      LedgerEvent le = g_ledger[n - 1 - r];
      s += StringFormat("\n#%-3d %-4s id %-7d %-13s %-5s %s   parent %s   sweep %s   tgt %s   %s",
                        r + 1, TfName(le.tf), le.id, EventText(le.ev), DirText(le.dir),
                        TimeText(le.evTime), TimeText(le.parentTime), TimeText(le.sweepTime),
                        PriceText(le.target), EntryText(le.state, le.entryOpen));
   }

   Comment(s);
}


// ============================================================================
// EVENT HANDLERS
// ============================================================================

int OnInit()
{
   if(InpSweepLookback < 1 || InpMssLookback < 1 || InpMicroMaxBars < 1 || InpWarmupBars < 10)
   {
      Print("Invalid micro-engine / warm-up inputs");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpRiskMode == RISK_PERCENT && (InpRiskPercent <= 0.0 || InpRiskPercent > 10.0))
   {
      Print("Risk per trade must be between 0 and 10%");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpSessStartHour < 0 || InpSessStartHour > 23 || InpSessEndHour < 0 || InpSessEndHour > 23 ||
      InpSessStartMin < 0 || InpSessStartMin > 59 || InpSessEndMin < 0 || InpSessEndMin > 59)
   {
      Print("Invalid session time");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_biasIdx = -1;
   if(InpBiasMode != BIAS_OFF)
   {
      for(int i = 0; i < ENG_COUNT; i++)
         if(g_tfs[i] == InpBiasTF)
            g_biasIdx = i;
   }

   g_entryIdx = -1;
   for(int i = 2; i < ENG_COUNT; i++)
      if(g_tfs[i] == InpEntryTF)
         g_entryIdx = i;
   if(g_entryIdx < 0)
   {
      Print("Entry timeframe must be H4, H1, M30, M15 or M5");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpBiasMode != BIAS_OFF && (g_biasIdx < 0 || g_biasIdx >= g_entryIdx))
   {
      Print("HTF bias timeframe must be higher than the entry timeframe");
      return INIT_PARAMETERS_INCORRECT;
   }
   // In an optimization the bias timeframe does nothing while the bias is
   // off: run that case once (with H1) instead of once per timeframe.
   if(MQLInfoInteger(MQL_OPTIMIZATION) && InpBiasMode == BIAS_OFF && InpBiasTF != PERIOD_H1)
      return INIT_PARAMETERS_INCORRECT;

   g_silent  = (bool)MQLInfoInteger(MQL_OPTIMIZATION);
   g_noChart = (bool)MQLInfoInteger(MQL_TESTER) && !(bool)MQLInfoInteger(MQL_VISUAL_MODE);

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints((ulong)InpSlippagePts);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   // FVG needs the two previous bars; lookbacks need their own window.
   g_histMax = (int)MathMax(MathMax(InpSweepLookback, InpMssLookback), 2);

   for(int i = 0; i < ENG_COUNT; i++)
      ResetEngine(g_eng[i], g_tfs[i]);
   ResetMicro();
   ArrayResize(g_ledger, 0);
   g_drawnCrtId = -1;
   g_lastSkip   = "-";

   if(!g_silent && !g_noChart)
      ObjectsDeleteAll(0, OBJ_PFX);

   if(InpLedgerCSV && !g_silent)
      OpenCsv();

   // If history is not loaded yet, OnTick retries.
   // The tester keeps input values from earlier runs: print what is really used.
   Log(StringFormat("CRT MTF EA v1.25 | entry %s %s | risk %.2f%% | max trades/day %s | session %s | "
                    "min SL %.2f / %.1fx spread | min sweep %.0f%% | min RR %.2f | 50%% rule %s",
                    TfName(InpEntryTF), InpEntryMode == ENTRY_MICRO_1M ? "+1M micro" : "CRT close",
                    InpRiskPercent, InpMaxTradesDay > 0 ? IntegerToString(InpMaxTradesDay) : "NO LIMIT",
                    InpUseSession ? StringFormat("%02d:%02d-%02d:%02d", InpSessStartHour, InpSessStartMin,
                                                 InpSessEndHour, InpSessEndMin) : "OFF",
                    InpMinSL, InpMinSLSpreadX, InpMinSweepPct, InpMinRR, EnumToString(InpMidRule)));

   g_ready = InitEngines();
   if(g_ready)
      UpdatePanel();

   return INIT_SUCCEEDED;
}

// Optimization criterion ("Custom max"): profit factor, but only for runs
// with enough trades to mean something (also applied to the forward part).
double OnTester()
{
   double trades = TesterStatistics(STAT_TRADES);
   if(trades < InpOptMinTrades)
      return 0.0;
   return TesterStatistics(STAT_PROFIT_FACTOR);
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

   // Entry deal: keep its commission so the trade result includes both sides.
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

   Log(StringFormat("CLOSE pos %s | %s | %s %s | %+.2fR",
                    IntegerToString((long)posId), DealReasonText(reason),
                    money >= 0.0 ? "+" : "-", DoubleToString(MathAbs(money), 2), r));
}

void OnDeinit(const int reason)
{
   PrintTradeSummary();

   if(g_csv != INVALID_HANDLE)
   {
      FileClose(g_csv);
      g_csv = INVALID_HANDLE;
   }
   Comment("");

   // Keep the drawings on the tester chart so the run can be inspected.
   if(!MQLInfoInteger(MQL_TESTER))
      ObjectsDeleteAll(0, OBJ_PFX);
}

void OnTick()
{
   if(!g_ready)
   {
      g_ready = InitEngines();
      if(!g_ready)
         return;
   }

   ManagePositions();

   // Everything else runs once per closed 1M bar.
   datetime m1Open = iTime(_Symbol, PERIOD_M1, 0);
   if(m1Open <= 0 || m1Open == g_lastM1Open)
      return;
   g_lastM1Open = m1Open;

   ProcessNewBars(m1Open);
   ExtendActiveDrawings();
   UpdatePanel();
}
//+------------------------------------------------------------------+
