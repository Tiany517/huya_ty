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
# Independent weekly tier supply expectation: dedupe live days by anchor inside each
# ACU tier, then divide by seven. This verifies the exact approximate-output contract.
def fixed_tier(acu):
 return '头部' if acu>=2000 else '腰部' if acu>=100 else '尾部' if acu>=0 else '非基期主播（新增/历史记录）'
ref_index=len(meta['weeks'])-2
ref_acu={}
for r in raw['anchorWeekly']:
 if r[wc['week']]!=ref_index:continue
 total=ref_acu.setdefault(r[wc['anchor']],[0,0]);total[0]+=r[wc['acuSum']];total[1]+=r[wc['acuDays']]
tier_by_anchor={anchor:fixed_tier(total/day if day else -1) for anchor,(total,day) in ref_acu.items()}
for week_index in range(len(meta['weeks'])-2,len(meta['weeks'])):
 week_label=meta['weeks'][week_index]
 selected=[r for r in raw['anchorWeekly'] if r[wc['week']]==week_index]
 grouped={tier:{} for tier in ['头部','腰部','尾部']}
 for r in selected:
  tier=tier_by_anchor.get(r[wc['anchor']],'非基期主播（新增/历史记录）')
  if tier not in grouped:continue
  anchor=r[wc['anchor']];grouped[tier][anchor]=max(grouped[tier].get(anchor,0),r[wc['liveDays']] or 0)
 for tier,anchor_days in grouped.items():
  expectations.append({'scope':'tier','id':tier,'metric':'liveAnchors','start':meta['weekRanges'][week_label]['start'],'end':meta['weekRanges'][week_label]['end'],'value':sum(anchor_days.values())/7})
checks.append({'check':'weekly_tier_supply_expectations_prepared','passed':len(expectations)>=6,'weeks':meta['weeks'][-2:],'tiers':['头部','腰部','尾部'],'note':'周路径近似；跨品类换播可能低估；实际比对由JS引擎对账步骤完成'})
checks.append({'check':'anchor_weekly_export_unchanged','passed':payload['anchorWeekly']==raw['anchorWeekly']})
checks.append({'check':'anchor_daily_export_unchanged','passed':payload['anchorDaily']==raw['anchorDaily']})
# Independent micro-path expectation: choose each anchor's max-DAU category/guild
# for each week, remove that category's event days, then aggregate raw daily rows.
wc_payload={v:i for i,v in enumerate(payload['anchorColumns'])}
dcol={v:i for i,v in enumerate(payload['anchorDailyColumns'])}
cur_i=len(payload['weeks'])-1;base_i=cur_i-1
path_maps=[]
for wi in (cur_i,base_i):
 best={}
 for r in payload['anchorWeekly']:
  if r[wc_payload['week']]!=wi:continue
  anchor_id=r[wc_payload['anchor']];v=r[wc_payload['dau']]
  if anchor_id not in best or (v is not None and (best[anchor_id][wc_payload['dau']] is None or v>best[anchor_id][wc_payload['dau']])):best[anchor_id]=r
 path_maps.append(best)
daily_by_anchor={}
for r in payload['anchorDaily']:daily_by_anchor.setdefault(r[dcol['anchor']],[]).append(r)
def micro_summary(anchor,path,range_):
 cat=payload['categories'][path[wc_payload['category']]]
 excluded=set(payload['eventDays'].get(str(cat['id']),[]))
 rows=[r for r in daily_by_anchor.get(anchor,[]) if range_['start']<=r[dcol['date']]<=range_['end'] and r[dcol['date']] not in excluded]
 vals=[float(r[dcol['dau']]) for r in rows if r[dcol['dau']] is not None]
 return {'current':sum(vals)/len(vals) if vals else None,'days':len(vals),'live':sum(1 for r in rows if r[dcol['isLive']]==1),'eventCovered':str(cat['id']) in payload['eventDays']}
micro=[]
cur_map,base_map=path_maps
for anchor in sorted(set(cur_map)&set(base_map)):
 cp,bp=cur_map[anchor],base_map[anchor]
 cs=micro_summary(anchor,cp,payload['weekRanges'][payload['weeks'][cur_i]])
 bs=micro_summary(anchor,bp,payload['weekRanges'][payload['weeks'][base_i]])
 if not cs['eventCovered'] or not bs['eventCovered'] or cs['days']<3 or bs['days']<3 or cs['current'] is None or bs['current'] is None:continue
 am=payload['anchors'][anchor]
 micro.append({'scope':'anchor','id':str(am['id']),'anchorIndex':anchor,'name':am['name'],'guildIndex':cp[wc_payload['guild']],'current':cs['current'],'baseline':bs['current'],'delta':cs['current']-bs['current'],'currentDays':cs['days'],'baselineDays':bs['days'],'currentLiveDays':cs['live'],'baselineLiveDays':bs['live']})
micro.sort(key=lambda x:x['delta'])
selected=micro[:12]+sorted(micro,key=lambda x:x['delta'],reverse=True)[:6]
guild_expected=[]
for gi in {x['guildIndex'] for x in micro}:
 rows=[x for x in micro if x['guildIndex']==gi]
 if rows:
  guild_expected.append({'scope':'guild','id':gi,'name':payload['guilds'][gi],'current':sum(x['current'] for x in rows),'baseline':sum(x['baseline'] for x in rows),'delta':sum(x['delta'] for x in rows),'anchors':len(rows)})
guild_expected.sort(key=lambda x:x['delta'])
selected+=guild_expected[:8]+sorted(guild_expected,key=lambda x:x['delta'],reverse=True)[:4]
checks.append({'check':'micro_event_expectations_prepared','passed':len(micro)>0,'anchors':len(micro),'guilds':len(guild_expected),'weeks':[payload['weeks'][base_i],payload['weeks'][cur_i]]})
report={'status':'passed' if all(c['passed'] for c in checks) else 'failed','scope':'export-to-payload; warehouse all-history and visual acceptance remain separate','checks':checks,'engineExpectations':expectations,'microExpectations':selected}
a.output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps({'status':report['status'],'checks':len(checks),'engineExpectations':len(expectations)}));assert report['status']=='passed'
