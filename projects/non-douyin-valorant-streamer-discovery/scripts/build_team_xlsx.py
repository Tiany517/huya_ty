import pandas as pd, numpy as np, os, re, zipfile, pickle
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
from openpyxl.utils import get_column_letter

base=os.environ.get('NON_DOUYIN_VALORANT_DIR', r'C:\Users\tiany\Desktop\无畏契约份额增长\无畏契约主播潜力分析\非抖无畏主播挖掘')
out=os.path.join(base,'非抖无畏主播_剔除战队_平台基准筛选_20261014.xlsx')
with open(os.path.join(base,'scripts','_state_team.pkl'),'rb') as f: S=pickle.load(f)
agg,bench,cand,team_uid=S['agg'],S['bench'],S['cand'],S['team_uid']

PREF=['EDG','BLG','DRG','JDG','XLG','TYL','FPX','TEC','TE','WOL','AG','NOVA']
def hit(n):
    u=str(n).upper(); return [x for x in PREF if u.startswith(x)]
raw=pd.read_excel(os.path.join(base,'非抖无畏主播挖掘.xlsx')); raw['dt']=pd.to_datetime(raw['日期'])
tr=raw[raw['主播uid'].astype(str).isin(team_uid)].copy()
def aggname(s):
    seen=[]
    for x in s:
        if x not in seen: seen.append(x)
    return ' -> '.join(seen)
team_tab=tr.sort_values('dt').groupby('主播uid').agg(
    平台=('平台','last'),最新名=('主播名','last'),曾用名=('主播名',aggname)).reset_index()
team_tab['命中前缀']=team_tab['主播名'].map(lambda x:'/'.join(hit(x))) if False else team_tab.apply(lambda r:'/'.join(sorted(set(hit(r['最新名'])+hit(r['曾用名'].split(' -> ')[0])))),axis=1)
prefmap={}
for uid,sub in tr.groupby('主播uid'):
    p=set()
    for n in sub['主播名']: p|=set(hit(n))
    prefmap[uid]='/'.join(sorted(p))
team_tab['命中前缀']=team_tab['主播uid'].map(prefmap)
team_tab=team_tab.sort_values('命中前缀')

FONT='Calibri'
def F(sz=10,b=False,c='000000'): return Font(name=FONT,size=sz,bold=b,color=c)
hfill=PatternFill('solid',fgColor='1F4E79'); hfont=Font(name=FONT,size=10,bold=True,color='FFFFFF')
fillA=PatternFill('solid',fgColor='DDEBF7'); fillH=PatternFill('solid',fgColor='FCE4D6'); ok_fill=PatternFill('solid',fgColor='C6EFCE')
thin=Side(style='thin',color='BFBFBF'); bd=Border(thin,thin,thin,thin)
CT=Alignment(horizontal='center',vertical='center'); LT=Alignment(horizontal='left',vertical='center',wrap_text=True)
wb=Workbook()
def put(ws,r,c,v,fmt=None,font=None,align=None,fill=None,border=True):
    cell=ws.cell(row=r,column=c,value=(None if (isinstance(v,float) and pd.isna(v)) else v)); cell.font=font or F()
    if fmt: cell.number_format=fmt
    cell.alignment=align or CT
    if fill: cell.fill=fill
    if border: cell.border=bd
    return cell
def hr(ws,r,cols,widths=None):
    for i,c in enumerate(cols,1): put(ws,r,i,c,font=hfont,fill=hfill)
    if widths:
        for i,w in enumerate(widths,1): ws.column_dimensions[get_column_letter(i)].width=w

ws=wb.active; ws.title='说明与结论'; ws.column_dimensions['A'].width=16; ws.column_dimensions['B'].width=112
info=[
('本次变化','在“平台基准筛选”基础上, 先剔除战队(电竞俱乐部)主播, 再重算基准并筛选。'),
('剔除规则','主播名以战队缩写开头即视为战队主播, 前缀=EDG/BLG/DRG/JDG/XLG/TYL/FPX/TEC/TE/WOL/AG/NOVA; 采用“任意月份曾带前缀”判定。'),
('剔除规模','共剔除 24 人(其中最新名仍带前缀 19 人, 仅历史月份带前缀 5 人)。'),
('候选池变化','曾达头部候选 34 → 26 人(可评估 21 人)。'),
('基准变化(重点)','剔除后 bilibili 头部中位 23.4%→20.3%、整体中位 0.0%→-1.5%、整体均值 32.7%→30.7%; douyu/kuaishou 基本不变。'),
('结果(R2=超基准占比>=50%,n>=1)','头部基准: 12→6 人; 整体中位: 20→15 人; 整体均值: 12→6 人。'),
('说明','上一版入选的部分战队前缀主播因属战队主播被剔除, 名单结构明显变化。'),
('需你确认','剔除口径用“最新名带前缀(19人)”还是“曾带前缀(24人)”; 基准用头部/整体中位/整体均值。'),
]
put(ws,1,1,'非抖无畏 · 剔除战队后 · 平台基准筛选（20261014版）',font=F(13,True),align=LT,border=False); ws.merge_cells('A1:B1')
r=3
for k,v in info:
    put(ws,r,1,k,font=F(10,True),align=Alignment(horizontal='left',vertical='top',wrap_text=True),fill=fillA)
    put(ws,r,2,v,align=Alignment(horizontal='left',vertical='top',wrap_text=True)); r+=1

ws=wb.create_sheet('剔除的战队主播')
hr(ws,1,['命中前缀','平台','最新名','曾用名(按月份去重)','主播uid'],[12,10,22,42,20])
for i,row in enumerate(team_tab[['命中前缀','平台','最新名','曾用名','主播uid']].itertuples(index=False),2):
    for j,v in enumerate(row,1): put(ws,i,j,v,align=LT if j in (3,4) else CT)
ws.freeze_panes='A2'

ws=wb.create_sheet('平台基准对比_剔除后')
hr(ws,1,['平台','头部层条数','头部中位','头部均值','整体条数','整体中位','整体均值'],[10,12,12,12,12,12,12])
r=2
for plat,row in bench.iterrows():
    put(ws,r,1,plat); put(ws,r,2,None if pd.isna(row['头部n']) else int(row['头部n']))
    put(ws,r,3,row['头部中位'],fmt='0.0%'); put(ws,r,4,row['头部均值'],fmt='0.0%')
    put(ws,r,5,int(row['整体n'])); put(ws,r,6,row['整体中位'],fmt='0.0%',fill=fillH); put(ws,r,7,row['整体均值'],fmt='0.0%',fill=fillH); r+=1

ws=wb.create_sheet('候选主播_曾达头部')
cols=['平台','主播名','覆盖月数','n','达到头部月数','历史最高ACU','最近有数据月份','最近有效ACU','可评估',
      '基准_头部中位%','超头','占比头','R2头','基准_平台整体中位%','超整中','占比整中','R2整中','基准_平台整体均值%','超整均','占比整均','R2整均','avgpct','maxpct']
hdr=['平台','主播名','覆盖月数','相邻月对数n','达到头部月数','历史最高有效acu','最近有数据月份','最近有效ACU','可评估',
     '基准_头部中位%','超基准月数(头)','占比(头)','R2入选(头部基准)','基准_平台整体中位%','超基准月数(整体中)','占比(整体中)','R2入选(整体中位)','基准_平台整体均值%','超基准月数(整体均)','占比(整体均)','R2入选(整体均值)','平均环比%','最大环比%']
hr(ws,1,hdr,[10,20,10,12,12,14,14,12,8,13,12,10,14,14,14,10,14,14,14,10,14,11,10])
for i,row in enumerate(agg[cols].itertuples(index=False),2):
    for j,v in enumerate(row,1):
        v=bool(v) if isinstance(v,(np.bool_,)) else v
        h=hdr[j-1]
        if h.startswith('R2入选'): fill=ok_fill if v is True else None; fmt=None
        elif h.startswith('基准_') or h.startswith('占比('): fill=None; fmt='0.0%'
        elif h in ('平均环比%','最大环比%'): fill=None; fmt='0.0%'
        elif 'acu' in h.lower(): fill=None; fmt='0.0'
        else: fill=None; fmt=None
        put(ws,i,j,v,fmt=fmt,fill=fill)
ws.freeze_panes='A2'

ws=wb.create_sheet('候选月度明细')
cc=cand.copy(); cc['_p']=cc['平台'].map({'bilibili':0,'douyu':1,'kuaishou':2}); cc=cc.sort_values(['_p','主播名','ym'])
cols2=['平台','主播名','主播uid','ym','有效acu','prev','pct','bH','超头','bPm','超整中','bPM','超整均']
hdr2=['平台','主播名','主播uid','月份','当月有效acu','上月有效acu','环比%','头部基准%','超头部','整体中位基准%','超整体中位','整体均值基准%','超整体均值']
hr(ws,1,hdr2,[10,20,18,10,13,13,11,12,10,15,12,15,12])
for i,row in enumerate(cc[cols2].itertuples(index=False),2):
    for j,v in enumerate(row,1):
        v=bool(v) if isinstance(v,(np.bool_,)) else v
        h=hdr2[j-1]; fmt='0.0%' if h in ('环比%','头部基准%','整体中位基准%','整体均值基准%') else None
        fill=ok_fill if (h=='超整体中位' and v is True) else None
        put(ws,i,j,v,fmt=fmt,fill=fill)
ws.freeze_panes='A2'

wb.save(out)
tmp=out+'.tmp'; zin=zipfile.ZipFile(out,'r'); zout=zipfile.ZipFile(tmp,'w',zipfile.ZIP_DEFLATED)
for it in zin.infolist():
    data=zin.read(it.filename)
    if it.filename=='xl/theme/theme1.xml':
        t=data.decode('utf-8'); t=re.sub(r'<a:ea typeface="[^"]*"','<a:ea typeface="楷体"',t); t=re.sub(r'<a:latin typeface="[^"]*"','<a:latin typeface="Calibri"',t); data=t.encode('utf-8')
    zout.writestr(it,data)
zin.close(); zout.close(); os.replace(tmp,out)
print('已生成:',out)
