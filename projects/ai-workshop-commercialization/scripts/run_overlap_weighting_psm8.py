import json
from pathlib import Path
import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler

ROOT=Path(r'C:\Users\tiany\Desktop\AI工坊专题\AI工坊曝光用户PSM8分析_区分AI礼物打赏')
CACHE=ROOT/'AI工坊PSM分析8_full_cache_2m_uncompressed'
OUT=ROOT/'PSM8_overlap_weighting'
OUT.mkdir(exist_ok=True)
parts=sorted(CACHE.glob('part-*.pkl'))
cols=['user_ukey','is_treatment','user_group','dt']
cols += [f'before{w}d_{x}' for w in [6,13,20,30] for x in ['consume_amount','consume_order_cnt','ai_consume_amount','ai_consume_order_cnt','normal_consume_amount','normal_consume_order_cnt','active_dcnt','watch_dcnt','watch_duration','watch_anchorcnt','watch_gamecnt']]
cols += [f'after{w}d_{x}' for w in [6,13,20] for x in ['consume_amount','consume_order_cnt','ai_consume_amount','ai_consume_order_cnt','normal_consume_amount','normal_consume_order_cnt','active_dcnt','watch_dcnt','watch_duration','watch_anchorcnt','watch_gamecnt']]
available=set(pd.read_pickle(parts[0]).columns); cols=[c for c in dict.fromkeys(cols) if c in available]
frames=[]
for f in parts:
    x=pd.read_pickle(f); frames.append(x[cols])
df=pd.concat(frames,ignore_index=True)
df=df[~df.dt.isin(['2026-08-14','2026-08-15'])].copy()
t=df[df.is_treatment==1].sort_values(['user_ukey','dt']).drop_duplicates('user_ukey').copy()
tkeys=set(t.user_ukey)
c=df[(df.is_treatment==0)&(~df.user_ukey.isin(tkeys))].sort_values(['user_ukey','dt']).drop_duplicates('user_ukey').copy()
# user_group 是缓存中已经固定的业务标签，禁止按样本量反推组别。
c1=c[c.user_group=='曝光未支付'].copy()
c2=c[c.user_group=='未曝光未支付'].copy()
features=[x for x in df.columns if x.startswith('before')]
df[features]=df[features].replace([np.inf,-np.inf],np.nan).fillna(0).astype(float)
df[features]=np.log1p(df[features].clip(lower=0))
def wm(x,w): return float(np.sum(x*w)/np.sum(w))
def smd(a,wa,b,wb):
    ma=wm(a,wa); mb=wm(b,wb); va=wm((a-ma)**2,wa); vb=wm((b-mb)**2,wb); den=np.sqrt((va+vb)/2)
    return 0 if den==0 else (ma-mb)/den
summary=[]
for label,ctrl in [('曝光未支付',c1),('未曝光未支付',c2)]:
    rows=[]
    for day,tt in t.groupby('dt'):
        cc=ctrl[ctrl.dt==day]
        if len(tt)==0 or len(cc)==0: continue
        cc_model=cc.sample(n=min(100000,len(cc)),random_state=20260909) if len(cc)>100000 else cc
        z=pd.concat([tt[features],cc_model[features]],ignore_index=True); y=np.r_[np.ones(len(tt)),np.zeros(len(cc_model))]
        scaler=StandardScaler().fit(z); z=scaler.transform(z); model=LogisticRegression(max_iter=2000,class_weight='balanced',solver='liblinear').fit(z,y)
        p=model.predict_proba(z)[:,1]; pc=model.predict_proba(scaler.transform(cc[features]))[:,1]
        for i in range(len(tt)): rows.append((tt.iloc[i].user_ukey,tt['dt'].iloc[i],1,float(1-p[i])))
        for i in range(len(cc)): rows.append((cc.iloc[i].user_ukey,cc['dt'].iloc[i],0,float(pc[i])))
    w=pd.DataFrame(rows,columns=['user_ukey','dt','treatment','weight'])
    mt=t.merge(w[w.treatment==1],on=['user_ukey','dt']); mc=ctrl.merge(w[w.treatment==0],on=['user_ukey','dt'])
    smds={x:smd(mt[x].to_numpy(),mt.weight.to_numpy(),mc[x].to_numpy(),mc.weight.to_numpy()) for x in features}
    ess_t=(mt.weight.sum()**2)/(mt.weight.pow(2).sum()); ess_c=(mc.weight.sum()**2)/(mc.weight.pow(2).sum())
    summary.append({'对比':'A vs '+label,'实验组用户数':len(t),'对照组用户数':len(ctrl),'实验组覆盖率':1.0,'实验组ESS':ess_t,'对照组ESS':ess_c,'最大绝对SMD':max(abs(v) for v in smds.values())})
    w.to_csv(OUT/f'weights_A_{label}.csv',index=False,encoding='utf-8-sig')
    out=[]
    for win in [6,13,20]:
        for metric in ['consume_amount','active_dcnt','watch_dcnt','watch_duration']:
            col=f'after{win}d_{metric}'; tv=wm(mt[col].to_numpy(),mt.weight.to_numpy())/win; cv=wm(mc[col].to_numpy(),mc.weight.to_numpy())/win
            out.append({'对比':'A vs '+label,'窗口':f'后{win}日','指标':metric,'实验组加权日均人均':tv,'对照组加权日均人均':cv,'差异':tv-cv})
    pd.DataFrame(out).to_csv(OUT/f'metrics_A_{label}.csv',index=False,encoding='utf-8-sig')
pd.DataFrame(summary).to_csv(OUT/'overlap_summary.csv',index=False,encoding='utf-8-sig')
print(json.dumps({'summary':summary},ensure_ascii=False),flush=True)
