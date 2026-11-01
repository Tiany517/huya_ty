import pandas as pd, numpy as np, os, re, zipfile
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
from openpyxl.utils import get_column_letter

base=os.environ.get('NON_DOUYIN_VALORANT_DIR', r'C:\Users\tiany\Desktop\无畏契约份额增长\无畏契约主播潜力分析\非抖无畏主播挖掘')
out=os.path.join(base,'非抖无畏主播_头部基准筛选_含战队与剔战队_20261014.xlsx')
PREF=['EDG','BLG','DRG','JDG','XLG','TYL','FPX','TEC','TE','WOL','AG','NOVA']
raw=pd.read_excel(os.path.join(base,'非抖无畏主播挖掘.xlsx'))
raw['dt']=pd.to_datetime(raw['日期'])
raw['ym']=raw['dt'].dt.strftime('%Y-%m')
raw['ymidx']=raw['dt'].dt.year*12+raw['dt'].dt.month
raw['uid']=raw['主播uid'].astype(str)
team=set(raw[raw['主播名'].apply(lambda x:any(str(x).upper().startswith(k) for k in PREF))]['uid'])
MON=[f'2026-{m:02d}' for m in range(1,10)]
PLATS=['bilibili','douyu','kuaishou']

def layer(x): return '头部' if x>=2000 else '颈部' if x>=1000 else '腰部' if x>=100 else '尾部'
raw['层']=raw['有效acu'].apply(layer)
raw['是战队']=raw['uid'].isin(team)

def addpct(df):
    d=df.sort_values(['uid','dt']).copy()
    d['prev']=d.groupby('uid')['有效acu'].shift(1); d['pi']=d.groupby('uid')['ymidx'].shift(1)
    ok=(d['ymidx']-d['pi']==1)&(d['prev']>0)
    d['pct']=np.where(ok,(d['有效acu']-d['prev'])/d['prev'],np.nan)
    return d.dropna(subset=['pct'])

dA=addpct(raw); dE=addpct(raw[~raw['是战队']])

def med(d,plat,m,head,minn):
    s=d[(d['平台']==plat)&(d['ym']==m)]
    s=s[s['层']=='头部'] if head else s
    return s['pct'].median() if len(s)>=minn else np.nan

H_ALL={}; H_EX={}; A_ALL={}; A_EX={}
for p in PLATS:
    for m in MON:
        H_ALL[(p,m)]=med(dA,p,m,True,3)
        H_EX[(p,m)] =med(dE,p,m,True,3)
        A_ALL[(p,m)]=med(dA,p,m,False,10)
        A_EX[(p,m)] =med(dE,p,m,False,10)

everE=set(raw[~raw['是战队']].groupby('uid')['有效acu'].max().pipe(lambda s:s[s>=2000]).index)
everT=set(raw[raw['是战队']].groupby('uid')['有效acu'].max().pipe(lambda s:s[s>=2000]).index)

def bench_for(plat,is_team):
    if is_team: return H_ALL,'头部中位(含战队)'
    if plat=='bilibili': return H_EX,'头部中位(剔战队)'
    return A_ALL,'全体中位(斗鱼/快手)'

rows=[]; details=[]
for grp,df,d,pool,isteam in [('非战队',raw[~raw['是战队']],dE,everE,False),('战队',raw[raw['是战队']],dA,everT,True)]:
    for uid in pool:
        gp=df[df['uid']==uid].sort_values('dt')
        plat=gp['平台'].iloc[-1]; nm=gp['主播名'].iloc[-1]
        rec=d[d['uid']==uid].copy()
        B,blab=bench_for(plat,isteam)
        rec['bench']=rec.apply(lambda r: B.get((r['平台'],r['ym']),np.nan),axis=1)
        rec=rec.dropna(subset=['bench'])
        rec['跑赢']=rec['pct']>rec['bench']
        n=len(rec); hit=int(rec['跑赢'].sum()); share=hit/n if n else 0.0
        last=gp['ym'].iloc[-1]; best=gp['有效acu'].max(); cur=gp['有效acu'].iloc[-1]
        if last!='2026-09': reason='最近无9月数据(可能已停播)'
        elif n<2: reason='可比月数不足'
        elif share<0.5: reason='未跑赢一半月份'
        else: reason=''
        sel_s='是' if (not reason and n>=4) else '否'
        sel_w='是' if not reason else '否'
        rows.append({'平台':plat,'类型':grp,'主播名':nm,'主播uid':uid,'历史最高有效ACU':best,'最近有数据月份':last,'最近有效ACU':cur,
            '层级':layer(cur),'所用基准':blab,'可比月数':n,'超基准月数':hit,'占比':share,
            '最近日均互动人数':gp['日均互动人数'].iloc[-1],'最近礼物价值':gp['礼物价值'].iloc[-1],'预测年薪酬':gp['预测年薪酬'].iloc[-1],
            '入选(稳健n>=4)':sel_s,'入选(放宽n>=2)':sel_w,'未入选原因':reason})
        for _,rr in rec.iterrows():
            details.append({'平台':plat,'类型':grp,'主播名':nm,'主播uid':uid,'月份':rr['ym'],'当月有效ACU':rr['有效acu'],
                '上月有效ACU':rr['prev'],'环比%':rr['pct'],'所用基准':blab,'对应基准%':rr['bench'],'是否跑赢':bool(rr['跑赢']),'当月层级':rr['层']})

T=pd.DataFrame(rows); D=pd.DataFrame(details)
T['档位']=np.where(T['入选(稳健n>=4)']=='是','稳健',np.where(T['入选(放宽n>=2)']=='是','仅放宽','未入选'))
ordm={'稳健':0,'仅放宽':1,'未入选':2}
T=T.sort_values(['档位','占比','历史最高有效ACU'],key=lambda s:s.map(ordm) if s.name=='档位' else s,ascending=[True,False,False])
FIN=T[T['档位']!='未入选'].copy()
print('总人数',len(T),' 入选',len(FIN))
print(T.groupby(['类型','档位']).size().to_string())
print()
print('斗鱼/快手判定结果:')
print(T[T['平台'].isin(['douyu','kuaishou'])][['平台','主播名','历史最高有效ACU','最近有数据月份','最近有效ACU','可比月数','超基准月数','占比','档位','未入选原因']].to_string(index=False))

FONT='Calibri'
def F(sz=10,b=False,c='000000'): return Font(name=FONT,size=sz,bold=b,color=c)
hfill=PatternFill('solid',fgColor='1F4E79'); hfont=Font(name=FONT,size=10,bold=True,color='FFFFFF')
fillB=PatternFill('solid',fgColor='FCE4D6'); fillA=PatternFill('solid',fgColor='DDEBF7')
fillG=PatternFill('solid',fgColor='E2EFDA'); fillN=PatternFill('solid',fgColor='EDEDED')
thin=Side(style='thin',color='BFBFBF'); bd=Border(thin,thin,thin,thin)
CT=Alignment(horizontal='center',vertical='center'); LT=Alignment(horizontal='left',vertical='center',wrap_text=True)
wb=Workbook()

def put(ws,r,c,v,fmt=None,font=None,align=None,fill=None,border=True):
    cell=ws.cell(row=r,column=c,value=(None if (isinstance(v,float) and pd.isna(v)) else v))
    cell.font=font or F()
    if fmt: cell.number_format=fmt
    cell.alignment=align or CT
    if fill: cell.fill=fill
    if border: cell.border=bd
    return cell

ws0=wb.active; ws0.title='说明与口径'; ws0.column_dimensions['A'].width=22; ws0.column_dimensions['B'].width=108
put(ws0,1,1,'非抖三平台 · 头部基准筛选（2026-01~09）· 最终版',font=Font(name=FONT,size=13,bold=True),align=LT,border=False)
items=[('筛选池','历史进过头部的主播 = 历史最高有效ACU>=2000（任一月进入过头部层）。'),
 ('环比定义','本月有效ACU / 上月有效ACU - 1；仅当上月为相邻自然月且上月ACU>0；1月无上月为空。'),
 ('头部层定义','当月有效ACU>=2000。'),
 ('基准① 战队主播','该平台当月头部层环比中位（含战队主播）。'),
 ('基准② 非战队主播(bilibili)','该平台当月头部层环比中位（剔除战队主播）。'),
 ('基准③ 非战队主播(斗鱼/快手)','这两个平台头部样本只有0~2个，头部中位不可用，改用该平台当月全体主播的环比中位。'),
 ('基准可用性','头部中位需当月头部样本>=3；全体中位需当月有环比样本>=10；不足则该月不参与判定。'),
 ('入选规则','超基准月份占比>=50% 且 可比月数>=4(稳健)/>=2(放宽) 且 2026-09有数据。'),
 ('最近有数据月份','2026-01~09中最后一个月有ACU记录的自然月，即最近一次直播月份。'),
 ('战队主播口径','主播名曾以战队缩写开头(EDG/BLG/DRG/JDG/XLG/TYL/FPX/TEC/TE/WOL/AG/NOVA)，共24人。'),
 ('页签说明','最终名单=入选的人；判定总表=全部历史头部主播(34人)含未入选原因；明细=逐月跑赢/未跑赢证据。'),
 ('视图','本文件未设置冻结窗格。')]
for i,(k,v) in enumerate(items,3): put(ws0,i,1,k,font=F(10,True),align=LT,fill=fillB); put(ws0,i,2,v,align=LT)

ws=wb.create_sheet('平台月度基准'); ws.column_dimensions['A'].width=26
for i in range(2,11): ws.column_dimensions[get_column_letter(i)].width=10
r=1
for title,B,fill in [('一、头部主播·环比中位（含战队）· 战队主播用',H_ALL,fillB),('二、头部主播·环比中位（剔除战队）· bilibili非战队用',H_EX,fillB),
                     ('三、全体主播·环比中位（含战队）· 斗鱼/快手用',A_ALL,fillG),('四、全体主播·环比中位（剔除战队）· 参考',A_EX,fillA)]:
    put(ws,r,1,title,font=F(11,True),align=LT,fill=fill,border=False); r+=1
    put(ws,r,1,'平台',font=hfont,fill=hfill)
    for j,m in enumerate(MON,2): put(ws,r,j,f'{int(m[-2:])}月',font=hfont,fill=hfill)
    r+=1
    for p in PLATS:
        put(ws,r,1,p,font=F(10,True))
        for j,m in enumerate(MON,2):
            v=B[(p,m)]; put(ws,r,j,(None if pd.isna(v) else v),fmt='0.0%',fill=(fill if not pd.isna(v) else fillN))
        r+=1
    r+=1
put(ws,r,1,'注: 灰色=样本不足，该月不参与判定。斗鱼/快手头部样本0~2个，故改用全体中位。',align=LT,border=False)

def dump(ws,data,title,widths):
    ws.insert_rows(1)
    put(ws,1,1,title,font=F(11,True),align=LT,border=False)
    for j,c in enumerate(data.columns,1):
        cell=ws.cell(row=2,column=j,value=c); cell.font=hfont; cell.fill=hfill; cell.border=bd; cell.alignment=CT
    for i,(_,rr) in enumerate(data.iterrows(),3):
        for j,c in enumerate(data.columns,1):
            v=rr[c]
            if isinstance(v,float) and pd.isna(v): v=None
            cell=ws.cell(row=i,column=j,value=v); cell.border=bd; cell.alignment=CT; cell.font=F()
            if c in ('占比','环比%','对应基准%'): cell.number_format='0%' if c=='占比' else '0.0%'
            if c in ('历史最高有效ACU','最近有效ACU','最近日均互动人数','最近礼物价值','预测年薪酬','当月有效ACU','上月有效ACU'): cell.number_format='#,##0'
            if c=='主播uid': cell.number_format='@'
            if c=='档位' and v=='稳健': cell.fill=fillG
            elif c=='档位' and v=='仅放宽': cell.fill=fillB
            if c=='是否跑赢' and v: cell.fill=fillG
    for i,w in enumerate(widths,1): ws.column_dimensions[get_column_letter(i)].width=w

colsF=['平台','类型','主播名','主播uid','历史最高有效ACU','最近有数据月份','最近有效ACU','层级','档位','所用基准','可比月数','超基准月数','占比','最近日均互动人数','最近礼物价值','预测年薪酬']
wF=[10,8,20,18,14,14,12,8,8,20,9,10,9,13,13,12]
dump(wb.create_sheet('最终名单'),FIN[colsF],'最终名单 · 入选主播（含战队与非战队，斗鱼/快手用全体中位基准）',wF)
colsT=['平台','类型','主播名','主播uid','历史最高有效ACU','最近有数据月份','最近有效ACU','层级','档位','所用基准','可比月数','超基准月数','占比','未入选原因']
wT=[10,8,20,18,14,14,12,8,8,20,9,10,9,22]
dump(wb.create_sheet('判定总表'),T[colsT],'判定总表 · 全部历史进过头部的主播（34人）',wT)
wD=['平台','类型','主播名','主播uid','月份','当月有效ACU','上月有效ACU','环比%','所用基准','对应基准%','是否跑赢','当月层级']
wDw=[10,8,20,18,10,13,13,11,20,12,10,9]
dump(wb.create_sheet('明细_非战队'),D[D['类型']=='非战队'][wD],'明细 · 非战队主播 逐月判定',wDw)
dump(wb.create_sheet('明细_战队'),D[D['类型']=='战队'][wD],'明细 · 战队主播 逐月判定',wDw)

wb.save(out)
tmp=out+'.tmp'; zin=zipfile.ZipFile(out,'r'); zout=zipfile.ZipFile(tmp,'w',zipfile.ZIP_DEFLATED)
for it in zin.infolist():
    data=zin.read(it.filename)
    if it.filename=='xl/theme/theme1.xml':
        x=data.decode('utf-8')
        x=re.sub(r'<a:ea typeface="[^"]*"','<a:ea typeface="楷体"',x)
        x=re.sub(r'<a:latin typeface="[^"]*"','<a:latin typeface="Calibri"',x)
        data=x.encode('utf-8')
    zout.writestr(it,data)
zin.close(); zout.close(); os.replace(tmp,out)
print('已生成:',out); print(wb.sheetnames)
