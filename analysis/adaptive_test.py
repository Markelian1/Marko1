"""Walk-forward test of self-learning ("adaptive") trade filters on the v1.8 shadow data.

Every rule decides each day using ONLY earlier sessions, exactly as a live EA would.
Usage: python3 adaptive_test.py <sessions.csv> [<sessions.csv> ...]
"""
import sys

import numpy as np
import pandas as pd


def load(paths):
    s = pd.concat([pd.read_csv(p, sep=";") for p in paths], ignore_index=True)
    s = s.drop_duplicates("date").sort_values("date").reset_index(drop=True)
    sh = s[s.sh_dir != "-"].copy().reset_index(drop=True)
    sh["year"] = sh.date.str[:4]
    sh["mins"] = sh.sh_time.str[11:13].astype(int) * 60 + sh.sh_time.str[14:16].astype(int) - 17 * 60
    sh["with_trend"] = ((sh.sh_dir == "LONG") & (sh.px_vs_sma_pct > 0)) | ((sh.sh_dir == "SHORT") & (sh.px_vs_sma_pct < 0))
    sh["rb"] = np.where(sh.ratio <= 0, -1, np.where(sh.ratio <= 0.7, 0, np.where(sh.ratio <= 1.25, 1, 2)))
    sh["early"] = sh.mins <= 5
    return sh


def rules(sh):
    r = sh.sh_R.values
    d = sh.sh_dir.values
    g = list(zip(sh.with_trend, sh.rb, sh.early))
    out = {}
    # 1) equity-curve switch: trade only while the last 20 signals summed > 0
    out["1 equity switch (20)"] = [i >= 20 and r[i - 20:i].sum() > 0 for i in range(len(sh))]
    # 2) direction learner: trade a direction only while its last 20 signals summed > 0
    t2 = []
    for i in range(len(sh)):
        prev = [r[j] for j in range(i - 1, -1, -1) if d[j] == d[i]][:20]
        t2.append(len(prev) == 20 and sum(prev) > 0)
    out["2 direction learner (20)"] = t2
    # 3) condition learner: same (trend, range size, timing) group positive over the last 250 signals
    t3 = []
    for i in range(len(sh)):
        prev = [r[j] for j in range(max(0, i - 250), i) if g[j] == g[i]]
        t3.append(len(prev) >= 15 and np.mean(prev) > 0)
    out["3 condition learner (250)"] = t3
    return out


def main(paths):
    sh = load(paths)
    by_year = {"no filter": sh.groupby("year").sh_R.sum()}
    for name, take in rules(sh).items():
        by_year[name] = sh[pd.Series(take)].groupby("year").sh_R.sum()
    print(pd.DataFrame(by_year).fillna(0).round(1).T.to_string())


if __name__ == "__main__":
    main(sys.argv[1:])
