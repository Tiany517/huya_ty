"""Build V1.2 daily UI from immutable source exports; validation status is explicit."""
from __future__ import annotations
import argparse,base64,gzip,json,hashlib,csv,statistics,html
from collections import defaultdict
from pathlib import Path
from datetime import date,datetime,timedelta,timezone
from analyst_upgrade import load_supplement,read_result
from build_daily_alert_report import build_daily_series,load_platform_daily,classify_change

def load_major_event_days(path,meta_path=None):
    """Load selected major-event days and preserve event-selection provenance."""
    with Path(path).open(encoding='utf-8-sig',newline='') as handle:
        rows=list(csv.DictReader(handle))
    if not rows: raise ValueError('empty major event-day source')
    required={'dt','gameid','match_id','match_name'}
    if required-set(rows[0]): raise ValueError('major event-day source missing required columns')
    selected=defaultdict(set);matches=defaultdict(dict);meta={};seen=set()
    for row in rows:
        gameid=str(row['gameid']).strip();match_id=str(row['match_id']).strip();dt=str(row['dt']).strip();key=(dt,gameid,match_id)
        if key in seen: raise ValueError('duplicate major event-day key')
        seen.add(key);selected[gameid].add(dt)
        matches[gameid][match_id]=str(row['match_name']).strip()
    manifest={}
    if meta_path:
        manifest=json.loads(Path(meta_path).read_text(encoding='utf-8-sig'))
        rule=manifest.get('rule') or '按单赛事周期识别并剔除异常低规模赛事'
        categories=manifest.get('categories',{})
    else:
        rule='按单赛事周期识别并剔除异常低规模赛事'
        categories={}
    for gameid,days in selected.items():
        source=categories.get(gameid,{})
        selected_events=[{'matchId':match_id,'matchName':name} for match_id,name in sorted(matches[gameid].items())]
        meta[gameid]={'eventDayCount':len(days),'selectedDayCount':len(days),'rule':rule,'snapshot':str(path),
                      'selectedEvents':source.get('selectedEvents',selected_events),
                      'excludedLowEvents':source.get('excludedLowEvents',[]),
                      'selectionThreshold':source.get('selectionThreshold')}
    return {k:sorted(v) for k,v in selected.items()},meta

def build_payload(data,platform,supplement,report_day,event_days_path=None,event_meta_path=None):
    _,by_category,_,_=build_daily_series(data);lookup,events,evidence=load_supplement(supplement)
    registered={k:sorted(v) for k,v in events.items()}
    event_days,event_meta=(load_major_event_days(event_days_path,event_meta_path) if event_days_path else (registered,{k:{'eventDayCount':len(v),'selectedDayCount':len(v),'rule':'未提供大赛事日源，回退全部登记日','snapshot':None} for k,v in registered.items()}))
    if event_days_path:
        evidence['eventSource']=str(event_days_path)
        evidence['eventRule']='按单赛事周期识别；剔除低于品类最大赛事日均5%的赛事；赛事数不少于4时叠加log日均Tukey下限；只剔除入选赛事的版权登记日'
        evidence['eventMetaSource']=str(event_meta_path) if event_meta_path else None
    meta=data['meta'];date_values=sorted(by_category);date_index={d:i for i,d in enumerate(date_values)}
    fields=['dau','revenue','payUsers','attributionUsers','liveAnchors','interactionUsers','newUsers','returnUsers','newReturnUsers','interactionCount','viewMinutes']
    raw_cols={k:i for i,k in enumerate(meta['categoryColumns'])};raw_lookup={(r[0],int(r[1])):r for r in data['categoryDaily']}
    category_rows=[]
    platform_live={}
    for dt,cats in sorted(by_category.items()):
        for idx,v in cats.items():
            v=dict(v);v.update(lookup.get((dt,str(meta['categories'][idx]['id'])),{}))
            raw=raw_lookup[(dt,idx)];v['viewMinutes']=raw[raw_cols['viewMinutes']]
            platform_live[dt]=max(platform_live.get(dt,0),raw[raw_cols['totalLiveAnchors']])
            category_rows.append([date_index[dt],idx]+[v.get(m) for m in fields])
    global_acq=[]
    if supplement and (Path(supplement)/'v12_platform_acquisition_retry.json').exists():
        for r in read_result(Path(supplement)/'v12_platform_acquisition_retry.json'):
            values={m:float(r[m]) for m in ['newUsers','returnUsers','newReturnUsers']}
            assert values['newReturnUsers']==values['newUsers']+values['returnUsers']-float(r['intersectionUsers'])
            global_acq.append([r['dt'],values['newUsers'],values['returnUsers'],values['newReturnUsers']])
    if supplement and (Path(supplement)/'v12_platform_independent.json').exists():
        independent=read_result(Path(supplement)/'v12_platform_independent.json')
        actual={r[0]:r for r in global_acq}
        assert len(independent)==len(global_acq)>0
        for r in independent:
            assert [float(r[m]) for m in ['newUsers','returnUsers','newReturnUsers']]==actual[r['dt']][1:]
        evidence['platformAcquisitionIndependentDates']=len(independent)
    return {'version':'1.2','reportDate':report_day,'dates':date_values,'categories':meta['categories'],'groups':meta['contentGroups'],
            'guilds':meta['guilds'],'anchors':meta['anchors'],'weeks':meta['weeks'],'weekRanges':meta['weekRanges'],
            'categoryMetrics':fields,'categoryRows':category_rows,'anchorDailyColumns':meta['anchorDailyColumns'],
            'anchorColumns':meta['anchorColumns'],'anchorDaily':data['anchorDaily'],'anchorWeekly':data['anchorWeekly'],
            'platform':sorted(platform.items()),'platformLive':sorted(platform_live.items()),'platformAcquisition':global_acq,'eventDays':event_days,'registeredEventDays':registered,'eventMeta':event_meta,
            'evidence':evidence,'sourceLatestPartition':meta.get('sourceLatestPartition'),'ratingVersion':'试行混合规则 v20261125',
            'limitations':['互动率分子/分母语义未通过，暂不可计算正式比率。','日级主播表只有专项历史覆盖；搜索索引覆盖全部已有周表主播，不代表全部都有日历史。',
               '公会、层级、交叉维度只有完整周数据；日级主播记录不带日级公会路径，不能用最新公会替代历史日维度。',
               '公会开播主播数沿用周路径内同主播最大开播天数，跨品类换播可能低估，尚非精确主播日并集；供给结论待复算。',
               '拉新/回流来自上游四端归因，不含鸿蒙；不能除以含鸿蒙平台DAU作为转化率。',
               '赛事剔除按单赛事周期的日均DAU识别大赛事，并剔除品类相对下限以下的异常低赛事；未覆盖赛事记录的品类不能等同于无赛事，赛事覆盖未知时评级待判断。',
               '旧混合评级未定义低等级，低对象计数为0。未正式校准；比率和新增过程指标等级待判断。']}

def backtest(payload):
    fields=payload['categoryMetrics'];metrics=['dau','revenue','payUsers','liveAnchors','attributionUsers','newUsers','returnUsers','newReturnUsers','interactionUsers']
    lookup={(payload['dates'][r[0]],r[1]):r for r in payload['categoryRows']};summary={};examples=[]
    for metric in metrics:
        column=fields.index(metric)+2;values=[];counts={};pairs={}
        # Most recent 56 report dates with four observed previous weekdays; no padding.
        for (dt,idx),r in lookup.items():
            if dt<str(date.fromisoformat(payload['reportDate'])-timedelta(days=55)) or r[column] is None:continue
            baseline=[lookup.get((str(date.fromisoformat(dt)-timedelta(days=7*n)),idx)) for n in range(1,5)]
            if any(v is None or v[column] is None for v in baseline):continue
            c=classify_change(metric,r[column],[v[column] for v in baseline]);z=abs(c['robustZ']);values.append(z);counts[c['severity']]=counts.get(c['severity'],0)+1
            proposed='高' if z>=3 else '中' if z>=2 else '低' if z>=1 else '正常';k=c['severity']+' / '+proposed;pairs[k]=pairs.get(k,0)+1
            if len(examples)<20 and c['severity']!=proposed and r[column]>1000:examples.append({'date':dt,'category':payload['categories'][idx]['name'],'metric':metric,'current':r[column],'old':c['severity'],'candidate':proposed,'score':c['robustZ']})
        values.sort();n=len(values);q=lambda p:values[min(n-1,int((n-1)*p))] if n else None
        summary[metric]={'observations':n,'oldCounts':counts,'absoluteZQuantiles':{'p50':q(.5),'p90':q(.9),'p95':q(.95),'p99':q(.99)},'candidateCounts':{'高':sum(v>=3 for v in values),'中':sum(2<=v<3 for v in values),'低':sum(1<=v<2 for v in values),'正常':sum(v<1 for v in values)},'oldCandidateCross':pairs}
    return {'status':'探索回测已运行，未校准验收','window':'最近56个日历日，合格品类日','candidate':'|robustZ|: 高≥3、中[2,3)、低[1,2)、正常<1；只提案，未应用',
            'warning':'这是历史报警率与旧规则分歧评估，不是真实异常标签的准确率；尚需人工案例核验、赛事分层和低基数敏感性。排查优先级不得用来替代该候选等级。', 'metrics':summary,'caseReviewCandidates':examples}

def main():
    p=argparse.ArgumentParser();p.add_argument('--data',type=Path,required=True);p.add_argument('--platform',type=Path,required=True);p.add_argument('--supplement',type=Path);p.add_argument('--event-days',type=Path);p.add_argument('--event-meta',type=Path);p.add_argument('--event-top',type=Path,help='deprecated alias for --event-days');p.add_argument('--output',type=Path,required=True);p.add_argument('--report-date');a=p.parse_args()
    if a.output.exists():raise SystemExit('use a new output directory; no source overwrite')
    if a.event_days and a.event_top:raise SystemExit('use --event-days instead of deprecated --event-top')
    if a.event_meta and not (a.event_days or a.event_top):raise SystemExit('--event-meta requires --event-days')
    event_days=a.event_days or a.event_top;event_meta=a.event_meta if a.event_days else None
    data=json.loads(a.data.read_text(encoding='utf-8'));report=a.report_date or max(r[0] for r in data['categoryDaily']);payload=build_payload(data,load_platform_daily(a.platform),a.supplement,report,event_days,event_meta)
    assets=Path(__file__).resolve().parent.parent/'assets';template=(assets/'daily_v12.html').read_text(encoding='utf-8')
    engine=(assets/'daily_v12_engine.mjs').read_text(encoding='utf-8').replace('export ','');filters=(assets/'anomaly_filters.mjs').read_text(encoding='utf-8').replace('export ','');controller=(assets/'daily_v12.js').read_text(encoding='utf-8')
    encoded=base64.b64encode(gzip.compress(json.dumps(payload,ensure_ascii=False,separators=(',',':'),allow_nan=False).encode())).decode()
    result=template.replace('__CSS__',(assets/'daily_v12.css').read_text(encoding='utf-8')).replace('__PAYLOAD__',encoded).replace('__ENGINE__',engine).replace('__FILTERS__',filters).replace('__APP__',controller)
    a.output.mkdir(parents=True);target=a.output/'生态异动日报_V1.2.html';target.write_text(result,encoding='utf-8')
    bt=backtest(payload);(a.output/'评级历史回测_候选未上线.json').write_text(json.dumps(bt,ensure_ascii=False,indent=2),encoding='utf-8')
    text=['# 试行混合规则与异常分候选回测','',bt['warning'],'',bt['candidate'],'','| 指标 | 合格观测 | 旧高 | 候选高 | 绝对分P95 |','|---|---:|---:|---:|---:|']
    for m,s in bt['metrics'].items():text.append(f"|{m}|{s['observations']}|{s['oldCounts'].get('高',0)}|{s['candidateCounts']['高']}|{s['absoluteZQuantiles']['p95']}|")
    (a.output/'评级历史回测_候选未上线.md').write_text('\n'.join(text),encoding='utf-8')
    manifest={'version':'1.2','reportDate':report,'status':'交互待验收；数据与评级部分待验证','htmlBytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),
              'data':{'path':str(a.data),'sha256':hashlib.sha256(a.data.read_bytes()).hexdigest()},'platform':str(a.platform),'eventDays':({'path':str(event_days),'sha256':hashlib.sha256(event_days.read_bytes()).hexdigest()} if event_days else None),'eventMeta':({'path':str(event_meta),'sha256':hashlib.sha256(event_meta.read_bytes()).hexdigest()} if event_meta else None),'counts':{k:len(payload[k]) for k in ['categoryRows','anchorWeekly','anchorDaily','anchors','platformAcquisition']},'limitations':payload['limitations'],'supplementEvidence':payload['evidence'],
              'supplementInputs':[{'name':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(a.supplement.glob('*.json')) if p.name.startswith(('upgrade_result_','upgrade_independent','v12_platform'))] if a.supplement else []}
    (a.output/'V1.2_运行清单.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(manifest,ensure_ascii=False))

if __name__=='__main__':main()
