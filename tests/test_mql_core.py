"""Cross-check the CKalmanVolume class of the EA against model/kalman_volume.py.

The class lives in mql5/Experts/KalmanVolumeXAU.mq5 between the
"BEGIN KalmanVolume" / "END KalmanVolume" markers (the EA is a single file).
MetaEditor is not available here, so the MQL5 class is compiled as C++: a small
shim provides the MQL5 math/array functions and dynamic member arrays
(`double m_x[];`) are rewritten to std::vector. Both implementations are run on
real XAUUSD M15 tick volumes (cold fit, online day, warm-start refit) for the
standard and the robust filter, and must agree to ~1e-9.

  python3 -I tests/test_mql_core.py
"""

import re
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "model"))
from kalman_volume import KalmanVolume  # noqa: E402
from walkforward import build_grid, load_mt5  # noqa: E402

SHIM = r"""
#include <cmath>
#include <vector>
#include <cstdio>
#include <algorithm>
inline double MathLog(double x) { return std::log(x); }
inline double MathExp(double x) { return std::exp(x); }
inline double MathSqrt(double x) { return std::sqrt(x); }
inline double MathAbs(double x) { return std::fabs(x); }
inline double MathMax(double a, double b) { return a > b ? a : b; }
inline double MathMin(double a, double b) { return a < b ? a : b; }
template <class T> int ArrayResize(std::vector<T> &v, int n) { v.resize(n); return n; }
"""

DRIVER = r"""
int main(int argc, char **argv) {
  FILE *f = std::fopen(argv[1], "r");
  int T, I; double k; int iters;
  std::fscanf(f, "%d %d %lf %d", &T, &I, &k, &iters);
  std::vector<double> train((T + 1) * I), online(I);
  for (int t = 0; t < (T + 1) * I; t++) std::fscanf(f, "%lf", &train[t]);
  for (int i = 0; i < I; i++) std::fscanf(f, "%lf", &online[i]);
  CKalmanVolume kv;
  kv.Setup(I, T, k);
  for (int d = 0; d < T; d++) for (int b = 0; b < I; b++) kv.SetVolume(d, b, train[d * I + b]);
  int it = kv.Fit(iters, 0.0, false);
  std::printf("fit %d %.17g %.17g %.17g %.17g %.17g\n", it, kv.AEta(), kv.AMu(), kv.SEta2(), kv.SMu2(), kv.R());
  for (int i = 0; i < I; i++) std::printf("phi %.17g\n", kv.Phi(i));
  std::printf("act %.17g\n", kv.DayActivity());
  for (int i = 0; i < I; i++) {
    double f1 = kv.ForecastLog(1), fm = kv.ForecastMeanVolume(8), e, s, z;
    kv.Update(online[i], e, s, z);
    std::printf("on %.17g %.17g %.17g %.17g %.17g %.17g\n", f1, fm, e, s, z, kv.DayActivity());
  }
  // warm-start refit on the window shifted by one day
  kv.Setup(I, T, k);
  for (int d = 0; d < T; d++) for (int b = 0; b < I; b++) kv.SetVolume(d, b, train[(d + 1) * I + b]);
  it = kv.Fit(3, 0.0, true);
  std::printf("warm %d %.17g %.17g %.17g %.17g %.17g\n", it, kv.AEta(), kv.AMu(), kv.SEta2(), kv.SMu2(), kv.R());
  std::printf("f %.17g\n", kv.ForecastLog(5));
  return 0;
}
"""


EA = ROOT / "mql5/Experts/KalmanVolumeXAU.mq5"


def core_block():
    """The CKalmanVolume class as embedded in the EA."""
    src = EA.read_text()
    start = src.index("//=== BEGIN KalmanVolume")
    end = src.index("//=== END KalmanVolume ===")
    return src[start:end]


def mql_to_cpp(src):
    """Rewrite the few MQL5-only constructs used by the CKalmanVolume class."""
    out = []
    for line in src.splitlines():
        m = re.match(r"^(\s*)(double|bool|int)(\s+)(m_\w+\[\].*;)\s*$", line)
        if m:
            decl = m.group(4).replace("[]", "")
            line = f"{m.group(1)}std::vector<{m.group(2)}>{m.group(3)}{decl}"
        out.append(line)
    return SHIM + "\n".join(out) + "\n" + DRIVER


def python_run(train, online, T, I, k, iters):
    vol = lambda v: (np.log(v), True) if v >= 1 else (0.0, False)
    m = KalmanVolume(I, robust_k=k)
    y, o = zip(*[vol(v) for v in train[: T * I]])
    it = m.fit(y, o, max_iter=iters, tol=0.0)
    res = {"fit": [it, *m.params().values()], "phi": list(m.phi), "act": m.day_activity(), "on": []}
    for v in online:
        f1 = m.forecast_log(1)
        fm = np.mean([np.exp(m.forecast_log(h)) for h in range(1, 9)])
        yy, ob = vol(v)
        e, S, z = m.update(yy, ob)
        res["on"].append([f1, fm, e, S, z, m.day_activity()])
    y, o = zip(*[vol(v) for v in train[I:]])
    it = m.fit(y, o, max_iter=3, tol=0.0, warm_start=True)
    res["warm"] = [it, *m.params().values()]
    res["f"] = m.forecast_log(5)
    return res


def cpp_run(binary, inp):
    out = subprocess.run([binary, inp], capture_output=True, text=True, check=True).stdout
    res = {"phi": [], "on": []}
    for line in out.splitlines():
        tag, *vals = line.split()
        vals = [float(v) for v in vals]
        if tag in ("phi",):
            res["phi"].append(vals[0])
        elif tag == "on":
            res["on"].append(vals)
        elif tag in ("act", "f"):
            res[tag] = vals[0]
        else:
            res[tag] = vals
    return res


def compare(a, b, path=""):
    if isinstance(a, (list, tuple)):
        return max((compare(x, y, f"{path}[{i}]") for i, (x, y) in enumerate(zip(a, b))), default=0.0)
    if isinstance(a, dict):
        return max(compare(a[k], b[k], f"{path}.{k}") for k in a)
    return abs(float(a) - float(b)) / max(abs(float(a)), 1e-9)


def main():
    df = load_mt5(ROOT / "data/xauusd/XAUUSD_M15.csv.gz")
    days, I, Y, OBS, _ = build_grid(df, 60, 1440, 15, 40)
    T = 40
    vol = np.where(OBS, np.exp(Y), 0.0)
    # window that contains early-close holidays -> exercises missing bins
    start = int(np.argmax([(~OBS[d:d + T + 2]).sum() > 20 for d in range(len(days) - T - 2)]))
    train = vol[start:start + T + 1].ravel()
    online = vol[start + T + 1]
    print(f"window {days[start].date()}..{days[start + T + 1].date()}, "
          f"missing bins in train: {(~OBS[start:start + T + 1]).sum()}")

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        (tmp / "kv.cpp").write_text(mql_to_cpp(core_block()))
        subprocess.run(["g++", "-O2", "-std=c++17", "-Wall", "-Wno-unused-variable", "-Wno-unused-result",
                        "-o", str(tmp / "kv"), str(tmp / "kv.cpp")], check=True)
        worst = 0.0
        for k in (0.0, 3.0):
            inp = tmp / f"in_{k}.txt"
            with open(inp, "w") as f:
                f.write(f"{T} {I} {k} 8\n")
                f.write(" ".join(f"{v:.1f}" for v in train) + "\n")
                f.write(" ".join(f"{v:.1f}" for v in online) + "\n")
            py = python_run(train, online, T, I, k, 8)
            cc = cpp_run(str(tmp / "kv"), str(inp))
            err = compare(py, cc)
            worst = max(worst, err)
            label = "robust k=3" if k else "standard  "
            print(f"  {label}: max relative difference MQL5(C++) vs Python = {err:.2e}  "
                  f"(a_eta={cc['fit'][1]:.4f} a_mu={cc['fit'][2]:.4f} r={cc['fit'][5]:.5f})")
    ok = worst < 1e-8
    print("PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
