import pandas as pd, numpy as np, os, re, zipfile
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
from openpyxl.utils import get_column_letter

base=os.environ.get('NON_DOUYIN_VALORANT_DIR', r'C:\Users\tiany\Desktop\无畏契约份额增长\无畏契约主播潜力分析\非抖无畏主播挖掘')
src=os.path.join(base,'非抖无畏主播挖掘.xlsx')
out=os.path.join(base,'非抖无畏主播_剔除战队_平台基准筛选_20261014.xlsx')
PREF=['EDG','BLG','DRG','JDG','XLG','TYL','FPX','TEC','TE','WOL','AG','NOVA']
def hit(n):
    u=str(n).upper(); return [x for x in PREF if u.startswith(x)]

raw=pd.read_excel(src); raw['dt']=pd.to_datetime(raw['日期'])
team_uid=set(raw[raw['主播名'].apply(lambda x:len(hit(x))>0)]['主播uid'].astype(str))
team_names=raw[raw['主播uid'].astype(str).isin(team_uid)].sort_values('dt').groupby('主播uid')['主播名'].agg(['last','first'])
team_plat=raw[raw['主播uid'].astype(str).isin(team_uid)].groupby('主播uid')['平台'].last()
print('剔除战队主播数(任意月份曾带前缀):',len(team_uid))

df=raw[~raw['主播uid'].astype(str).isin(team_uid)].copy()
df['ym']=df['dt'].dt.strftime('%Y-%m'); df['ymidx']=df['dt'].dt.year*12+df['dt'].dt.month
def layer(x): return '头部' if x>=2000 else '颈部' if x>=1000 else '腰部' if x>=100 else '尾部'
df['层']=df['有效acu'].apply(layer)
nm=df.sort_values('dt').groupby('主播uid')['主播名'].last(); pf=df.groupby('主播uid')['平台'].last()
head_uid=set(df[df['有效acu']>=2000]['主播uid'].astype(str))

d=df.sort_values(['主播uid','dt']).copy()
d['prev']=d.groupby('主播uid')['有效acu'].shift(1); d['pi']=d.groupby('主播uid')['ymidx'].shift(1)
ok=(d['ymidx']-d['pi']==1)&(d['prev']>0)
d['pct']=np.where(ok,(d['有效acu']-d['prev'])/d['prev'],np.nan)
g=d.dropna(subset=['pct']).copy()
hg=d[d['层']=='头部'].dropna(subset=['pct'])
H=hg.groupby('平台')['pct'].agg(头部中位='median',头部均值='mean',头部n='size')
P=g.groupby('平台')['pct'].agg(整体中位='median',整体均值='mean',整体n='size')
bench=P.join(H,how='outer')

cand=g[g['主播uid'].astype(str).isin(head_uid)].copy()
cand['bH']=cand['平台'].map(H['头部中位']); cand['bPm']=cand['平台'].map(P['整体中位']); cand['bPM']=cand['平台'].map(P['整体均值'])
for c,b in [('超头','bH'),('超整中','bPm'),('超整均','bPM')]: cand[c]=np.where(cand[b].notna(),cand['pct']>cand[b],np.nan)
allids=pd.Index(sorted(head_uid),name='主播uid')
agg=cand.groupby('主播uid').agg(n=('ym','size'),超头=('超头','sum'),超整中=('超整中','sum'),超整均=('超整均','sum'),avgpct=('pct','mean'),maxpct=('pct','max')).reindex(allids)
for c in ['n','超头','超整中','超整均']: agg[c]=agg[c].fillna(0).astype(int)
agg['主播名']=agg.index.map(nm); agg['平台']=agg.index.map(pf)
agg['覆盖月数']=df.groupby('主播uid')['ym'].nunique().reindex(allids)
agg['达到头部月数']=df.assign(h=df['有效acu']>=2000).groupby('主播uid')['h'].sum().reindex(allids)
agg['历史最高ACU']=df.groupby('主播uid')['有效acu'].max().reindex(allids)
rec=df.sort_values(['主播uid','dt']).groupby('主播uid').agg(最近月=('ym','last'),最近ACU=('有效acu','last')).reindex(allids)
agg['最近有数据月份']=rec['最近月']; agg['最近有效ACU']=rec['最近ACU']
nn=agg['n'].replace(0,np.nan)
agg['占比头']=(agg['超头']/nn).round(3); agg['占比整中']=(agg['超整中']/nn).round(3); agg['占比整均']=(agg['超整均']/nn).round(3)
agg['R2头']=(agg['占比头']>=0.5); agg['R2整中']=(agg['占比整中']>=0.5); agg['R2整均']=(agg['占比整均']>=0.5)
agg['基准_头部中位%']=agg['平台'].map(H['头部中位']); agg['基准_平台整体中位%']=agg['平台'].map(P['整体中位']); agg['基准_平台整体均值%']=agg['平台'].map(P['整体均值'])
agg['可评估']=agg['n']>=1
agg=agg.sort_values(['可评估','R2整中','占比整中','avgpct'],ascending=[False,False,False,False])

print('剔除后 曾达头部候选:',len(head_uid),' 可评估:',int(agg['可评估'].sum()))
print('平台基准(剔除后):'); print(bench.round(3).to_string())
print('R2 头部基准:',int(agg['R2头'].sum()),' | R2 整体中位:',int(agg['R2整中'].sum()),' | R2 整体均值:',int(agg['R2整均'].sum()))
for tag,flag in [('头部基准','R2头'),('整体中位','R2整中'),('整体均值','R2整均')]:
    s=agg[agg[flag]]
    print(f'\n=== R2 [{tag}] 入选 {len(s)} 人 ===')
    print(s[['平台','主播名','n','占比头','占比整中','占比整均']].round(3).to_string())

with open(os.path.join(base,'scripts','_state_team.pkl'),'wb') as f:
    import pickle; pickle.dump(dict(agg=agg,bench=bench,cand=cand,team_names=team_names,team_plat=team_plat,team_uid=team_uid),f)
print('\n已保存计算中间态')
