#!/usr/bin/env python3
"""Analyze an MT5 walk-forward optimization XML: gates, ranking, MC, session diagnostics, plateau check.
Usage: python3 analyze_optimization.py file.xml [--target-months 2] [--risk 0.5] [--min-trades 95] [--dd-weight 0.16]
       [--fwd-frac 0.5] [--months N] [--rr-col ATR_RR] [--rr 2.5] [--plateau-min 0.5] [--out-dir .]"""
import sys, os, re, argparse
import xml.etree.ElementTree as ET
import numpy as np, pandas as pd

NS='{urn:schemas-microsoft-com:office:spreadsheet}'
STD=['Pass','ForwardResult','BackResult','Profit','ExpectedPayoff','ProfitFactor',
     'RecoveryFactor','SharpeRatio','Custom','EquityDD','Trades']

def parse(path):
    rows=[]; header=None; title=''
    for ev,elem in ET.iterparse(path,events=('end',)):
        tag=elem.tag.rsplit('}',1)[-1]  # Title lives in the office namespace, not the spreadsheet one
        if tag=='Title' and not title: title=(elem.text or '').strip()
        if tag=='Row':
            vals=[(c.find(NS+'Data').text if c.find(NS+'Data') is not None else None) for c in elem.findall(NS+'Cell')]
            if header is None and vals and vals[0]=='Pass':
                header=[(v or '').replace(' ','') for v in vals]
            elif header is not None and len(vals)>=len(STD):
                rows.append((vals+[None]*len(header))[:len(header)])
            elem.clear()
    if header is None: sys.exit("!! No header row starting with 'Pass' — this is not an MT5 optimization export.")
    params=header[len(STD):]
    raw=pd.DataFrame(rows,columns=STD+params,dtype=object)
    df=raw.copy()
    for c in df.columns:
        low=raw[c].dropna().astype(str).str.strip().str.lower()
        if c in params and len(low) and low.isin(['true','false']).all():
            df[c]=raw[c].astype(str).str.strip().str.lower().map({'true':1,'false':0})
        else:
            df[c]=pd.to_numeric(raw[c],errors='coerce')
    return df,raw,params,title

def plateau(d,surv,varying):
    """For each pass: (survivor neighbors, existing neighbors). Neighbor = one varying param moved ±1 grid step."""
    if not varying: return {}
    grids={c:np.sort(d[c].dropna().unique()) for c in varying}
    key=lambda r:tuple(round(float(r[c]),10) if pd.notna(r[c]) else None for c in varying)
    lut={key(r):bool(s) for (_,r),s in zip(d.iterrows(),surv)}
    def check(r):
        k=list(key(r)); ok=n=0
        for i,c in enumerate(varying):
            if k[i] is None: continue
            g=grids[c]; j=int(np.searchsorted(g,k[i]))
            for jj in (j-1,j+1):
                if 0<=jj<len(g):
                    nb=k.copy(); nb[i]=round(float(g[jj]),10)
                    if tuple(nb) in lut: n+=1; ok+=lut[tuple(nb)]
        return ok,n
    return check

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('xml'); ap.add_argument('--target-months',type=float,default=2)
    ap.add_argument('--risk',type=float,default=0.5); ap.add_argument('--min-trades',type=int,default=95)
    ap.add_argument('--dd-weight',type=float,default=0.16)
    ap.add_argument('--fwd-frac',type=float,default=0.5,help='forward share of the period (MT5 Forward 1/2 = 0.5)')
    ap.add_argument('--months',type=float,default=None,help='override period length if the title has no dates')
    ap.add_argument('--rr-col',default='ATR_RR'); ap.add_argument('--rr',type=float,default=2.5,help='fixed RR if --rr-col is absent')
    ap.add_argument('--plateau-min',type=float,default=0.5,help='min share of grid neighbors that must also survive')
    ap.add_argument('--out-dir',default='.')
    a=ap.parse_args()
    df,raw,params,title=parse(a.xml)
    print(f"TITLE: {title or '(none)'}\nPasses: {len(df)} | Param cols: {params}")
    m=re.search(r'(\d{4})\.(\d{2})\.(\d{2})-(\d{4})\.(\d{2})\.(\d{2})',title)
    if a.months: months=a.months
    elif m:
        y1,mo1,d1,y2,mo2,d2=map(int,m.groups())
        months=((y2-y1)*12+(mo2-mo1)+(d2-d1)/30.44)
    else:
        months=30.3; print("!! No YYYY.MM.DD-YYYY.MM.DD period in the title — assuming 30.3 months. Pass --months to fix the MC frequency.")
    print(f"Period months: {months:.1f} | forward share: {a.fwd_frac}")
    d=df.dropna(subset=['ForwardResult','BackResult','ProfitFactor'])
    cf=np.corrcoef(d.ProfitFactor,d.ForwardResult)[0,1]; cb=np.corrcoef(d.ProfitFactor,d.BackResult)[0,1]
    print(f"corr(PF,Fwd)={cf:.4f} corr(PF,Back)={cb:.4f}")
    if cf<0.95:
        print("!! STRUCTURE WARNING: main metrics may NOT be the OOS forward segment. Stop and verify export.")
    d=df.copy(); d['FwdPF']=d.ForwardResult; d['BackPF']=d.BackResult
    pct=(d.Profit>0).mean()*100
    print(f"\nPOPULATION: Profit>0 OOS: {(d.Profit>0).sum()}/{len(d)} ({pct:.0f}%)  "
          f"[benchmarks: GER40 66, JPY 55, XAU 42, OIL 27, GBP-Lon 24; <20 = weak]")
    print(f"FwdPF med {d.FwdPF.median():.3f} p90 {d.FwdPF.quantile(.9):.3f} max {d.FwdPF.max():.3f} | DD med {d.EquityDD.median():.2f}")
    print("VERDICT: "+("STRONG edge (>=40%)" if pct>=40 else "MODERATE edge (20-40%) — usable, check session first" if pct>=20
                       else "WEAK edge (<20%) — diversifier-only or re-optimize (check session before discarding)"))
    # session diagnostic on hour params that were actually optimized
    hourcols=[c for c in params if re.search('hour',c,re.I) and d[c].nunique()>=3]
    for hc in hourcols:
        g=d.groupby(d[hc].astype('Int64')).agg(pct=('Profit',lambda x:(x>0).mean()*100),pf_max=('FwdPF','max'),n=('Profit','size'))
        print(f"\nEdge by {hc}:\n{g.round(2).to_string()}")
        pcts=g['pct'].values; dp=np.diff(pcts)
        if (dp>0).all() or (dp<0).all():
            print("!! SESSION WARNING: edge is monotonic toward a range boundary -> true edge may be OUTSIDE tested hours. Recommend extending the range.")
        elif pcts.argmax() in (0,len(pcts)-1):
            print("!! SESSION NOTE: best hour sits on the boundary of the tested range -> consider extending.")
    gates={'Profit>0':d.Profit>0,'FwdPF>=1.20':d.FwdPF>=1.20,'BackPF>=1.20':d.BackPF>=1.20,
           'FwdPF>=0.85*BackPF':d.FwdPF>=0.85*d.BackPF,'Sharpe>0':d.SharpeRatio>0,'Recovery>0':d.RecoveryFactor>0,
           f'Trades>={a.min_trades}':d.Trades>=a.min_trades}
    gate=np.logical_and.reduce(list(gates.values()))
    s=d[gate].copy()
    print(f"\nSURVIVORS: {len(s)}  (fail counts: "+', '.join(f"{k} {int((~v).sum())}" for k,v in gates.items())+")")
    if len(s)==0: print("No survivors — weak population or wrong session. Do not force a pick."); return
    rrc=a.rr_col if a.rr_col in s else None
    print(f"RR source: {'column '+rrc if rrc else f'fixed {a.rr} (no {a.rr_col} column; pass --rr-col/--rr)'}")
    s['RR']=s[rrc] if rrc else a.rr
    s['WinRate']=s.FwdPF/(s.FwdPF+s.RR)
    s['consistency']=1-(s.BackPF-s.FwdPF).clip(lower=0)/s.BackPF
    def z(x):
        sd=x.std(ddof=0); return (x-x.mean())/sd if sd>0 else x*0
    wDD=a.dd_weight; wSh=.28-(wDD-.16)/2; wRec=.24-(wDD-.16)/2
    s['pre']=wSh*z(s.SharpeRatio)+wRec*z(s.RecoveryFactor)+.18*z(s.FwdPF)+wDD*z(-s.EquityDD)+.08*z(s.consistency)+.06*z(s.Trades)
    sl=s.sort_values('pre',ascending=False).head(40).copy()
    np.random.seed(11); FWD=months*a.fwd_frac
    def mc(wr,rr,n,sims=120000):
        w=np.random.binomial(n,wr,sims); return w*rr*a.risk-(n-w)*a.risk
    varying=[c for c in params if df[c].nunique()>1]
    plat=plateau(df,gate,varying)
    out=[]
    for i,r in sl.iterrows():
        n=max(1,int(round(r.Trades/FWD*a.target_months)))
        p=mc(r.WinRate,r.RR,n)
        ok,nb=plat(r) if varying else (0,0)
        rec={'Pass':int(r.Pass)}
        for pc in varying[:8]: rec[pc]=raw.at[i,pc]
        rec.update({'WR':round(r.WinRate,3),'OOStr':int(r.Trades),'FwdPF':round(r.FwdPF,2),'BackPF':round(r.BackPF,2),
                    'DD':round(r.EquityDD,2),'Rec':round(r.RecoveryFactor,2),'Shp':round(r.SharpeRatio,2),
                    'med':round(float(np.median(p)),2),'Ppos':round(float((p>0).mean()),3),'wc5':round(float(np.percentile(p,5)),2),
                    'plat':f"{ok}/{nb}",'_plat_ok':nb>0 and ok/nb>=a.plateau_min,'_idx':i})
        out.append(rec)
    o=pd.DataFrame(out).sort_values(['Ppos','wc5','med'],ascending=[False,False,False])
    pd.set_option('display.width',250); pd.set_option('display.max_columns',40)
    print(f"\nTOP 10 (by P(positive over {a.target_months:g} months) at {a.risk}% risk; plat = surviving/existing ±1-step neighbors):")
    print(o.drop(columns=['_plat_ok','_idx']).head(10).to_string(index=False))
    top=o.iloc[0]; good=o[o._plat_ok]
    if len(good)==0:
        win=top; print(f"\n!! NO PLATEAU: no top-40 pass has >={a.plateau_min:.0%} surviving neighbors. Every candidate is a spike — "
                       "treat as curve-fit risk; prefer re-optimizing over deploying.")
    else:
        win=good.iloc[0]
        if win.Pass!=top.Pass:
            print(f"\n!! Pass {int(top.Pass)} ranked #1 but is a solitary spike (plat {top.plat}) -> rejected. "
                  f"Best plateau member: Pass {int(win.Pass)} (plat {win.plat}).")
    i=win._idx
    lines=[f"{c}={raw.at[i,c]}" for c in params]
    print(f"\n=== WINNER SET — Pass {int(win.Pass)} | FwdPF {win.FwdPF} BackPF {win.BackPF} DD {win.DD}% OOS trades {win.OOStr} "
          f"| P(>0,{a.target_months:g}m) {win.Ppos} med {win.med}% wc5 {win.wc5}% | plateau {win.plat} ===")
    print('\n'.join(lines))
    os.makedirs(a.out_dir,exist_ok=True)
    top_csv=os.path.join(a.out_dir,'set_analyzer_top.csv'); set_txt=os.path.join(a.out_dir,'set_analyzer_winner.txt')
    o.drop(columns=['_plat_ok','_idx']).to_csv(top_csv,index=False)
    with open(set_txt,'w') as f: f.write('\n'.join(lines)+'\n')
    print(f"\nSaved: {top_csv} | {set_txt}")
    print(f"NEXT: backtest Pass {int(win.Pass)} in MT5, then: validate_backtest.py report.xlsx --expected-pf {win.FwdPF} --set {set_txt}")
if __name__=='__main__': main()
