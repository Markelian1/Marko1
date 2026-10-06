//+------------------------------------------------------------------+
//|                                                 KalmanVolume.mqh |
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
//|  Keep this file inside the C++-compatible subset of MQL5 (no     |
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
