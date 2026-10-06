"""Syntax/type check of the EA without MetaEditor.

mql5/Experts/KalmanVolumeXAU.mq5 (+ KalmanVolume.mqh) is rewritten into C++
(input/group/property lines, dynamic local arrays, the #includes) and compiled
with g++ -fsyntax-only against stub declarations of the MQL5 API it uses.
This catches typos, wrong argument counts and type errors in the EA logic.
It does NOT prove the EA compiles in MetaEditor: compile it there (F7) before
running it.

  python3 -I tests/test_ea_compiles.py
"""

import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_mql_core import SHIM, mql_to_cpp  # noqa: E402

API = r"""
#include <string>
#include <cstdarg>
typedef long long datetime;
// ulong comes from <sys/types.h> (unsigned long, 64-bit like MQL5 ulong)
typedef unsigned int uint;
typedef std::string string;
enum ENUM_TIMEFRAMES { PERIOD_CURRENT = 0 };
enum ENUM_INIT_RETCODE { INIT_SUCCEEDED = 0, INIT_FAILED = 1, INIT_PARAMETERS_INCORRECT = 2 };
enum ENUM_SERIESMODE { MODE_OPEN, MODE_LOW, MODE_HIGH, MODE_CLOSE };
enum ENUM_SYMBOL_INFO_DOUBLE { SYMBOL_VOLUME_STEP, SYMBOL_VOLUME_MAX, SYMBOL_VOLUME_MIN,
                               SYMBOL_TRADE_TICK_SIZE, SYMBOL_TRADE_TICK_VALUE };
enum ENUM_SYMBOL_INFO_INTEGER { SYMBOL_SPREAD, SYMBOL_TRADE_STOPS_LEVEL };
enum ENUM_POSITION_PROPERTY_STRING { POSITION_SYMBOL };
enum ENUM_POSITION_PROPERTY_INTEGER { POSITION_MAGIC, POSITION_TIME };
enum ENUM_ACCOUNT_INFO_DOUBLE { ACCOUNT_EQUITY };
const int INVALID_HANDLE = -1;
const int TIME_DATE = 1;
const uint TRADE_RETCODE_DONE = 10009, TRADE_RETCODE_PLACED = 10008;
struct MqlRates { datetime time; double open, high, low, close; long tick_volume; int spread; long real_volume; };
struct MqlTick { datetime time; double bid, ask, last; ulong volume; };
struct MqlDateTime { int year, mon, day, hour, min, sec, day_of_week, day_of_year; };
extern const string _Symbol;
extern const ENUM_TIMEFRAMES _Period;
extern const int _Digits;
extern const double _Point;
class CTrade {
public:
  void SetExpertMagicNumber(ulong) {}
  void SetDeviationInPoints(ulong) {}
  bool SetTypeFillingBySymbol(const string &) { return true; }
  bool Buy(double, const string &, double, double, double, const string &) { return true; }
  bool Sell(double, const string &, double, double, double, const string &) { return true; }
  bool PositionClose(ulong) { return true; }
  uint ResultRetcode() const { return 0; }
};
inline double MathFloor(double x) { return std::floor(x); }
inline double MathCeil(double x) { return std::ceil(x); }
inline double MathLog10(double x) { return std::log10(x); }
inline double MathPow(double a, double b) { return std::pow(a, b); }
inline double NormalizeDouble(double x, int) { return x; }
int PeriodSeconds(ENUM_TIMEFRAMES);
bool TimeToStruct(datetime, MqlDateTime &);
string TimeToString(datetime, int);
string StringFormat(const char *, ...);
void PrintFormat(const char *, ...);
void Print(const string &);
void Comment(const string &);
int GetLastError();
template <class T> bool ArraySetAsSeries(std::vector<T> &, bool) { return true; }
int CopyRates(const string &, ENUM_TIMEFRAMES, datetime, int, std::vector<MqlRates> &);
int CopyBuffer(int, int, int, int, std::vector<double> &);
int CopyTickVolume(const string &, ENUM_TIMEFRAMES, int, int, std::vector<long> &);
datetime iTime(const string &, ENUM_TIMEFRAMES, int);
double iOpen(const string &, ENUM_TIMEFRAMES, int);
double iHigh(const string &, ENUM_TIMEFRAMES, int);
double iLow(const string &, ENUM_TIMEFRAMES, int);
double iClose(const string &, ENUM_TIMEFRAMES, int);
long iVolume(const string &, ENUM_TIMEFRAMES, int);
int iHighest(const string &, ENUM_TIMEFRAMES, ENUM_SERIESMODE, int, int);
int iLowest(const string &, ENUM_TIMEFRAMES, ENUM_SERIESMODE, int, int);
int iBarShift(const string &, ENUM_TIMEFRAMES, datetime, bool);
int iATR(const string &, ENUM_TIMEFRAMES, int);
bool IndicatorRelease(int);
double SymbolInfoDouble(const string &, ENUM_SYMBOL_INFO_DOUBLE);
long SymbolInfoInteger(const string &, ENUM_SYMBOL_INFO_INTEGER);
bool SymbolInfoTick(const string &, MqlTick &);
double AccountInfoDouble(ENUM_ACCOUNT_INFO_DOUBLE);
int PositionsTotal();
ulong PositionGetTicket(int);
string PositionGetString(ENUM_POSITION_PROPERTY_STRING);
long PositionGetInteger(ENUM_POSITION_PROPERTY_INTEGER);
"""


def ea_to_cpp(src, core_cpp):
    out = []
    for line in src.splitlines():
        s = line.strip()
        if s.startswith("#property") or s.startswith("input group"):
            continue
        if s.startswith("#include"):
            continue
        line = re.sub(r"^input\s+", "const ", line)
        m = re.match(r"^(\s*)(MqlRates|long|int|double)\s+(\w+)\[\];\s*$", line)
        if m:
            line = f"{m.group(1)}std::vector<{m.group(2)}> {m.group(3)};"
        out.append(line)
    return core_cpp + API + "\n".join(out) + "\n"


def main():
    core = mql_to_cpp((ROOT / "mql5/Include/KalmanVolume.mqh").read_text())
    core = core[: core.index("int main(")]  # drop the core test driver
    cpp = ea_to_cpp((ROOT / "mql5/Experts/KalmanVolumeXAU.mq5").read_text(), core)
    with tempfile.TemporaryDirectory() as tmp:
        f = Path(tmp) / "ea.cpp"
        f.write_text(cpp)
        r = subprocess.run(["g++", "-std=c++17", "-fsyntax-only", "-Wall", "-Wno-unused-variable",
                            "-Wno-format-security", str(f)], capture_output=True, text=True)
    print(r.stderr[-4000:] if r.stderr else "")
    print("PASS (sintaksa/tipet ne rregull)" if r.returncode == 0 else "FAIL")
    sys.exit(r.returncode)


if __name__ == "__main__":
    main()
