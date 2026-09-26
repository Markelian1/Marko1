//+------------------------------------------------------------------+
//|                                       XAUUSD_SessionScanner.mq5  |
//|   24/5 scan of the opening-range breakout and its reversal.     |
//|   ANALYSIS TOOL -- it never trades.                              |
//|                                                                  |
//|   Every InpSlotStep minutes of the day a "session" starts:       |
//|     range     = first InpRangeMinutes minutes (M1 highs/lows),   |
//|     breakout  = first M1 close beyond the range within           |
//|                 InpBreakoutWindow minutes after the range,       |
//|                 SL at the far side, TP rr x width beyond it,     |
//|     reversal  = after that breakout is stopped out (within       |
//|                 InpReversalWindow minutes after the range),      |
//|                 enter the other way at the stop level, SL at the |
//|                 far side, TP rr x width beyond the range,        |
//|     flatten   = InpHoldMinutes after the range ends.             |
//|   The NY defaults of the Reverse Hunter (range 16:30-17:00,      |
//|   breakout until 18:30, reversal until 20:00, flat 23:00) are    |
//|   the slot starting at 16:30 with the default windows.           |
//|                                                                  |
//|   Bars are processed on M1 close, SL before TP when both are hit |
//|   inside one bar (conservative). Prices are bid; the bar spread  |
//|   at entry is recorded so costs can be deducted in the analysis. |
//|   Output: <prefix>_slots.csv in Terminal\Common\Files.           |
//|   Run it in the Strategy Tester, "1 minute OHLC" is enough.      |
//+------------------------------------------------------------------+
#property copyright "Roboquant AI"
#property version   "1.00"
#property strict

input int    InpSlotStep        = 30;    // Minutes between session starts
input int    InpRangeMinutes    = 30;    // Opening range length (min)
input int    InpBreakoutWindow  = 90;    // Breakout allowed for N min after the range
input int    InpReversalWindow  = 180;   // Reversal allowed for N min after the range
input int    InpHoldMinutes     = 360;   // Flatten N min after the range
input double InpRrTarget        = 2.0;   // Target (x range width beyond the range)
input int    InpMinRangeBars    = 20;    // Skip ranges with fewer M1 bars (market closed)
input string InpFilePrefix      = "SCAN"; // File name prefix (Terminal\Common\Files)

struct Slot
{
   bool     active;
   int      state;        // 1 range, 2 wait breakout, 3 breakout open, 4 reversal open, 5 done
   datetime start;
   datetime rangeEnd;
   datetime boDeadline;
   datetime rvDeadline;
   datetime flatTime;
   int      bars;
   double   hi;
   double   lo;
   double   spread;       // price units, at the breakout entry bar
   int      boDir;
   int      boMin;        // minutes after the range end
   double   boEntry;
   double   boSL;
   double   boTP;
   double   boExit;
   string   boOut;
   int      rvDir;
   double   rvEntry;
   double   rvSL;
   double   rvTP;
   double   rvExit;
   string   rvOut;
};

Slot     g_s[];
int      g_file      = INVALID_HANDLE;
datetime g_lastBar   = 0;
double   g_lastClose = 0.0;
long     g_rows      = 0;

void ResetSlot(Slot &s)
{
   s.active = false;  s.state = 0;
   s.start = 0;       s.rangeEnd = 0;  s.boDeadline = 0;  s.rvDeadline = 0;  s.flatTime = 0;
   s.bars = 0;        s.hi = 0.0;      s.lo = 0.0;        s.spread = 0.0;
   s.boDir = 0;       s.boMin = 0;     s.boEntry = 0.0;   s.boSL = 0.0;  s.boTP = 0.0;  s.boExit = 0.0;  s.boOut = "-";
   s.rvDir = 0;       s.rvEntry = 0.0; s.rvSL = 0.0;      s.rvTP = 0.0;  s.rvExit = 0.0; s.rvOut = "-";
}

string Px(const double v)  { return DoubleToString(v, _Digits); }
string Num(const double v) { return DoubleToString(v, 3); }

string WeekdayName(const datetime when)
{
   MqlDateTime d;
   TimeToStruct(when, d);
   string names[] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
   return names[d.day_of_week];
}

//--- Write the session row and free the slot
void FinishSlot(Slot &s)
{
   if(!s.active) return;

   if(s.state == 3) { s.boExit = g_lastClose; s.boOut = "FLAT"; }
   if(s.state == 4) { s.rvExit = g_lastClose; s.rvOut = "FLAT"; }

   if(s.bars >= InpMinRangeBars && s.hi > s.lo)
   {
      double boRisk = MathAbs(s.boEntry - s.boSL);
      double boR    = (s.boDir != 0 && boRisk > 0.0) ? s.boDir * (s.boExit - s.boEntry) / boRisk : 0.0;
      double rvRisk = MathAbs(s.rvEntry - s.rvSL);
      double rvR    = (s.rvDir != 0 && rvRisk > 0.0) ? s.rvDir * (s.rvExit - s.rvEntry) / rvRisk : 0.0;

      FileWrite(g_file,
                TimeToString(s.start, TIME_DATE), TimeToString(s.start, TIME_MINUTES),
                WeekdayName(s.start), Px(s.hi - s.lo), Px(s.spread),
                (s.boDir == 1 ? "LONG" : (s.boDir == -1 ? "SHORT" : "-")),
                IntegerToString(s.boMin), Px(s.boEntry), Px(boRisk), s.boOut, Num(boR),
                (s.rvDir == 1 ? "LONG" : (s.rvDir == -1 ? "SHORT" : "-")),
                Px(rvRisk), s.rvOut, Num(rvR));
      g_rows++;
   }
   ResetSlot(s);
}

void StartSlot(Slot &s, const datetime t)
{
   ResetSlot(s);
   s.active     = true;
   s.state      = 1;
   s.start      = t;
   s.rangeEnd   = t + InpRangeMinutes * 60;
   s.boDeadline = s.rangeEnd + InpBreakoutWindow * 60;
   s.rvDeadline = s.rangeEnd + InpReversalWindow * 60;
   s.flatTime   = s.rangeEnd + InpHoldMinutes * 60;
}

//--- Advance one slot by one closed M1 bar
void ProcessSlot(Slot &s, const int k, const MqlRates &r, const int minuteOfDay)
{
   if(s.active && r.time >= s.flatTime) FinishSlot(s);
   if(minuteOfDay == k * InpSlotStep)
   {
      FinishSlot(s);
      StartSlot(s, r.time);
   }
   if(!s.active) return;

   // ---- build the range ----
   if(r.time < s.rangeEnd)
   {
      if(s.bars == 0) { s.hi = r.high; s.lo = r.low; }
      else
      {
         if(r.high > s.hi) s.hi = r.high;
         if(r.low  < s.lo) s.lo = r.low;
      }
      s.bars++;
      return;
   }

   double w = s.hi - s.lo;
   if(s.state == 1) s.state = 2;
   if(w <= 0.0 || s.bars < InpMinRangeBars) { s.state = 5; return; }

   // ---- wait for the breakout (entry at the closing price of the bar) ----
   if(s.state == 2)
   {
      if(r.time >= s.boDeadline) { s.state = 5; return; }
      if(r.close > s.hi)
      {
         s.boDir = 1;  s.boEntry = r.close;  s.boSL = s.lo;  s.boTP = s.hi + InpRrTarget * w;
      }
      else if(r.close < s.lo)
      {
         s.boDir = -1; s.boEntry = r.close;  s.boSL = s.hi;  s.boTP = s.lo - InpRrTarget * w;
      }
      else return;
      s.boMin  = (int)((r.time - s.rangeEnd) / 60);
      s.spread = r.spread * _Point;
      s.state  = 3;
      return;
   }

   // ---- breakout open: SL first, then TP ----
   if(s.state == 3)
   {
      bool sl = (s.boDir == 1) ? (r.low <= s.boSL)  : (r.high >= s.boSL);
      bool tp = (s.boDir == 1) ? (r.high >= s.boTP) : (r.low <= s.boTP);
      if(sl)
      {
         s.boExit = s.boSL;  s.boOut = "SL";
         if(r.time < s.rvDeadline)
         {
            s.rvDir   = -s.boDir;
            s.rvEntry = s.boSL;                                   // enter at the failed stop
            s.rvSL    = (s.rvDir == 1) ? s.lo : s.hi;
            s.rvTP    = (s.rvDir == 1) ? s.hi + InpRrTarget * w : s.lo - InpRrTarget * w;
            s.state   = 4;
         }
         else s.state = 5;
      }
      else if(tp) { s.boExit = s.boTP; s.boOut = "TP"; s.state = 5; }
      return;
   }

   // ---- reversal open: SL first, then TP ----
   if(s.state == 4)
   {
      bool sl = (s.rvDir == 1) ? (r.low <= s.rvSL)  : (r.high >= s.rvSL);
      bool tp = (s.rvDir == 1) ? (r.high >= s.rvTP) : (r.low <= s.rvTP);
      if(sl)      { s.rvExit = s.rvSL; s.rvOut = "SL"; s.state = 5; }
      else if(tp) { s.rvExit = s.rvTP; s.rvOut = "TP"; s.state = 5; }
   }
}

int OnInit()
{
   if(InpSlotStep < 5 || 1440 % InpSlotStep != 0 || InpRangeMinutes < 5 ||
      InpBreakoutWindow < 1 || InpReversalWindow < InpBreakoutWindow || InpHoldMinutes < InpReversalWindow)
   {
      Print("Invalid scanner settings.");
      return INIT_PARAMETERS_INCORRECT;
   }

   int n = 1440 / InpSlotStep;
   ArrayResize(g_s, n);
   for(int k = 0; k < n; k++) ResetSlot(g_s[k]);

   string name = InpFilePrefix + "_slots.csv";
   g_file = FileOpen(name, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
   if(g_file == INVALID_HANDLE)
   {
      PrintFormat("Could not open %s (error %d)", name, GetLastError());
      return INIT_FAILED;
   }
   FileWrite(g_file, "date", "slot", "weekday", "width", "spread",
             "bo_dir", "bo_min", "bo_entry", "bo_risk", "bo_out", "bo_R",
             "rv_dir", "rv_risk", "rv_out", "rv_R");

   g_lastBar   = 0;
   g_lastClose = 0.0;
   g_rows      = 0;
   PrintFormat("Session scanner: %d slots every %d min | range %d | breakout %d | reversal %d | hold %d | rr %.2f",
               n, InpSlotStep, InpRangeMinutes, InpBreakoutWindow, InpReversalWindow, InpHoldMinutes, InpRrTarget);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_file == INVALID_HANDLE) return;
   for(int k = 0; k < ArraySize(g_s); k++) FinishSlot(g_s[k]);
   FileClose(g_file);
   g_file = INVALID_HANDLE;
   PrintFormat("Session scanner finished: %I64d rows in %s_slots.csv (Terminal\\Common\\Files)", g_rows, InpFilePrefix);
}

void OnTick()
{
   datetime t0 = iTime(_Symbol, PERIOD_M1, 0);
   if(t0 == 0 || t0 == g_lastBar) return;
   g_lastBar = t0;

   MqlRates r[];
   if(CopyRates(_Symbol, PERIOD_M1, 1, 1, r) != 1) return;   // the bar that just closed

   int minuteOfDay = (int)((r[0].time % 86400) / 60);
   for(int k = 0; k < ArraySize(g_s); k++)
      ProcessSlot(g_s[k], k, r[0], minuteOfDay);

   g_lastClose = r[0].close;
}
//+------------------------------------------------------------------+
