//+------------------------------------------------------------------+
//|                                    XAUUSD_StabilityScanner.mq5   |
//|   Stability check of the Reverse Hunter v2.2 settings.          |
//|   ANALYSIS TOOL -- it never trades.                              |
//|                                                                  |
//|   One single run replaces the 36-pass optimization: the NY       |
//|   (16:30) and Asia (03:00) sessions are followed side by side    |
//|   for every range length (20, 30, 40 min) and every target       |
//|   (1.5, 2.0, 2.5, 3.0 x range width), 24 configurations.         |
//|   Same logic as XAUUSD_SessionScanner:                           |
//|     breakout  = first M1 close beyond the range within 90 min,   |
//|     reversal  = after that breakout is stopped out within        |
//|                 180 min, enter the other way at the stop level,  |
//|                 SL at the far side, TP rr x width beyond,        |
//|     flatten   = 360 min after the range.                         |
//|   Bars are processed on M1 close, SL before TP inside one bar.   |
//|   Output: STAB_slots.csv in Terminal\Common\Files.               |
//|   Run it in the Strategy Tester, "1 minute OHLC" is enough.      |
//+------------------------------------------------------------------+
#property copyright "Roboquant AI"
#property version   "1.00"
#property strict

input int    InpBreakoutWindow  = 90;    // Breakout allowed for N min after the range
input int    InpReversalWindow  = 180;   // Reversal allowed for N min after the range
input int    InpHoldMinutes     = 360;   // Flatten N min after the range
input int    InpMinRangeBars    = 15;    // Skip ranges with fewer M1 bars (market closed)
input string InpFilePrefix      = "STAB"; // File name prefix (Terminal\Common\Files)

struct Slot
{
   string   name;         // session
   int      startMin;     // minute of the day (server)
   int      rangeMin;
   double   rr;
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
   s.boDir = 0;       s.boEntry = 0.0; s.boSL = 0.0;      s.boTP = 0.0;  s.boExit = 0.0;  s.boOut = "-";
   s.rvDir = 0;       s.rvEntry = 0.0; s.rvSL = 0.0;      s.rvTP = 0.0;  s.rvExit = 0.0;  s.rvOut = "-";
}

string Px(const double v)  { return DoubleToString(v, _Digits); }
string Num(const double v) { return DoubleToString(v, 3); }

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
                TimeToString(s.start, TIME_DATE), s.name, IntegerToString(s.rangeMin), DoubleToString(s.rr, 1),
                Px(s.hi - s.lo), Px(s.spread),
                (s.boDir == 1 ? "LONG" : (s.boDir == -1 ? "SHORT" : "-")), s.boOut, Num(boR),
                (s.rvDir == 1 ? "LONG" : (s.rvDir == -1 ? "SHORT" : "-")),
                Px(s.rvEntry), Px(rvRisk), s.rvOut, Num(rvR));
      g_rows++;
   }
   ResetSlot(s);                                              // keeps the configuration
}

void StartSlot(Slot &s, const datetime t)
{
   s.active     = true;
   s.state      = 1;
   s.start      = t;
   s.rangeEnd   = t + s.rangeMin * 60;
   s.boDeadline = s.rangeEnd + InpBreakoutWindow * 60;
   s.rvDeadline = s.rangeEnd + InpReversalWindow * 60;
   s.flatTime   = s.rangeEnd + InpHoldMinutes * 60;
}

//--- Advance one configuration by one closed M1 bar
void ProcessSlot(Slot &s, const MqlRates &r, const int minuteOfDay)
{
   if(s.active && r.time >= s.flatTime) FinishSlot(s);
   if(minuteOfDay == s.startMin)
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
         s.boDir = 1;  s.boEntry = r.close;  s.boSL = s.lo;  s.boTP = s.hi + s.rr * w;
      }
      else if(r.close < s.lo)
      {
         s.boDir = -1; s.boEntry = r.close;  s.boSL = s.hi;  s.boTP = s.lo - s.rr * w;
      }
      else return;
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
            s.rvTP    = (s.rvDir == 1) ? s.hi + s.rr * w : s.lo - s.rr * w;
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
   if(InpBreakoutWindow < 1 || InpReversalWindow < InpBreakoutWindow || InpHoldMinutes < InpReversalWindow)
   {
      Print("Invalid scanner settings.");
      return INIT_PARAMETERS_INCORRECT;
   }

   string names[]  = {"NY", "ASIA"};
   int    starts[] = {990, 180};            // 16:30 and 03:00 server
   int    ranges[] = {20, 30, 40};
   double rrs[]    = {1.5, 2.0, 2.5, 3.0};

   ArrayResize(g_s, ArraySize(names) * ArraySize(ranges) * ArraySize(rrs));
   int k = 0;
   for(int a = 0; a < ArraySize(names); a++)
      for(int b = 0; b < ArraySize(ranges); b++)
         for(int c = 0; c < ArraySize(rrs); c++)
         {
            ResetSlot(g_s[k]);
            g_s[k].name     = names[a];
            g_s[k].startMin = starts[a];
            g_s[k].rangeMin = ranges[b];
            g_s[k].rr       = rrs[c];
            k++;
         }

   string name = InpFilePrefix + "_slots.csv";
   g_file = FileOpen(name, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
   if(g_file == INVALID_HANDLE)
   {
      PrintFormat("Could not open %s (error %d)", name, GetLastError());
      return INIT_FAILED;
   }
   FileWrite(g_file, "date", "session", "range", "rr", "width", "spread",
             "bo_dir", "bo_out", "bo_R", "rv_dir", "rv_entry", "rv_risk", "rv_out", "rv_R");

   g_lastBar   = 0;
   g_lastClose = 0.0;
   g_rows      = 0;
   PrintFormat("Stability scanner: %d configurations | breakout %d | reversal %d | hold %d",
               ArraySize(g_s), InpBreakoutWindow, InpReversalWindow, InpHoldMinutes);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_file == INVALID_HANDLE) return;
   for(int k = 0; k < ArraySize(g_s); k++) FinishSlot(g_s[k]);
   FileClose(g_file);
   g_file = INVALID_HANDLE;
   PrintFormat("Stability scanner finished: %I64d rows in %s_slots.csv (Terminal\\Common\\Files)", g_rows, InpFilePrefix);
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
      ProcessSlot(g_s[k], r[0], minuteOfDay);

   g_lastClose = r[0].close;
}
//+------------------------------------------------------------------+
