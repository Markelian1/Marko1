#!/usr/bin/env python3
"""Validate an MT5 backtest XLSX (Spanish report) for a chosen set.
Usage: python3 validate_backtest.py file.xlsx [--expected-pf 1.46] [--deploy-risk 0.3] [--target 5]"""
import argparse, datetime as dt, calendar
import numpy as np, pandas as pd
from openpyxl import load_workbook

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('xlsx'); ap.add_argument('--expected-pf',type=float,default=None)
    ap.add_argument('--deploy-risk',type=float,default=None); ap.add_argument('--target',type=float,default=5.0)
    a=ap.parse_args()
    wb=load_workbook(a.xlsx,read_only=True,data_only=True); ws=wb[wb.sheetnames[0]]
    rows=list(ws.iter_rows(values_only=True))
    # config & summary
    cfg={}; native_risk=None
    for row in rows[:120]:
        vals=[str(c) for c in row if c is not None]; j=' | '.join(vals)
        for key in ['RiskPercent','ATR_Period','ATR_Mult','ATR_RR','LiquidityHour1','LiquidityMin1','LiquidityHour2','LiquidityMin2','TradeFriday','UseNewsFilter']:
            if key in j: cfg[key]=j
        for key in ['Beneficio Neto','Factor de Beneficio','Reducción máxima del balance','Ratio de Sharpe','Factor de Recuperación','Total de operaciones','rentables','cortas','largas']:
            if key in j: print('SUMMARY:',j[:120])
    for k,v in cfg.items(): print('CFG:',v[:100])
    import re
    m=re.search(r'RiskPercent\D*([\d.]+)',' '.join(cfg.get('RiskPercent','')))
    if m: native_risk=float(m.group(1)); print(f"Native RiskPercent: {native_risk}")
    # deals
    dh=None
    for i,row in enumerate(rows):
        vals=[str(c) for c in row if c is not None]
        if 'Beneficio' in vals and 'Balance' in vals and 'Dirección' in vals: dh=i; break
    recs=[]; daylink=[]; cur=None; shorts=0; longs=0
    for r in rows[dh+1:]:
        t=r[0]
        if isinstance(t,str):
            try: t=dt.datetime.strptime(t.strip(),'%Y.%m.%d %H:%M:%S')
            except: t=None
        if isinstance(t,dt.datetime):
            if r[4]=='in':
                cur=t
                if r[3]=='buy': longs+=1
                elif r[3]=='sell': shorts+=1
            elif r[4] in ('out','out by') and isinstance(r[10],(int,float)) and cur is not None:
                daylink.append((cur,t,r[10]))
            if isinstance(r[11],(int,float)): recs.append((t,r[11]))
    d=pd.DataFrame(recs,columns=['time','balance']); d['delta']=d.balance.diff(); d.loc[0,'delta']=d.balance.iloc[0]-1e5
    real=d[d.delta.abs()>1e-9].copy().reset_index(drop=True)
    real['r']=real.delta/(real.balance-real.delta)
    net=(real.balance.iloc[-1]/1e5-1)*100
    gross_w=real.delta[real.delta>0].sum(); gross_l=-real.delta[real.delta<0].sum()
    pf=gross_w/gross_l if gross_l>0 else float('inf')
    print(f"\nCloses: {len(real)} | Net: {net:.1f}% | close-level PF: {pf:.3f} | win% {(real.delta>0).mean()*100:.1f}")
    if a.expected_pf:
        ok=abs(pf-a.expected_pf)<=0.08
        print(f"PF MATCH vs optimization {a.expected_pf}: {'OK' if ok else '!! MISMATCH — do not deploy'}")
    print(f"DIRECTION: longs {longs} shorts {shorts}" + ("  !! LONG-ONLY (regime-dependent)" if shorts==0 else "") + ("  !! SHORT-ONLY" if longs==0 else ""))
    # day-of-week attribution
    if daylink:
        L=pd.DataFrame(daylink,columns=['tin','tout','pnl']); L['dow']=L.tin.dt.weekday
        names={0:'Lun',1:'Mar',2:'Mié',3:'Jue',4:'Vie'}
        g=L.groupby('dow').agg(n=('pnl','size'),sum_usd=('pnl','sum'),win=('pnl',lambda x:round((x>0).mean()*100,1)))
        g.index=[names.get(i,i) for i in g.index]; tot=L.pnl.sum()
        g['pct_profit']=(L.groupby('dow').pnl.sum()/tot*100).round(1).values
        print("\nP&L by ENTRY day:\n"+g.round(1).to_string())
        if (g['pct_profit']>70).any(): print("!! DAY CONCENTRATION: one entry day carries >70% of profit — fragile edge, check session")
        overnight=(L.tout.dt.date>L.tin.dt.date).sum(); wknd=((L.tout.dt.weekday<L.tin.dt.weekday)|((L.tout-L.tin).dt.days>=2)).sum()
        print(f"Overnight holds: {overnight}/{len(L)} | weekend-crossing: ~{wknd}  (Master: weekend prohibited -> re-baseline if material)")
    # rolling windows at deploy risk
    mult=(a.deploy_risk/native_risk) if (a.deploy_risk and native_risk) else 1.0
    print(f"\nScaling to deploy risk: x{mult:.2f}" if mult!=1.0 else "\n(no deploy-risk scaling)")
    def plus2(tt):
        m2=tt.month-1+2; y=tt.year+m2//12; m2=m2%12+1
        return pd.Timestamp(y,m2,min(tt.day,calendar.monthrange(y,m2)[1]))
    t0,tN=real.time.iloc[0],real.time.iloc[-1]; w=[]
    for s in pd.date_range(t0.normalize(),tN.normalize(),freq='D'):
        e=plus2(s)
        if e>tN: break
        rs=real.r.values[(real.time>=s).values&(real.time<e).values]*mult
        if len(rs): w.append((np.prod(1+rs)-1)*100)
    w=np.array(w)
    eq=1e5*np.cumprod(1+real.r.values*mult); pk=np.maximum.accumulate(eq)
    print(f"2-mo windows: n={len(w)} median {np.median(w):.2f}% P(>0) {(w>0).mean():.3f} P(>={a.target:.0f}%) {(w>=a.target).mean():.3f} worst {w.min():.2f}% worst5% {np.percentile(w,5):.2f}%")
    print(f"MaxDD @deploy: {((eq-pk)/pk).min()*100:.2f}% | worst single close: {(real.r.min()*mult)*100:.3f}% | biggest single win: {(real.r.max()*mult)*100:.3f}%")
    real[['time','r','balance']].to_csv('/home/claude/set_analyzer_backtest.csv',index=False)
    print("\nStream saved to /home/claude/set_analyzer_backtest.csv (for portfolio combination via lpx-portfolio-manager)")
if __name__=='__main__': main()
