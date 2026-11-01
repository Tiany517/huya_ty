from pathlib import Path
import numpy as np, pandas as pd
from scipy.stats import ttest_1samp
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Border, Side, Alignment
from openpyxl.utils import get_column_letter

ROOT=Path(r'C:\Users\tiany\Desktop\AI工坊专题\AI工坊曝光用户PSM8分析_区分AI礼物打赏')
CACHE=ROOT/'AI工坊PSM分析8_full_cache_2m_uncompressed'
MATCH=ROOT/'PSM8_PSM7_style_caliper005'/'matches_A_曝光未支付.csv'
OUT=ROOT/'PSM8_A_B_DID报告_caliper005.xlsx'
mm=pd.read_csv(MATCH,encoding='utf-8-sig')
mm['dt']=mm['dt'].astype(str)
tk=set(mm.treatment_ukey); ck=set(mm.control_ukey)
metrics=['consume_amount','consume_order_cnt','ai_consume_amount','ai_consume_order_cnt','normal_consume_amount','normal_consume_order_cnt','active_dcnt','watch_dcnt','watch_duration','watch_anchorcnt','watch_gamecnt']
need=['user_ukey','dt']+[f'{p}{w}d_{m}' for p in ('before','after') for w in (6,13,20) for m in metrics]
parts=sorted(CACHE.glob('part-*.pkl')); chunks=[]
for f in parts:
    x=pd.read_pickle(f)
    x=x[x.user_ukey.isin(tk|ck)]
    if len(x): chunks.append(x[[c for c in need if c in x.columns]])
data=pd.concat(chunks,ignore_index=True)
data=data[data.dt.isin(set(mm.dt))].copy()
t=data[data.user_ukey.isin(tk)].merge(mm[['treatment_ukey','dt']],left_on=['user_ukey','dt'],right_on=['treatment_ukey','dt'])
c=data[data.user_ukey.isin(ck)].merge(mm[['control_ukey','dt']],left_on=['user_ukey','dt'],right_on=['control_ukey','dt'])
rows=[]
names={'consume_amount':'总打赏金额（元）','consume_order_cnt':'总打赏订单数','ai_consume_amount':'AI礼物打赏金额（元）','ai_consume_order_cnt':'AI礼物打赏订单数','normal_consume_amount':'普通礼物打赏金额（元）','normal_consume_order_cnt':'普通礼物打赏订单数','active_dcnt':'活跃天数','watch_dcnt':'观看天数','watch_duration':'观看时长','watch_anchorcnt':'观看主播数','watch_gamecnt':'观看游戏数'}
for w in (6,13,20):
  for m in metrics:
    b1=t[f'before{w}d_{m}'].astype(float).to_numpy()/w; a1=t[f'after{w}d_{m}'].astype(float).to_numpy()/w
    b0=c[f'before{w}d_{m}'].astype(float).to_numpy()/w; a0=c[f'after{w}d_{m}'].astype(float).to_numpy()/w
    n=min(len(b1),len(b0)); d=(a1[:n]-b1[:n])-(a0[:n]-b0[:n]); p=float(ttest_1samp(d,0,nan_policy='omit').pvalue) if len(d)>1 else np.nan
    did=float(np.nanmean(d)); rows.append([f'后{w}日',names[m],float(np.nanmean(b1)),float(np.nanmean(a1)),float(np.nanmean(a1-b1)),float(np.nanmean(b0)),float(np.nanmean(a0)),float(np.nanmean(a0-b0)),did,p,'显著' if p<.05 else '不显著'])
cols=['窗口','指标','实验组前置日均','实验组后置日均','实验组变化','对照组前置日均','对照组后置日均','对照组变化','DID','p值','显著性']
df=pd.DataFrame(rows,columns=cols)
wb=Workbook(); ws=wb.active; ws.title='DID效果'
ws.append(['AI工坊 PSM8 A/B DID 分析（PSM7同口径，caliper=0.05）']); ws.merge_cells(start_row=1,start_column=1,end_row=1,end_column=len(cols))
ws.append(cols)
for r in df.itertuples(index=False): ws.append(list(r))
for cell in ws[1]: cell.font=Font(name='微软雅黑',size=14,bold=True); cell.fill=PatternFill('solid',fgColor='D6DCE5')
for cell in ws[2]: cell.font=Font(name='微软雅黑',size=10,bold=True,color='FFFFFF'); cell.fill=PatternFill('solid',fgColor='4472C4')
for row in ws.iter_rows(min_row=3):
  for cell in row: cell.font=Font(name='微软雅黑',size=10); cell.alignment=Alignment(horizontal='center'); cell.number_format='0.0000'
for i,w in enumerate([12,28,16,16,16,16,16,16,16,12,12],1): ws.column_dimensions[get_column_letter(i)].width=w
for name in ['样本与匹配','口径说明']:
  s=wb.create_sheet(name); s.sheet_view.showGridLines=False
  if name=='样本与匹配':
    vals=[['项目','数值'],['实验组候选用户数',4138],['对照组候选用户数',int(len(ck))],['匹配对数',len(mm)],['实验组覆盖率',len(mm)/4138],['匹配方式','首次cohort、同日期、1:1最近邻、控制组不复用'],['caliper','0.05（logit propensity score）']]
  else:
    vals=[['项目','说明'],['实验组','曝光且支付用户'],['对照组','曝光未支付用户'],['粒度','用户级首次cohort，每个用户只出现一次'],['排除日期','2026-08-14、2026-08-15'],['前置特征','前6/13/20/30日消费、活跃、观看行为'],['DID','（实验组后置−前置）−（对照组后置−前置）'],['单位','金额为元；活跃/观看指标按窗口天数换算为日均人均']]
  for r in vals: s.append(r)
  for cell in s[1]: cell.font=Font(name='微软雅黑',size=11,bold=True,color='FFFFFF'); cell.fill=PatternFill('solid',fgColor='4472C4')
  for row in s.iter_rows():
    for cell in row: cell.font=Font(name='微软雅黑',size=10); cell.alignment=Alignment(wrap_text=True,vertical='top')
  s.column_dimensions['A'].width=28; s.column_dimensions['B'].width=75
wb.save(OUT)
print(OUT)
