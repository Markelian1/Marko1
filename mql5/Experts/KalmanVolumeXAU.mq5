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
//|  Skedar i vetem: klasa CKalmanVolume eshte brenda ketij skedari.  |
//+------------------------------------------------------------------+
#property copyright "Markelian1/Marko1"
#property version   "1.00"

#include <Trade\Trade.mqh>

//=== BEGIN KalmanVolume (klasa e modelit, e futur ketu qe EA te jete nje skedar) ===
//+------------------------------------------------------------------+
//|                                    class CKalmanVolume           |
//|  Intraday volume forecasting with a Kalman filter + EM           |
//|  Chen, Feng & Palomar, "Forecasting Intraday Trading Volume:     |
//|  A Kalman Filter Approach" (SSRN 3101695)                        |
//|                                                                  |
//|  log V(t,i) = eta(t) + phi(i) + mu(t,i) + v(t,i) [+ z(t,i)]      |
//|  state x = [eta, mu]; eta moves only at day boundaries,          |
//|  mu is AR(1) bin to bin. Parameters: closed-form EM (Alg. 3).    |
//|                                                                  |
//|  Robust variant: Lasso soft-threshold of the innovation (eq. 33) |
//|  with threshold k*sqrt(S), i.e. lambda = 2k/sqrt(S).             |
//|                                                                  |
//|  Mirrors model/kalman_volume.py; tests/ checks both agree.       |
//|  Keep this block inside the C++-compatible subset of MQL5 (no    |
//|  array parameters, no MQL-only API) so the test harness can      |
//|  compile it with g++.                                            |
//+------------------------------------------------------------------+
#ifndef KALMAN_VOLUME_MQH
#define KALMAN_VOLUME_MQH

#define KV_MIN_VAR 1e-8
#define KV_A_MIN   0.0
#define KV_A_MAX   0.9999

class CKalmanVolume
  {
private:
   int               m_I;            // bins per day
   int               m_T;            // training days
   int               m_N;            // m_T * m_I
   double            m_robustK;      // 0 = standard Kalman filter
   // parameters theta
   double            m_aEta, m_aMu, m_sEta2, m_sMu2, m_r;
   double            m_pi0, m_pi1;
   double            m_S00, m_S01, m_S11;
   double            m_phi[];
   double            m_etaMean;
   bool              m_fitted;
   // training data
   double            m_y[];
   bool              m_obs[];
   // filter / smoother work arrays
   double            m_xp0[], m_xp1[], m_Pp00[], m_Pp01[], m_Pp11[];
   double            m_xf0[], m_xf1[], m_Pf00[], m_Pf01[], m_Pf11[];
   double            m_xs0[], m_xs1[], m_Ps00[], m_Ps01[], m_Ps11[];
   double            m_Pc0[], m_Pc1[];
   double            m_z[];
   // online state: predicted x(tau+1|tau) for bin m_curBin
   double            m_x0, m_x1, m_P00, m_P01, m_P11;
   int               m_curBin;

   //--- (a0, a1, q0, q1) for the step INTO flat index tNext
   void              Transition(int tNext, double &a0, double &a1, double &q0, double &q1)
     {
      a1 = m_aMu;
      q1 = m_sMu2;
      if(tNext % m_I == 0)
        {
         a0 = m_aEta;
         q0 = m_sEta2;
        }
      else
        {
         a0 = 1.0;
         q0 = 0.0;
        }
     }

   double            Shrink(double e, double S)
     {
      if(m_robustK <= 0.0)
         return 0.0;
      double th = m_robustK * MathSqrt(S);
      if(e > th)
         return e - th;
      if(e < -th)
         return e + th;
      return 0.0;
     }

   void              InitParams(void)
     {
      double tot = 0.0;
      int cnt = 0;
      for(int t = 0; t < m_N; t++)
         if(m_obs[t])
           {
            tot += m_y[t];
            cnt++;
           }
      double ybar = (cnt > 0) ? tot / cnt : 0.0;
      for(int i = 0; i < m_I; i++)
        {
         double s = 0.0;
         int c = 0;
         for(int d = 0; d < m_T; d++)
           {
            int t = d * m_I + i;
            if(m_obs[t])
              {
               s += m_y[t];
               c++;
              }
           }
         m_phi[i] = (c > 0) ? s / c : ybar;
        }
      double s1 = 0.0, s2 = 0.0, dmSum = 0.0, dmSum2 = 0.0;
      int c1 = 0, dc = 0;
      for(int d = 0; d < m_T; d++)
        {
         double ds = 0.0;
         int dn = 0;
         for(int i = 0; i < m_I; i++)
           {
            int t = d * m_I + i;
            if(m_obs[t])
              {
               double e = m_y[t] - m_phi[i];
               s1 += e;
               s2 += e * e;
               c1++;
               ds += e;
               dn++;
              }
           }
         if(dn > 0)
           {
            double mm = ds / dn;
            dmSum += mm;
            dmSum2 += mm * mm;
            dc++;
           }
        }
      double v = 1.0;
      if(c1 > 0)
         v = s2 / c1 - (s1 / c1) * (s1 / c1);
      double varD = 0.1 * v;
      if(dc > 0)
         varD = dmSum2 / dc - (dmSum / dc) * (dmSum / dc);
      varD = MathMax(varD, 1e-4);
      double w = MathMax(MathMax(v - varD, 0.1 * v), 1e-4);
      m_aEta  = 0.9;
      m_aMu   = 0.5;
      m_sEta2 = MathMax(varD * (1.0 - m_aEta * m_aEta), 1e-6);
      m_sMu2  = 0.25 * w;
      m_r     = 0.5 * w;
      m_pi0 = 0.0;
      m_pi1 = 0.0;
      m_S00 = varD;
      m_S01 = 0.0;
      m_S11 = w;
     }

   //--- E-step part 1: forward Kalman filter over the training window
   void              Filter(void)
     {
      double x0 = m_pi0, x1 = m_pi1;
      double P00 = m_S00, P01 = m_S01, P11 = m_S11;
      for(int t = 0; t < m_N; t++)
        {
         m_xp0[t] = x0;
         m_xp1[t] = x1;
         m_Pp00[t] = P00;
         m_Pp01[t] = P01;
         m_Pp11[t] = P11;
         m_z[t] = 0.0;
         if(m_obs[t])
           {
            double S  = P00 + 2.0 * P01 + P11 + m_r;
            double e  = m_y[t] - m_phi[t % m_I] - x0 - x1;
            double zt = Shrink(e, S);
            m_z[t] = zt;
            double k0 = (P00 + P01) / S;
            double k1 = (P01 + P11) / S;
            double eu = e - zt;
            x0 += k0 * eu;
            x1 += k1 * eu;
            P00 -= k0 * k0 * S;
            P01 -= k0 * k1 * S;
            P11 -= k1 * k1 * S;
           }
         m_xf0[t] = x0;
         m_xf1[t] = x1;
         m_Pf00[t] = P00;
         m_Pf01[t] = P01;
         m_Pf11[t] = P11;
         if(t + 1 < m_N)
           {
            double a0, a1, q0, q1;
            Transition(t + 1, a0, a1, q0, q1);
            x0 *= a0;
            x1 *= a1;
            P00 = a0 * a0 * P00 + q0;
            P01 = a0 * a1 * P01;
            P11 = a1 * a1 * P11 + q1;
           }
        }
     }

   //--- E-step part 2: RTS smoother + lag-one covariances (Alg. 2)
   void              Smooth(void)
     {
      int n = m_N - 1;
      m_xs0[n] = m_xf0[n];
      m_xs1[n] = m_xf1[n];
      m_Ps00[n] = m_Pf00[n];
      m_Ps01[n] = m_Pf01[n];
      m_Ps11[n] = m_Pf11[n];
      m_Pc0[0] = 0.0;
      m_Pc1[0] = 0.0;
      for(int t = m_N - 2; t >= 0; t--)
        {
         double a0, a1, q0, q1;
         Transition(t + 1, a0, a1, q0, q1);
         double f00 = m_Pf00[t], f01 = m_Pf01[t], f11 = m_Pf11[t];
         double p00 = m_Pp00[t + 1], p01 = m_Pp01[t + 1], p11 = m_Pp11[t + 1];
         double det = p00 * p11 - p01 * p01;
         double i00 = p11 / det, i01 = -p01 / det, i11 = p00 / det;
         double m00 = f00 * a0, m01 = f01 * a1, m10 = f01 * a0, m11 = f11 * a1;
         double L00 = m00 * i00 + m01 * i01;
         double L01 = m00 * i01 + m01 * i11;
         double L10 = m10 * i00 + m11 * i01;
         double L11 = m10 * i01 + m11 * i11;
         double d0 = m_xs0[t + 1] - m_xp0[t + 1];
         double d1 = m_xs1[t + 1] - m_xp1[t + 1];
         m_xs0[t] = m_xf0[t] + L00 * d0 + L01 * d1;
         m_xs1[t] = m_xf1[t] + L10 * d0 + L11 * d1;
         double D00 = m_Ps00[t + 1] - p00;
         double D01 = m_Ps01[t + 1] - p01;
         double D11 = m_Ps11[t + 1] - p11;
         double n00 = L00 * D00 + L01 * D01, n01 = L00 * D01 + L01 * D11;
         double n10 = L10 * D00 + L11 * D01, n11 = L10 * D01 + L11 * D11;
         m_Ps00[t] = f00 + n00 * L00 + n01 * L01;
         m_Ps01[t] = f01 + n00 * L10 + n01 * L11;
         m_Ps11[t] = f11 + n10 * L10 + n11 * L11;
         // Cov(x[t+1], x[t] | N) = Ps[t+1] * L' (diagonal terms only)
         double s00 = m_Ps00[t + 1], s01 = m_Ps01[t + 1], s11 = m_Ps11[t + 1];
         m_Pc0[t + 1] = s00 * L00 + s01 * L01;
         m_Pc1[t + 1] = s01 * L10 + s11 * L11;
        }
     }

   //--- M-step: closed-form updates (eqs. 17-24, robust 35-36)
   void              MStep(void)
     {
      double numE = 0.0, denE = 0.0;
      for(int t = m_I; t < m_N; t += m_I)
        {
         numE += m_Pc0[t] + m_xs0[t] * m_xs0[t - 1];
         denE += m_Ps00[t - 1] + m_xs0[t - 1] * m_xs0[t - 1];
        }
      double numM = 0.0, denM = 0.0;
      for(int t = 1; t < m_N; t++)
        {
         numM += m_Pc1[t] + m_xs1[t] * m_xs1[t - 1];
         denM += m_Ps11[t - 1] + m_xs1[t - 1] * m_xs1[t - 1];
        }
      double aEta = MathMin(MathMax(numE / denE, KV_A_MIN), KV_A_MAX);
      double aMu  = MathMin(MathMax(numM / denM, KV_A_MIN), KV_A_MAX);
      double se = 0.0;
      for(int t = m_I; t < m_N; t += m_I)
        {
         double Pt  = m_Ps00[t] + m_xs0[t] * m_xs0[t];
         double Pt1 = m_Ps00[t - 1] + m_xs0[t - 1] * m_xs0[t - 1];
         double Pct = m_Pc0[t] + m_xs0[t] * m_xs0[t - 1];
         se += Pt + aEta * aEta * Pt1 - 2.0 * aEta * Pct;
        }
      double sm = 0.0;
      for(int t = 1; t < m_N; t++)
        {
         double Pt  = m_Ps11[t] + m_xs1[t] * m_xs1[t];
         double Pt1 = m_Ps11[t - 1] + m_xs1[t - 1] * m_xs1[t - 1];
         double Pct = m_Pc1[t] + m_xs1[t] * m_xs1[t - 1];
         sm += Pt + aMu * aMu * Pt1 - 2.0 * aMu * Pct;
        }
      m_aEta  = aEta;
      m_aMu   = aMu;
      m_sEta2 = MathMax(se / (m_T - 1), KV_MIN_VAR);
      m_sMu2  = MathMax(sm / (m_N - 1), KV_MIN_VAR);
      for(int i = 0; i < m_I; i++)
        {
         double s = 0.0;
         int c = 0;
         for(int d = 0; d < m_T; d++)
           {
            int t = d * m_I + i;
            if(m_obs[t])
              {
               s += m_y[t] - m_z[t] - m_xs0[t] - m_xs1[t];
               c++;
              }
           }
         if(c > 0)
            m_phi[i] = s / c;
        }
      double rs = 0.0;
      int rc = 0;
      for(int t = 0; t < m_N; t++)
         if(m_obs[t])
           {
            double e = m_y[t] - m_z[t] - m_phi[t % m_I] - m_xs0[t] - m_xs1[t];
            rs += e * e + m_Ps00[t] + 2.0 * m_Ps01[t] + m_Ps11[t];
            rc++;
           }
      m_r = MathMax(rs / rc, KV_MIN_VAR);
      m_pi0 = m_xs0[0];
      m_pi1 = m_xs1[0];
      m_S00 = MathMax(m_Ps00[0], KV_MIN_VAR);
      m_S01 = m_Ps01[0];
      m_S11 = MathMax(m_Ps11[0], KV_MIN_VAR);
     }

public:
                     CKalmanVolume(void)
     {
      m_I = 0;
      m_T = 0;
      m_N = 0;
      m_robustK = 0.0;
      m_aEta = 0.0;
      m_aMu = 0.0;
      m_sEta2 = 0.0;
      m_sMu2 = 0.0;
      m_r = 0.0;
      m_pi0 = 0.0;
      m_pi1 = 0.0;
      m_S00 = 0.0;
      m_S01 = 0.0;
      m_S11 = 0.0;
      m_etaMean = 0.0;
      m_fitted = false;
      m_x0 = 0.0;
      m_x1 = 0.0;
      m_P00 = 0.0;
      m_P01 = 0.0;
      m_P11 = 0.0;
      m_curBin = 0;
     }

   //--- allocate for `days` x `binsPerDay` training observations
   bool              Setup(int binsPerDay, int days, double robustK)
     {
      if(binsPerDay < 2 || days < 5)
         return false;
      if(m_I != binsPerDay)
        {
         m_fitted = false;
         ArrayResize(m_phi, binsPerDay);
        }
      m_I = binsPerDay;
      m_T = days;
      m_N = days * binsPerDay;
      m_robustK = robustK;
      int n = m_N;
      if(ArrayResize(m_y, n) != n || ArrayResize(m_obs, n) != n)
         return false;
      ArrayResize(m_xp0, n);
      ArrayResize(m_xp1, n);
      ArrayResize(m_Pp00, n);
      ArrayResize(m_Pp01, n);
      ArrayResize(m_Pp11, n);
      ArrayResize(m_xf0, n);
      ArrayResize(m_xf1, n);
      ArrayResize(m_Pf00, n);
      ArrayResize(m_Pf01, n);
      ArrayResize(m_Pf11, n);
      ArrayResize(m_xs0, n);
      ArrayResize(m_xs1, n);
      ArrayResize(m_Ps00, n);
      ArrayResize(m_Ps01, n);
      ArrayResize(m_Ps11, n);
      ArrayResize(m_Pc0, n);
      ArrayResize(m_Pc1, n);
      if(ArrayResize(m_z, n) != n)
         return false;
      for(int t = 0; t < n; t++)
        {
         m_y[t] = 0.0;
         m_obs[t] = false;
        }
      return true;
     }

   //--- training observation: day 0 = oldest; volume < 1 is treated as missing
   void              SetVolume(int day, int bin, double volume)
     {
      if(day < 0 || day >= m_T || bin < 0 || bin >= m_I)
         return;
      int t = day * m_I + bin;
      if(volume >= 1.0)
        {
         m_y[t] = MathLog(volume);
         m_obs[t] = true;
        }
      else
        {
         m_y[t] = 0.0;
         m_obs[t] = false;
        }
     }

   //--- EM calibration; warmStart reuses the previous fit as initial values.
   //    Returns the number of EM iterations, or -1 if the data are unusable.
   int               Fit(int maxIter, double tol, bool warmStart)
     {
      int nObs = 0;
      for(int t = 0; t < m_N; t++)
         if(m_obs[t])
            nObs++;
      if(nObs < m_N / 2)
         return -1;
      if(!(warmStart && m_fitted))
         InitParams();
      int it = 0;
      for(it = 1; it <= maxIter; it++)
        {
         double o0 = m_aEta, o1 = m_aMu, o2 = m_sEta2, o3 = m_sMu2, o4 = m_r;
         Filter();
         Smooth();
         MStep();
         double rel = MathAbs(m_aEta - o0) / MathMax(MathAbs(o0), 1e-12);
         rel = MathMax(rel, MathAbs(m_aMu - o1) / MathMax(MathAbs(o1), 1e-12));
         rel = MathMax(rel, MathAbs(m_sEta2 - o2) / MathMax(MathAbs(o2), 1e-12));
         rel = MathMax(rel, MathAbs(m_sMu2 - o3) / MathMax(MathAbs(o3), 1e-12));
         rel = MathMax(rel, MathAbs(m_r - o4) / MathMax(MathAbs(o4), 1e-12));
         if(rel < tol)
            break;
        }
      if(it > maxIter)
         it = maxIter;
      // final pass with the fitted parameters: eta baseline + online state
      Filter();
      Smooth();
      double s = 0.0;
      for(int d = 0; d < m_T; d++)
         s += m_xs0[d * m_I];
      m_etaMean = s / m_T;
      m_fitted = true;
      OnlineReset();
      return it;
     }

   //--- predicted state for bin 0 of the day after the training window
   void              OnlineReset(void)
     {
      int n = m_N - 1;
      double a0 = m_aEta, a1 = m_aMu;
      m_x0 = a0 * m_xf0[n];
      m_x1 = a1 * m_xf1[n];
      m_P00 = a0 * a0 * m_Pf00[n] + m_sEta2;
      m_P01 = a0 * a1 * m_Pf01[n];
      m_P11 = a1 * a1 * m_Pf11[n] + m_sMu2;
      m_curBin = 0;
     }

   //--- h-step-ahead log-volume forecast (h=1: the bin m_curBin)
   double            ForecastLog(int h)
     {
      double eta = m_x0, mu = m_x1;
      int b = m_curBin;
      for(int k = 1; k < h; k++)
        {
         b++;
         if(b == m_I)
           {
            b = 0;
            eta *= m_aEta;
           }
         mu *= m_aMu;
        }
      return eta + mu + m_phi[b];
     }

   double            ForecastVolume(int h) { return MathExp(ForecastLog(h)); }

   //--- mean forecast volume over the next h bins
   double            ForecastMeanVolume(int h)
     {
      if(h < 1)
         return 0.0;
      double s = 0.0;
      for(int k = 1; k <= h; k++)
         s += ForecastVolume(k);
      return s / h;
     }

   //--- correct with the volume of bin m_curBin (volume < 1 = missing) and
   //    predict the next bin. innov = log(actual / forecast) before the update.
   void              Update(double volume, double &innov, double &innovVar, double &outlier)
     {
      double x0 = m_x0, x1 = m_x1;
      double P00 = m_P00, P01 = m_P01, P11 = m_P11;
      double S = P00 + 2.0 * P01 + P11 + m_r;
      innov = 0.0;
      outlier = 0.0;
      innovVar = S;
      if(volume >= 1.0)
        {
         double e = MathLog(volume) - m_phi[m_curBin] - x0 - x1;
         double zt = Shrink(e, S);
         double k0 = (P00 + P01) / S;
         double k1 = (P01 + P11) / S;
         double eu = e - zt;
         x0 += k0 * eu;
         x1 += k1 * eu;
         P00 -= k0 * k0 * S;
         P01 -= k0 * k1 * S;
         P11 -= k1 * k1 * S;
         innov = e;
         outlier = zt;
        }
      int nb = m_curBin + 1;
      double a0 = 1.0, q0 = 0.0;
      if(nb == m_I)
        {
         nb = 0;
         a0 = m_aEta;
         q0 = m_sEta2;
        }
      double a1 = m_aMu, q1 = m_sMu2;
      m_x0 = a0 * x0;
      m_x1 = a1 * x1;
      m_P00 = a0 * a0 * P00 + q0;
      m_P01 = a0 * a1 * P01;
      m_P11 = a1 * a1 * P11 + q1;
      m_curBin = nb;
     }

   //--- step over a bin with no data
   void              Skip(void)
     {
      double e, s, z;
      Update(0.0, e, s, z);
     }

   //--- today's volume level vs the training-window norm (1.0 = normal day)
   double            DayActivity(void) { return MathExp(m_x0 - m_etaMean); }

   bool              IsFitted(void) { return m_fitted; }
   int               CurBin(void)   { return m_curBin; }
   int               Bins(void)     { return m_I; }
   double            AEta(void)     { return m_aEta; }
   double            AMu(void)      { return m_aMu; }
   double            SEta2(void)    { return m_sEta2; }
   double            SMu2(void)     { return m_sMu2; }
   double            R(void)        { return m_r; }
   double            Phi(int i)     { return m_phi[i]; }
   double            Eta(void)      { return m_x0; }
   double            Mu(void)       { return m_x1; }
  };

#endif
//+------------------------------------------------------------------+
//=== END KalmanVolume ===

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
