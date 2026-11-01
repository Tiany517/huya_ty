import openpyxl, pandas as pd, os
base=os.environ.get('NON_DOUYIN_VALORANT_DIR', r'C:\Users\tiany\Desktop\无畏契约份额增长\无畏契约主播潜力分析\非抖无畏主播挖掘')
p=os.path.join(base,'非抖无畏主播_头部基准筛选_含战队与剔战队_20261014.xlsx')
wb=openpyxl.load_workbook(p)
print('sheets:',wb.sheetnames)
for s in wb.sheetnames: print('  freeze',s,'=',wb[s].freeze_panes)
for s in ['最终名单','判定总表']:
    df=pd.read_excel(p,sheet_name=s,header=1)
    print('====',s,df.shape)
    if s=='最终名单':
        print(df[['平台','类型','主播名','历史最高有效ACU','最近有数据月份','最近有效ACU','档位','所用基准','可比月数','超基准月数','占比']].to_string(index=False))
    else:
        print(df[['平台','类型','主播名','历史最高有效ACU','最近有数据月份','最近有效ACU','档位','可比月数','超基准月数','占比','未入选原因']].to_string(index=False))
    print()
