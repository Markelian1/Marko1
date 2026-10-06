"""Reference implementation of the intraday volume Kalman filter.

Chen, Feng & Palomar, "Forecasting Intraday Trading Volume: A Kalman Filter
Approach" (SSRN 3101695). Log-volume of bin i on day t is modelled as

    y[t,i] = eta[t] + phi[i] + mu[t,i] + v[t,i] (+ z[t,i] in the robust model)

with state x = [eta, mu]. eta only moves at day boundaries, mu is AR(1) per bin.
Parameters are calibrated with the closed-form EM of Algorithm 3.

This file mirrors mql5/Include/KalmanVolume.mqh line by line (same
initialisation, update order and convergence rule) so the two can be checked
against each other numerically (see tests/).

Robust variant: the paper soft-thresholds the innovation at lambda/(2W) with
W = 1/S. Here the threshold is k * sqrt(S), i.e. lambda = 2k/sqrt(S): the same
Lasso shrinkage expressed in innovation standard deviations so that k does not
depend on the scale of the data.
"""

import math

import numpy as np

MIN_VAR = 1e-8
A_MIN, A_MAX = 0.0, 0.9999


class KalmanVolume:
    def __init__(self, bins_per_day, robust_k=0.0):
        self.I = int(bins_per_day)
        self.robust_k = float(robust_k)  # 0 => standard Kalman filter
        self.a_eta = self.a_mu = 0.0
        self.s_eta2 = self.s_mu2 = self.r = 0.0
        self.pi = [0.0, 0.0]
        self.S1 = [0.0, 0.0, 0.0]  # (00, 01, 11)
        self.phi = [0.0] * self.I
        self.eta_mean = 0.0
        self.fitted = False

    # ------------------------------------------------------------------ helpers
    def _transition(self, t_next):
        """(a0, a1, q0, q1) for the step into flat index t_next."""
        if t_next % self.I == 0:
            return self.a_eta, self.a_mu, self.s_eta2, self.s_mu2
        return 1.0, self.a_mu, 0.0, self.s_mu2

    def _shrink(self, e, S):
        """Lasso soft-threshold (eq. 33): returns the outlier estimate z."""
        if self.robust_k <= 0.0:
            return 0.0
        th = self.robust_k * math.sqrt(S)
        if e > th:
            return e - th
        if e < -th:
            return e + th
        return 0.0

    # ------------------------------------------------------------------ init
    def init_params(self, y, obs):
        I, N = self.I, len(y)
        T = N // I
        tot, cnt = 0.0, 0
        for t in range(N):
            if obs[t]:
                tot += y[t]
                cnt += 1
        ybar = tot / cnt if cnt else 0.0
        for i in range(I):
            s, c = 0.0, 0
            for d in range(T):
                t = d * I + i
                if obs[t]:
                    s += y[t]
                    c += 1
            self.phi[i] = s / c if c else ybar
        # residual variance and variance of daily mean residual
        s1 = s2 = 0.0
        c = 0
        dm_sum = dm_sum2 = 0.0
        dc = 0
        for d in range(T):
            ds, dn = 0.0, 0
            for i in range(I):
                t = d * I + i
                if obs[t]:
                    e = y[t] - self.phi[i]
                    s1 += e
                    s2 += e * e
                    c += 1
                    ds += e
                    dn += 1
            if dn:
                m = ds / dn
                dm_sum += m
                dm_sum2 += m * m
                dc += 1
        v = s2 / c - (s1 / c) ** 2 if c else 1.0
        var_d = dm_sum2 / dc - (dm_sum / dc) ** 2 if dc else 0.1 * v
        var_d = max(var_d, 1e-4)
        w = max(v - var_d, 0.1 * v, 1e-4)
        self.a_eta, self.a_mu = 0.9, 0.5
        self.s_eta2 = max(var_d * (1.0 - self.a_eta ** 2), 1e-6)
        self.s_mu2 = 0.25 * w
        self.r = 0.5 * w
        self.pi = [0.0, 0.0]
        self.S1 = [var_d, 0.0, w]

    # ------------------------------------------------------------------ E-step
    def _filter(self, y, obs):
        N = len(y)
        xp = np.zeros((N, 2)); Pp = np.zeros((N, 3))
        xf = np.zeros((N, 2)); Pf = np.zeros((N, 3))
        z = np.zeros(N)
        x0, x1 = self.pi
        P00, P01, P11 = self.S1
        for t in range(N):
            xp[t] = (x0, x1); Pp[t] = (P00, P01, P11)
            if obs[t]:
                S = P00 + 2.0 * P01 + P11 + self.r
                e = y[t] - self.phi[t % self.I] - x0 - x1
                zt = self._shrink(e, S)
                z[t] = zt
                k0 = (P00 + P01) / S
                k1 = (P01 + P11) / S
                eu = e - zt
                x0 += k0 * eu
                x1 += k1 * eu
                P00 -= k0 * k0 * S
                P01 -= k0 * k1 * S
                P11 -= k1 * k1 * S
            xf[t] = (x0, x1); Pf[t] = (P00, P01, P11)
            if t + 1 < N:
                a0, a1, q0, q1 = self._transition(t + 1)
                x0 *= a0
                x1 *= a1
                P00 = a0 * a0 * P00 + q0
                P01 = a0 * a1 * P01
                P11 = a1 * a1 * P11 + q1
        return xp, Pp, xf, Pf, z

    def _smooth(self, xp, Pp, xf, Pf):
        N = len(xp)
        xs = np.zeros((N, 2)); Ps = np.zeros((N, 3)); Pc = np.zeros((N, 2))
        xs[N - 1] = xf[N - 1]; Ps[N - 1] = Pf[N - 1]
        for t in range(N - 2, -1, -1):
            a0, a1, _, _ = self._transition(t + 1)
            f00, f01, f11 = Pf[t]
            p00, p01, p11 = Pp[t + 1]
            det = p00 * p11 - p01 * p01
            i00, i01, i11 = p11 / det, -p01 / det, p00 / det
            # L = Pf * A' * inv(Pp[t+1])
            m00, m01, m10, m11 = f00 * a0, f01 * a1, f01 * a0, f11 * a1
            L00 = m00 * i00 + m01 * i01
            L01 = m00 * i01 + m01 * i11
            L10 = m10 * i00 + m11 * i01
            L11 = m10 * i01 + m11 * i11
            d0 = xs[t + 1, 0] - xp[t + 1, 0]
            d1 = xs[t + 1, 1] - xp[t + 1, 1]
            xs[t, 0] = xf[t, 0] + L00 * d0 + L01 * d1
            xs[t, 1] = xf[t, 1] + L10 * d0 + L11 * d1
            D00 = Ps[t + 1, 0] - p00
            D01 = Ps[t + 1, 1] - p01
            D11 = Ps[t + 1, 2] - p11
            # L * D * L'
            n00, n01 = L00 * D00 + L01 * D01, L00 * D01 + L01 * D11
            n10, n11 = L10 * D00 + L11 * D01, L10 * D01 + L11 * D11
            Ps[t, 0] = f00 + n00 * L00 + n01 * L01
            Ps[t, 1] = f01 + n00 * L10 + n01 * L11
            Ps[t, 2] = f11 + n10 * L10 + n11 * L11
            # lag-one covariance Cov(x[t+1], x[t] | N) = Ps[t+1] * L'  (diagonal only)
            s00, s01, s11 = Ps[t + 1]
            Pc[t + 1, 0] = s00 * L00 + s01 * L01
            Pc[t + 1, 1] = s01 * L10 + s11 * L11
        return xs, Ps, Pc

    # ------------------------------------------------------------------ M-step
    def _mstep(self, y, obs, xs, Ps, Pc, z):
        I, N = self.I, len(y)
        T = N // I
        num_e = den_e = 0.0
        for t in range(I, N, I):
            num_e += Pc[t, 0] + xs[t, 0] * xs[t - 1, 0]
            den_e += Ps[t - 1, 0] + xs[t - 1, 0] ** 2
        num_m = den_m = 0.0
        for t in range(1, N):
            num_m += Pc[t, 1] + xs[t, 1] * xs[t - 1, 1]
            den_m += Ps[t - 1, 2] + xs[t - 1, 1] ** 2
        a_eta = min(max(num_e / den_e, A_MIN), A_MAX)
        a_mu = min(max(num_m / den_m, A_MIN), A_MAX)
        se = 0.0
        for t in range(I, N, I):
            Pt = Ps[t, 0] + xs[t, 0] ** 2
            Pt1 = Ps[t - 1, 0] + xs[t - 1, 0] ** 2
            Pct = Pc[t, 0] + xs[t, 0] * xs[t - 1, 0]
            se += Pt + a_eta * a_eta * Pt1 - 2.0 * a_eta * Pct
        sm = 0.0
        for t in range(1, N):
            Pt = Ps[t, 2] + xs[t, 1] ** 2
            Pt1 = Ps[t - 1, 2] + xs[t - 1, 1] ** 2
            Pct = Pc[t, 1] + xs[t, 1] * xs[t - 1, 1]
            sm += Pt + a_mu * a_mu * Pt1 - 2.0 * a_mu * Pct
        self.a_eta, self.a_mu = a_eta, a_mu
        self.s_eta2 = max(se / (T - 1), MIN_VAR)
        self.s_mu2 = max(sm / (N - 1), MIN_VAR)
        for i in range(I):
            s, c = 0.0, 0
            for d in range(T):
                t = d * I + i
                if obs[t]:
                    s += y[t] - z[t] - xs[t, 0] - xs[t, 1]
                    c += 1
            if c:
                self.phi[i] = s / c
        rs, rc = 0.0, 0
        for t in range(N):
            if obs[t]:
                e = y[t] - z[t] - self.phi[t % I] - xs[t, 0] - xs[t, 1]
                rs += e * e + Ps[t, 0] + 2.0 * Ps[t, 1] + Ps[t, 2]
                rc += 1
        self.r = max(rs / rc, MIN_VAR)
        self.pi = [xs[0, 0], xs[0, 1]]
        self.S1 = [max(Ps[0, 0], MIN_VAR), Ps[0, 1], max(Ps[0, 2], MIN_VAR)]

    # ------------------------------------------------------------------ public
    def fit(self, y, obs, max_iter=30, tol=1e-4, warm_start=False):
        y = [float(v) for v in y]
        obs = [bool(o) for o in obs]
        N = len(y)
        assert N % self.I == 0 and N // self.I >= 5, "need >= 5 whole days"
        if not (warm_start and self.fitted):
            self.init_params(y, obs)
        it = 0
        for it in range(1, max_iter + 1):
            old = (self.a_eta, self.a_mu, self.s_eta2, self.s_mu2, self.r)
            xp, Pp, xf, Pf, z = self._filter(y, obs)
            xs, Ps, Pc = self._smooth(xp, Pp, xf, Pf)
            self._mstep(y, obs, xs, Ps, Pc, z)
            new = (self.a_eta, self.a_mu, self.s_eta2, self.s_mu2, self.r)
            rel = max(abs(n - o) / max(abs(o), 1e-12) for n, o in zip(new, old))
            if rel < tol:
                break
        # final pass with the fitted parameters: online state + eta baseline
        xp, Pp, xf, Pf, z = self._filter(y, obs)
        xs, _, _ = self._smooth(xp, Pp, xf, Pf)
        self.eta_mean = float(np.mean(xs[::self.I, 0]))
        self._last_xf, self._last_Pf = xf[-1].copy(), Pf[-1].copy()
        self.fitted = True
        self.online_reset()
        return it

    # ------------------------------------------------------------------ online
    def online_reset(self):
        """Predicted state for bin 0 of the day after the training window."""
        a0, a1, q0, q1 = self.a_eta, self.a_mu, self.s_eta2, self.s_mu2
        x0, x1 = self._last_xf
        P00, P01, P11 = self._last_Pf
        self.x = [a0 * x0, a1 * x1]
        self.P = [a0 * a0 * P00 + q0, a0 * a1 * P01, a1 * a1 * P11 + q1]
        self.cur_bin = 0

    def forecast_log(self, h=1):
        """h-step-ahead log-volume forecast from the current predicted state."""
        eta, mu = self.x
        b = self.cur_bin
        for _ in range(h - 1):
            b += 1
            if b == self.I:
                b = 0
                eta *= self.a_eta
            mu *= self.a_mu
        return eta + mu + self.phi[b]

    def update(self, y, observed=True):
        """Correct with the observation for cur_bin, then predict the next bin.

        Returns (innovation, innovation variance, outlier z).
        """
        x0, x1 = self.x
        P00, P01, P11 = self.P
        S = P00 + 2.0 * P01 + P11 + self.r
        e = zt = 0.0
        if observed:
            e = y - self.phi[self.cur_bin] - x0 - x1
            zt = self._shrink(e, S)
            k0 = (P00 + P01) / S
            k1 = (P01 + P11) / S
            eu = e - zt
            x0 += k0 * eu
            x1 += k1 * eu
            P00 -= k0 * k0 * S
            P01 -= k0 * k1 * S
            P11 -= k1 * k1 * S
        nb = self.cur_bin + 1
        if nb == self.I:
            nb = 0
            a0, q0 = self.a_eta, self.s_eta2
        else:
            a0, q0 = 1.0, 0.0
        a1, q1 = self.a_mu, self.s_mu2
        self.x = [a0 * x0, a1 * x1]
        self.P = [a0 * a0 * P00 + q0, a0 * a1 * P01, a1 * a1 * P11 + q1]
        self.cur_bin = nb
        return e, S, zt

    def day_activity(self):
        """exp(eta - long-run mean eta): today's volume level vs normal."""
        return math.exp(self.x[0] - self.eta_mean)

    def params(self):
        return {"a_eta": self.a_eta, "a_mu": self.a_mu, "s_eta2": self.s_eta2,
                "s_mu2": self.s_mu2, "r": self.r}


def simulate(I, T, a_eta, a_mu, s_eta2, s_mu2, r, phi, seed=0, eta0=0.0):
    """Draw log-volumes from the state-space model (eqs. 4-5)."""
    rng = np.random.default_rng(seed)
    N = I * T
    y = np.zeros(N)
    eta, mu = eta0, 0.0
    for t in range(N):
        if t > 0:
            if t % I == 0:
                eta = a_eta * eta + rng.normal(0, math.sqrt(s_eta2))
            mu = a_mu * mu + rng.normal(0, math.sqrt(s_mu2))
        y[t] = eta + mu + phi[t % I] + rng.normal(0, math.sqrt(r))
    return y


def gold_like_seasonality(I):
    """Synthetic intraday log-volume shape with Asia lull, London and NY peaks."""
    h = 1.0 + np.arange(I) * 23.0 / I  # server-time hour of each bin, 01:00-24:00
    shape = (0.6 * np.exp(-0.5 * ((h - 10.0) / 1.2) ** 2)    # London open
             + 1.2 * np.exp(-0.5 * ((h - 15.75) / 1.0) ** 2)  # NY data + COMEX open
             + 0.5 * np.exp(-0.5 * ((h - 17.5) / 1.5) ** 2)
             - 0.4 * np.exp(-0.5 * ((h - 23.5) / 0.8) ** 2))  # rollover lull
    return 6.0 + shape
