import json
from pathlib import Path
import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.neighbors import NearestNeighbors
from sklearn.preprocessing import StandardScaler

CACHE = Path(r'C:\Users\tiany\Desktop\AI工坊专题\AI工坊曝光用户PSM8分析_区分AI礼物打赏\AI工坊PSM分析8_full_cache_2m_uncompressed')
OUT = CACHE.parent / 'PSM8_A_B_C对比结果_corrected_overlap_stdnn'
OUT.mkdir(exist_ok=True)
parts = sorted(CACHE.glob('part-*.pkl'))
need = ['user_uid','is_treatment','user_group','dt']
for w in (6,13,20,30):
    need += [f'before{w}d_{x}' for x in ['consume_amount','consume_order_cnt','ai_consume_amount','normal_consume_amount','active_dcnt','watch_dcnt','watch_duration','watch_anchorcnt','watch_gamecnt'] if f'before{w}d_{x}' not in need]
for w in (6,13,20):
    need += [f'after{w}d_{x}' for x in ['consume_amount','ai_consume_amount','normal_consume_amount','active_dcnt','watch_dcnt','watch_duration','watch_anchorcnt','watch_gamecnt']]
need = list(dict.fromkeys(need))
available = set(pd.read_pickle(parts[0]).columns)
need = [c for c in need if c in available]
for key_col in ['user_uid','user_ukey','is_treatment','user_group','dt']:
    if key_col not in need:
        need.insert(0, key_col)
frames=[]
for f in parts:
    x=pd.read_pickle(f)
    frames.append(x[need])
df=pd.concat(frames,ignore_index=True)
df=df[~df.dt.isin(['2026-08-14','2026-08-15'])].copy()
# 先锁定实验组用户的首次实验 cohort，再对照组去重，避免用户先出现对照记录导致实验用户被误删。
t=df[df.is_treatment==1].sort_values(['user_ukey','dt']).drop_duplicates('user_ukey',keep='first').copy()
t_keys=set(t.user_ukey)
df_control=df[(df.is_treatment==0)&(~df.user_ukey.isin(t_keys))].sort_values(['user_ukey','dt']).drop_duplicates('user_ukey',keep='first').copy()
df=pd.concat([t,df_control],ignore_index=True)
df['is_treatment']=pd.to_numeric(df['is_treatment'],errors='coerce').fillna(0).astype(int)
features=[c for c in df.columns if c.startswith('before')]
features=[c for c in features if c not in ['before30d_watch_duration']]
df[features]=df[features].replace([np.inf,-np.inf],np.nan).fillna(0).astype(float)
df[features]=np.log1p(df[features].clip(lower=0))

def smd(a,b):
    x=a.to_numpy(float); y=b.to_numpy(float)
    den=np.sqrt((x.var(ddof=1)+y.var(ddof=1))/2)
    return 0 if den==0 else (x.mean()-y.mean())/den

def match_pair(t,c,label):
    pairs=[]
    for day,tt in t.groupby('dt'):
        cc=c[c.dt==day]
        if len(tt)==0 or len(cc)==0: continue
        zt=tt[features].to_numpy(float); zc=cc[features].to_numpy(float)
        scaler=StandardScaler().fit(np.vstack([zt,zc]))
        zt=scaler.transform(zt); zc=scaler.transform(zc)
        nn=NearestNeighbors(n_neighbors=1,metric='euclidean',algorithm='brute').fit(zc)
        dist,idx=nn.kneighbors(zt)
        for i,(d,jarr) in enumerate(zip(dist[:,0],idx[:,0])):
            j=int(jarr); pairs.append((tt.iloc[i].user_ukey,cc.iloc[j].user_ukey,day,float(d)))
    m=pd.DataFrame(pairs,columns=['treatment_ukey','control_ukey','dt','distance'])
    if len(m): m.to_csv(OUT/f'matches_A_{label}.csv',index=False,encoding='utf-8-sig')
    return m

# user_group 在原始文件中存在编码显示异常，按两个非实验组的真实取值和规模识别：
# 较小的一组为曝光未支付，较大的一组为未曝光未支付；不依赖中文字符串匹配。
gcounts=df.loc[df.is_treatment==0].groupby('user_group').size().sort_values()
gs=list(gcounts.index)
if len(gs)>=2:
    c1=df[(df.is_treatment==0)&(df.user_group==gs[0])].copy()
    c2=df[(df.is_treatment==0)&(df.user_group==gs[-1])].copy()
else:
    c1=df.iloc[0:0].copy(); c2=df.iloc[0:0].copy()
print(json.dumps({'preflight_after_ukey_dedup': {'treatment': int(t.user_ukey.nunique()) if 't' in globals() else None, 'rows_after_dedup': len(df), 'control_groups': [int(len(c1)), int(len(c2))]}}, ensure_ascii=False), flush=True)
results=[]
for label,c in [('曝光未支付',c1),('未曝光未支付',c2)]:
    m=match_pair(t,c,label)
    mt=df[df.user_ukey.isin(m.treatment_ukey)].copy(); mc=df[df.user_ukey.isin(m.control_ukey)].copy()
    bal={f:max(abs(smd(mt[x],mc[x])) for x in features) if len(m) else np.nan}
    results.append({'对比':'A vs '+label,'实验组候选数':len(t),'对照组候选数':len(c),'匹配对数':len(m),'实验组覆盖率':len(m)/len(t) if len(t) else np.nan,'最大绝对SMD':bal[f]})
    rows=[]
    for w in (6,13,20):
        for metric in ['consume_amount','active_dcnt','watch_dcnt','watch_duration']:
            col=f'after{w}d_{metric}'
            if not len(m): continue
            tv=mt[col].mean()/w; cv=mc[col].mean()/w
            rows.append({'对比':'A vs '+label,'窗口':f'后{w}日','指标':metric,'实验组日均人均':tv,'对照组日均人均':cv,'差异':tv-cv})
    pd.DataFrame(rows).to_csv(OUT/f'metrics_A_{label}.csv',index=False,encoding='utf-8-sig')
pd.DataFrame(results).to_csv(OUT/'match_summary.csv',index=False,encoding='utf-8-sig')
print(json.dumps({'treatment':len(t),'control_exposed_unpaid':len(c1),'control_unexposed_unpaid':len(c2),'summary':results},ensure_ascii=False))
