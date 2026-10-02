//+------------------------------------------------------------------+
//|                                          GOOGLE_STRATEG_PRO.mq5  |
//|   GOOGLE STRATEG XAUUSD, i testuar dhe i permiresuar             |
//+------------------------------------------------------------------+
//  v3.00: ekzekutim ne M5. Tre logjika, secila me magic-un e vet:
//   1. NY CLOSE M5 (aktive): range 15:00-17:00 server (08:00-10:00 NY).
//      Kur nje qiri M5 mbyllet pertej range-it (+0.50 $) ne drejtim te
//      trendit ditor -> hyrje me treg. SL ne mes te range-it, TP 3R,
//      dalje ne 23:00 server (16:00 NY) nese s'eshte mbyllur.
//   2. AZIA RETEST M5 (aktive): range 01:00-09:00 server (18:00-02:00
//      NY). Pas mbylljes M5 pertej range-it ne drejtim te trendit ->
//      limit ne skajin e range-it (retest). SL pertej anes tjeter, TP 2R.
//      Anulohet ne 14:00 ose kur cmimi arrin TP pa retest.
//   3. STOP v2.00 (joaktive): buy / sell stop te range-it (logjika e
//      origjinalit me permiresimet e v2.00), per krahasim.
//  Testi (backtest/google_m5.py, MQL5/README.md): u provuan 1 200
//  variante me 5 logjika (close, retest, FVG, pullback, fade). Vetem
//  1 dhe 2 fitojne ne 2020-22, 2022-25, 2025 dhe 2026 (jashte zgjedhjes),
//  edhe kur ndryshohen ora, TP-ja dhe buffer-i, dhe e kalojne kontrollin
//  pa sinjal.
//  Trendi: mbyllja e djeshme mbi / nen SMA 50 D1 (origjinali: EMA 200 H1).
//  Gabime te origjinalit te rregulluara: "return" para menaxhimit te
//  pozicioneve, buffer ne pips qe varet nga shifrat e brokerit, mesazhe
//  gabimi ne cdo tick.
#property copyright "Copyright 2026"
#property link      "https://www.mql5.com"
#property version   "3.00"
#property description "Range breakout ne M5: mbyllje NY, retest i Azise, ne drejtim te trendit ditor"

#include <Trade/Trade.mqh>

CTrade trade;

#define SLOTS 3

enum ENUM_GS_TREND
  {
   TREND_D1_SMA50  = 0,   // D1: mbyllja e djeshme vs SMA 50
   TREND_H1_EMA200 = 1    // H1: mbyllja vs EMA 200 (origjinali)
  };

enum ENUM_GS_SL
  {
   SL_MID   = 0,          // ne mes te range-it
   SL_RANGE = 1,          // pertej anes tjeter te range-it
   SL_BAR   = 2           // pertej qiririt te sinjalit
  };

enum ENUM_GS_TYPE
  {
   GS_CLOSE  = 0,
   GS_RETEST = 1,
   GS_STOP   = 2
  };

input group "=== RREZIKU ==="
input double          InpRiskPercent      = 0.25;           // Rreziku per tregtim (%)
input double          InpMaxDailyDrawdown = 4.0;            // Humbja max ditore (%)
input double          InpMinRiskUSD       = 1.0;            // SL minimal ($): me pak, spread-i ha shume
input ulong           InpMagicNumber      = 123460;         // Magic baze (+0, +1, +2 per logjikat)

input group "=== TIMEFRAME DHE TRENDI ==="
input ENUM_TIMEFRAMES InpSignalTF         = PERIOD_M5;      // Timeframe i sinjaleve
input ENUM_GS_TREND   InpTrend            = TREND_D1_SMA50; // Filtri i trendit
input int             InpServerMinusNY    = 7;              // Ora e serverit - ora e New York (FP: 7)

input group "=== LOGJIKA 1: NY CLOSE M5 ==="
input bool            InpL1On             = true;           // Aktive
input string          InpL1Start          = "15:00";        // Fillimi i range (08:00 NY)
input string          InpL1End            = "17:00";        // Fundi i range (10:00 NY)
input string          InpL1Cancel         = "21:00";        // Pa hyrje te reja pas (14:00 NY)
input string          InpL1Exit           = "23:00";        // Dalje me ore (16:00 NY), bosh = pa dalje
input double          InpL1Buffer         = 0.50;           // Mbyllja pertej range-it me ($)
input ENUM_GS_SL      InpL1SL             = SL_MID;         // SL
input double          InpL1RR             = 3.0;            // TP = SL x RR

input group "=== LOGJIKA 2: AZIA RETEST M5 ==="
input bool            InpL2On             = true;           // Aktive
input string          InpL2Start          = "01:00";        // Fillimi i range (18:00 NY)
input string          InpL2End            = "09:00";        // Fundi i range (02:00 NY)
input string          InpL2Cancel         = "14:00";        // Anulimi i limit (07:00 NY)
input string          InpL2Exit           = "";             // Dalje me ore, bosh = pa dalje
input double          InpL2Buffer         = 0.50;           // Mbyllja pertej range-it me ($)
input ENUM_GS_SL      InpL2SL             = SL_RANGE;       // SL
input double          InpL2RR             = 2.0;            // TP = SL x RR

input group "=== LOGJIKA 3: STOP v2.00 (per krahasim) ==="
input bool            InpL3On             = false;          // Aktive
input string          InpL3Start          = "15:00";        // Fillimi i range
input string          InpL3End            = "17:00";        // Fundi i range / urdhri
input string          InpL3Cancel         = "21:00";        // Anulimi i urdhrit
input double          InpL3Buffer         = 1.50;           // Buffer nga range ($)
input ENUM_GS_SL      InpL3SL             = SL_RANGE;       // SL (mes ose pertej range-it)
input double          InpL3RR             = 3.0;            // TP = SL x RR

input group "=== DITARI DHE GRAFIKU ==="
input bool            InpJournal          = true;           // Ditar CSV ne Common\Files
input bool            InpDraw             = true;           // Vizato range dhe nivelet

struct GSTrade
  {
   int               slot;
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
   datetime          opened;
   bool              closed;               // u mbyll ose urdhri u anulua
   string            why;
  };

string   g_name[SLOTS] = {"NY CLOSE M5", "AZIA RETEST M5", "STOP v2"};
int      g_type[SLOTS] = {GS_CLOSE, GS_RETEST, GS_STOP};
bool     g_on[SLOTS];
int      g_s[SLOTS], g_e[SLOTS], g_c[SLOTS], g_x[SLOTS];   // sekonda nga mesnata, g_x < 0: pa dalje me ore
double   g_buf[SLOTS], g_rr[SLOTS];
int      g_slm[SLOTS];
// gjendja e dites per cdo logjike
bool     g_done[SLOTS];
bool     g_ready[SLOTS];
int      g_dir[SLOTS];
int      g_tries[SLOTS];
double   g_hi[SLOTS], g_lo[SLOTS], g_pct[SLOTS];
string   g_stat[SLOTS];
// rezultatet
int      g_n[SLOTS], g_w[SLOTS];
double   g_sumR[SLOTS], g_gw[SLOTS], g_gl[SLOTS];

GSTrade  g_tr[];
int      g_trendHandle = INVALID_HANDLE;
datetime g_day = 0;
datetime g_lastBar = 0;
bool     g_ddStop = false;
double   g_dayBalance = 0.0;
int      g_file = INVALID_HANDLE;
string   g_fileName = "";
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

string NYClock(const int secs)
  {
   int s = ((secs - InpServerMinusNY * 3600) % 86400 + 86400) % 86400;
   return StringFormat("%02d:%02d", s / 3600, (s % 3600) / 60);
  }

string HMClock(const int secs)
  {
   return StringFormat("%02d:%02d", secs / 3600, (secs % 3600) / 60);
  }

string NYTime(const datetime t)
  {
   return TimeToString(t - InpServerMinusNY * 3600, TIME_MINUTES);
  }

string DayName(const datetime t)
  {
   static string names[7] = {"E diel", "E hene", "E marte", "E merkure", "E enjte", "E premte", "E shtune"};
   MqlDateTime d;
   TimeToStruct(t - InpServerMinusNY * 3600, d);
   return names[d.day_of_week];
  }

ulong SlotMagic(const int s)
  {
   return InpMagicNumber + (ulong)s;
  }

//+------------------------------------------------------------------+
bool SetSlot(const int s, const bool on, const string st, const string en, const string cx, const string ex,
             const double buf, const int slm, const double rr)
  {
   g_on[s] = on;
   g_s[s] = ParseHM(st);
   g_e[s] = ParseHM(en);
   g_c[s] = ParseHM(cx);
   g_x[s] = ex == "" ? -1 : ParseHM(ex);
   g_buf[s] = buf;
   g_slm[s] = slm;
   g_rr[s] = rr;
   if(!on)
      return true;
   if(g_s[s] < 0 || g_e[s] < 0 || g_c[s] < 0 || !(g_s[s] < g_e[s] && g_e[s] < g_c[s]) || (ex != "" && g_x[s] <= g_e[s])
      || buf < 0.0 || rr <= 0.0)
     {
      Print("GABIM te ", g_name[s], ": oraret duhet te jene HH:MM, fillimi < fundi < anulimi (< dalja) brenda dites.");
      return false;
     }
   return true;
  }

int OnInit()
  {
   if(!SetSlot(0, InpL1On, InpL1Start, InpL1End, InpL1Cancel, InpL1Exit, InpL1Buffer, InpL1SL, InpL1RR)
      || !SetSlot(1, InpL2On, InpL2Start, InpL2End, InpL2Cancel, InpL2Exit, InpL2Buffer, InpL2SL, InpL2RR)
      || !SetSlot(2, InpL3On, InpL3Start, InpL3End, InpL3Cancel, "", InpL3Buffer, InpL3SL, InpL3RR))
      return INIT_PARAMETERS_INCORRECT;
   if(InpRiskPercent <= 0.0)
      return INIT_PARAMETERS_INCORRECT;

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
   for(int s = 0; s < SLOTS; s++)
     {
      g_n[s] = g_w[s] = 0;
      g_sumR[s] = g_gw[s] = g_gl[s] = 0.0;
      if(g_on[s])
         Print(g_name[s], " | range ", HMClock(g_s[s]), "-", HMClock(g_e[s]), " server (", NYClock(g_s[s]), "-",
               NYClock(g_e[s]), " NY) | deri ", HMClock(g_c[s]), " | SL ", EnumToString((ENUM_GS_SL)g_slm[s]),
               " | TP ", DoubleToString(g_rr[s], 1), "R", g_x[s] >= 0 ? " | dalje " + HMClock(g_x[s]) : "");
     }
   if(InpJournal)
      JournalOpen();
   Print("GOOGLE STRATEG PRO v3.00 | sinjalet ", EnumToString(InpSignalTF), " | trendi ",
         InpTrend == TREND_D1_SMA50 ? "D1 SMA50" : "H1 EMA200", " | rreziku ", DoubleToString(InpRiskPercent, 2), "%");
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
   for(int s = 0; s < SLOTS; s++)
      if(g_on[s])
         Print("GOOGLE STRATEG PRO v3.00 ", g_name[s], ": ", g_n[s], " tregtime, ", g_w[s], " fitime (",
               DoubleToString(g_n[s] > 0 ? 100.0 * g_w[s] / g_n[s] : 0.0, 1), "%), PF ",
               DoubleToString(g_gl[s] > 0 ? g_gw[s] / g_gl[s] : 0.0, 2), ", shuma ", DoubleToString(g_sumR[s], 1), "R");
   if(g_fileName != "")
      Print("Ditari: Common\\Files\\", g_fileName);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   datetime now = TimeCurrent();
   datetime day = now - now % 86400;
   if(day != g_day)
     {
      g_day = day;
      g_ddStop = false;
      g_dayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      for(int s = 0; s < SLOTS; s++)
        {
         g_done[s] = !g_on[s];
         g_ready[s] = false;
         g_dir[s] = 0;
         g_tries[s] = 0;
         g_stat[s] = g_on[s] ? "pritet range " + HMClock(g_s[s]) + "-" + HMClock(g_e[s]) : "joaktive";
        }
     }

   if(!g_ddStop && g_dayBalance - AccountInfoDouble(ACCOUNT_EQUITY) >= g_dayBalance * InpMaxDailyDrawdown / 100.0)
     {
      g_ddStop = true;
      for(int s = 0; s < SLOTS; s++)
        {
         ClosePositions(s, day, true);
         DeletePendings(s);
         g_done[s] = true;
         g_stat[s] = "humbja ditore " + DoubleToString(InpMaxDailyDrawdown, 1) + "%: pa tregtime deri neser";
        }
      Print("KUJDES: humbja ditore u arrit, pozicionet u mbyllen.");
     }

   for(int s = 0; s < SLOTS; s++)
     {
      if(!g_on[s])
         continue;
      if(g_x[s] >= 0)
         ClosePositions(s, day, now >= day + g_x[s]);
      if(now >= day + g_c[s])
        {
         if(DeletePendings(s) > 0)
            g_stat[s] = "urdhri nuk u mbush deri " + HMClock(g_c[s]) + ": u anulua";
         g_done[s] = true;
        }
     }
   CancelRetestsAtTP();

   datetime bt = iTime(_Symbol, InpSignalTF, 0);
   if(bt != 0 && bt != g_lastBar)
     {
      g_lastBar = bt;
      if(!g_ddStop)
         for(int s = 0; s < SLOTS; s++)
            if(g_type[s] != GS_STOP)
               OnBarClosed(s, day);
     }
   if(!g_ddStop && g_on[2] && !g_done[2] && now >= day + g_e[2] && now < day + g_c[2])
      TryStop(2, day);

   if(now - g_lastPanel >= 60)
     {
      g_lastPanel = now;
      string txt = "GOOGLE STRATEG PRO v3.00 (" + EnumToString(InpSignalTF) + ")\n";
      for(int s = 0; s < SLOTS; s++)
         if(g_on[s])
            txt += g_name[s] + ": " + g_stat[s] + " | " + IntegerToString(g_n[s]) + " tregtime, "
                   + DoubleToString(g_sumR[s], 1) + "R\n";
      Comment(txt);
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

string TrendText(const int s)
  {
   return (InpTrend == TREND_D1_SMA50 ? "Trendi ditor " : "Trendi H1 ") + (g_dir[s] == 1 ? "UP" : (g_dir[s] == -1 ? "DOWN" : "pa drejtim"))
          + StringFormat(": mbyllja %+.2f%% nga ", g_pct[s]) + (InpTrend == TREND_D1_SMA50 ? "SMA50 D1" : "EMA200 H1");
  }

bool RangeBounds(const datetime t0, const datetime t1, double &hi, double &lo)
  {
   MqlRates r[];
   int n = CopyRates(_Symbol, InpSignalTF, t0, t1, r);
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

// range-i dhe trendi, nje here ne dite per cdo logjike
bool PrepareDay(const int s, const datetime day)
  {
   if(g_ready[s])
      return g_dir[s] != 0;
   double hi, lo;
   if(!RangeBounds(day + g_s[s], day + g_e[s], hi, lo))
     {
      g_stat[s] = "pa qirinj ne range (feste?)";
      return false;
     }
   g_ready[s] = true;
   g_hi[s] = hi;
   g_lo[s] = lo;
   double pct;
   g_dir[s] = GetTrend(pct);
   g_pct[s] = pct;
   if(g_dir[s] == 0)
     {
      g_done[s] = true;
      g_stat[s] = "pa trend: sot pa tregtim";
      return false;
     }
   g_stat[s] = StringFormat("range %.2f-%.2f, trendi %s: pritet ", lo, hi, g_dir[s] == 1 ? "UP" : "DOWN")
               + (g_type[s] == GS_STOP ? "urdhri stop" : "mbyllja " + EnumToString(InpSignalTF) + " pertej range-it");
   if(InpDraw)
     {
      string p = "GS" + IntegerToString(s) + "_" + TimeToString(day, TIME_DATE) + "_range";
      ObjectCreate(0, p, OBJ_RECTANGLE, 0, day + g_s[s], hi, day + g_e[s], lo);
      ObjectSetInteger(0, p, OBJPROP_COLOR, s == 1 ? clrSlateGray : clrDarkGray);
      ObjectSetInteger(0, p, OBJPROP_FILL, true);
      ObjectSetInteger(0, p, OBJPROP_BACK, true);
      ObjectSetInteger(0, p, OBJPROP_SELECTABLE, false);
      ObjectSetString(0, p, OBJPROP_TOOLTIP, g_name[s] + ": " + g_stat[s] + " | " + TrendText(s));
     }
   return true;
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

string SLText(const int s, const int dir)
  {
   if(g_slm[s] == SL_MID)
      return "mesi i range-it";
   if(g_slm[s] == SL_RANGE)
      return StringFormat("%s %s $%.2f (pertej range-it)", dir == 1 ? "fundi" : "maja", dir == 1 ? "-" : "+", g_buf[s]);
   return StringFormat("pertej qiririt te sinjalit %s $%.2f", dir == 1 ? "-" : "+", g_buf[s]);
  }

//+------------------------------------------------------------------+
// logjikat 1 dhe 2: vendimi merret ne mbylljen e qiririt te sinjalit
void OnBarClosed(const int s, const datetime day)
  {
   if(!g_on[s] || g_done[s])
      return;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, InpSignalTF, 1, 1, r) != 1)
      return;
   datetime tb = r[0].time;
   if(tb < day + g_e[s] || tb >= day + g_c[s])
      return;
   if(!PrepareDay(s, day))
      return;
   int d = g_dir[s];
   double hi = g_hi[s], lo = g_lo[s], buf = g_buf[s];
   if(!((d == 1 && r[0].close > hi + buf) || (d == -1 && r[0].close < lo - buf)))
      return;
   g_done[s] = true;                       // nje sinjal ne dite
   double sl;
   if(g_slm[s] == SL_MID)
      sl = (hi + lo) / 2.0;
   else
      if(g_slm[s] == SL_RANGE)
         sl = d == 1 ? lo - buf : hi + buf;
      else
         if(g_type[s] == GS_RETEST)
            sl = d == 1 ? MathMin(r[0].low, hi - InpMinRiskUSD) - buf : MathMax(r[0].high, lo + InpMinRiskUSD) + buf;
         else
            sl = d == 1 ? r[0].low - buf : r[0].high + buf;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = g_type[s] == GS_CLOSE ? (d == 1 ? ask : bid) : (d == 1 ? hi : lo);
   double risk = d == 1 ? entry - sl : sl - entry;
   if(risk < InpMinRiskUSD)
     {
      g_stat[s] = StringFormat("SL vetem $%.2f (< $%.2f): sot pa tregtim", risk, InpMinRiskUSD);
      return;
     }
   sl = NormalizeDouble(sl, _Digits);
   double tp = NormalizeDouble(d == 1 ? entry + g_rr[s] * risk : entry - g_rr[s] * risk, _Digits);
   double lots = LotSize(risk);
   if(lots <= 0.0)
     {
      g_stat[s] = "loti del nen minimumin: sot pa tregtim";
      return;
     }
   string head = StringFormat("%s %s: range %s-%s server (%s-%s NY) %.2f-%.2f ($%.2f). %s. Qiriri %s i %s (%s NY) mbylli %.2f %s $%.2f",
                              g_name[s], d == 1 ? "BUY" : "SELL", HMClock(g_s[s]), HMClock(g_e[s]), NYClock(g_s[s]),
                              NYClock(g_e[s]), lo, hi, hi - lo, TrendText(s), EnumToString(InpSignalTF),
                              TimeToString(tb, TIME_MINUTES), NYTime(tb), r[0].close, d == 1 ? "mbi majen +" : "nen fundin -", buf);
   trade.SetExpertMagicNumber(SlotMagic(s));
   bool ok;
   string why;
   if(g_type[s] == GS_CLOSE)
     {
      why = head + StringFormat(" -> hyrje me treg. SL = %s, TP = %.1fR ($%.2f)%s.", SLText(s, d), g_rr[s], g_rr[s] * risk,
                                g_x[s] >= 0 ? ", dalje ne " + HMClock(g_x[s]) + " server (" + NYClock(g_x[s]) + " NY) nese s'mbyllet me pare" : "");
      ok = d == 1 ? trade.Buy(lots, _Symbol, 0.0, sl, tp, g_name[s] + " BUY") : trade.Sell(lots, _Symbol, 0.0, sl, tp, g_name[s] + " SELL");
     }
   else
     {
      double minDist = (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) + 1) * _Point;
      if((d == 1 && ask - entry < minDist) || (d == -1 && entry - bid < minDist))
        {
         g_stat[s] = "cmimi eshte tashme te skaji: pa limit sot";
         return;
        }
      entry = NormalizeDouble(entry, _Digits);
      why = head + StringFormat(" -> %s ne %s %.2f (retest). SL = %s, TP = %.1fR ($%.2f). Anulohet ne %s ose kur cmimi arrin TP pa retest.",
                                d == 1 ? "buy limit" : "sell limit", d == 1 ? "majen" : "fundin", entry, SLText(s, d),
                                g_rr[s], g_rr[s] * risk, HMClock(g_c[s]));
      ok = d == 1 ? trade.BuyLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_DAY, 0, g_name[s] + " BUY")
           : trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_DAY, 0, g_name[s] + " SELL");
     }
   if(!ok || trade.ResultOrder() == 0)
     {
      g_stat[s] = "urdhri u refuzua: " + IntegerToString(trade.ResultRetcode()) + " " + trade.ResultRetcodeDescription();
      Print(g_name[s], " GABIM: ", g_stat[s]);
      return;
     }
   AddTrade(s, trade.ResultOrder(), d, entry, sl, tp, lots, why);
   g_stat[s] = g_type[s] == GS_CLOSE ? (d == 1 ? "BLERJE" : "SHITJE") + string(" e hapur")
               : (d == 1 ? "buy limit ne " : "sell limit ne ") + DoubleToString(entry, _Digits);
   Print("URDHER: ", why);
   if(InpDraw)
      DrawLevels(s, tb, day + g_c[s], entry, sl, tp, why);
  }

// logjika 3 (v2.00): urdher stop, provohet ne cdo tick deri sa cmimi te jete para hyrjes
void TryStop(const int s, const datetime day)
  {
   if(!PrepareDay(s, day))
      return;
   int d = g_dir[s];
   double hi = g_hi[s], lo = g_lo[s], buf = g_buf[s], rng = hi - lo;
   double dist = g_slm[s] == SL_MID ? rng / 2.0 + buf : rng + 2.0 * buf;
   double entry = NormalizeDouble(d == 1 ? hi + buf : lo - buf, _Digits);
   double sl = NormalizeDouble(d == 1 ? entry - dist : entry + dist, _Digits);
   double tp = NormalizeDouble(d == 1 ? entry + g_rr[s] * dist : entry - g_rr[s] * dist, _Digits);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minDist = (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) + 1) * _Point;
   if((d == 1 && entry - ask < minDist) || (d == -1 && bid - entry < minDist))
     {
      g_stat[s] = "cmimi eshte pertej hyrjes " + DoubleToString(entry, _Digits) + ": pritet kthimi";
      return;
     }
   double lots = LotSize(dist);
   if(lots <= 0.0)
     {
      g_done[s] = true;
      g_stat[s] = "loti del nen minimumin: sot pa urdher";
      return;
     }
   string why = StringFormat("%s %s STOP: range %s-%s server (%s-%s NY) %.2f-%.2f ($%.2f). %s. Hyrja = %s %s $%.2f, SL = %s, TP = %.1fR ($%.2f).",
                             g_name[s], d == 1 ? "BUY" : "SELL", HMClock(g_s[s]), HMClock(g_e[s]), NYClock(g_s[s]), NYClock(g_e[s]),
                             lo, hi, rng, TrendText(s), d == 1 ? "maja" : "fundi", d == 1 ? "+" : "-", buf,
                             g_slm[s] == SL_MID ? "mesi i range-it" : SLText(s, d), g_rr[s], g_rr[s] * dist);
   trade.SetExpertMagicNumber(SlotMagic(s));
   bool ok = d == 1 ? trade.BuyStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_DAY, 0, g_name[s] + " BUY")
             : trade.SellStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_DAY, 0, g_name[s] + " SELL");
   if(!ok || trade.ResultOrder() == 0)
     {
      if(++g_tries[s] >= 3)
        {
         g_done[s] = true;
         g_stat[s] = "urdhri u refuzua 3 here: sot pa urdher";
        }
      return;
     }
   g_done[s] = true;
   AddTrade(s, trade.ResultOrder(), d, entry, sl, tp, lots, why);
   g_stat[s] = (d == 1 ? "buy stop ne " : "sell stop ne ") + DoubleToString(entry, _Digits);
   Print("URDHER: ", why);
   if(InpDraw)
      DrawLevels(s, day + g_e[s], day + g_c[s], entry, sl, tp, why);
  }

void AddTrade(const int s, const ulong order, const int d, const double entry, const double sl, const double tp,
              const double lots, const string why)
  {
   int k = ArraySize(g_tr);
   ArrayResize(g_tr, k + 1);
   g_tr[k].slot = s;
   g_tr[k].order = order;
   g_tr[k].pos = 0;
   g_tr[k].dir = d;
   g_tr[k].entry = entry;
   g_tr[k].sl = sl;
   g_tr[k].tp = tp;
   g_tr[k].hi = g_hi[s];
   g_tr[k].lo = g_lo[s];
   g_tr[k].trendPct = g_pct[s];
   g_tr[k].lots = lots;
   g_tr[k].fill = 0.0;
   g_tr[k].riskMoney = 0.0;
   g_tr[k].opened = 0;
   g_tr[k].closed = false;
   g_tr[k].why = why;
  }

//+------------------------------------------------------------------+
// closeAll: mbyll te gjitha pozicionet e logjikes; perndryshe vetem ato te hapura dite me pare
void ClosePositions(const int s, const datetime day, const bool closeAll)
  {
   trade.SetExpertMagicNumber(SlotMagic(s));
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != (long)SlotMagic(s))
         continue;
      if(closeAll || (datetime)PositionGetInteger(POSITION_TIME) < day)
         trade.PositionClose(tk);
     }
  }

int DeletePendings(const int s)
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0 || OrderGetString(ORDER_SYMBOL) != _Symbol || OrderGetInteger(ORDER_MAGIC) != (long)SlotMagic(s))
         continue;
      if(trade.OrderDelete(tk))
         n++;
     }
   for(int k = ArraySize(g_tr) - 1; k >= 0; k--)
      if(g_tr[k].slot == s && !g_tr[k].closed && g_tr[k].pos == 0 && !OrderSelect(g_tr[k].order))
         g_tr[k].closed = true;
   return n;
  }

// logjika 2: limit-i anulohet kur cmimi arrin TP para retest-it
void CancelRetestsAtTP()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0 || OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      long magic = OrderGetInteger(ORDER_MAGIC);
      int s = (int)(magic - (long)InpMagicNumber);
      if(s < 0 || s >= SLOTS || g_type[s] != GS_RETEST)
         continue;
      double tp = OrderGetDouble(ORDER_TP);
      ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if((t == ORDER_TYPE_BUY_LIMIT && SymbolInfoDouble(_Symbol, SYMBOL_BID) >= tp)
         || (t == ORDER_TYPE_SELL_LIMIT && SymbolInfoDouble(_Symbol, SYMBOL_ASK) <= tp))
         if(trade.OrderDelete(tk))
           {
            g_stat[s] = "cmimi arriti TP pa retest: limit-i u anulua";
            for(int k = ArraySize(g_tr) - 1; k >= 0; k--)
               if(g_tr[k].order == tk)
                  g_tr[k].closed = true;
           }
     }
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
   long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(magic < (long)InpMagicNumber || magic >= (long)InpMagicNumber + SLOTS || HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
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
      g_stat[g_tr[j].slot] = (g_tr[j].dir == 1 ? "BLERJE" : "SHITJE") + string(" e hapur ne ") + DoubleToString(price, _Digits);
      Print("HYRJE ", g_tr[j].dir == 1 ? "BUY " : "SELL ", DoubleToString(price, _Digits), " | ARSYEJA: ", g_tr[j].why);
      return;
     }
   if(kind != DEAL_ENTRY_OUT && kind != DEAL_ENTRY_OUT_BY)
      return;
   int k = FindTrade(0, pos);
   if(k < 0)
      return;
   int s = g_tr[k].slot;
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                   + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   double r = g_tr[k].riskMoney > 0.0 ? profit / g_tr[k].riskMoney : 0.0;
   long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   string out = "manual";
   if(reason == DEAL_REASON_SL)
      out = "SL";
   else
      if(reason == DEAL_REASON_TP)
         out = "TP";
      else
         if(reason == DEAL_REASON_SO)
            out = "stop out";
         else
            if(reason == DEAL_REASON_EXPERT)
               out = "EA (ora / humbja ditore)";
   g_n[s]++;
   g_sumR[s] += r;
   if(r > 0.0)
     {
      g_w[s]++;
      g_gw[s] += r;
     }
   else
      g_gl[s] -= r;
   g_stat[s] = StringFormat("u mbyll %s %+.2fR", out, r);
   Print("DALJE ", g_name[s], " ", out, " ", DoubleToString(price, _Digits), " | ", StringFormat("%+.2fR %+.2f$", r, profit));
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
      FileWriteString(g_file, "nr,logjika,hyrja (server),hyrja (NY),dita,drejtimi,entry,SL,TP,loti,range low,range high,range $,"
                      "trendi %,dalja (server),cmimi i daljes,dalja,rezultati R,fitimi $,arsyeja e hyrjes (analiza)\r\n");
   FileSeek(g_file, 0, SEEK_END);
  }

void JournalWrite(const int k, const datetime tOut, const double pOut, const string out, const double r, const double profit)
  {
   int s = g_tr[k].slot;
   string why = g_tr[k].why;
   StringReplace(why, ",", ";");
   FileWriteString(g_file, StringFormat("%d,%s,%s,%s,%s,%s,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%s,%.2f,%s,%.2f,%.2f,%s\r\n",
                                        g_n[0] + g_n[1] + g_n[2], g_name[s], TimeToString(g_tr[k].opened, TIME_DATE | TIME_MINUTES),
                                        NYTime(g_tr[k].opened), DayName(g_tr[k].opened), g_tr[k].dir == 1 ? "BUY" : "SELL",
                                        g_tr[k].fill, g_tr[k].sl, g_tr[k].tp, g_tr[k].lots, g_tr[k].lo, g_tr[k].hi,
                                        g_tr[k].hi - g_tr[k].lo, g_tr[k].trendPct, TimeToString(tOut, TIME_DATE | TIME_MINUTES),
                                        pOut, out, r, profit, why));
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

void DrawLevels(const int s, const datetime t1, const datetime t2, const double entry, const double sl, const double tp, const string why)
  {
   string p = "GS" + IntegerToString(s) + "_" + TimeToString(t1, TIME_DATE | TIME_MINUTES) + "_";
   DrawLine(p + "entry", t1, entry, t2, entry, clrDodgerBlue, STYLE_SOLID, "hyrja " + DoubleToString(entry, _Digits) + " | " + why);
   DrawLine(p + "sl", t1, sl, t2, sl, clrRed, STYLE_DOT, "SL " + DoubleToString(sl, _Digits));
   DrawLine(p + "tp", t1, tp, t2, tp, clrLimeGreen, STYLE_DOT, "TP " + DoubleToString(tp, _Digits));
  }

void DrawExit(const int k, const datetime t, const double price, const double r, const string out)
  {
   string name = "GS" + IntegerToString(g_tr[k].slot) + "_" + TimeToString(g_tr[k].opened, TIME_DATE | TIME_MINUTES) + "_trade";
   DrawLine(name, g_tr[k].opened, g_tr[k].fill, t, price, r > 0.0 ? clrLimeGreen : clrRed, STYLE_DASH,
            StringFormat("%s %+.2fR (%s) | %s", g_tr[k].dir == 1 ? "BUY" : "SELL", r, out, g_tr[k].why));
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
  }
//+------------------------------------------------------------------+
