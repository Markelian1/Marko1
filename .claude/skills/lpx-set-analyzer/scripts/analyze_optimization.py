#!/usr/bin/env python3
"""Analyze an MT5 walk-forward optimization XML: gates, ranking, MC, session diagnostics.
Usage: python3 analyze_optimization.py file.xml [--target-months 2] [--risk 0.5] [--min-trades 95] [--dd-weight 0.16]"""
import sys, argparse, csv
import xml.etree.ElementTree as ET
import numpy as np, pandas as pd

NS='{urn:schemas-microsoft-com:office:spreadsheet}'
STD=['Pass','ForwardResult','BackResult','Profit','ExpectedPayoff','ProfitFactor',
     'RecoveryFactor','SharpeRatio','Custom','EquityDD','Trades']

def parse(path):
    rows=[]; header=None; title=''
    for ev,elem in ET.iterparse(path,events=('end',)):
        tag=elem.tag.replace(NS,'')
        if tag=='Title': title=elem.text or ''
        if tag=='Row':
            vals=[(c.find(NS+'Data').text if c.find(NS+'Data') is not None else None) for c in elem.findall(NS+'Cell')]
            if header is None and vals and vals[0]=='Pass':
                header=[v.replace(' ','') for v in vals]
            elif header is not None and len(vals)>=len(header):
                rows.append(vals[:len(header)])
            elem.clear()
    cols=STD+[h for h in header[len(STD):]] if header else STD
    df=pd.DataFrame(rows,columns=cols)
    for c in df.columns: df[c]=pd.to_numeric(df[c],errors='coerce')
    return df,cols[len(STD):],title

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('xml'); ap.add_argument('--target-months',type=float,default=2)
    ap.add_argument('--risk',type=float,default=0.5); ap.add_argument('--min-trades',type=int,default=95)
    ap.add_argument('--dd-weight',type=float,default=0.16)
    a=ap.parse_args()
    df,params,title=parse(a.xml)
    print(f"TITLE: {title}\nPasses: {len(df)} | Param cols: {params}")
    # months in period from title (e.g., 2024.01.01-2026.07.11)
    import re
    m=re.search(r'(\d{4})\.(\d{2})\.(\d{2})-(\d{4})\.(\d{2})\.(\d{2})',title)
    months=30.3
    if m:
        y1,mo1,d1,y2,mo2,d2=map(int,m.groups())
        months=((y2-y1)*12+(mo2-mo1)+(d2-d1)/30.44)
    print(f"Period months: {months:.1f}")
    d=df.dropna(subset=['ForwardResult','BackResult','ProfitFactor'])
    cf=np.corrcoef(d.ProfitFactor,d.ForwardResult)[0,1]; cb=np.corrcoef(d.ProfitFactor,d.BackResult)[0,1]
    print(f"corr(PF,Fwd)={cf:.4f} corr(PF,Back)={cb:.4f}")
    if cf<0.95:
        print("!! STRUCTURE WARNING: main metrics may NOT be the OOS forward segment. Stop and verify export."); 
    d=df.copy(); d['FwdPF']=d.ForwardResult; d['BackPF']=d.BackResult
    print(f"\nPOPULATION: Profit>0 OOS: {(d.Profit>0).sum()}/{len(d)} ({(d.Profit>0).mean()*100:.0f}%)  "
          f"[benchmarks: GER40 66, JPY 55, XAU 42, OIL 27, GBP-Lon 24; <20 = weak]")
    print(f"FwdPF med {d.FwdPF.median():.3f} p90 {d.FwdPF.quantile(.9):.3f} max {d.FwdPF.max():.3f} | DD med {d.EquityDD.median():.2f}")
    # session diagnostic on any *Hour1 column
    hourcols=[c for c in params if 'Hour1' in c or c=='LiqHour1']
    for hc in hourcols:
        g=d.groupby(d[hc].astype('Int64')).agg(pct=('Profit',lambda x:(x>0).mean()*100),pf_max=('FwdPF','max'),n=('Profit','size'))
        print(f"\nEdge by {hc}:\n{g.round(2).to_string()}")
        idx=g.index.dropna().astype(int).tolist()
        if len(idx)>=3:
            pcts=g.loc[idx,'pct'].values
            if pcts.argmax()in(0,len(pcts)-1) and (np.diff(pcts)>0).all() or (np.diff(pcts)<0).all():
                print("!! SESSION WARNING: edge is monotonic toward a range boundary -> true edge may be OUTSIDE tested hours. Recommend extending the range.")
            elif pcts.argmax() in (0,len(pcts)-1):
                print("!! SESSION NOTE: best hour sits on the boundary of the tested range -> consider extending.")
    gate=((d.Profit>0)&(d.FwdPF>=1.20)&(d.BackPF>=1.20)&(d.FwdPF>=0.85*d.BackPF)
          &(d.SharpeRatio>0)&(d.RecoveryFactor>0)&(d.Trades>=a.min_trades))
    s=d[gate].copy()
    print(f"\nSURVIVORS: {len(s)}")
    if len(s)==0: print("No survivors — weak population or wrong session. Do not force a pick."); return
    s['WinRate']=s.FwdPF/(s.FwdPF+s.ATR_RR) if 'ATR_RR' in s else s.FwdPF/(s.FwdPF+2.5)
    s['consistency']=1-(s.BackPF-s.FwdPF).clip(lower=0)/s.BackPF
    def z(x):
        sd=x.std(ddof=0); return (x-x.mean())/sd if sd>0 else x*0
    wDD=a.dd_weight; wSh=.28-(wDD-.16)/2; wRec=.24-(wDD-.16)/2
    s['pre']=wSh*z(s.SharpeRatio)+wRec*z(s.RecoveryFactor)+.18*z(s.FwdPF)+wDD*z(-s.EquityDD)+.08*z(s.consistency)+.06*z(s.Trades)
    sl=s.sort_values('pre',ascending=False).head(40).copy()
    np.random.seed(11); FWD=months/2
    def mc(wr,rr,n,sims=120000):
        w=np.random.random((sims,n))<wr; return np.where(w,rr*a.risk,-a.risk).sum(axis=1)
    out=[]
    for _,r in sl.iterrows():
        rr=r['ATR_RR'] if 'ATR_RR' in sl else 2.5
        n=max(1,int(round(r.Trades/FWD*a.target_months)))
        p=mc(r.WinRate,rr,n)
        rec={'Pass':int(r.Pass)}
        for pc in [c for c in sl.columns if c not in STD+['FwdPF','BackPF','WinRate','consistency','pre']][:8]:
            rec[pc]=r[pc]
        rec.update({'WR':round(r.WinRate,3),'OOStr':int(r.Trades),'FwdPF':round(r.FwdPF,2),'BackPF':round(r.BackPF,2),
                    'DD':round(r.EquityDD,2),'Rec':round(r.RecoveryFactor,2),'Shp':round(r.SharpeRatio,2),
                    'med':round(float(np.median(p)),2),'Ppos':round(float((p>0).mean()),3),'wc5':round(float(np.percentile(p,5)),2)})
        out.append(rec)
    o=pd.DataFrame(out).sort_values(['Ppos','wc5','med'],ascending=[False,False,False])
    pd.set_option('display.width',250); pd.set_option('display.max_columns',40)
    print("\nTOP 10 (by P(positive over target window)):")
    print(o.head(10).to_string(index=False))
    o.to_csv('/home/claude/set_analyzer_top.csv',index=False)
    print("\nNEXT: check the winner sits on a plateau (neighbors in the top list), then ask for its backtest and run validate_backtest.py")
if __name__=='__main__': main()
