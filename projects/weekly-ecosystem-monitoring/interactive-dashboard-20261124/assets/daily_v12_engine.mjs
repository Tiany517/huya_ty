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
export const dims={group:'内容大类',category:'品类',guild:'公会',tier:'主播层级',anchor:'主播',event:'版权登记属性'};
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
 const anchorPaths=new Map();for(const row of data.anchorWeekly){const w=row[0],ca=row[1],g=row[2],guild=row[3],anchor=row[4],acu=row[10]?row[9]/row[10]:null,liveDays=Number(row[16]);const r={date:data.weekRanges[data.weeks[w]].start,end:data.weekRanges[data.weeks[w]].end,week:w,category:ca,group:g,guild,anchor,tier:fixedTier(acu),values:{dau:row[5],revenue:row[6],payUsers:row[7],attributionUsers:row[13],interactionCount:row[14],interactionUsers:row[15],liveAnchors:Number.isFinite(liveDays)?liveDays/7:null,acu,viewMinutes:row[12]?row[11]/row[12]:null},row};weekly.push(r);const old=anchorPaths.get(anchor);if(!old||old.week<w)anchorPaths.set(anchor,r)}
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
 function eventOf(row){const id=data.categories[row.category]?.id,set=eventDays.get(String(id));if(!set)return '映射未知';if(set.has(row.date))return '登记比赛日';return '非登记日（窗口待核验）'}
 function label(dim,id){if(dim==='category')return data.categories[id]?.name||'未知';if(dim==='group')return data.groups[id]||'未知';if(dim==='guild')return data.guilds[id]||'无公会';if(dim==='anchor')return data.anchors[id]?.name||'未知';return String(id)}
 function baseRows(scope,start,end,paths=[]){const anchorNeeded=paths.some(p=>['guild','tier','anchor'].includes(p.dim))||['guild','tier','anchor','categoryGuild','categoryTier'].includes(scope);let kind=anchorNeeded?'weekly':'daily',source=anchorNeeded?weekly:catRows;
  const weeklyAligned=data.weeks.filter(w=>data.weekRanges[w].start>=start&&data.weekRanges[w].end<=end);
  if(anchorNeeded&&(weeklyAligned.length===0||data.weekRanges[weeklyAligned[0]].start!==start||data.weekRanges[weeklyAligned.at(-1)].end!==end))return {rows:[],kind,unsupported:'此层级仅有完整周路径数据，请选择完整自然周；不会将周数据伪装成日级。'};
  let rows=anchorNeeded?[...weeklyByDate].filter(([dt])=>dt>=start&&dt<=end).flatMap(([,r])=>r):span(start,end).flatMap(dt=>catByDate.get(dt)||[]);rows=rows.filter(r=>(r.end||r.date)<=end);for(const p of paths)rows=rows.filter(r=>String(p.dim==='event'?eventOf(r):r[p.dim])===String(p.value));
  if(kind==='weekly'&&(scope==='event'||paths.some(p=>p.dim==='event')))return {rows:[],kind,unsupported:'版权属性为日级映射，不能把整周按周一的赛事状态分类。请使用日级品类分析。'};
  return {rows,kind};}
 const aggregateCache=new Map();
 function aggregate(scope,metric,start,end,paths=[]){const cacheKey=JSON.stringify([scope,metric,start,end,paths]);if(aggregateCache.has(cacheKey))return aggregateCache.get(cacheKey);const {rows,kind,unsupported}=baseRows(scope,start,end,paths);if(unsupported)return {rows:[],kind,unsupported};const m=metrics[metric];const groups=new Map(),expectedDays=span(start,end).length;
  for(const r of rows){let key=scope==='total'?'total':scope==='categoryGuild'?r.category+'|'+r.guild:scope==='categoryTier'?r.category+'|'+r.tier:scope==='event'?eventOf(r):r[scope];if(key==null)continue;let a=groups.get(key);if(!a){a={id:key,name:scope==='total'?'当前范围':scope==='categoryGuild'?label('category',r.category)+' / '+label('guild',r.guild):scope==='categoryTier'?label('category',r.category)+' / '+r.tier:label(scope,key),dates:new Set(),values:{},weights:{},live:new Map(),category:r.category,group:r.group,guild:r.guild,anchor:r.anchor,tier:r.tier};groups.set(key,a)}
   // A ratio must aggregate numerator and denominator over the SAME valid rows.
   const issue=ratioIssue(r.values,metric);if(issue){a.invalidReason=issue;continue}if(valueFor(r.values,metric)==null)continue;
   const ingredients=m?.ratio||[metric];for(const field of ingredients){const raw=r.values[field];if(raw==null||!Number.isFinite(Number(raw)))continue;const v=Number(raw);if(field==='liveAnchors'&&kind==='weekly'){const lk=r.week+'|'+r.anchor;a.live.set(lk,Math.max(a.live.get(lk)??0,v*7));continue}if(field==='viewMinutes'||field==='acu'){const weight=field==='viewMinutes'?(kind==='weekly'?r.row[12]:r.values.dau||0):(kind==='weekly'?r.row[10]:1);a.values[field]=(a.values[field]||0)+v*weight;a.weights[field]=(a.weights[field]||0)+weight}else a.values[field]=(a.values[field]||0)+v}
   for(const d of span(r.date,r.end||r.date))a.dates.add(d);
  }
  const result=[...groups.values()].map(a=>{if(a.live.size)a.values.liveAnchors=[...a.live.values()].reduce((x,y)=>x+y,0);for(const m of ['viewMinutes','acu'])if(a.weights[m])a.values[m]/=a.weights[m];const count=a.dates.size;let v=a.invalidReason?null:valueFor(a.values,metric);if(m?.agg==='mean'&&v!=null)v/=count||1;const parts=m?.ratio&&!a.invalidReason?m.ratio.map(k=>a.values[k]??null):null;return {...a,value:v,parts,dates:[...a.dates],complete:!a.invalidReason&&count===expectedDays}});const response={rows:result,kind};if(aggregateCache.size>300)aggregateCache.delete(aggregateCache.keys().next().value);aggregateCache.set(cacheKey,response);return response;
 }
 const cache=new Map();
 function ranking(scope,metric,options={}){const {start=data.reportDate,end=start,comparison='weekday',baseStart=shift(start,-7),baseEnd=shift(end,-7),paths=[],grain='day'}=options;const key=JSON.stringify([scope,metric,options]);if(cache.has(key))return cache.get(key);
  const current=aggregate(scope,metric,start,end,paths),isDaily=start===end,baselineRanges=comparison==='weekday'&&isDaily?Array.from({length:4},(_,i)=>[shift(start,-7*(i+1)),shift(end,-7*(i+1))]):[[baseStart,baseEnd]];
  const base=baselineRanges.map(([a,b])=>new Map(aggregate(scope,metric,a,b,paths).rows.map(r=>[String(r.id),r])));
  const canRate=(isDaily&&grain==='day')||(grain==='week'&&completeBucket(start,end,'week')&&days(start,end).length===7);
  const historyRanges=canRate?Array.from({length:4},(_,i)=>[shift(start,-7*(i+1)),shift(end,-7*(i+1))]):[];
  const hist=historyRanges.map(([a,b])=>new Map(aggregate(scope,metric,a,b,paths).rows.map(r=>[String(r.id),r])));
  let rows=current.rows.map(c=>{const b=base.map(m=>m.get(String(c.id))),valid=b.every(r=>r?.complete&&r.value!=null),currentValue=c.complete?c.value:null,parts=valid&&metrics[metric]?.ratio?metrics[metric].ratio.map((_,i)=>median(b.map(r=>r.parts[i]))):null,baseline=valid?(parts?parts[1]>0?parts[0]/parts[1]:null:median(b.map(r=>r.value))):null,history=hist.map(m=>{const r=m.get(String(c.id));return r?.complete?r.value:null}),rating=canRate?classify(metric,currentValue,history):{severity:'待判断',robustZ:null,historyCount:0,rule:'非日/完整单周粒度暂无匹配历史评级'};
   const anchor=scope==='anchor'?data.anchors[c.id]:null;return {id:c.id,name:c.name,path:anchor?'UID '+anchor.id+' / Room '+anchor.roomid:(scope==='guild'?'全品类公会':label('group',c.group)),scope,metric,current:currentValue,baseline,delta:currentValue!=null&&baseline!=null?currentValue-baseline:null,changePct:baseline&&currentValue!=null?(currentValue-baseline)/baseline:null,currentParts:currentValue!=null?c.parts:null,baselineParts:valid&&metrics[metric]?.ratio?metrics[metric].ratio.map((_,i)=>median(b.map(r=>r.parts[i]))):null,...rating,baselineDates:baselineRanges.map(r=>r.join('—')),ratingDates:historyRanges.map(r=>r.join('—')),period:start+'—'+end,comparisonPeriod:baselineRanges.map(r=>r.join('—')).join('；'),complete:c.complete,kind:current.kind,category:scope==='category'?c.category:scope==='categoryGuild'||scope==='categoryTier'?c.category:null,group:c.group,guild:scope==='guild'?c.guild:null,anchor:scope==='anchor'?c.anchor:null,tier:c.tier};});
  if(metric==='liveAnchors'&&current.kind==='weekly'&&scope!=='anchor')rows=rows.map(r=>({...r,severity:'待判断',robustZ:null,rule:'周路径开播天数最大值不能替代跨品类主播日并集；供给待独立复算'}));
  rows=rows.map((r,i)=>{const c=current.rows[i],baseIssue=base.map(m=>m.get(String(r.id))?.invalidReason).find(Boolean);return {...r,currentReason:c.invalidReason||(r.current==null?'本期指标缺失或日期覆盖不完整':null),baselineReason:baseIssue||(r.baseline==null?'比较期缺记录、覆盖不完整或分母为零':null),scoreReason:metrics[metric]?.blocked?'口径未通过核验':metrics[metric]?.pending?'指标评级尚未校准':r.robustZ==null?r.rule:null}});
  rows=contributions(rows,metric);rows.forEach(r=>r.priority=priority(r));const result={rows,kind:current.kind,unsupported:current.unsupported};cache.set(key,result);return result;
 }
 function anchorHistory(index,metric,start,end,grain='day'){const raw=(dailyByAnchor.get(index)||[]).filter(r=>r[dailyColumns.date]>=start&&r[dailyColumns.date]<=end),map=new Map();for(const record of raw){const r=dailyObject(record);if(valueFor(r.values,metric)==null)continue;const k=bucket(r.date,grain),a=map.get(k)||{dates:new Set(),values:{},weight:0};for(const m of metrics[metric]?.ratio||[metric]){const v=r.values[m];if(v==null)continue;if(m==='viewMinutes'){a.values[m]=(a.values[m]||0)+v*(r.values.dau||0);a.weight+=r.values.dau||0}else a.values[m]=(a.values[m]||0)+v}a.dates.add(r.date);map.set(k,a)}return [...map].sort().map(([key,a])=>{if(a.weight)a.values.viewMinutes/=a.weight;let value=valueFor(a.values,metric);if(metrics[metric]?.agg==='mean'&&value!=null)value/=a.dates.size;return {key,value,days:a.dates.size}})}
 function tierMigration(curWeek=data.weeks.length-1,baseWeek=curWeek-1){const cur=new Map(),base=new Map();for(const r of weekly)if(r.week===curWeek||r.week===baseWeek){const m=r.week===curWeek?cur:base,a=m.get(r.anchor)||{acuSum:0,acuDays:0,dau:0,revenue:0};a.acuSum+=r.row[9];a.acuDays+=r.row[10];a.dau+=r.values.dau;a.revenue+=r.values.revenue;m.set(r.anchor,a)}const matrix=new Map(),cohorts=new Map();for(const ai of new Set([...cur.keys(),...base.keys()])){const c=cur.get(ai),b=base.get(ai),bt=b?fixedTier(b.acuDays?b.acuSum/b.acuDays:null):'新增',ct=c?fixedTier(c.acuDays?c.acuSum/c.acuDays:null):'退出',k=bt+' → '+ct;matrix.set(k,(matrix.get(k)||0)+1);const co=cohorts.get(bt)||{tier:bt,anchors:0,currentDau:0,baselineDau:0,currentRevenue:0,baselineRevenue:0};co.anchors++;co.currentDau+=(c?.dau||0)/7;co.baselineDau+=(b?.dau||0)/7;co.currentRevenue+=c?.revenue||0;co.baselineRevenue+=b?.revenue||0;cohorts.set(bt,co)}return {matrix:[...matrix].map(([path,count])=>({path,count})),cohorts:[...cohorts.values()],baseWeek:data.weeks[baseWeek],curWeek:data.weeks[curWeek]}}
 return {ranking,aggregate,baseRows,anchorHistory,tierMigration,label,eventOf,weekly,catRows,dailyByAnchor,anchorPaths};
}
