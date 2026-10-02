//+------------------------------------------------------------------+
//|                                          GOOGLE_STRATEG_PRO.mq5  |
//|   GOOGLE STRATEG XAUUSD v1.10, i testuar dhe i permiresuar       |
//+------------------------------------------------------------------+
//  Ideja e origjinalit: range i disa oreve, pastaj nje urdher stop ne
//  drejtim te trendit (buy stop mbi maje / sell stop nen fund).
//
//  Cfare ndryshoi dhe pse (testi ne historikun XAUUSD 2020-2026, shih
//  backtest/google_strateg.py dhe MQL5/README.md):
//   1. SL pertej GJITHE range-it (jo ne mes): me SL ne mes, thyerjet e
//      rreme (sweep) e nxirrnin tregtimin brenda pak minutash.
//   2. Pa breakeven ne +1R: BE e kthente ne zero shumicen e tregtimeve
//      qe me pas arrinin 3R.
//   3. Trendi ditor (mbyllja e djeshme mbi / nen SMA 50 D1) ne vend te
//      EMA 200 H1, qe ndryshon drejtim disa here ne jave.
//   4. Range 15:00-17:00 ora e serverit (08:00-10:00 New York), urdhri
//      anulohet 21:00 (14:00 NY). Range 11:30-14:30 i origjinalit fiton
//      tani, por me pak.
//   5. Rreziku 0.25% (jo 1%): 18-29 humbje rresht ndodhin me TP 3R.
//  Gabime te origjinalit qe u rregulluan:
//   - kur urdhri nuk mund te vendosej (cmimi pertej hyrjes, pa trend),
//     OnTick dilte me "return" para menaxhimit te pozicioneve;
//   - buffer-i ne "pips" (_Point x 10) ndryshon me numrin e shifrave te
//     brokerit: tani jepet ne dollare;
//   - mesazhet e gabimit perseriteshin ne cdo tick.
//  Shtesa: ditar CSV me arsyen e cdo hyrjeje, vizatim i range-it dhe i
//  niveleve, panel me statusin.
#property copyright "Copyright 2026"
#property link      "https://www.mql5.com"
#property version   "2.00"
#property description "Breakout i range-it ne drejtim te trendit ditor, SL pertej range-it, TP 3R"

#include <Trade/Trade.mqh>

CTrade trade;

enum ENUM_GS_TREND
  {
   TREND_D1_SMA50  = 0,   // D1: mbyllja e djeshme vs SMA 50 (e re)
   TREND_H1_EMA200 = 1    // H1: mbyllja vs EMA 200 (origjinali)
  };

enum ENUM_GS_SL
  {
   SL_FULL_RANGE = 0,     // pertej gjithe range-it (e re)
   SL_HALF_RANGE = 1      // ne mes te range-it (origjinali)
  };

input group "=== RREZIKU ==="
input double        InpRiskPercent      = 0.25;           // Rreziku per tregtim (%)
input double        InpMaxDailyDrawdown = 4.0;            // Humbja max ditore (%)
input ulong         InpMagicNumber      = 123457;         // Magic Number

input group "=== STRATEGJIA ==="
input ENUM_GS_TREND InpTrend            = TREND_D1_SMA50; // Filtri i trendit
input ENUM_GS_SL    InpSLMode           = SL_FULL_RANGE;  // Ku vendoset SL
input double        InpBufferUSD        = 1.50;           // Buffer nga range ($)
input double        InpRewardRatio      = 3.0;            // TP = SL x RR
input bool          InpBreakeven        = false;          // Breakeven ne +1R (origjinali: true)
input bool          InpAllowBuys        = true;           // Lejo blerje
input bool          InpAllowSells       = true;           // Lejo shitje

input group "=== ORARI - ORA E SERVERIT ==="
input string        InpRangeStart       = "15:00";        // Fillimi i range (08:00 NY)
input string        InpRangeEnd         = "17:00";        // Fundi i range / urdhri (10:00 NY)
input string        InpCancelTime       = "21:00";        // Anulimi i urdhrit (14:00 NY)
input int           InpServerMinusNY    = 7;              // Ora e serverit - ora e New York (FP: 7)

input group "=== DITARI DHE GRAFIKU ==="
input bool          InpJournal          = true;           // Ditar CSV ne Common\Files
input bool          InpDraw             = true;           // Vizato range dhe nivelet

struct GSTrade
  {
   ulong             order;
   ulong             pos;
   int               dir;
   double            entry;
   double            sl;
   double            tp;
   double            hi;
   double            lo;
   double            trendPct;
   double            lots;
   double            fill;
   double            riskMoney;
   datetime          placed;
   datetime          opened;
   bool              closed;               // u mbyll ose urdhri u anulua
   string            why;
  };

GSTrade  g_tr[];
int      g_trendHandle = INVALID_HANDLE;
int      g_rs = 0, g_re = 0, g_rc = 0;     // sekonda nga mesnata
datetime g_day = 0;
bool     g_done = false;                   // urdhri i dites u vendos ose dita u mbyll
bool     g_ddStop = false;
int      g_tries = 0;
double   g_dayBalance = 0.0;
string   g_status = "";
int      g_file = INVALID_HANDLE;
string   g_fileName = "";
int      g_n = 0, g_wins = 0;
double   g_sumR = 0.0, g_grossW = 0.0, g_grossL = 0.0;
datetime g_lastPanel = 0;

//+------------------------------------------------------------------+
int ParseHM(const string s)
  {
   int p = StringFind(s, ":");
   if(p < 1)
      return -1;
   int h = (int)StringToInteger(StringSubstr(s, 0, p));
   int m = (int)StringToInteger(StringSubstr(s, p + 1));
   if(h < 0 || h > 23 || m < 0 || m > 59)
      return -1;
   return h * 3600 + m * 60;
  }

string NYTime(const datetime t)
  {
   return TimeToString(t - InpServerMinusNY * 3600, TIME_MINUTES);
  }

string NYClock(const int secs)
  {
   int s = ((secs - InpServerMinusNY * 3600) % 86400 + 86400) % 86400;
   return StringFormat("%02d:%02d", s / 3600, (s % 3600) / 60);
  }

string DayName(const datetime t)
  {
   static string names[7] = {"E diel", "E hene", "E marte", "E merkure", "E enjte", "E premte", "E shtune"};
   MqlDateTime d;
   TimeToStruct(t - InpServerMinusNY * 3600, d);
   return names[d.day_of_week];
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   g_rs = ParseHM(InpRangeStart);
   g_re = ParseHM(InpRangeEnd);
   g_rc = ParseHM(InpCancelTime);
   if(g_rs < 0 || g_re < 0 || g_rc < 0 || !(g_rs < g_re && g_re < g_rc))
     {
      Print("GABIM: oraret duhet te jene HH:MM dhe fillimi < fundi < anulimi brenda dites.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpRiskPercent <= 0.0 || InpRewardRatio <= 0.0 || InpBufferUSD < 0.0)
      return INIT_PARAMETERS_INCORRECT;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(InpTrend == TREND_D1_SMA50)
      g_trendHandle = iMA(_Symbol, PERIOD_D1, 50, 0, MODE_SMA, PRICE_CLOSE);
   else
      g_trendHandle = iMA(_Symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
   if(g_trendHandle == INVALID_HANDLE)
     {
      Print("GABIM: mesatarja e trendit nuk u krijua.");
      return INIT_FAILED;
     }

   if(InpJournal)
      JournalOpen();

   Print("GOOGLE STRATEG PRO v2.00 | range ", InpRangeStart, "-", InpRangeEnd, " server (",
         NYClock(g_rs), "-", NYClock(g_re), " NY) | anulimi ", InpCancelTime, " | trendi ",
         InpTrend == TREND_D1_SMA50 ? "D1 SMA50" : "H1 EMA200", " | SL ",
         InpSLMode == SL_FULL_RANGE ? "pertej range-it" : "mes range-it", " | TP ",
         DoubleToString(InpRewardRatio, 1), "R | rreziku ", DoubleToString(InpRiskPercent, 2), "%");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_trendHandle != INVALID_HANDLE)
      IndicatorRelease(g_trendHandle);
   if(g_file != INVALID_HANDLE)
      FileClose(g_file);
   Comment("");
   Print("GOOGLE STRATEG PRO v2.00: ", g_n, " tregtime, ", g_wins, " fitime (",
         DoubleToString(g_n > 0 ? 100.0 * g_wins / g_n : 0.0, 1), "%), PF ",
         DoubleToString(g_grossL > 0 ? g_grossW / g_grossL : 0.0, 2), ", shuma ",
         DoubleToString(g_sumR, 1), "R", g_fileName != "" ? ", ditari: Common\\Files\\" + g_fileName : "");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   datetime now = TimeCurrent();
   datetime day = now - now % 86400;
   if(day != g_day)
     {
      g_day = day;
      g_done = false;
      g_ddStop = false;
      g_tries = 0;
      g_dayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_status = "pritet range " + InpRangeStart + "-" + InpRangeEnd;
     }

   // pozicionet menaxhohen gjithmone, para cdo kontrolli tjeter
   if(InpBreakeven)
      ManageBreakeven();

   if(!g_ddStop && g_dayBalance - AccountInfoDouble(ACCOUNT_EQUITY) >= g_dayBalance * InpMaxDailyDrawdown / 100.0)
     {
      g_ddStop = true;
      CloseOurPositions();
      DeletePendings();
      g_status = "humbja ditore " + DoubleToString(InpMaxDailyDrawdown, 1) + "% u arrit: pa tregtime deri neser";
      Print("KUJDES: ", g_status);
     }

   if(now >= day + g_rc)
     {
      if(DeletePendings() > 0)
         g_status = "urdhri nuk u mbush deri " + InpCancelTime + ": u anulua";
      g_done = true;
     }
   else
      if(!g_ddStop && !g_done && now >= day + g_re)
         TrySetup(day);

   if(now - g_lastPanel >= 60)
     {
      g_lastPanel = now;
      Comment("GOOGLE STRATEG PRO v2.00\n",
              "Range ", InpRangeStart, "-", InpRangeEnd, " server (", NYClock(g_rs), "-", NYClock(g_re),
              " NY), anulimi ", InpCancelTime, "\n",
              "Statusi: ", g_status, "\n",
              "Tregtime ", g_n, " | fitime ", g_wins, " | shuma ", DoubleToString(g_sumR, 1), "R");
     }
  }

//+------------------------------------------------------------------+
int GetTrend(double &pct)
  {
   pct = 0.0;
   double ma[1];
   if(CopyBuffer(g_trendHandle, 0, 1, 1, ma) != 1 || ma[0] <= 0.0)
      return 0;
   double c = iClose(_Symbol, InpTrend == TREND_D1_SMA50 ? PERIOD_D1 : PERIOD_H1, 1);
   if(c <= 0.0)
      return 0;
   pct = 100.0 * (c - ma[0]) / ma[0];
   return c > ma[0] ? 1 : (c < ma[0] ? -1 : 0);
  }

bool RangeBounds(const datetime t0, const datetime t1, double &hi, double &lo)
  {
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_M15, t0, t1, r);
   hi = -DBL_MAX;
   lo = DBL_MAX;
   for(int i = 0; i < n; i++)
      if(r[i].time >= t0 && r[i].time < t1)
        {
         hi = MathMax(hi, r[i].high);
         lo = MathMin(lo, r[i].low);
        }
   return hi > -DBL_MAX && lo < DBL_MAX && hi > lo;
  }

double LotSize(const double dist)
  {
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(tv <= 0.0 || ts <= 0.0 || st <= 0.0 || dist <= 0.0)
      return 0.0;
   double lots = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0 / (dist / ts * tv);
   lots = MathFloor(lots / st + 1e-9) * st;
   if(lots < mn)
      return 0.0;                          // asnjehere me shume rrezik se sa kerkohet
   return NormalizeDouble(MathMin(lots, mx), 2);
  }

//+------------------------------------------------------------------+
void TrySetup(const datetime day)
  {
   datetime t0 = day + g_rs, t1 = day + g_re, t2 = day + g_rc;
   double hi, lo;
   if(!RangeBounds(t0, t1, hi, lo))
     {
      g_status = "pa qirinj M15 ne range (feste?)";
      return;                              // provohet perseri ne tick-un tjeter
     }
   double pct;
   int dir = GetTrend(pct);
   string trendTxt = (InpTrend == TREND_D1_SMA50 ? "Trendi ditor " : "Trendi H1 ") + (dir == 1 ? "UP" : (dir == -1 ? "DOWN" : "pa drejtim"))
                     + StringFormat(": mbyllja %+.2f%% nga ", pct) + (InpTrend == TREND_D1_SMA50 ? "SMA50 D1" : "EMA200 H1");
   if(dir == 0 || (dir == 1 && !InpAllowBuys) || (dir == -1 && !InpAllowSells))
     {
      g_done = true;
      g_status = trendTxt + ": sot pa urdher";
      return;
     }
   double buf = InpBufferUSD;
   double rng = hi - lo;
   double dist = InpSLMode == SL_FULL_RANGE ? rng + 2.0 * buf : rng / 2.0 + buf;
   double entry = NormalizeDouble(dir == 1 ? hi + buf : lo - buf, _Digits);
   double sl = NormalizeDouble(dir == 1 ? entry - dist : entry + dist, _Digits);
   double tp = NormalizeDouble(dir == 1 ? entry + InpRewardRatio * dist : entry - InpRewardRatio * dist, _Digits);

   // cmimi duhet te jete ende para hyrjes; ndryshe pritet kthimi (si origjinali)
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minDist = (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) + 1) * _Point;
   if((dir == 1 && entry - ask < minDist) || (dir == -1 && bid - entry < minDist))
     {
      g_status = "cmimi eshte pertej hyrjes " + DoubleToString(entry, _Digits) + ": pritet kthimi deri " + InpCancelTime;
      return;
     }
   double lots = LotSize(dist);
   if(lots <= 0.0)
     {
      g_done = true;
      g_status = "loti del nen minimumin per " + DoubleToString(InpRiskPercent, 2) + "%: sot pa urdher";
      Print(g_status);
      return;
     }

   string why = StringFormat("%s STOP: range %s-%s server (%s-%s NY) %.2f-%.2f ($%.2f). %s. Hyrja = %s %s $%.2f, "
                             "SL = %s %s $%.2f (%s), TP = %.1fR ($%.2f).",
                             dir == 1 ? "BUY" : "SELL", InpRangeStart, InpRangeEnd, NYTime(t0), NYTime(t1), lo, hi, rng, trendTxt,
                             dir == 1 ? "maja" : "fundi", dir == 1 ? "+" : "-", buf,
                             InpSLMode == SL_FULL_RANGE ? (dir == 1 ? "fundi" : "maja") : "mesi",
                             dir == 1 ? "-" : "+", InpSLMode == SL_FULL_RANGE ? buf : 0.0,
                             InpSLMode == SL_FULL_RANGE ? "pertej gjithe range-it" : "mes range-it",
                             InpRewardRatio, InpRewardRatio * dist);
   bool ok = dir == 1 ? trade.BuyStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_DAY, 0, "GS PRO BUY")
             : trade.SellStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_DAY, 0, "GS PRO SELL");
   if(!ok || trade.ResultOrder() == 0)
     {
      g_tries++;
      Print("GABIM ", dir == 1 ? "BUY" : "SELL", " STOP: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      if(g_tries >= 3)
        {
         g_done = true;
         g_status = "urdhri u refuzua 3 here: sot pa urdher";
        }
      return;
     }
   g_done = true;
   int k = ArraySize(g_tr);
   ArrayResize(g_tr, k + 1);
   g_tr[k].order = trade.ResultOrder();
   g_tr[k].pos = 0;
   g_tr[k].dir = dir;
   g_tr[k].entry = entry;
   g_tr[k].sl = sl;
   g_tr[k].tp = tp;
   g_tr[k].hi = hi;
   g_tr[k].lo = lo;
   g_tr[k].trendPct = pct;
   g_tr[k].lots = lots;
   g_tr[k].fill = 0.0;
   g_tr[k].riskMoney = 0.0;
   g_tr[k].placed = TimeCurrent();
   g_tr[k].opened = 0;
   g_tr[k].closed = false;
   g_tr[k].why = why;
   g_status = (dir == 1 ? "BUY" : "SELL") + string(" STOP ne ") + DoubleToString(entry, _Digits) + " deri " + InpCancelTime;
   Print("URDHER: ", why);
   if(InpDraw)
      DrawSetup(t0, t1, t2, hi, lo, entry, sl, tp, why);
  }

//+------------------------------------------------------------------+
void ManageBreakeven()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber)
         continue;
      double op = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      if(sl <= 0.0)
         continue;
      double r = MathAbs(op - sl);
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double nsl = NormalizeDouble(op + 2.0 * _Point, _Digits);
         if(sl < op && bid >= op + r && nsl < bid)
            trade.PositionModify(tk, nsl, tp);
        }
      else
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double nsl = NormalizeDouble(op - 2.0 * _Point, _Digits);
         if(sl > op && ask <= op - r && nsl > ask)
            trade.PositionModify(tk, nsl, tp);
        }
     }
  }

void CloseOurPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == (long)InpMagicNumber)
         trade.PositionClose(tk);
     }
  }

int DeletePendings()
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0 || OrderGetString(ORDER_SYMBOL) != _Symbol || OrderGetInteger(ORDER_MAGIC) != (long)InpMagicNumber)
         continue;
      ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if((t == ORDER_TYPE_BUY_STOP || t == ORDER_TYPE_SELL_STOP) && trade.OrderDelete(tk))
         n++;
     }
   // urdhrat e pambushur nuk ndiqen me
   for(int k = ArraySize(g_tr) - 1; k >= 0; k--)
      if(!g_tr[k].closed && g_tr[k].pos == 0 && !OrderSelect(g_tr[k].order))
         g_tr[k].closed = true;
   return n;
  }

//+------------------------------------------------------------------+
int FindTrade(const ulong order, const ulong pos)
  {
   for(int i = ArraySize(g_tr) - 1; i >= 0; i--)
     {
      if(g_tr[i].closed)
         continue;
      if(order > 0 && g_tr[i].order == order && g_tr[i].pos == 0)
         return i;
      if(pos > 0 && g_tr[i].pos == pos)
         return i;
     }
   return -1;
  }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != (long)InpMagicNumber || HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;
   long     kind  = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   ulong    order = (ulong)HistoryDealGetInteger(trans.deal, DEAL_ORDER);
   ulong    pos   = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   double   price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   datetime t     = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
   double   tv    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double   ts    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(kind == DEAL_ENTRY_IN)
     {
      int j = FindTrade(order, 0);
      if(j < 0)
         return;
      g_tr[j].pos = pos;
      g_tr[j].opened = t;
      g_tr[j].fill = price;
      g_tr[j].lots = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
      g_tr[j].riskMoney = ts > 0.0 ? MathAbs(price - g_tr[j].sl) / ts * tv * g_tr[j].lots : 0.0;
      g_status = (g_tr[j].dir == 1 ? "BLERJE" : "SHITJE") + string(" e hapur ne ") + DoubleToString(price, _Digits);
      Print("HYRJE ", g_tr[j].dir == 1 ? "BUY " : "SELL ", DoubleToString(price, _Digits), " | ARSYEJA: ", g_tr[j].why);
      return;
     }
   if(kind != DEAL_ENTRY_OUT && kind != DEAL_ENTRY_OUT_BY)
      return;
   int k = FindTrade(0, pos);
   if(k < 0)
      return;
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                   + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   double r = g_tr[k].riskMoney > 0.0 ? profit / g_tr[k].riskMoney : 0.0;
   long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   string out = reason == DEAL_REASON_SL ? "SL" : reason == DEAL_REASON_TP ? "TP" : reason == DEAL_REASON_SO ? "stop out"
                : reason == DEAL_REASON_EXPERT ? "EA (humbja ditore)" : "manual";
   g_n++;
   g_sumR += r;
   if(r > 0.0)
     {
      g_wins++;
      g_grossW += r;
     }
   else
      g_grossL -= r;
   Print("DALJE ", out, " ", DoubleToString(price, _Digits), " | ", StringFormat("%+.2fR %+.2f$", r, profit));
   if(InpDraw)
      DrawExit(k, t, price, r, out);
   if(g_file != INVALID_HANDLE)
      JournalWrite(k, t, price, out, r, profit);
   g_tr[k].closed = true;
  }

//+------------------------------------------------------------------+
void JournalOpen()
  {
   g_fileName = "GOOGLE_STRATEG_PRO_journal.csv";
   g_file = FileOpen(g_fileName, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
   if(g_file == INVALID_HANDLE)            // i hapur ne Excel: skedar i ri me date
     {
      g_fileName = "GOOGLE_STRATEG_PRO_journal_" + TimeToString(TimeLocal(), TIME_DATE) + ".csv";
      StringReplace(g_fileName, ".", "");
      StringReplace(g_fileName, "csv", ".csv");
      g_file = FileOpen(g_fileName, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
     }
   if(g_file == INVALID_HANDLE)
     {
      Print("Ditari nuk u hap (", GetLastError(), ")");
      g_fileName = "";
      return;
     }
   if(FileSize(g_file) == 0)
      FileWriteString(g_file, "nr,hyrja (server),hyrja (NY),dita,drejtimi,entry,SL,TP,loti,range low,range high,range $,"
                      "trendi %,dalja (server),cmimi i daljes,dalja,rezultati R,fitimi $,arsyeja e hyrjes (analiza)\r\n");
   FileSeek(g_file, 0, SEEK_END);
  }

void JournalWrite(const int k, const datetime tOut, const double pOut, const string out, const double r, const double profit)
  {
   string why = g_tr[k].why;
   StringReplace(why, ",", ";");
   FileWriteString(g_file, StringFormat("%d,%s,%s,%s,%s,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%s,%.2f,%s,%.2f,%.2f,%s\r\n",
                                        g_n, TimeToString(g_tr[k].opened, TIME_DATE | TIME_MINUTES), NYTime(g_tr[k].opened),
                                        DayName(g_tr[k].opened), g_tr[k].dir == 1 ? "BUY" : "SELL", g_tr[k].fill, g_tr[k].sl,
                                        g_tr[k].tp, g_tr[k].lots, g_tr[k].lo, g_tr[k].hi, g_tr[k].hi - g_tr[k].lo, g_tr[k].trendPct,
                                        TimeToString(tOut, TIME_DATE | TIME_MINUTES), pOut, out, r, profit, why));
   FileFlush(g_file);
  }

//+------------------------------------------------------------------+
void DrawLine(const string name, const datetime t1, const double p1, const datetime t2, const double p2, const color c,
              const int style, const string tip)
  {
   ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
  }

void DrawSetup(const datetime t0, const datetime t1, const datetime t2, const double hi, const double lo,
               const double entry, const double sl, const double tp, const string why)
  {
   string p = "GS_" + TimeToString(t0, TIME_DATE) + "_";
   ObjectCreate(0, p + "range", OBJ_RECTANGLE, 0, t0, hi, t1, lo);
   ObjectSetInteger(0, p + "range", OBJPROP_COLOR, clrDarkGray);
   ObjectSetInteger(0, p + "range", OBJPROP_FILL, true);
   ObjectSetInteger(0, p + "range", OBJPROP_BACK, true);
   ObjectSetInteger(0, p + "range", OBJPROP_SELECTABLE, false);
   ObjectSetString(0, p + "range", OBJPROP_TOOLTIP, why);
   DrawLine(p + "entry", t1, entry, t2, entry, clrDodgerBlue, STYLE_SOLID, "hyrja " + DoubleToString(entry, _Digits));
   DrawLine(p + "sl", t1, sl, t2, sl, clrRed, STYLE_DOT, "SL " + DoubleToString(sl, _Digits));
   DrawLine(p + "tp", t1, tp, t2, tp, clrLimeGreen, STYLE_DOT, "TP " + DoubleToString(tp, _Digits));
  }

void DrawExit(const int k, const datetime t, const double price, const double r, const string out)
  {
   string name = "GS_" + TimeToString(g_tr[k].opened, TIME_DATE | TIME_MINUTES) + "_trade";
   DrawLine(name, g_tr[k].opened, g_tr[k].fill, t, price, r > 0.0 ? clrLimeGreen : clrRed, STYLE_DASH,
            StringFormat("%s %+.2fR (%s) | %s", g_tr[k].dir == 1 ? "BUY" : "SELL", r, out, g_tr[k].why));
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
  }
//+------------------------------------------------------------------+
