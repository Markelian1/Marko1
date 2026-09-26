//+------------------------------------------------------------------+
//|                    XAUUSD_MultiSession_ReverseHunter_v21.mq5     |
//|   Reverse Hunter on several sessions of the day, one EA.         |
//|                                                                  |
//|   Each session (server time):                                    |
//|     range     = high/low of the first RangeMin minutes after     |
//|                 Start (M1 bars),                                 |
//|     breakout  = first M1 close beyond the range within           |
//|                 BreakoutWin minutes after the range; followed    |
//|                 virtually (SL at the far side, TP rr x width     |
//|                 beyond the range) and traded only if TradeBO,    |
//|     reversal  = when that breakout is stopped out within         |
//|                 ReversalWin minutes after the range, enter once  |
//|                 the other way: SL at the far side, TP rr x width |
//|                 beyond the range,                                |
//|     flatten   = HoldMin minutes after the range.                 |
//|                                                                  |
//|   Defaults (2020-2026 XAUUSD scan, net of spread):               |
//|     NY     16:30, range 30 -> reversal +47.8R, 6/7 years         |
//|     Asia   03:00, range 30 -> reversal +81.9R, 6/7 years         |
//|     London Asian range 03:00-10:00 broken at the London open --  |
//|            NOT validated yet, off until the scan says otherwise. |
//|   Each session trades with its own magic (InpMagicBase + n).     |
//|   A trades journal (<prefix>_trades.csv) is written to           |
//|   Terminal\Common\Files during single backtests and live.        |
//+------------------------------------------------------------------+
#property copyright "Roboquant AI"
#property version   "2.10"
#property strict

#include <Trade\Trade.mqh>

//====================== INPUTS ======================================
input group "=== Risk ==="
input double InpRiskPercent   = 0.5;       // Risk per trade (% of equity, 0 = fixed lot)
input double InpLotSize       = 0.10;      // Fixed lot (used when risk % = 0)
input double InpMaxLots       = 1.00;      // Max lots per trade
input double InpRrTarget      = 2.0;       // Target (x range width beyond the range)
input long   InpMagicBase     = 20261000;  // Magic base (session n uses base + n)

input group "=== Session 1: New York ==="
input bool   InpS1On          = true;      // Enabled
input int    InpS1Hour        = 16;        // Start hour (server)
input int    InpS1Minute      = 30;        // Start minute
input int    InpS1Range       = 30;        // Range length (min)
input int    InpS1BoWin       = 90;        // Breakout window after the range (min)
input int    InpS1RvWin       = 180;       // Reversal window after the range (min)
input int    InpS1Hold        = 360;       // Flatten after the range (min)
input bool   InpS1TradeBO     = false;     // Trade the breakout itself
input bool   InpS1Reversal    = true;      // Trade the reversal after a failed breakout

input group "=== Session 2: Asia (Tokyo / Shanghai open) ==="
input bool   InpS2On          = true;      // Enabled
input int    InpS2Hour        = 3;         // Start hour (server)
input int    InpS2Minute      = 0;         // Start minute
input int    InpS2Range       = 30;        // Range length (min)
input int    InpS2BoWin       = 90;        // Breakout window after the range (min)
input int    InpS2RvWin       = 180;       // Reversal window after the range (min)
input int    InpS2Hold        = 360;       // Flatten after the range (min)
input bool   InpS2TradeBO     = false;     // Trade the breakout itself
input bool   InpS2Reversal    = true;      // Trade the reversal after a failed breakout

input group "=== Session 3: London (Asian range 03:00-10:00, not validated) ==="
input bool   InpS3On          = false;     // Enabled
input int    InpS3Hour        = 3;         // Start hour (server)
input int    InpS3Minute      = 0;         // Start minute
input int    InpS3Range       = 420;       // Range length (min): 03:00-10:00
input int    InpS3BoWin       = 90;        // Breakout window after the range (min)
input int    InpS3RvWin       = 180;       // Reversal window after the range (min)
input int    InpS3Hold        = 360;       // Flatten after the range (min)
input bool   InpS3TradeBO     = false;     // Trade the breakout itself
input bool   InpS3Reversal    = true;      // Trade the reversal after a failed breakout

input group "=== Journal ==="
input bool   InpWriteJournal  = true;      // Write <prefix>_trades.csv (not during optimization)
input string InpJournalPrefix = "MRH";     // File name prefix (Terminal\Common\Files)

//====================== TYPES / GLOBALS =============================
struct Session
{
   // configuration
   string   name;
   bool     on;
   int      startMin;
   int      rangeMin;
   int      boWin;
   int      rvWin;
   int      holdMin;
   bool     tradeBO;
   bool     useRV;
   long     magic;
   // daily state
   int      day;
   bool     haveRange;
   bool     frozen;
   double   hi;
   double   lo;
   int      vbDir;
   bool     vbActive;
   bool     vbDone;
   datetime vbBar;
   double   vbSL;
   double   vbTP;
   int      revPending;
   bool     revDone;
   bool     flatDone;
   // open trade (journal)
   bool     inTrade;
   string   trModule;
   int      trDir;
   datetime trTime;
   double   trEntry;
   double   trSL;
   double   trTP;
   double   trLots;
   double   trCost;
   string   pendModule;
   double   pendSL;
   double   pendTP;
};

CTrade   trade;
Session  g_s[3];
int      g_journalFile = INVALID_HANDLE;

//====================== HELPERS =====================================

string Px(const double v)  { return DoubleToString(v, _Digits); }
string Num(const double v) { return DoubleToString(v, 3); }

void Configure(Session &s, const string name, const bool on, const int hour, const int minute,
               const int rangeMin, const int boWin, const int rvWin, const int holdMin,
               const bool tradeBO, const bool useRV, const long magic)
{
   s.name     = name;
   s.on       = on;
   s.startMin = hour * 60 + minute;
   s.rangeMin = rangeMin;
   s.boWin    = boWin;
   s.rvWin    = rvWin;
   s.holdMin  = holdMin;
   s.tradeBO  = tradeBO;
   s.useRV    = useRV;
   s.magic    = magic;
   s.day      = -1;
   s.inTrade  = false;
   s.pendModule = "";
   s.pendSL   = 0.0;
   s.pendTP   = 0.0;
}

bool ValidSession(const Session &s)
{
   if(!s.on) return true;
   if(s.startMin < 0 || s.startMin >= 1440 || s.rangeMin < 1 || s.boWin < 1 ||
      s.rvWin < s.boWin || s.holdMin < s.rvWin) return false;
   return (s.startMin + s.rangeMin + s.holdMin < 1440);   // must not cross midnight
}

void ResetDay(Session &s, const int day)
{
   s.day        = day;
   s.haveRange  = false;
   s.frozen     = false;
   s.hi         = 0.0;
   s.lo         = 0.0;
   s.vbDir      = 0;
   s.vbActive   = false;
   s.vbDone     = false;
   s.vbBar      = 0;
   s.vbSL       = 0.0;
   s.vbTP       = 0.0;
   s.revPending = 0;
   s.revDone    = false;
   s.flatDone   = false;
}

int CountPositions(const long magic)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      count++;
   }
   return count;
}

void ClosePositions(const long magic)
{
   trade.SetExpertMagicNumber(magic);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      trade.PositionClose(ticket);
   }
}

//--- Lot whose stop loss costs InpRiskPercent of equity (0 when the minimum lot risks more)
double CalcLots(const double entry, const double stop)
{
   if(InpRiskPercent <= 0.0) return InpLotSize;

   double dist      = MathAbs(entry - stop);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double volStep   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double volMin    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volMax    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(dist <= 0.0 || tickSize <= 0.0 || tickValue <= 0.0 || volStep <= 0.0) return 0.0;

   double lossPerLot = dist / tickSize * tickValue;
   double budget     = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0;
   double lots       = MathFloor(budget / lossPerLot / volStep) * volStep;
   lots = MathMin(lots, MathMin(volMax, InpMaxLots));
   if(lots < volMin) return 0.0;

   int volDigits = (int)MathMax(0.0, MathCeil(-MathLog10(volStep)));
   return NormalizeDouble(lots, volDigits);
}

//--- Market order for one session (dir +1 buy / -1 sell)
bool SendOrder(Session &s, const int dir, const double sl, const double tp, const string module)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double px  = (dir == 1) ? ask : bid;
   if(px <= 0.0) return false;
   if(dir == 1 && (sl >= px || tp <= px)) return false;
   if(dir == -1 && (sl <= px || tp >= px)) return false;

   double lots = CalcLots(px, sl);
   if(lots <= 0.0)
   {
      PrintFormat("%s %s skipped: risk budget", s.name, module);
      return false;
   }

   s.pendModule = module;
   s.pendSL     = sl;
   s.pendTP     = tp;
   trade.SetExpertMagicNumber(s.magic);
   string comment = s.name + " " + module;
   bool ok = (dir == 1) ? trade.Buy(lots, _Symbol, 0.0, sl, tp, comment)
                        : trade.Sell(lots, _Symbol, 0.0, sl, tp, comment);
   if(ok)
      PrintFormat("%s %s %s @ %.2f x%.2f | stop %.2f | target %.2f (range %.2f-%.2f)",
                  s.name, module, (dir == 1 ? "LONG" : "SHORT"), px, lots, sl, tp, s.lo, s.hi);
   else
      PrintFormat("%s %s rejected retcode=%d", s.name, module, trade.ResultRetcode());
   return ok;
}

//====================== SESSION ENGINE ==============================

void ProcessSession(Session &s, const int day, const int nowMin, const double bid, const double ask)
{
   if(!s.on) return;

   if(day != s.day)
   {
      if(CountPositions(s.magic) > 0) ClosePositions(s.magic);   // nothing survives a day change
      ResetDay(s, day);
   }

   int rangeEnd = s.startMin + s.rangeMin;
   int boEnd    = rangeEnd + s.boWin;
   int rvEnd    = rangeEnd + s.rvWin;
   int flatMin  = rangeEnd + s.holdMin;

   // ---- flatten ----
   if(nowMin >= flatMin)
   {
      if(!s.flatDone)
      {
         if(CountPositions(s.magic) > 0)
         {
            ClosePositions(s.magic);
            PrintFormat("%s session flatten", s.name);
         }
         if(CountPositions(s.magic) == 0) s.flatDone = true;
      }
      return;
   }
   if(nowMin < s.startMin) return;

   // ---- build the range from the current M1 bar ----
   if(nowMin < rangeEnd)
   {
      double h = iHigh(_Symbol, PERIOD_M1, 0);
      double l = iLow(_Symbol, PERIOD_M1, 0);
      if(h <= 0.0 || l <= 0.0) return;
      if(!s.haveRange) { s.hi = h; s.lo = l; s.haveRange = true; }
      else
      {
         if(h > s.hi) s.hi = h;
         if(l < s.lo) s.lo = l;
      }
      return;
   }
   if(!s.haveRange) return;
   if(!s.frozen)
   {
      s.frozen = true;
      PrintFormat("%s range frozen: %.2f - %.2f (width %.2f)", s.name, s.lo, s.hi, s.hi - s.lo);
   }

   double width = s.hi - s.lo;
   if(width <= 0.0) return;

   // ---- virtual breakout: open on the first M1 close beyond the range ----
   if(!s.vbActive && !s.vbDone)
   {
      if(nowMin >= boEnd) s.vbDone = true;
      else
      {
         datetime bar = iTime(_Symbol, PERIOD_M1, 0);
         if(bar != s.vbBar)
         {
            s.vbBar = bar;
            double closed = iClose(_Symbol, PERIOD_M1, 1);
            int dir = 0;
            if(closed > s.hi)      dir = 1;
            else if(closed > 0.0 && closed < s.lo) dir = -1;
            if(dir != 0)
            {
               s.vbDir    = dir;
               s.vbSL     = (dir == 1) ? s.lo : s.hi;
               s.vbTP     = (dir == 1) ? s.hi + InpRrTarget * width : s.lo - InpRrTarget * width;
               s.vbActive = true;
               if(s.tradeBO) SendOrder(s, dir, s.vbSL, s.vbTP, "breakout");
            }
         }
      }
   }
   // ---- virtual breakout: TP or SL (a stop-out requests the reversal) ----
   else if(s.vbActive)
   {
      bool stopped = (s.vbDir == 1) ? (bid <= s.vbSL) : (ask >= s.vbSL);
      bool target  = (s.vbDir == 1) ? (bid >= s.vbTP) : (ask <= s.vbTP);
      if(stopped || target)
      {
         s.vbActive = false;
         s.vbDone   = true;
         if(stopped && s.useRV && !s.revDone && nowMin < rvEnd)
            s.revPending = -s.vbDir;
      }
   }

   // ---- reversal: once the session has no open position ----
   if(s.revPending != 0 && !s.revDone)
   {
      if(nowMin >= rvEnd) { s.revPending = 0; s.revDone = true; return; }
      if(CountPositions(s.magic) > 0) return;   // the stopped breakout trade is still closing
      int dir = s.revPending;
      s.revPending = 0;
      s.revDone    = true;
      double sl = (dir == 1) ? s.lo : s.hi;
      double tp = (dir == 1) ? s.hi + InpRrTarget * width : s.lo - InpRrTarget * width;
      SendOrder(s, dir, sl, tp, "reversal");
   }
}

//====================== JOURNAL =====================================

void JournalOpen()
{
   if(!InpWriteJournal || (bool)MQLInfoInteger(MQL_OPTIMIZATION)) return;
   string name = InpJournalPrefix + "_trades.csv";
   g_journalFile = FileOpen(name, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
   if(g_journalFile == INVALID_HANDLE)
   {
      PrintFormat("Journal disabled: could not open %s (error %d)", name, GetLastError());
      return;
   }
   FileWrite(g_journalFile, "open_time", "close_time", "session", "module", "dir", "lots",
             "entry", "sl", "tp", "exit", "exit_reason", "profit_usd", "risk_price", "result_R");
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   if(g_journalFile == INVALID_HANDLE) return;
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;

   int idx = (int)(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) - InpMagicBase - 1);
   if(idx < 0 || idx > 2) return;
   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

   if(entry == DEAL_ENTRY_IN)
   {
      g_s[idx].inTrade  = true;
      g_s[idx].trModule = g_s[idx].pendModule;
      g_s[idx].trDir    = (HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY) ? 1 : -1;
      g_s[idx].trTime   = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
      g_s[idx].trEntry  = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
      g_s[idx].trLots   = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
      g_s[idx].trCost   = HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
      g_s[idx].trSL     = g_s[idx].pendSL;
      g_s[idx].trTP     = g_s[idx].pendTP;
      return;
   }

   if((entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY) && g_s[idx].inTrade)
   {
      double   exitPx = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
      datetime closeT = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
      double   profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                      + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION)
                      + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                      + g_s[idx].trCost;
      long     reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
      string   why    = (reason == DEAL_REASON_SL) ? "SL" : (reason == DEAL_REASON_TP) ? "TP" : "CLOSE";
      double   risk   = MathAbs(g_s[idx].trEntry - g_s[idx].trSL);
      double   resR   = (risk > 0.0) ? g_s[idx].trDir * (exitPx - g_s[idx].trEntry) / risk : 0.0;

      FileWrite(g_journalFile,
                TimeToString(g_s[idx].trTime, TIME_DATE | TIME_MINUTES),
                TimeToString(closeT, TIME_DATE | TIME_MINUTES),
                g_s[idx].name, g_s[idx].trModule, (g_s[idx].trDir == 1 ? "LONG" : "SHORT"),
                DoubleToString(g_s[idx].trLots, 2),
                Px(g_s[idx].trEntry), Px(g_s[idx].trSL), Px(g_s[idx].trTP), Px(exitPx),
                why, DoubleToString(profit, 2), Px(risk), Num(resR));
      g_s[idx].inTrade = false;
   }
}

//====================== EVENTS ======================================

int OnInit()
{
   trade.SetDeviationInPoints(30);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);

   Configure(g_s[0], "NY",     InpS1On, InpS1Hour, InpS1Minute, InpS1Range, InpS1BoWin, InpS1RvWin, InpS1Hold,
             InpS1TradeBO, InpS1Reversal, InpMagicBase + 1);
   Configure(g_s[1], "ASIA",   InpS2On, InpS2Hour, InpS2Minute, InpS2Range, InpS2BoWin, InpS2RvWin, InpS2Hold,
             InpS2TradeBO, InpS2Reversal, InpMagicBase + 2);
   Configure(g_s[2], "LONDON", InpS3On, InpS3Hour, InpS3Minute, InpS3Range, InpS3BoWin, InpS3RvWin, InpS3Hold,
             InpS3TradeBO, InpS3Reversal, InpMagicBase + 3);

   for(int i = 0; i < 3; i++)
   {
      if(!ValidSession(g_s[i]))
      {
         PrintFormat("Session %s: invalid times (windows must grow, and the session must end before midnight).",
                     g_s[i].name);
         return INIT_PARAMETERS_INCORRECT;
      }
   }
   if(InpRiskPercent < 0.0 || InpLotSize <= 0.0 || InpMaxLots <= 0.0 || InpRrTarget <= 0.0)
   {
      Print("Risk, lot and target inputs must be positive.");
      return INIT_PARAMETERS_INCORRECT;
   }

   JournalOpen();
   for(int i = 0; i < 3; i++)
      if(g_s[i].on)
         PrintFormat("Session %s on | start %02d:%02d | range %d | breakout %d%s | reversal %s until +%d | flat +%d | magic %I64d",
                     g_s[i].name, g_s[i].startMin / 60, g_s[i].startMin % 60, g_s[i].rangeMin,
                     g_s[i].boWin, (g_s[i].tradeBO ? " (traded)" : " (watch only)"),
                     (g_s[i].useRV ? "on" : "off"), g_s[i].rvWin, g_s[i].holdMin, g_s[i].magic);
   PrintFormat("Multi-Session Reverse Hunter v2.1 | risk %.2f%% | rr %.2f", InpRiskPercent, InpRrTarget);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_journalFile != INVALID_HANDLE)
   {
      FileClose(g_journalFile);
      g_journalFile = INVALID_HANDLE;
      PrintFormat("Journal written: %s_trades.csv in Terminal\\Common\\Files", InpJournalPrefix);
   }
}

void OnTick()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   int day    = t.year * 1000 + t.day_of_year;
   int nowMin = t.hour * 60 + t.min;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return;

   for(int i = 0; i < 3; i++)
      ProcessSession(g_s[i], day, nowMin, bid, ask);
}
//+------------------------------------------------------------------+
