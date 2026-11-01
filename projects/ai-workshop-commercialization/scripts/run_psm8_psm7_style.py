import json
from pathlib import Path
import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler

ROOT=Path(r'C:\Users\tiany\Desktop\AI工坊专题\AI工坊曝光用户PSM8分析_区分AI礼物打赏')
CACHE=ROOT/'AI工坊PSM分析8_full_cache_2m_uncompressed'
OUT=ROOT/'PSM8_PSM7_style_caliper005'
OUT.mkdir(exist_ok=True)
parts=sorted(CACHE.glob('part-*.pkl'))
base=['user_uid','user_ukey','is_treatment','user_group','dt']
metrics=['consume_amount','consume_order_cnt','ai_consume_amount','ai_consume_order_cnt','normal_consume_amount','normal_consume_order_cnt','active_dcnt','watch_dcnt','watch_duration','watch_anchorcnt','watch_gamecnt']
need=base+[f'before{w}d_{x}' for w in (6,13,20,30) for x in metrics]+[f'after{w}d_{x}' for w in (6,13,20) for x in metrics]
avail=set(pd.read_pickle(parts[0]).columns); need=[c for c in dict.fromkeys(need) if c in avail]
frames=[]
for f in parts: frames.append(pd.read_pickle(f)[need])
df=pd.concat(frames,ignore_index=True)
df=df[~df.dt.isin(['2026-08-14','2026-08-15'])].copy()
# 用户级首次 cohort：实验组先锁定首次 treatment，控制组保留首次 control cohort。
t=df[df.user_group=='曝光且支付'].sort_values(['user_ukey','dt']).drop_duplicates('user_ukey').copy()
b=df[df.user_group=='曝光未支付'].sort_values(['user_ukey','dt']).drop_duplicates('user_ukey').copy()
c=df[df.user_group=='未曝光未支付'].sort_values(['user_ukey','dt']).drop_duplicates('user_ukey').copy()
features=[x for x in need if x.startswith('before')]
for x in features: df[x]=pd.to_numeric(df[x],errors='coerce').replace([np.inf,-np.inf],np.nan).fillna(0).clip(lower=0)
def match(t,ctrl,label):
    rows=[]
    for day,tt in t.groupby('dt'):
        cc=ctrl[ctrl.dt==day].copy()
        if len(tt)==0 or len(cc)==0: continue
        z=pd.concat([tt[features],cc[features]],ignore_index=True).to_numpy(float)
        z=np.log1p(z); sc=StandardScaler().fit(z); z=sc.transform(z)
        y=np.r_[np.ones(len(tt)),np.zeros(len(cc))]
        model=LogisticRegression(max_iter=2000,class_weight='balanced',solver='liblinear').fit(z,y)
        ps=model.predict_proba(z)[:,1]; lt=np.log(np.clip(ps[:len(tt)],1e-8,1-1e-8)/np.clip(1-ps[:len(tt)],1e-8,1))
        lc=np.log(np.clip(ps[len(tt):],1e-8,1-1e-8)/np.clip(1-ps[len(tt):],1e-8,1))
        # 一维 logit 最近邻索引，避免实验组×对照组的全量双重循环。
        order=np.argsort(lc); sorted_lc=lc[order]
        cand=[]
        for i,x in enumerate(lt):
            pos=np.searchsorted(sorted_lc,x)
            for k in (pos-1,pos):
                if 0<=k<len(sorted_lc):
                    j=int(order[k]); d=abs(x-lc[j])
                    if d<=0.05: cand.append((d,i,j))
        used_t=set(); used_c=set()
        for d,i,j in sorted(cand):
            if i not in used_t and j not in used_c:
                used_t.add(i); used_c.add(j)
                rows.append((tt.iloc[i].user_ukey,cc.iloc[j].user_ukey,day,d))
    m=pd.DataFrame(rows,columns=['treatment_ukey','control_ukey','dt','caliper_distance'])
    m.to_csv(OUT/f'matches_A_{label}.csv',index=False,encoding='utf-8-sig')
    return m
def smd(a,b):
    a=np.asarray(a,float); b=np.asarray(b,float); den=np.sqrt((a.var(ddof=1)+b.var(ddof=1))/2)
    return 0 if den==0 else (a.mean()-b.mean())/den
results=[]
for label,ctrl in [('曝光未支付',b),('未曝光未支付',c)]:
    m=match(t,ctrl,label)
    mt=t[t.user_ukey.isin(m.treatment_ukey)].copy(); mc=ctrl[ctrl.user_ukey.isin(m.control_ukey)].copy()
    smds={x:smd(mt[x],mc[x]) for x in features}
    results.append({'对比':'A vs '+label,'实验组候选数':len(t),'对照组候选数':len(ctrl),'匹配对数':len(m),'实验组覆盖率':len(m)/len(t),'最大绝对SMD':max(abs(x) for x in smds.values())})
    out=[]
    for w in (6,13,20):
        for x in ['consume_amount','active_dcnt','watch_dcnt','watch_duration']:
            col=f'after{w}d_{x}'; tv=mt[col].mean()/w; cv=mc[col].mean()/w
            out.append({'对比':'A vs '+label,'窗口':f'后{w}日','指标':x,'实验组日均人均':tv,'对照组日均人均':cv,'差异':tv-cv})
    pd.DataFrame(out).to_csv(OUT/f'metrics_A_{label}.csv',index=False,encoding='utf-8-sig')
pd.DataFrame(results).to_csv(OUT/'match_summary.csv',index=False,encoding='utf-8-sig')
print(json.dumps({'treatment':len(t),'B':len(b),'C':len(c),'summary':results},ensure_ascii=False),flush=True)
