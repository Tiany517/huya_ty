"""Metric-first analyst views. Supplement inputs are immutable query-result envelopes."""
from __future__ import annotations
import ast
import base64
import csv
import gzip
import io
import json
import re
import statistics
from collections import defaultdict
from datetime import date, timedelta
from pathlib import Path

LABELS = {'dau':'观看 DAU','revenue':'打赏流水（元）','payUsers':'打赏人数','attributionUsers':'归属用户数',
          'liveAnchors':'开播主播数（日均）','interactionUsers':'互动人数（主播UV合计）',
          'newUsers':'拉新人数','returnUsers':'回流人数','newReturnUsers':'拉新回流去重合计',
          'interactionRate':'互动率（待核验）'}
TRIAL_RULES = {'interactionUsers':(.10,50),'newUsers':(.10,50),'returnUsers':(.10,50),'newReturnUsers':(.10,50)}

def read_result(path):
    envelope=json.loads(Path(path).read_text(encoding='utf-8'))
    result=ast.literal_eval(envelope['content'][0]['text'])
    if not result.get('success'): raise ValueError('query failed: '+str(path))
    return list(csv.DictReader(io.StringIO(result['data'].lstrip('\ufeff'))))

def number(v):
    return None if v is None or str(v).lower() in ('null','','none') else float(v)

def signed_contributions(rows):
    denominator=sum(abs(r['delta']) for r in rows)
    for row in rows: row['contribution']=row['delta']/denominator if denominator else 0
    return rows

def ratio_contributions(current, baseline):
    """Exact structural percentage-point bridge, not a normalized change share."""
    c=sum(d for n,d in current); b=sum(d for n,d in baseline)
    if not c or not b: return [None]*len(current)
    return [cn/c-bn/b for (cn,_),(bn,_) in zip(current,baseline)]

def load_supplement(directory):
    if not directory: return {},{},{}
    root=Path(directory)
    acq=read_result(root/'upgrade_result_0.json'); inter=read_result(root/'upgrade_result_1.json')
    events=read_result(root/'upgrade_result_2.json')
    acq_dates=sorted({r['dt'] for r in acq}); inter_dates=sorted({r['dt'] for r in inter})
    if not acq_dates or not inter_dates: raise ValueError('empty supplement source')
    for dates in (acq_dates,inter_dates):
        expected=(date.fromisoformat(dates[-1])-date.fromisoformat(dates[0])).days+1
        if len(dates)!=expected: raise ValueError('missing supplement source dates; do not fill zeros')
    lookup={}
    for row in acq:
        k=(row['dt'],row['gameid'])
        if k in lookup: raise ValueError('duplicate acquisition key')
        v={m:number(row[m]) for m in ('newUsers','returnUsers','newReturnUsers')}
        assert v['newReturnUsers']==v['newUsers']+v['returnUsers']-float(row['intersectionUsers'])
        lookup[k]=v
    seen=set()
    for row in inter:
        k=(row['dt'],row['gameid'])
        if k in seen: raise ValueError('duplicate interaction key')
        seen.add(k)
        lookup.setdefault(k,{}).update({m:number(row[m]) for m in ('interactionUsers','interactionDenominator')})
    registered=defaultdict(set)
    for r in events: registered[r['gameid']].add(r['dt'])
    evidence={'acquisitionRows':len(acq),'interactionRows':len(inter),'registeredEventCategories':len(registered),
              'anchorKeys':sum(int(r['anchorKeys']) for r in inter),
              'matchedAnchorKeys':sum(int(r['matchedAnchorKeys']) for r in inter),
              'numeratorAboveDenominatorKeys':sum(int(r['numeratorAboveDenominatorKeys']) for r in inter),
              'coverageStart':max(acq_dates[0],inter_dates[0]),'coverageEnd':min(acq_dates[-1],inter_dates[-1]),
              'status':'探索补充；互动率未通过语义核验；源表独立复算待执行'}
    independent=root/'upgrade_independent_result.json'
    if independent.exists():
        check=read_result(independent)
        for r in check:
            actual=lookup[(r['dt'],r['gameid'])]
            if any(actual[m]!=number(r[m]) for m in ('newUsers','returnUsers','newReturnUsers')):
                raise ValueError('independent acquisition reconciliation failed')
        evidence['independentAcquisitionSampleKeys']=len(check)
        evidence['status']='探索补充；报告日5品类拉新回流独立复算通过；历史全量及互动率语义尚未通过验收'
    return lookup,registered,evidence

def build_upgrade(data, report_day, by_category, dimensions, classify, supplement_dir=None):
    lookup,events,evidence=load_supplement(supplement_dir)
    meta=data['meta']; cats=meta['categories']; groups=meta['contentGroups']
    # Only confirmed acquisition source partitions may turn missing category records into zero.
    for dt, values in by_category.items():
        for idx,v in values.items():
            gameid=str(cats[idx]['id']); supplement=lookup.get((dt,gameid),{})
            v.update(supplement)
            if supplement_dir and evidence['coverageStart']<=dt<=evidence['coverageEnd']:
                for m in ('newUsers','returnUsers','newReturnUsers'): v.setdefault(m,0.)
    def change(metric,current,hist):
        result=classify(metric,current,hist)
        result['trial']=metric in TRIAL_RULES
        return result
    rows=[]; canvas=[]
    for dt,values in by_category.items():
        for idx,v in values.items():
            canvas.append([dt,idx]+[v.get(m) for m in LABELS if m!='interactionRate'])
    base_days=[(report_day-timedelta(days=7*n)).isoformat() for n in range(1,5)]
    for idx,cur in by_category.get(report_day.isoformat(),{}).items():
        cat=cats[idx]; gameid=str(cat['id']); history=[by_category.get(dt,{}).get(idx,{}) for dt in base_days]
        registered=events.get(gameid)
        event_status='登记赛日' if registered and report_day.isoformat() in registered else '非登记赛日' if registered else '赛事覆盖待核验'
        for metric in LABELS:
            if metric=='interactionRate': continue
            if cur.get(metric) is None or any(h.get(metric) is None for h in history): continue
            row=dict(change(metric,cur[metric],[h[metric] for h in history]),scope='category',
                     name=cat['name'],path=groups[int(cat['group'])],group=groups[int(cat['group'])],
                     category=idx,event=event_status,period=report_day.isoformat()+' vs 前4个同星期中位数',mode='standard')
            rows.append(row)
            # Registered-event exclusion is descriptive. No records != no events.
            if registered and report_day.isoformat() not in registered:
                clean=[]; selected=[]
                for n in range(1,27):
                    dt=(report_day-timedelta(days=7*n)).isoformat()
                    if dt<'2026-05-29': break
                    value=by_category.get(dt,{}).get(idx,{}).get(metric)
                    if dt not in registered and value is not None: clean.append(value);selected.append(dt)
                    if len(clean)==4: break
                if len(clean)==4:
                    rows.append(dict(row,**change(metric,cur[metric],clean),mode='registeredFree',
                                     baselineDates=selected,period=report_day.isoformat()+' vs 前4个非登记赛日同星期中位数'))
    # Weekly candidates: aggregate ALL objects before metric ranking, never reuse DAU Top50.
    columns={k:i for i,k in enumerate(meta['anchorColumns'])}; weeks=meta['weeks']; ci=len(weeks)-1
    agg=defaultdict(lambda:defaultdict(lambda:defaultdict(float))); live={}; tiers={}
    for r in data['anchorWeekly']:
        if int(r[columns['week']])!=ci: continue
        key=(int(r[columns['anchor']]),int(r[columns['category']]),int(r[columns['guild']]))
        acu=r[columns['acuSum']]/r[columns['acuDays']] if r[columns['acuDays']] else 0
        tiers[key]='头部' if acu>=2000 else '腰部' if acu>=100 else '尾部'
    for r in data['anchorWeekly']:
        wi=int(r[columns['week']]); ai=int(r[columns['anchor']]); ca=int(r[columns['category']]); gi=int(r[columns['guild']]); key=(ai,ca,gi)
        if wi<ci-4: continue
        for scope,obj in [('guild',gi),('anchor',key),('tier',tiers.get(key,'历史退出主播'))]:
            target=agg[(scope,obj)][wi]
            for metric in ('dau','revenue','payUsers','attributionUsers','interactionUsers'):
                target[metric]+=float(r[columns[metric]] or 0)/7
            # Unique anchor per object; guild overlap across category uses max, as source contract.
            lk=(scope,obj,wi,ai)
            live[lk]=max(live.get(lk,0),float(r[columns['liveDays']] or 0)/7)
    for (scope,obj,wi,ai),v in live.items(): agg[(scope,obj)][wi]['liveAnchors']+=v
    for (scope,obj),values in agg.items():
        if ci not in values or ci-1 not in values: continue # absent != zero
        if scope=='anchor':
            ai,ca,gi=obj; a=meta['anchors'][ai]; name=a['name']; path=f"UID {a['id']} · 房间 {a.get('roomid','')} · {cats[ca]['name']} · {meta['guilds'][gi]}"
        else: name=meta['guilds'][obj] if scope=='guild' else obj;path='全品类 / '+scope
        for metric in ('dau','revenue','payUsers','attributionUsers','interactionUsers','liveAnchors'):
            cur=values[ci][metric];prev=values[ci-1][metric]; hist=[values[w][metric] for w in range(ci-4,ci) if w in values]
            result=change(metric,cur,hist) if len(hist)==4 else {'severity':'待核验','robustZ':None,'confidence':'low'}
            rows.append(dict(result,scope=scope,metric=metric,name=name,path=path,group='',event='周榜未剔除赛事',mode='standard',
                             current=cur,baseline=prev,delta=cur-prev,changePct=(cur-prev)/prev if prev else None,
                             period=weeks[ci]+' vs '+weeks[ci-1]+'（日均）；级别对自身前4周',severityBaseline=statistics.median(hist) if len(hist)==4 else None))
    for scope in ('category','guild','anchor','tier'):
        for mode in ('standard','registeredFree'):
            for m in LABELS: signed_contributions([r for r in rows if r['scope']==scope and r['metric']==m and r['mode']==mode])
    findings=[]
    # Surface quantity/revenue divergence outside the copyright-covered pool too,
    # but label event coverage unknown rather than declaring it non-tournament.
    daily_pairs={}
    for r in rows:
        if r['scope']=='category' and r['mode']=='standard': daily_pairs.setdefault(r['category'],{})[r['metric']]=r
    divergences=[]
    for idx,metrics in daily_pairs.items():
        a=metrics.get('dau'); b=metrics.get('revenue'); supply=metrics.get('liveAnchors')
        if not a or not b or '娱乐' not in a['group']: continue
        if a['delta']*b['delta']<0 and abs(b['delta'])>=5000 and a['current']>=1000:
            divergences.append((abs(b['delta']),a,b,supply))
    for _,a,b,supply in sorted(divergences,key=lambda x:x[0],reverse=True)[:2]:
        text=f"量收背离：DAU变化{a['changePct']:.1%}，流水变化{b['changePct']:.1%}。"
        if supply and supply['changePct'] is not None: text+=f"开播主播数变化{supply['changePct']:.1%}。"
        text+='需查付费用户与ARPPU结构；赛事覆盖尚未核验，不能认定已排除赛事。'
        findings.append(dict(name=b['name'],metric=LABELS['revenue'],current=b['current'],baseline=b['baseline'],changePct=b['changePct'],text=text,baselineDates=base_days))
    for metric in ('dau','revenue','newReturnUsers','interactionUsers'):
        candidates=sorted([r for r in rows if r['scope']=='category' and r['mode']=='registeredFree' and r['metric']==metric and r['delta']<0 and r['severity']!='正常'],key=lambda r:r['delta'])
        if candidates:
            r=candidates[0]; findings.append({'name':r['name'],'metric':LABELS[metric],'current':r['current'],'baseline':r['baseline'],
                'changePct':r['changePct'],'text':'排除版权登记赛日后仍下降；尚不能排除赛后回落、休赛日和其他活动影响。','baselineDates':r['baselineDates']})
    return {'rows':rows,'canvas':canvas,'canvasMetrics':[m for m in LABELS if m!='interactionRate'],
            'categories':cats,'labels':LABELS,'findings':findings,'evidence':evidence}

def render_upgrade(payload):
    packed=base64.b64encode(gzip.compress(json.dumps(payload,ensure_ascii=False,separators=(',',':')).encode())).decode()
    assets=Path(__file__).resolve().parent.parent/'assets'
    return '<style>'+ (assets/'analyst_upgrade.css').read_text(encoding='utf-8')+'</style>'+'''
<section id="focusFindings"><div class="section-head"><div><h2>赛事之外，哪些异动还在？</h2><p>先看量收背离，再看剔除登记赛日后的异常；补充指标为探索数据，独立源复算及视觉验收尚未全部完成。</p></div></div><div id="focusCards" class="focus-cards"></div></section>
<section id="metricRankings"><div class="section-head"><div><h2>异动榜单</h2><p id="rankingPeriod"></p></div></div><div class="section-body">
<div class="compact-controls"><label>对象<select id="rankScope"><option value="category">品类</option><option value="guild">公会</option><option value="anchor">主播</option><option value="tier">主播层级</option></select></label>
<label>指标<select id="rankMetric"></select></label><label>赛事对照<select id="rankMode"><option value="standard">常规基线</option><option value="registeredFree">剔除登记赛日对照</option></select></label>
<label>搜索<input id="rankSearch" type="search" placeholder="名称、UID、房间、公会"></label><label>大类<select id="rankGroup"><option value="">全部</option></select></label>
<label>级别<select id="rankLevel"><option value="">全部</option><option>高</option><option>中</option><option>低</option><option>正常</option><option>待核验</option></select></label>
<label>排序<select id="rankSort"><option value="absolute">变化绝对值</option><option value="delta">变化值</option><option value="changePct">变化率</option><option value="current">本期值</option><option value="contribution">贡献占比</option><option value="robustZ">异常分</option><option value="name">名称</option></select></label>
<label>方向<select id="rankDirection"><option value="desc">降序</option><option value="asc">升序</option></select></label><label>Top N<input id="rankLimit" type="number" min="1" max="200" value="10"></label></div>
<p id="rankCoverage" class="small-note"></p><div class="table-scroll"><table><thead><tr><th>对象 / 路径</th><th data-sort="current">本期值 ↕</th><th data-sort="baseline">对比值 ↕</th><th data-sort="delta">变化值 ↕</th><th data-sort="changePct">变化率 ↕</th><th data-sort="contribution">变化贡献占比 ↕</th><th>级别</th></tr></thead><tbody id="metricRows"></tbody></table></div>
<p class="small-note">贡献占比＝对象变化值÷该层级、该指标全部可比对象变化绝对值之和；筛选和Top N不改变分母，绝对占比合计100%，不是对平台净变化的因果贡献。日榜级别对前4个同星期；周榜变化对上周、级别对自身前4周，基线不同已分别标注。新补互动/拉新/回流指标暂用10%变化线、最小绝对变化50，沿用异常分判级，属于待回测试行阈值。缺期不补零，缺4期历史则待核验。主播层级固定按当前周ACU：头部≥2000、腰部100–1999、尾部&lt;100；历史退出主播单列。</p></div></section>
<section id="additionalCanvas"><div class="section-head"><div><h2>用户与互动分析画布</h2><p>补充流水、互动、拉新和回流；按可用日期聚合，未覆盖日期不补零。</p></div></div><div class="section-body"><div class="compact-controls"><label>指标<select id="extraMetric"></select></label><label>品类搜索<input id="extraSearch" type="search" placeholder="模糊搜索品类"></label><label>对比品类<select id="extraCategories" multiple size="3" aria-label="对比品类（可多选）"></select></label><label>粒度<select id="extraGrain"><option value="day">日</option><option value="week">周</option><option value="month">月</option><option value="quarter">季度</option></select></label><label>开始<input id="extraStart" type="date"></label><label>结束<input id="extraEnd" type="date"></label><label>图形<select id="extraType"><option value="line">折线</option><option value="bar">并列柱状</option><option value="stack">100%堆积</option></select></label></div><p id="extraNote" class="small-note"></p><div id="extraChart"></div><div id="extraLegend" class="small-note"></div></div></section>
<script type="text/plain" id="analyst-upgrade-data">'''+packed+'</script><script>'+ (assets/'analyst_upgrade.js').read_text(encoding='utf-8')+'</script>'

def apply_upgrade(html_text,payload):
    # Keep the previous views inert for recovery; visible ranking uses full metric candidates.
    for identifier in ('analystWorkbench','categoryTopTitle','guildTopTitle','anchorTopTitle'):
        pattern=r'<section\b[^>]*>(?:(?!<section\b).)*?id="'+identifier+r'"(?:(?!</section>).)*?</section>'
        if identifier=='analystWorkbench': pattern=r'<section id="analystWorkbench">.*?</section><script>.*?</script>'
        html_text=re.sub(pattern,lambda m:'<template class="legacy-view">'+m.group(0)+'</template>',html_text,flags=re.S)
    html_text=re.sub(r'<section><div class="section-head"><div><h2>主播层级</h2>.*?</section>',lambda m:'<template>'+m.group(0)+'</template>',html_text,flags=re.S)
    html_text=html_text.replace('<div class="grid-two">\n    <section><div class="section-head"><h2>今日结论', '<details class="legacy-summary"><summary>平台概览与原始预警</summary><div class="grid-two">\n    <section><div class="section-head"><h2>今日结论',1)
    html_text=html_text.replace('  <section class="visualization-space"', '</details>\n  <section class="visualization-space"',1)
    upgrade=render_upgrade(payload)
    html_text=html_text.replace('<div class="kpis">',upgrade+'<div class="kpis">',1)
    return html_text
