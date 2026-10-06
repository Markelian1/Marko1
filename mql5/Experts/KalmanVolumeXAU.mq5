//+------------------------------------------------------------------+
//|                                              KalmanVolumeXAU.mq5 |
//|  EA per XAUUSD i ndertuar mbi parashikimin Kalman te vellimit    |
//|  (Chen, Feng & Palomar, SSRN 3101695).                           |
//|                                                                  |
//|  Hyrja: breakout Donchian (ose momentum/fade) ne mbyllje te barit |
//|  Moduli A: volume surprise (vellimi real / parashikimi)          |
//|  Moduli B: hyrje e ndare sipas vellimit te parashikuar (VWAP)    |
//|  Moduli C: regjimi i vellimit (aktiviteti i dites + SL adaptiv)  |
//|  Cdo modul ndizet/fiket vecmas nga parametrat. Default = vlerat  |
//|  me sjelljen me te mire IS+OOS (Donchian + B + C), PA fitim te    |
//|  provuar: shih analysis/XAUUSD_ANALIZA.md para perdorimit.       |
//|                                                                  |
//|  Rregullat jane te njejta me strategy/backtest.py.               |
//+------------------------------------------------------------------+
#property copyright "Markelian1/Marko1"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <KalmanVolume.mqh>

enum ENUM_KV_TRIGGER
  {
   TRIG_DONCHIAN = 0,   // Breakout Donchian
   TRIG_MOMENTUM = 1,   // Momentum i barit
   TRIG_FADE     = 2    // Kunder barit (fade)
  };

input group "=== Modeli i vellimit (Kalman) ==="
input int      InpTrainDays     = 60;     // Ditet e trajnimit per EM
input double   InpRobustK       = 3.0;    // Pragu robust ne sigma (0 = Kalman standard)
input int      InpSessionStart  = 100;    // Fillimi i sesionit, HHMM ora e serverit
input int      InpSessionEnd    = 2400;   // Fundi i sesionit, HHMM (ekskluziv)
input int      InpMinBinsPerDay = 40;     // Min. bare qe nje dite te hyje ne trajnim
input int      InpEMIterCold    = 30;     // Iteracione EM ne fitimin e pare
input int      InpEMIterWarm    = 5;      // Iteracione EM ne rifitimin ditor

input group "=== Hyrja ==="
input ENUM_KV_TRIGGER InpTrigger = TRIG_DONCHIAN; // Sinjali baze
input int      InpDonchian      = 20;     // Donchian: numri i bareve
input double   InpBodyATR       = 0.5;    // Momentum/Fade: trupi min. ne ATR
input int      InpTradeStart    = 900;    // Hyrje nga ora HHMM (serveri)
input int      InpTradeEnd      = 2000;   // Hyrje deri ne HHMM (ekskluziv)
input int      InpFlatAt        = 2330;   // Mbyll gjithcka ne HHMM
input int      InpMaxTradesDay  = 2;      // Max sinjale ne dite

input group "=== Rreziku dhe daljet ==="
input double   InpRiskPercent   = 1.0;    // Rreziku per tregti (% e equity)
input int      InpATRPeriod     = 14;     // Periudha ATR
input double   InpSL_ATR        = 1.5;    // Stop loss = x ATR
input double   InpRR            = 2.0;    // Take profit = x stop loss
input int      InpMaxHoldBars   = 16;     // Mbyll pas kaq baresh (0 = jo)
input int      InpMaxSpreadPts  = 40;     // Spread max per hyrje (pike)
input int      InpDeviationPts  = 20;     // Devijimi max i cmimit (pike)
input long     InpMagic         = 26010;  // Magic number

input group "=== Moduli A: volume surprise ==="
input bool     InpUseA          = false;  // Aktivizo modulin A (te dhenat: e demton breakout-in)
input double   InpA_MinZ        = 2.0;    // Surprise min: z = log(real/parashikim)/sigma
input double   InpA_MaxZ        = 99.0;   // Surprise max (z)

input group "=== Moduli B: hyrje e ndare sipas vellimit (VWAP) ==="
input bool     InpUseB          = true;   // Aktivizo modulin B
input int      InpB_Slices      = 3;      // Ne sa copa ndahet hyrja (2-6)

input group "=== Moduli C: regjimi i vellimit ==="
input bool     InpUseC          = true;   // Aktivizo modulin C
input double   InpC_ActMin      = 0.0;    // Aktiviteti min i dites (1 = normal)
input double   InpC_ActMax      = 99.0;   // Aktiviteti max i dites
input double   InpC_Beta        = 0.5;    // SL ~ (vellim i pritshem / aktual)^beta
input double   InpC_AdjMin      = 0.6;    // Shumezuesi min i SL
input double   InpC_AdjMax      = 1.8;    // Shumezuesi max i SL
input int      InpC_Horizon     = 8;      // Horizonti i parashikimit (bare)

//--- globals
CTrade         g_trade;
CKalmanVolume  g_kv;
int            g_atrHandle   = INVALID_HANDLE;
int            g_binMin      = 15;
int            g_startMin    = 60;
int            g_I           = 92;
bool           g_modelReady  = false;
long           g_modelDay    = -1;
datetime       g_lastBarTime = 0;
double         g_lastRatio   = 0.0;     // vellimi real / parashikimi i barit te fundit
double         g_lastZ       = 0.0;     // e njejta ne sigma: log(raporti) / sqrt(S)
bool           g_lastObserved = false;
int            g_emIters     = 0;
long           g_countDay    = -1;
int            g_tradesToday = 0;
// trade i gjalle / hyrje e ndare
datetime       g_signalTime  = 0;
int            g_dir         = 0;
double         g_sl          = 0.0;
double         g_tp          = 0.0;
double         g_lotsLeft    = 0.0;
int            g_slicesLeft  = 0;
double         g_lastAdj     = 1.0;

void FeedBar(datetime t, double volume);

//+------------------------------------------------------------------+
int HHMMToMin(int hhmm) { return (hhmm / 100) * 60 + hhmm % 100; }

int MinutesOfDay(datetime t)
  {
   MqlDateTime s;
   TimeToStruct(t, s);
   return s.hour * 60 + s.min;
  }

int HHMM(datetime t)
  {
   MqlDateTime s;
   TimeToStruct(t, s);
   return s.hour * 100 + s.min;
  }

long DayKey(datetime t) { return (long)t / 86400; }

int BinOf(datetime t)
  {
   int m = MinutesOfDay(t) - g_startMin;
   if(m < 0 || m % g_binMin != 0)
      return -1;
   int b = m / g_binMin;
   return (b < g_I) ? b : -1;
  }

//+------------------------------------------------------------------+
//| Rifiton modelin me ditet e plota para `today` dhe ushqen bare-t  |
//| e mbyllura te sotme deri ne `lastClosed`.                         |
//+------------------------------------------------------------------+
bool RefitModel(long today, datetime lastClosed)
  {
   int barsPerDay = 1440 / g_binMin;
   int need = (int)((InpTrainDays * 7 / 5 + 15) * barsPerDay);
   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   int got = CopyRates(_Symbol, _Period, lastClosed, need, rates);
   if(got <= 0)
     {
      PrintFormat("KalmanVolume: CopyRates deshtoi (%d)", GetLastError());
      return false;
     }
   //--- ditet e plota para dites se sotme
   long dayKeys[];
   int dayCount[];
   int nd = 0;
   for(int k = 0; k < got; k++)
     {
      long dk = DayKey(rates[k].time);
      if(dk >= today || BinOf(rates[k].time) < 0)
         continue;
      if(nd == 0 || dayKeys[nd - 1] != dk)
        {
         ArrayResize(dayKeys, nd + 1);
         ArrayResize(dayCount, nd + 1);
         dayKeys[nd] = dk;
         dayCount[nd] = 0;
         nd++;
        }
      dayCount[nd - 1]++;
     }
   long useKeys[];
   int nu = 0;
   for(int k = nd - 1; k >= 0 && nu < InpTrainDays; k--)
      if(dayCount[k] >= InpMinBinsPerDay)
        {
         ArrayResize(useKeys, nu + 1);
         useKeys[nu++] = dayKeys[k];
        }
   if(nu < InpTrainDays)
     {
      PrintFormat("KalmanVolume: vetem %d dite te vlefshme nga %d te kerkuara", nu, InpTrainDays);
      return false;
     }
   //--- useKeys eshte nga me e reja te me e vjetra -> dita 0 = me e vjetra
   if(!g_kv.Setup(g_I, InpTrainDays, InpRobustK))
      return false;
   for(int k = 0; k < got; k++)
     {
      long dk = DayKey(rates[k].time);
      int b = BinOf(rates[k].time);
      if(b < 0 || dk >= today)
         continue;
      for(int u = 0; u < nu; u++)
         if(useKeys[u] == dk)
           {
            g_kv.SetVolume(InpTrainDays - 1 - u, b, (double)rates[k].tick_volume);
            break;
           }
     }
   bool warm = g_kv.IsFitted();
   g_emIters = g_kv.Fit(warm ? InpEMIterWarm : InpEMIterCold, 1e-4, warm);
   if(g_emIters < 0)
     {
      Print("KalmanVolume: te dhena te pamjaftueshme per EM");
      return false;
     }
   PrintFormat("KalmanVolume: rifitim %s, EM=%d, a_eta=%.3f a_mu=%.3f s_eta2=%.4f s_mu2=%.4f r=%.4f",
               TimeToString((datetime)(today * 86400), TIME_DATE), g_emIters,
               g_kv.AEta(), g_kv.AMu(), g_kv.SEta2(), g_kv.SMu2(), g_kv.R());
   //--- ushqe bare-t e mbyllura te dites se sotme
   g_lastObserved = false;
   for(int k = 0; k < got; k++)
      if(DayKey(rates[k].time) == today && rates[k].time <= lastClosed)
         FeedBar(rates[k].time, (double)rates[k].tick_volume);
   return true;
  }

//+------------------------------------------------------------------+
//| Perditeson filtrin me nje bar te mbyllur                          |
//+------------------------------------------------------------------+
void FeedBar(datetime t, double volume)
  {
   g_lastObserved = false;
   g_lastRatio = 0.0;
   g_lastZ = 0.0;
   int b = BinOf(t);
   if(b < 0)
      return;
   int guard = 0;
   while(g_kv.CurBin() != b && guard++ < g_I)
     {
      if(g_kv.CurBin() > b)
         return;              // bar me i vjeter se gjendja, injoroje
      g_kv.Skip();            // bin pa te dhena
     }
   if(g_kv.CurBin() != b)
      return;
   double e, s, z;
   g_kv.Update(volume, e, s, z);
   if(volume >= 1.0)
     {
      g_lastObserved = true;
      g_lastRatio = MathExp(e);
      g_lastZ = e / MathSqrt(s);
     }
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   g_binMin = PeriodSeconds(_Period) / 60;
   g_startMin = HHMMToMin(InpSessionStart);
   int endMin = HHMMToMin(InpSessionEnd);
   if(g_binMin < 1 || g_binMin > 60 || endMin <= g_startMin || (endMin - g_startMin) % g_binMin != 0)
     {
      Print("KalmanVolume: timeframe ose sesion i pavlefshem (perdor M5-H1 dhe sesion qe ndahet ne bare)");
      return INIT_PARAMETERS_INCORRECT;
     }
   g_I = (endMin - g_startMin) / g_binMin;
   if(InpTrainDays < 10 || InpB_Slices < 2 || InpB_Slices > 6 || InpC_Horizon < 1 || InpRiskPercent <= 0)
      return INIT_PARAMETERS_INCORRECT;
   g_atrHandle = iATR(_Symbol, _Period, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
      return INIT_FAILED;
   g_trade.SetExpertMagicNumber((ulong)InpMagic);
   g_trade.SetDeviationInPoints((ulong)InpDeviationPts);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_modelReady = false;
   g_modelDay = -1;
   g_lastBarTime = 0;
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   Comment("");
  }

//+------------------------------------------------------------------+
//| Pozicionet e ketij EA                                             |
//+------------------------------------------------------------------+
int CountPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         n++;
     }
   return n;
  }

void CloseAll()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         g_trade.PositionClose(ticket);
     }
   g_slicesLeft = 0;
   g_lotsLeft = 0.0;
   g_signalTime = 0;
  }

datetime EarliestPositionTime()
  {
   datetime t = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      datetime pt = (datetime)PositionGetInteger(POSITION_TIME);
      if(t == 0 || pt < t)
         t = pt;
     }
   return t;
  }

double NormalizeLots(double lots)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0)
      return 0.0;
   lots = MathFloor(lots / step + 1e-9) * step;
   lots = MathMin(lots, vmax);
   int digits = (int)MathMax(0, MathCeil(-MathLog10(step)));
   return NormalizeDouble(lots, digits);
  }

double LotsForRisk(double slDist)
  {
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0 || tickValue <= 0 || slDist <= 0)
      return 0.0;
   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0;
   double lossPerLot = slDist / tickSize * tickValue;
   return riskMoney / lossPerLot;   // pa normalizim; behet per cdo cope
  }

//+------------------------------------------------------------------+
//| Dergon nje cope te hyrjes (ose te gjithe hyrjen pa modulin B)    |
//+------------------------------------------------------------------+
void ExecuteSlice()
  {
   if(g_slicesLeft <= 0 || g_lotsLeft <= 0)
      return;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;
   if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPts)
      return;                                   // provo ne barin tjeter
   //--- cmimi ka arritur tashme SL ose TP -> anulo pjesen e mbetur
   bool alive = (g_dir > 0) ? (tick.bid > g_sl && tick.bid < g_tp)
                            : (tick.ask < g_sl && tick.ask > g_tp);
   if(!alive)
     {
      g_slicesLeft = 0;
      g_lotsLeft = 0.0;
      return;
     }
   //--- pesha e copes: ek. 41, vellimi i barit tjeter / vellimi i copave te mbetura
   double w = 1.0;
   if(g_slicesLeft > 1)
     {
      double num = g_kv.ForecastVolume(1), den = 0.0;
      for(int h = 1; h <= g_slicesLeft; h++)
         den += g_kv.ForecastVolume(h);
      w = (den > 0) ? num / den : 1.0 / g_slicesLeft;
     }
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lots = NormalizeLots(g_lotsLeft * w);
   if(lots < minLot)
     {
      if(g_slicesLeft > 1)
        {
         g_slicesLeft--;                         // shtyje: pesha kalon te copat e tjera
         return;
        }
      lots = NormalizeLots(g_lotsLeft);
      if(lots < minLot)
        {
         g_slicesLeft = 0;
         g_lotsLeft = 0.0;
         return;
        }
     }
   double sl = NormalizeDouble(g_sl, _Digits);
   double tp = NormalizeDouble(g_tp, _Digits);
   bool ok = (g_dir > 0) ? g_trade.Buy(lots, _Symbol, tick.ask, sl, tp, "KVXAU")
                         : g_trade.Sell(lots, _Symbol, tick.bid, sl, tp, "KVXAU");
   if(ok && (g_trade.ResultRetcode() == TRADE_RETCODE_DONE || g_trade.ResultRetcode() == TRADE_RETCODE_PLACED))
     {
      g_lotsLeft -= lots;
      g_slicesLeft--;
     }
   else
      PrintFormat("KalmanVolume: urdhri deshtoi, retcode=%u", g_trade.ResultRetcode());
   if(g_slicesLeft <= 0 || g_lotsLeft < minLot)
     {
      g_slicesLeft = 0;
      g_lotsLeft = 0.0;
     }
  }

//+------------------------------------------------------------------+
//| Sinjali ne mbyllje te barit 1                                     |
//+------------------------------------------------------------------+
int SignalDirection(double atr)
  {
   double o = iOpen(_Symbol, _Period, 1), c = iClose(_Symbol, _Period, 1);
   if(InpTrigger == TRIG_DONCHIAN)
     {
      int hi = iHighest(_Symbol, _Period, MODE_HIGH, InpDonchian, 2);
      int lo = iLowest(_Symbol, _Period, MODE_LOW, InpDonchian, 2);
      if(hi < 0 || lo < 0)
         return 0;
      if(c > iHigh(_Symbol, _Period, hi))
         return 1;
      if(c < iLow(_Symbol, _Period, lo))
         return -1;
      return 0;
     }
   double body = c - o;
   if(MathAbs(body) < InpBodyATR * atr)
      return 0;
   int d = (body > 0) ? 1 : -1;
   return (InpTrigger == TRIG_FADE) ? -d : d;
  }

void TrySignal(datetime barTime)
  {
   int hhmm = HHMM(barTime);
   if(hhmm < InpTradeStart || hhmm >= InpTradeEnd)
      return;
   if(g_tradesToday >= InpMaxTradesDay)
      return;
   double atrBuf[];
   if(CopyBuffer(g_atrHandle, 0, 1, 1, atrBuf) != 1 || atrBuf[0] <= 0)
      return;
   double atr = atrBuf[0];
   int dir = SignalDirection(atr);
   if(dir == 0)
      return;
   //--- moduli A
   if(InpUseA && !(g_lastObserved && g_lastZ >= InpA_MinZ && g_lastZ <= InpA_MaxZ))
      return;
   //--- moduli C
   double adj = 1.0;
   if(InpUseC)
     {
      double act = g_kv.DayActivity();
      if(act < InpC_ActMin || act > InpC_ActMax)
         return;
      long vols[];
      if(CopyTickVolume(_Symbol, _Period, 1, 14, vols) == 14)
        {
         double v14 = 0.0;
         for(int k = 0; k < 14; k++)
            v14 += (double)vols[k];
         v14 /= 14.0;
         if(v14 > 0)
            adj = MathMin(MathMax(MathPow(g_kv.ForecastMeanVolume(InpC_Horizon) / v14, InpC_Beta),
                                  InpC_AdjMin), InpC_AdjMax);
        }
     }
   g_lastAdj = adj;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;
   if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPts)
      return;
   double dist = InpSL_ATR * atr * adj;
   double minDist = (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) + 1) * _Point
                    + (tick.ask - tick.bid);
   if(dist < minDist)
      return;
   double ref = (dir > 0) ? tick.ask : tick.bid;
   g_dir = dir;
   g_sl = ref - dir * dist;
   g_tp = ref + dir * InpRR * dist;
   g_lotsLeft = LotsForRisk(dist);
   g_slicesLeft = InpUseB ? InpB_Slices : 1;
   g_signalTime = barTime;
   g_tradesToday++;
   ExecuteSlice();
  }

//+------------------------------------------------------------------+
void ShowStatus(datetime barTime)
  {
   string s = StringFormat("KalmanVolume XAU | modeli %s | EM %d iter\n",
                           g_modelReady ? "gati" : "jo gati", g_emIters);
   if(g_modelReady)
     {
      s += StringFormat("a_eta %.3f  a_mu %.3f  r %.4f  bin %d/%d\n",
                        g_kv.AEta(), g_kv.AMu(), g_kv.R(), g_kv.CurBin(), g_I);
      s += StringFormat("Bari i fundit: vellimi/parashikimi = %.2fx (z = %+.2f)   aktiviteti i dites = %.2f\n",
                        g_lastRatio, g_lastZ, g_kv.DayActivity());
      s += StringFormat("Parashikimi i barit tjeter: %.0f   shumezuesi i SL (C): %.2f\n",
                        g_kv.ForecastVolume(1), g_lastAdj);
     }
   s += StringFormat("Moduli A %s | B %s | C %s", InpUseA ? "ON" : "off", InpUseB ? "ON" : "off",
                     InpUseC ? "ON" : "off");
   Comment(s);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   datetime t0 = iTime(_Symbol, _Period, 0);
   if(t0 == 0 || t0 == g_lastBarTime)
      return;
   g_lastBarTime = t0;
   datetime t1 = iTime(_Symbol, _Period, 1);
   long day1 = DayKey(t1);

   //--- 1) modeli: rifitim ne diten e re, perndryshe perditesim me barin e mbyllur.
   //    Nese rifitimi deshton (p.sh. historia ende po ngarkohet) provohet ne barin tjeter.
   if(day1 != g_modelDay)
     {
      g_modelReady = RefitModel(day1, t1);
      if(g_modelReady)
         g_modelDay = day1;
     }
   else if(g_modelReady)
      FeedBar(t1, (double)iVolume(_Symbol, _Period, 1));

   if(day1 != g_countDay)
     {
      g_countDay = day1;
      g_tradesToday = 0;
     }

   //--- 2) menaxhimi i tregtise se hapur
   int npos = CountPositions();
   if(npos > 0 && g_signalTime == 0)
      g_signalTime = EarliestPositionTime();    // pas restartit te EA/terminalit
   if(npos > 0 || g_slicesLeft > 0)
     {
      int held = iBarShift(_Symbol, _Period, g_signalTime, false) - 1;
      bool timeUp = (InpMaxHoldBars > 0 && held >= InpMaxHoldBars);
      bool flat = (HHMM(t1) >= InpFlatAt) || (DayKey(t0) != day1);
      if(timeUp || flat)
         CloseAll();
      else if(g_slicesLeft > 0)
         ExecuteSlice();
     }

   //--- 3) sinjal i ri vetem kur jemi flat
   if(g_modelReady && CountPositions() == 0 && g_slicesLeft == 0)
      TrySignal(t1);

   ShowStatus(t1);
  }
//+------------------------------------------------------------------+
