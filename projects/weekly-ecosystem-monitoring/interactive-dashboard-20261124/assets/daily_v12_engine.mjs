/** V1.2 pure analysis functions. Display filters live in anomaly_filters.mjs. */
export const metrics={
 dau:{label:'观看DAU',unit:'人/日',agg:'mean',pct:.05,min:5000},
 revenue:{label:'打赏流水',unit:'元',agg:'sum',pct:.10,min:5000},
 payUsers:{label:'付费人数',unit:'用户日',agg:'sum',pct:.10,min:50},
 liveAnchors:{label:'开播主播数',unit:'人/日',agg:'mean',pct:.10,min:10},
 attributionUsers:{label:'归属人数',unit:'用户日',agg:'sum',pct:.05,min:5000},
 interactionUsers:{label:'互动人数（主播UV合计）',unit:'用户日，可重叠',agg:'sum',pct:.10,min:50},
 interactionCount:{label:'互动次数',unit:'次',agg:'sum',pending:true},
 newUsers:{label:'拉新人数',unit:'用户日，不含鸿蒙',agg:'sum',pct:.10,min:50},
 returnUsers:{label:'回流人数',unit:'用户日，不含鸿蒙',agg:'sum',pct:.10,min:50},
 newReturnUsers:{label:'拉新回流并集',unit:'用户日，不含鸿蒙',agg:'sum',pct:.10,min:50},
 payRate:{label:'打赏率',unit:'%',ratio:['payUsers','dau'],pending:true},
 arppu:{label:'ARPPU',unit:'元/付费用户日',ratio:['revenue','payUsers'],pending:true},
 attributionRate:{label:'主播归属率（用户日）',unit:'%',ratio:['attributionUsers','dau'],pending:true},
 interactionRate:{label:'互动率（分母语义待核验）',unit:'%',ratio:['interactionUsers','dau'],blocked:true},
 interactionsPerUser:{label:'人均互动次数',unit:'次/互动用户日',ratio:['interactionCount','interactionUsers'],pending:true},
 viewMinutes:{label:'人均观时',unit:'分钟',agg:'weighted',pending:true},
 acu:{label:'平均ACU',unit:'人',agg:'weighted',pending:true},
 liveHours:{label:'开播时长',unit:'小时',agg:'sum',blocked:true}
};
export const dims={group:'内容大类',category:'品类',guild:'公会',tier:'主播层级',anchor:'主播',event:'赛事剔除属性'};
export const median=a=>{if(!a.length)return null;const s=[...a].sort((x,y)=>x-y),i=Math.floor(s.length/2);return s.length%2?s[i]:(s[i-1]+s[i])/2};
export const shift=(d,n)=>{const t=new Date(d+'T00:00:00Z');t.setUTCDate(t.getUTCDate()+n);return t.toISOString().slice(0,10)};
export function days(start,end){if(!start||!end||start>end)return [];const a=[];for(let d=start;d<=end;d=shift(d,1)){a.push(d);if(a.length>3700)throw Error('时间范围过大')}return a}
export function bucket(d,grain){if(grain==='day')return d;if(grain==='month')return d.slice(0,7);if(grain==='quarter')return d.slice(0,4)+'Q'+Math.ceil(+d.slice(5,7)/3);const t=new Date(d+'T00:00:00Z');return shift(d,-(t.getUTCDay()+6)%7)}
export function completeBucket(start,end,grain){if(grain==='day')return true;if(grain==='week')return new Date(start+'T00:00:00Z').getUTCDay()===1&&days(start,end).length%7===0&&new Date(end+'T00:00:00Z').getUTCDay()===0;if(grain==='month')return start.endsWith('-01')&&shift(end,1).endsWith('-01');if(grain==='quarter')return start.endsWith('-01')&&[1,4,7,10].includes(+start.slice(5,7))&&shift(end,1).endsWith('-01')&&[1,4,7,10].includes(+shift(end,1).slice(5,7));return false}
export function classify(metric,current,history){
 const m=metrics[metric];const unavailable={severity:'待判断',robustZ:null,historyCount:history.filter(v=>v!=null).length,rule:'试行混合规则；历史或口径不足'};
 if(current==null||history.length!==4||history.some(v=>v==null)||!m||m.pending||m.blocked)return unavailable;
 const baseline=median(history),variance=history.reduce((s,v)=>s+(v-history.reduce((a,b)=>a+b,0)/4)**2,0)/4;
 const scale=1.4826*median(history.map(v=>Math.abs(v-baseline)))||Math.sqrt(variance)||Math.max(Math.abs(baseline)*.02,1);
 const z=(current-baseline)/scale,delta=current-baseline,pct=baseline?delta/baseline:null;
 const cv=baseline?Math.sqrt(variance)/Math.abs(baseline):history.some(v=>v!==0)?Infinity:0;
 let severity='正常';if(Math.abs(delta)>=m.min){if(pct==null)severity='高';else if(Math.abs(pct)>=m.pct*3||(Math.abs(pct)>=m.pct*1.5&&Math.abs(z)>=3))severity='高';else if(Math.abs(pct)>=m.pct||Math.abs(z)>=2.5)severity='中'}
 if(cv>.3&&severity==='高')severity='中';
 return {severity,robustZ:z,ratingBaseline:baseline,historyCount:4,history,confidence:cv>.3?'偏低':cv>.15?'一般':'较高',rule:'试行混合规则 v20261125：绝对门槛＋变化率＋异常分＋可信度；未正式校准，低等级尚未定义'};
}
export function contributions(rows,metric){
 if(metrics[metric]?.ratio){const qualified=rows.filter(r=>r.currentParts&&r.baselineParts),c=qualified.reduce((s,r)=>s+r.currentParts[1],0),b=qualified.reduce((s,r)=>s+r.baselineParts[1],0);return rows.map(r=>({...r,contribution:c&&b&&r.currentParts&&r.baselineParts?r.currentParts[0]/c-r.baselineParts[0]/b:null,contributionKind:metrics[metric].unit==='%'?'结构百分点':'结构比率差'}))}
 const denominator=rows.reduce((s,r)=>s+(r.delta==null?0:Math.abs(r.delta)),0);
 return rows.map(r=>({...r,contribution:denominator&&r.delta!=null?r.delta/denominator:null,contributionDenominator:denominator,contributionKind:'带方向变化占比'}));
}
export function shapley(before,after){
 if(before.length!==3||after.length!==3||[...before,...after].some(v=>!Number.isFinite(v)||v<=0))return null;
 const orders=[[0,1,2],[0,2,1],[1,0,2],[1,2,0],[2,0,1],[2,1,0]],effect=[0,0,0],product=a=>a.reduce((a,b)=>a*b,1);
 for(const order of orders){const a=[...before];for(const i of order){const prev=product(a);a[i]=after[i];effect[i]+=(product(a)-prev)/6}}
 return {effects:effect,delta:product(after)-product(before),residual:effect.reduce((a,b)=>a+b,0)-(product(after)-product(before))};
}
export function symmetric(beforeRevenue,afterRevenue,beforePay,afterPay){if(!(beforePay>0&&afterPay>0))return null;const a=beforeRevenue/beforePay,b=afterRevenue/afterPay;return {pay:(afterPay-beforePay)*(a+b)/2,arppu:(b-a)*(afterPay+beforePay)/2}}
export function priority(row){const z=row.robustZ==null?0:Math.min(Math.abs(row.robustZ)/5,1),impact=Math.min(Math.abs(row.contribution||0)*5,1),scale=Math.log10(1+Math.max(row.current||0,row.baseline||0))/7;return .4*z+.4*impact+.2*Math.min(scale,1)}
export function fixedTier(acu){return acu==null?'未知':acu>=2000?'头部':acu>=100?'腰部':'尾部'}
export function ratioIssue(values,metric){if(metric==='payRate'&&values.payUsers!=null&&values.dau!=null&&(values.payUsers<0||values.dau<0||values.payUsers>values.dau))return '分子分母不一致：付费用户日超过观看用户日或出现负值；待源表核验';return null}
export function valueFor(values,metric){const m=metrics[metric];if(!m||m.blocked||ratioIssue(values,metric))return null;if(m.ratio){const [n,d]=m.ratio,value=values[n]!=null&&values[d]>0?values[n]/values[d]:null;return value!=null&&Number.isFinite(Number(value))?Number(value):null}const value=values[metric];return value!=null&&Number.isFinite(Number(value))?Number(value):null}
export function createEngine(data){
 const dates=data.dates,catCols=data.categoryMetrics,dc=data.anchorDailyColumns,wc=data.anchorColumns;
 const catMap=new Map(),dailyByAnchor=new Map(),weekly=[],catByDate=new Map(),weeklyByDate=new Map();
 const anchorPaths=new Map(),weeklyPathByWeekAnchor=new Map();for(const row of data.anchorWeekly){const w=row[0],ca=row[1],g=row[2],guild=row[3],anchor=row[4],acu=row[10]?row[9]/row[10]:null,liveDays=Number(row[16]);const r={date:data.weekRanges[data.weeks[w]].start,end:data.weekRanges[data.weeks[w]].end,week:w,category:ca,group:g,guild,anchor,tier:fixedTier(acu),values:{dau:row[5],revenue:row[6],payUsers:row[7],attributionUsers:row[13],interactionCount:row[14],interactionUsers:row[15],liveAnchors:Number.isFinite(liveDays)?liveDays/7:null,acu,viewMinutes:row[12]?row[11]/row[12]:null},row};weekly.push(r);const old=anchorPaths.get(anchor);if(!old||old.week<w)anchorPaths.set(anchor,r);const pathKey=w+'|'+anchor,pathOld=weeklyPathByWeekAnchor.get(pathKey),pathValue=Number.isFinite(Number(r.values.dau))?Number(r.values.dau):null;if(!pathOld||(pathValue!=null&&(pathOld.value==null||pathValue>pathOld.value)))weeklyPathByWeekAnchor.set(pathKey,{...r,value:pathValue})}
 for(const r of data.categoryRows){const values=Object.fromEntries(catCols.map((m,i)=>[m,r[i+2]])),cat=data.categories[r[1]],row={date:dates[r[0]],category:r[1],group:Number(cat.group),values};catMap.set(row.date+'|'+row.category,row)}
 const catRows=[...catMap.values()];
 for(const row of catRows){if(!catByDate.has(row.date))catByDate.set(row.date,[]);catByDate.get(row.date).push(row)}
 for(const row of weekly){if(!weeklyByDate.has(row.date))weeklyByDate.set(row.date,[]);weeklyByDate.get(row.date).push(row)}
 // Freeze the baseline cohort for tier comparison; migration is reported separately.
 const tierReference=data.weeks.length-2,tierAnchors=new Map();
 for(const r of weekly)if(r.week===tierReference){const a=tierAnchors.get(r.anchor)||{sum:0,days:0};a.sum+=r.row[9];a.days+=r.row[10];tierAnchors.set(r.anchor,a)}
 const fixedTiers=new Map([...tierAnchors].map(([a,v])=>[a,fixedTier(v.days?v.sum/v.days:null)]));
 for(const r of weekly){r.observedTier=r.tier;r.tier=fixedTiers.get(r.anchor)||'非基期主播（新增/历史记录）'}
 const dailyColumns=Object.fromEntries(dc.map((k,n)=>[k,n]));
 for(const raw of data.anchorDaily){const anchor=raw[dailyColumns.anchor];if(!dailyByAnchor.has(anchor))dailyByAnchor.set(anchor,[]);dailyByAnchor.get(anchor).push(raw)}
 function dailyObject(raw){const values={};for(const m of ['dau','revenue','payUsers','attributionUsers','interactionCount','interactionUsers','viewMinutes'])values[m]=raw[dailyColumns[m]]??null;values.liveAnchors=raw[dailyColumns.isLive];return {date:raw[dailyColumns.date],anchor:raw[dailyColumns.anchor],values}}
 const spanCache=new Map();const span=(start,end)=>{const key=start+'|'+end;if(!spanCache.has(key))spanCache.set(key,days(start,end));return spanCache.get(key)};
 const eventDays=new Map(Object.entries(data.eventDays||{}).map(([k,v])=>[k,new Set(v)]));
 const eventKey=category=>String(data.categories[category]?.id??category);
 function eventCoverage(category){return eventDays.has(eventKey(category))?'covered':'unknown'}
 function eventDaysFor(category,start,end){const set=eventDays.get(eventKey(category));return set?span(start,end).filter(d=>set.has(d)):null}
 const unionCache=new Map();function eventUnion(start,end){const key=start+'|'+end;if(!unionCache.has(key)){const set=new Set();for(const days of eventDays.values())for(const d of days)if(d>=start&&d<=end)set.add(d);unionCache.set(key,set)}return unionCache.get(key)}
 function eventOf(row){const set=eventDays.get(eventKey(row.category));if(!set)return '赛事覆盖未知';if(set.has(row.date))return '大赛事日';return '非赛事日'}
 function label(dim,id){if(dim==='category')return data.categories[id]?.name||'未知';if(dim==='group')return data.groups[id]||'未知';if(dim==='guild')return data.guilds[id]||'无公会';if(dim==='anchor')return data.anchors[id]?.name||'未知';return String(id)}
  function baseRows(scope,start,end,paths=[],options={}){const eventMode=options.eventMode||'all',anchorNeeded=paths.some(p=>['guild','tier','anchor'].includes(p.dim))||['guild','tier','anchor','categoryGuild','categoryTier'].includes(scope);let kind=anchorNeeded?'weekly':'daily',source=anchorNeeded?weekly:catRows;
  const weeklyAligned=data.weeks.filter(w=>data.weekRanges[w].start>=start&&data.weekRanges[w].end<=end);
  if(anchorNeeded&&(weeklyAligned.length===0||data.weekRanges[weeklyAligned[0]].start!==start||data.weekRanges[weeklyAligned.at(-1)].end!==end))return {rows:[],kind,unsupported:'此层级仅有完整周路径数据，请选择完整自然周；不会将周数据伪装成日级。'};
   if(eventMode==='nonEvent'&&anchorNeeded)return {rows:[],kind,unsupported:'赛事日只能从品类日级数据精确剔除；公会、层级和主播当前只有完整周聚合，不能伪装成日级赛事校准。'};
   let rows=anchorNeeded?[...weeklyByDate].filter(([dt])=>dt>=start&&dt<=end).flatMap(([,r])=>r):span(start,end).flatMap(dt=>catByDate.get(dt)||[]);rows=rows.filter(r=>(r.end||r.date)<=end);for(const p of paths)rows=rows.filter(r=>String(p.dim==='event'?eventOf(r):r[p.dim])===String(p.value));
   if(kind==='weekly'&&(scope==='event'||paths.some(p=>p.dim==='event')))return {rows:[],kind,unsupported:'赛事属性为日级映射，不能把整周按周一的赛事状态分类。请使用日级品类分析。'};
   if(eventMode==='nonEvent')rows=rows.filter(r=>{const set=eventDays.get(eventKey(r.category));return !(set&&set.has(r.date))});
  return {rows,kind};}
 const aggregateCache=new Map();
  function aggregate(scope,metric,start,end,paths=[],options={}){const eventMode=options.eventMode||'all',cacheKey=JSON.stringify([scope,metric,start,end,paths,eventMode]);if(aggregateCache.has(cacheKey))return aggregateCache.get(cacheKey);const {rows,kind,unsupported}=baseRows(scope,start,end,paths,{eventMode});if(unsupported)return {rows:[],kind,unsupported};const m=metrics[metric];const groups=new Map(),allDates=span(start,end),unionExcluded=eventMode==='nonEvent'?eventUnion(start,end):new Set();
  for(const r of rows){let key=scope==='total'?'total':scope==='categoryGuild'?r.category+'|'+r.guild:scope==='categoryTier'?r.category+'|'+r.tier:scope==='event'?eventOf(r):r[scope];if(key==null)continue;let a=groups.get(key);if(!a){a={id:key,name:scope==='total'?'当前范围':scope==='categoryGuild'?label('category',r.category)+' / '+label('guild',r.guild):scope==='categoryTier'?label('category',r.category)+' / '+r.tier:label(scope,key),dates:new Set(),values:{},weights:{},live:new Map(),category:r.category,group:r.group,guild:r.guild,anchor:r.anchor,tier:r.tier};groups.set(key,a)}
   // A ratio must aggregate numerator and denominator over the SAME valid rows.
   const issue=ratioIssue(r.values,metric);if(issue){a.invalidReason=issue;continue}if(valueFor(r.values,metric)==null)continue;
   const ingredients=m?.ratio||[metric];for(const field of ingredients){const raw=r.values[field];if(raw==null||!Number.isFinite(Number(raw)))continue;const v=Number(raw);if(field==='liveAnchors'&&kind==='weekly'){const lk=r.week+'|'+r.anchor;a.live.set(lk,Math.max(a.live.get(lk)??0,v*7));continue}if(field==='viewMinutes'||field==='acu'){const weight=field==='viewMinutes'?(kind==='weekly'?r.row[12]:r.values.dau||0):(kind==='weekly'?r.row[10]:1);a.values[field]=(a.values[field]||0)+v*weight;a.weights[field]=(a.weights[field]||0)+weight}else a.values[field]=(a.values[field]||0)+v}
   for(const d of span(r.date,r.end||r.date))a.dates.add(d);
  }
   const result=[...groups.values()].map(a=>{if(a.live.size)a.values.liveAnchors=[...a.live.values()].reduce((x,y)=>x+y,0);for(const m of ['viewMinutes','acu'])if(a.weights[m])a.values[m]/=a.weights[m];const categoryScope=['category','categoryGuild','categoryTier'].includes(scope)||scope==='category',categoryExcluded=eventMode==='nonEvent'&&categoryScope?(eventDaysFor(a.category,start,end)||[]):[...unionExcluded],expectedDays=allDates.length-categoryExcluded.length,coverage=eventMode==='all'?'notRequested':categoryScope?eventCoverage(a.category):'partial';const count=a.dates.size;let v=a.invalidReason?null:valueFor(a.values,metric);if(m?.agg==='mean'&&v!=null)v/=count||1;const parts=m?.ratio&&!a.invalidReason?m.ratio.map(k=>a.values[k]??null):null;return {...a,value:v,parts,dates:[...a.dates],complete:!a.invalidReason&&count===expectedDays,eventExcludedDates:categoryExcluded,eventDaysExcluded:categoryExcluded.length,eventCoverage:coverage}});const response={rows:result,kind};if(aggregateCache.size>300)aggregateCache.delete(aggregateCache.keys().next().value);aggregateCache.set(cacheKey,response);return response;
 }
 const cache=new Map();
  function ranking(scope,metric,options={}){const {start=data.reportDate,end=start,comparison='weekday',baseStart=shift(start,-7),baseEnd=shift(end,-7),paths=[],grain='day',eventMode='all'}=options;const key=JSON.stringify([scope,metric,options]);if(cache.has(key))return cache.get(key);
   const current=aggregate(scope,metric,start,end,paths,{eventMode}),isDaily=start===end,baselineRanges=comparison==='weekday'&&isDaily?Array.from({length:4},(_,i)=>[shift(start,-7*(i+1)),shift(end,-7*(i+1))]):[[baseStart,baseEnd]];
   const base=baselineRanges.map(([a,b])=>new Map(aggregate(scope,metric,a,b,paths,{eventMode}).rows.map(r=>[String(r.id),r])));
  const canRate=(isDaily&&grain==='day')||(grain==='week'&&completeBucket(start,end,'week')&&days(start,end).length===7);
  const historyRanges=canRate?Array.from({length:4},(_,i)=>[shift(start,-7*(i+1)),shift(end,-7*(i+1))]):[];
   const hist=historyRanges.map(([a,b])=>new Map(aggregate(scope,metric,a,b,paths,{eventMode}).rows.map(r=>[String(r.id),r])));
   let rows=current.rows.map(c=>{const b=base.map(m=>m.get(String(c.id))),valid=b.every(r=>r?.complete&&r.value!=null),currentValue=c.complete?c.value:null,parts=valid&&metrics[metric]?.ratio?metrics[metric].ratio.map((_,i)=>median(b.map(r=>r.parts[i]))):null,baseline=valid?(parts?parts[1]>0?parts[0]/parts[1]:null:median(b.map(r=>r.value))):null,history=hist.map(m=>{const r=m.get(String(c.id));return r?.complete?r.value:null}),coverageOk=eventMode==='all'||c.eventCoverage==='covered',rating=canRate&&coverageOk?classify(metric,currentValue,history):{severity:'待判断',robustZ:null,historyCount:0,rule:!coverageOk?'赛事日映射未覆盖该对象，阻断赛事剔除评级':'非日/完整单周粒度暂无匹配历史评级'};
    const anchor=scope==='anchor'?data.anchors[c.id]:null;return {id:c.id,name:c.name,path:anchor?'UID '+anchor.id+' / Room '+anchor.roomid:(scope==='guild'?'全品类公会':label('group',c.group)),scope,metric,current:currentValue,baseline,delta:currentValue!=null&&baseline!=null?currentValue-baseline:null,changePct:baseline&&currentValue!=null?(currentValue-baseline)/baseline:null,currentParts:currentValue!=null?c.parts:null,baselineParts:valid&&metrics[metric]?.ratio?metrics[metric].ratio.map((_,i)=>median(b.map(r=>r.parts[i]))):null,...rating,eventMode,eventCoverage:c.eventCoverage,eventExcludedDates:c.eventExcludedDates||[],eventDaysExcluded:c.eventDaysExcluded||0,baselineDates:baselineRanges.map(r=>r.join('—')),ratingDates:historyRanges.map(r=>r.join('—')),period:start+'—'+end,comparisonPeriod:baselineRanges.map(r=>r.join('—')).join('；'),complete:c.complete,kind:current.kind,category:scope==='category'?c.category:scope==='categoryGuild'||scope==='categoryTier'?c.category:null,group:c.group,guild:scope==='guild'?c.guild:null,anchor:scope==='anchor'?c.anchor:null,tier:c.tier};});
  if(metric==='liveAnchors'&&current.kind==='weekly'&&scope!=='anchor')rows=rows.map(r=>({...r,severity:'待判断',robustZ:null,rule:'周路径开播天数最大值不能替代跨品类主播日并集；供给待独立复算'}));
  rows=rows.map((r,i)=>{const c=current.rows[i],baseIssue=base.map(m=>m.get(String(r.id))?.invalidReason).find(Boolean);return {...r,currentReason:c.invalidReason||(r.current==null?'本期指标缺失或日期覆盖不完整':null),baselineReason:baseIssue||(r.baseline==null?'比较期缺记录、覆盖不完整或分母为零':null),scoreReason:metrics[metric]?.blocked?'口径未通过核验':metrics[metric]?.pending?'指标评级尚未校准':r.robustZ==null?r.rule:null}});
  rows=contributions(rows,metric);rows.forEach(r=>r.priority=priority(r));const result={rows,kind:current.kind,unsupported:current.unsupported};cache.set(key,result);return result;
 }
 // 主播日表没有品类/公会列。微观赛事剔除先为每个主播、每个完整周
 // 选择 DAU 最大的“品类+公会”作为主路径，再只保留该周主路径品类
 // 的非赛事日。它是“主播主路径非赛事日均”，不是跨品类去重总量。
 const microCache=new Map();
 function mainWeeklyPath(week,anchor){
   return weeklyPathByWeekAnchor.get(week+'|'+anchor)||null;
 }
 function dailySummary(anchor,path,start,end){
   if(!path)return null;
   const excluded=eventDays.get(eventKey(path.category));
   if(!excluded)return null;
   const values={},liveDates=new Set(),observedDates=new Set();
   for(const raw of dailyByAnchor.get(anchor)||[]){
     const dt=raw[dailyColumns.date];
     if(dt<start||dt>end||excluded.has(dt))continue;
     observedDates.add(dt);
     if(Number(raw[dailyColumns.isLive])===1)liveDates.add(dt);
     for(const metric of ['dau','revenue','payUsers','attributionUsers','interactionUsers']){
       const value=raw[dailyColumns[metric]];
       if(value==null||!Number.isFinite(Number(value)))continue;
       if(!values[metric])values[metric]=[];
       values[metric].push(Number(value));
     }
   }
   const averages={};
   for(const [metric,items] of Object.entries(values))averages[metric]=items.reduce((a,b)=>a+b,0)/items.length;
   return {...averages,days:observedDates.size,liveDays:liveDates.size,excludedDays:excluded?span(start,end).filter(d=>excluded.has(d)).length:0,eventCoverage:'covered'};
 }
 function anchorEventWeeklyComparison(metric='dau',options={}){
   const curWeek=options.curWeek??data.weeks.length-1,baseWeek=options.baseWeek??curWeek-1;
   const key='anchor|'+metric+'|'+curWeek+'|'+baseWeek;
   if(microCache.has(key))return microCache.get(key);
   if(curWeek<0||baseWeek<0||!data.weeks[curWeek]||!data.weeks[baseWeek])return {rows:[],curWeek:data.weeks[curWeek],baseWeek:data.weeks[baseWeek],unsupported:'缺少相邻完整周'};
   const cr=data.weekRanges[data.weeks[curWeek]],br=data.weekRanges[data.weeks[baseWeek]];
   const anchors=new Set([...weekly.filter(r=>r.week===curWeek||r.week===baseWeek).map(r=>r.anchor)]);
   const rows=[];
   for(const anchor of anchors){
     const cp=mainWeeklyPath(curWeek,anchor),bp=mainWeeklyPath(baseWeek,anchor);
     if(!cp||!bp)continue;
     if(eventCoverage(cp.category)==='unknown'||eventCoverage(bp.category)==='unknown')continue;
     const cs=dailySummary(anchor,cp,cr.start,cr.end),bs=dailySummary(anchor,bp,br.start,br.end);
     if(!cs||!bs||cs.days<3||bs.days<3)continue;
     const current=cs[metric],baseline=bs[metric];
     if(current==null||baseline==null)continue;
     const meta=data.anchors[anchor]||{};
     rows.push({id:cp.category+'|'+cp.guild+'|'+anchor,anchorId:anchor,uid:meta.id,roomid:meta.roomid,name:meta.name||label('anchor',anchor),category:cp.category,categoryName:label('category',cp.category),guild:cp.guild,guildName:label('guild',cp.guild),baselineGuild:bp.guild,baselineGuildName:label('guild',bp.guild),baselineCategory:bp.category,baselineCategoryName:label('category',bp.category),pathChanged:cp.category!==bp.category||cp.guild!==bp.guild,metric,current,baseline,delta:current-baseline,changePct:baseline?current/baseline-1:null,currentDays:cs.days,baselineDays:bs.days,currentLiveDays:cs.liveDays,baselineLiveDays:bs.liveDays,currentExcludedDays:cs.excludedDays,baselineExcludedDays:bs.excludedDays,currentInteractionUsers:cs.interactionUsers??null,baselineInteractionUsers:bs.interactionUsers??null,currentRevenue:cs.revenue??null,baselineRevenue:bs.revenue??null,curWeek:data.weeks[curWeek],baseWeek:data.weeks[baseWeek]});
   }
   rows.sort((a,b)=>a.delta-b.delta||String(a.name).localeCompare(String(b.name)));
   const response={rows,curWeek:data.weeks[curWeek],baseWeek:data.weeks[baseWeek],curRange:cr,baseRange:br,coverage:'主播主路径事件剔除；仅含有赛事映射且两期各有至少3个非赛事有效日的品类',kind:'anchor-daily-path'};
   microCache.set(key,response);return response;
 }
 function guildEventWeeklyComparison(metric='dau',options={}){
   const anchors=anchorEventWeeklyComparison(metric,options),groups=new Map(),key='guild|'+metric+'|'+anchors.curWeek+'|'+anchors.baseWeek;
   if(microCache.has(key))return microCache.get(key);
   for(const row of anchors.rows){
     if(!groups.has(row.guild))groups.set(row.guild,{id:row.guild,name:row.guildName,current:0,baseline:0,anchors:0,metric,curWeek:anchors.curWeek,baseWeek:anchors.baseWeek,currentInteractionUsers:0,baselineInteractionUsers:0,currentRevenue:0,baselineRevenue:0});
     const g=groups.get(row.guild);g.current+=row.current;g.baseline+=row.baseline;g.anchors+=1;g.currentInteractionUsers+=row.currentInteractionUsers||0;g.baselineInteractionUsers+=row.baselineInteractionUsers||0;g.currentRevenue+=row.currentRevenue||0;g.baselineRevenue+=row.baselineRevenue||0;
   }
   const rows=[...groups.values()].map(g=>({...g,delta:g.current-g.baseline,changePct:g.baseline?g.current/g.baseline-1:null}));rows.sort((a,b)=>a.delta-b.delta||String(a.name).localeCompare(String(b.name)));
   const response={...anchors,rows,coverage:'公会内可归因主播主路径日均加总；主播、品类之间可重叠'};
   microCache.set(key,response);return response;
 }
 function anchorHistory(index,metric,start,end,grain='day'){const raw=(dailyByAnchor.get(index)||[]).filter(r=>r[dailyColumns.date]>=start&&r[dailyColumns.date]<=end),map=new Map();for(const record of raw){const r=dailyObject(record);if(valueFor(r.values,metric)==null)continue;const k=bucket(r.date,grain),a=map.get(k)||{dates:new Set(),values:{},weight:0};for(const m of metrics[metric]?.ratio||[metric]){const v=r.values[m];if(v==null)continue;if(m==='viewMinutes'){a.values[m]=(a.values[m]||0)+v*(r.values.dau||0);a.weight+=r.values.dau||0}else a.values[m]=(a.values[m]||0)+v}a.dates.add(r.date);map.set(k,a)}return [...map].sort().map(([key,a])=>{if(a.weight)a.values.viewMinutes/=a.weight;let value=valueFor(a.values,metric);if(metrics[metric]?.agg==='mean'&&value!=null)value/=a.dates.size;return {key,value,days:a.dates.size}})}
 function tierMigration(curWeek=data.weeks.length-1,baseWeek=curWeek-1){const cur=new Map(),base=new Map();for(const r of weekly)if(r.week===curWeek||r.week===baseWeek){const m=r.week===curWeek?cur:base,a=m.get(r.anchor)||{acuSum:0,acuDays:0,dau:0,revenue:0};a.acuSum+=r.row[9];a.acuDays+=r.row[10];a.dau+=r.values.dau;a.revenue+=r.values.revenue;m.set(r.anchor,a)}const matrix=new Map(),cohorts=new Map();for(const ai of new Set([...cur.keys(),...base.keys()])){const c=cur.get(ai),b=base.get(ai),bt=b?fixedTier(b.acuDays?b.acuSum/b.acuDays:null):'新增',ct=c?fixedTier(c.acuDays?c.acuSum/c.acuDays:null):'退出',k=bt+' → '+ct;matrix.set(k,(matrix.get(k)||0)+1);const co=cohorts.get(bt)||{tier:bt,anchors:0,currentDau:0,baselineDau:0,currentRevenue:0,baselineRevenue:0};co.anchors++;co.currentDau+=(c?.dau||0)/7;co.baselineDau+=(b?.dau||0)/7;co.currentRevenue+=c?.revenue||0;co.baselineRevenue+=b?.revenue||0;cohorts.set(bt,co)}return {matrix:[...matrix].map(([path,count])=>({path,count})),cohorts:[...cohorts.values()],baseWeek:data.weeks[baseWeek],curWeek:data.weeks[curWeek]}}
  return {ranking,aggregate,baseRows,anchorEventWeeklyComparison,guildEventWeeklyComparison,anchorHistory,tierMigration,label,eventOf,eventCoverage,eventDaysFor,eventUnion,weekly,catRows,dailyByAnchor,anchorPaths};
}
