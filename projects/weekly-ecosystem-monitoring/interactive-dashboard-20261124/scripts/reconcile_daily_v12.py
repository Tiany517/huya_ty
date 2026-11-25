"""Independent export-to-HTML reconciliation; not a replacement for warehouse checks."""
import argparse,base64,gzip,json,re,math
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--data',type=Path,required=True);p.add_argument('--html',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
raw=json.loads(a.data.read_text(encoding='utf-8'));text=a.html.read_text(encoding='utf-8');encoded=re.search(r'id="v12-data">(.*?)</script>',text,re.S)[1];payload=json.loads(gzip.decompress(base64.b64decode(encoded)));meta=raw['meta'];checks=[];expectations=[]
# Read original column names rather than the builder's prepared dictionaries.
cols={v:i for i,v in enumerate(meta['categoryColumns'])};pc={v:i+2 for i,v in enumerate(payload['categoryMetrics'])};lookup={(payload['dates'][r[0]],r[1]):r for r in payload['categoryRows']}
for field in ['dau','revenue','payUsers','attributionUsers','liveAnchors','viewMinutes']:
 mismatch=[]
 for r in raw['categoryDaily']:
  out=lookup.get((r[0],int(r[1])));x=r[cols[field]];y=out[pc[field]] if out else None
  if x!=y and not(isinstance(x,(int,float)) and isinstance(y,(int,float)) and math.isclose(x,y,rel_tol=1e-12,abs_tol=1e-8)):mismatch.append([r[0],r[1],x,y])
 checks.append({'check':'all_category_cells_'+field,'passed':not mismatch,'rows':len(raw['categoryDaily']),'examples':mismatch[:5]})
wc={v:i for i,v in enumerate(meta['anchorColumns'])};week=len(meta['weeks'])-1;wr=meta['weekRanges'][meta['weeks'][week]]
for scope,column in [('guild','guild'),('anchor','anchor')]:
 ids=sorted({r[wc[column]] for r in raw['anchorWeekly'] if r[wc['week']]==week})[:5]
 for identifier in ids:
  selected=[r for r in raw['anchorWeekly'] if r[wc['week']]==week and r[wc[column]]==identifier]
  for metric in ['dau','revenue','payUsers','attributionUsers','interactionUsers']:
   value=sum(r[wc[metric]] for r in selected)/(7 if metric=='dau' else 1)
   expectations.append({'scope':scope,'id':identifier,'metric':metric,'start':wr['start'],'end':wr['end'],'value':value})
checks.append({'check':'anchor_weekly_export_unchanged','passed':payload['anchorWeekly']==raw['anchorWeekly']})
checks.append({'check':'anchor_daily_export_unchanged','passed':payload['anchorDaily']==raw['anchorDaily']})
report={'status':'passed' if all(c['passed'] for c in checks) else 'failed','scope':'export-to-payload; warehouse all-history and visual acceptance remain separate','checks':checks,'engineExpectations':expectations}
a.output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps({'status':report['status'],'checks':len(checks),'engineExpectations':len(expectations)}));assert report['status']=='passed'
