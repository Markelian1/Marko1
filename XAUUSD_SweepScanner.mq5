//+------------------------------------------------------------------+
//|                                        XAUUSD_SweepScanner.mq5   |
//|   Counts "liquidity sweep" entries and what happened after them. |
//|   ANALYSIS TOOL -- it never trades.                              |
//|                                                                  |
//|   Each day (server time, from InpDayStartHour) the day's low and |
//|   high are tracked. A sweep is a move beyond a level that is at  |
//|   least InpMinLevelAge minutes old, followed by an M1 close back |
//|   inside within InpReclaimMinutes:                               |
//|     sweep of the low  -> LONG at that close, SL at the sweep low |
//|     sweep of the high -> SHORT at that close, SL at the sweep high|
//|   One signal per side per day. Each signal is then followed for  |
//|   InpTrackHours hours: the best move in R before the stop        |
//|   (mfe_R), whether and when the stop was hit, and the R at the   |
//|   end. Any target (3R, 5R, 8R, the other side of the day's       |
//|   range, the previous day's high/low) is evaluated afterwards    |
//|   from mfe_R: it was reached if mfe_R >= target.                 |
//|   Bars are processed on M1 close; on a bar that hits the stop    |
//|   the favourable move is not counted (conservative). Prices are  |
//|   bid; the spread at entry is recorded for the analysis.         |
//|   Output: SWEEP_signals.csv in Terminal\Common\Files.            |
//|   Run it in the Strategy Tester, "1 minute OHLC" is enough.      |
//+------------------------------------------------------------------+
#property copyright "Roboquant AI"
#property version   "1.00"
#property strict

input int    InpDayStartHour    = 1;     // Day levels are built from this server hour
input int    InpFirstSignalHour = 3;     // No signal before this server hour
input int    InpLastSignalHour  = 22;    // No new signal from this server hour on
input int    InpMinLevelAge     = 60;    // The swept low/high must be at least N minutes old
input int    InpReclaimMinutes  = 15;    // Close back inside within N minutes of the break
input int    InpTrackHours      = 24;    // Follow each signal for N hours
input string InpFilePrefix      = "SWEEP"; // File name prefix (Terminal\Common\Files)

struct Side
{
   int      dir;          // +1 sweep of the low -> long, -1 sweep of the high -> short
   double   level;        // day low (long side) or day high (short side) so far
   datetime levelTime;    // when that level was made
   bool     broken;       // closed beyond an old level, waiting for the reclaim
   datetime breakTime;
   double   brokenLevel;
   int      brokenAge;    // minutes the broken level had stood
   double   ext;          // extreme since the break
   bool     done;         // one signal per side per day
};

struct SweepSignal
{
   bool     active;
   datetime t0;
   datetime endTime;
   int      dir;
   int      levelAge;
   double   entry;
   double   sl;
   double   risk;
   double   spread;
   double   dayR;         // distance to the other side of the day's range, in R
   double   pdR;          // distance to the previous day's high (long) / low (short), in R
   double   mfe;
   bool     slHit;
   int      slMin;
   double   endR;
};

Side     g_side[2];
SweepSignal g_sig[];
int      g_file      = INVALID_HANDLE;
datetime g_lastBar   = 0;
datetime g_day       = 0;
double   g_lastClose = 0.0;
long     g_rows      = 0;

string Px(const double v)  { return DoubleToString(v, _Digits); }
string Num(const double v) { return DoubleToString(v, 3); }

void ResetSide(Side &s, const int dir, const MqlRates &r)
{
   s.dir         = dir;
   s.level       = (dir == 1) ? r.low : r.high;
   s.levelTime   = r.time;
   s.broken      = false;
   s.breakTime   = 0;
   s.brokenLevel = 0.0;
   s.brokenAge   = 0;
   s.ext         = 0.0;
   s.done        = false;
}

void WriteSignal(SweepSignal &g)
{
   FileWrite(g_file,
             TimeToString(g.t0, TIME_DATE), TimeToString(g.t0, TIME_MINUTES),
             (g.dir == 1 ? "LONG" : "SHORT"), IntegerToString(g.levelAge),
             Px(g.entry), Px(g.risk), Px(g.spread),
             Num(g.dayR), Num(g.pdR), Num(g.mfe),
             (g.slHit ? "1" : "0"), IntegerToString(g.slMin), Num(g.endR));
   g_rows++;
   g.active = false;
}

void OpenSignal(const Side &s, const MqlRates &r, const double sl, const double otherSide)
{
   double risk = (s.dir == 1) ? r.close - sl : sl - r.close;
   if(risk <= 0.0) return;

   int k = ArraySize(g_sig);
   for(int i = 0; i < ArraySize(g_sig); i++)
      if(!g_sig[i].active) { k = i; break; }
   if(k == ArraySize(g_sig)) ArrayResize(g_sig, k + 1);

   double pd = (s.dir == 1) ? iHigh(_Symbol, PERIOD_D1, 1) : iLow(_Symbol, PERIOD_D1, 1);

   g_sig[k].active   = true;
   g_sig[k].t0       = r.time;
   g_sig[k].endTime  = r.time + InpTrackHours * 3600;
   g_sig[k].dir      = s.dir;
   g_sig[k].levelAge = s.brokenAge;
   g_sig[k].entry    = r.close;
   g_sig[k].sl       = sl;
   g_sig[k].risk     = risk;
   g_sig[k].spread   = r.spread * _Point;
   g_sig[k].dayR     = s.dir * (otherSide - r.close) / risk;
   g_sig[k].pdR      = (pd > 0.0) ? s.dir * (pd - r.close) / risk : 0.0;
   g_sig[k].mfe      = 0.0;
   g_sig[k].slHit    = false;
   g_sig[k].slMin    = 0;
   g_sig[k].endR     = 0.0;
}

//--- Follow one open signal by one closed M1 bar
void TrackSignal(SweepSignal &g, const MqlRates &r)
{
   if(!g.active || r.time <= g.t0) return;

   bool stop = (g.dir == 1) ? (r.low <= g.sl) : (r.high >= g.sl);
   if(stop)
   {
      g.slHit = true;
      g.slMin = (int)((r.time - g.t0) / 60);
      g.endR  = -1.0;
      WriteSignal(g);
      return;
   }
   double fav = (g.dir == 1) ? (r.high - g.entry) / g.risk : (g.entry - r.low) / g.risk;
   if(fav > g.mfe) g.mfe = fav;
   if(r.time >= g.endTime)
   {
      g.endR = g.dir * (r.close - g.entry) / g.risk;
      WriteSignal(g);
   }
}

//--- Advance one side (day low or day high) by one closed M1 bar
void ProcessSide(Side &s, const MqlRates &r, const int hour, const double otherSide)
{
   double beyond = (s.dir == 1) ? r.low  : r.high;            // the bar's extreme on this side
   bool   isNew  = (s.dir == 1) ? (beyond < s.level) : (beyond > s.level);
   bool   inWindow = (hour >= InpFirstSignalHour && hour < InpLastSignalHour);

   if(s.broken)
   {
      if(s.dir == 1 ? (r.low < s.ext) : (r.high > s.ext)) s.ext = beyond;
      bool back = (s.dir == 1) ? (r.close > s.brokenLevel) : (r.close < s.brokenLevel);
      if(back && r.time - s.breakTime <= InpReclaimMinutes * 60)
      {
         if(!s.done && inWindow) OpenSignal(s, r, s.ext, otherSide);
         s.done   = true;
         s.broken = false;
      }
      else if(r.time - s.breakTime > InpReclaimMinutes * 60)
         s.broken = false;                                    // accepted break, no signal
   }
   else if(isNew && !s.done && inWindow && r.time - s.levelTime >= InpMinLevelAge * 60)
   {
      s.brokenAge   = (int)((r.time - s.levelTime) / 60);
      s.brokenLevel = s.level;
      bool back = (s.dir == 1) ? (r.close > s.level) : (r.close < s.level);
      if(back)
      {
         OpenSignal(s, r, beyond, otherSide);                 // swept and reclaimed in one bar
         s.done = true;
      }
      else
      {
         s.broken    = true;
         s.breakTime = r.time;
         s.ext       = beyond;
      }
   }

   if(isNew) { s.level = beyond; s.levelTime = r.time; }
}

int OnInit()
{
   if(InpDayStartHour < 0 || InpDayStartHour > 23 || InpFirstSignalHour < InpDayStartHour ||
      InpLastSignalHour <= InpFirstSignalHour || InpLastSignalHour > 24 ||
      InpMinLevelAge < 1 || InpReclaimMinutes < 1 || InpTrackHours < 1)
   {
      Print("Invalid scanner settings.");
      return INIT_PARAMETERS_INCORRECT;
   }

   string name = InpFilePrefix + "_signals.csv";
   g_file = FileOpen(name, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
   if(g_file == INVALID_HANDLE)
   {
      PrintFormat("Could not open %s (error %d)", name, GetLastError());
      return INIT_FAILED;
   }
   FileWrite(g_file, "date", "time", "dir", "level_age", "entry", "risk", "spread",
             "day_R", "pd_R", "mfe_R", "sl_hit", "sl_min", "end_R");

   ArrayResize(g_sig, 0);
   g_lastBar   = 0;
   g_day       = 0;
   g_lastClose = 0.0;
   g_rows      = 0;
   PrintFormat("Sweep scanner: day from %02d:00 | signals %02d:00-%02d:00 | level age >= %d min | reclaim %d min | track %d h",
               InpDayStartHour, InpFirstSignalHour, InpLastSignalHour, InpMinLevelAge, InpReclaimMinutes, InpTrackHours);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_file == INVALID_HANDLE) return;
   for(int i = 0; i < ArraySize(g_sig); i++)
      if(g_sig[i].active)
      {
         g_sig[i].endR = g_sig[i].dir * (g_lastClose - g_sig[i].entry) / g_sig[i].risk;
         WriteSignal(g_sig[i]);
      }
   FileClose(g_file);
   g_file = INVALID_HANDLE;
   PrintFormat("Sweep scanner finished: %I64d signals in %s_signals.csv (Terminal\\Common\\Files)", g_rows, InpFilePrefix);
}

void OnTick()
{
   datetime t0 = iTime(_Symbol, PERIOD_M1, 0);
   if(t0 == 0 || t0 == g_lastBar) return;
   g_lastBar = t0;

   MqlRates r[];
   if(CopyRates(_Symbol, PERIOD_M1, 1, 1, r) != 1) return;   // the bar that just closed

   for(int i = 0; i < ArraySize(g_sig); i++) TrackSignal(g_sig[i], r[0]);
   g_lastClose = r[0].close;

   int      minuteOfDay = (int)((r[0].time % 86400) / 60);
   datetime today       = r[0].time - r[0].time % 86400;
   if(minuteOfDay < InpDayStartHour * 60) return;             // before the day starts

   if(today != g_day)
   {
      g_day = today;
      ResetSide(g_side[0],  1, r[0]);
      ResetSide(g_side[1], -1, r[0]);
      return;
   }

   int    hour = minuteOfDay / 60;
   double dayLow  = g_side[0].level;                           // the day's range before this bar
   double dayHigh = g_side[1].level;
   ProcessSide(g_side[0], r[0], hour, dayHigh);
   ProcessSide(g_side[1], r[0], hour, dayLow);
}
//+------------------------------------------------------------------+
