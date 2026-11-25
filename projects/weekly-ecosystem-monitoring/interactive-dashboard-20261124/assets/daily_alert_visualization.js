(async () => {
  'use strict';
  window.__visualizationScriptStarted = true;
  const palette=['#2878df','#55b7a3','#f2a65a','#e76f9a','#8d7cf3','#62a7d8','#95c85f','#cf7db9','#7b8da8'];
  const state={scope:__DEFAULT_SCOPE__,dimension:'none',selected:new Set(['all']),search:'',granularity:'day',chartType:'line',range:'all',customStart:'',customEnd:''};
  const fmt=value=>Number(value||0).toLocaleString('zh-CN',{maximumFractionDigits:0});
  const esc=value=>String(value??'').replace(/[&<>"']/g,ch=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
  const iso=value=>new Date(value).toISOString().slice(0,10);
  const parseDay=value=>new Date(value+'T00:00:00Z');
  function shiftDay(value,days){const date=parseDay(value);date.setUTCDate(date.getUTCDate()+days);return iso(date);}
  function bucketKey(dt,granularity){
    const d=parseDay(dt);
    if(granularity==='day')return dt;
    if(granularity==='week'){const t=new Date(d);t.setUTCDate(t.getUTCDate()-((t.getUTCDay()+6)%7));return iso(t);}
    if(granularity==='month')return dt.slice(0,7);
    return `${d.getUTCFullYear()}-Q${Math.floor(d.getUTCMonth()/3)+1}`;
  }
  function bucketLabel(key,granularity){
    if(granularity==='day')return key.slice(5).replace('-','/');
    if(granularity==='week')return key.slice(5).replace('-','/');
    if(granularity==='month')return key.replace('-','/');
    return key;
  }
  function tickIndexes(length,maxTicks=8){
    if(length<=0)return [];
    if(length<=maxTicks)return Array.from({length},(_,index)=>index);
    const intervals=Math.max(1,maxTicks-1),indices=new Set();
    for(let index=0;index<=intervals;index+=1)indices.add(Math.round(index*(length-1)/intervals));
    return [...indices].sort((a,b)=>a-b);
  }
  async function loadData(){
    const encoded=document.getElementById('visualization-data-gzip').textContent.trim();
    const compressed=Uint8Array.from(atob(encoded),ch=>ch.charCodeAt(0));
    return JSON.parse(await new Response(new Blob([compressed]).stream().pipeThrough(new DecompressionStream('gzip'))).text());
  }
  const data=await loadData();
  data.anchorDates=data.anchorDates||[];
  data.anchorOptions=data.anchorOptions||[];
  data.anchorRows=data.anchorRows||[];

  const scopeSelect=document.getElementById('visualizationScope');
  const dimensionSelect=document.getElementById('visualizationDimension');
  const objectSearch=document.getElementById('visualizationObjectSearch');
  const objectList=document.getElementById('visualizationDrillValue');
  const objectCount=document.getElementById('visualizationObjectCount');
  const selectVisibleButton=document.getElementById('visualizationSelectVisible');
  const resetObjectsButton=document.getElementById('visualizationResetObjects');
  const granSelect=document.getElementById('visualizationGranularity');
  const rangeSelect=document.getElementById('visualizationRange');
  const startDateInput=document.getElementById('visualizationStartDate');
  const endDateInput=document.getElementById('visualizationEndDate');
  const chartHost=document.getElementById('visualizationChart');
  const legendHost=document.getElementById('visualizationLegend');
  const crumbHost=document.getElementById('visualizationBreadcrumb');
  const tooltip=document.getElementById('visualizationTooltip');
  const rowLimitSpecs=[
    {label:'品类',inputId:'categoryTopLimit',titleId:'categoryTopTitle',bodyId:'categoryTableBody',defaultLimit:10},
    {label:'公会',inputId:'guildTopLimit',titleId:'guildTopTitle',bodyId:'guildTableBody',defaultLimit:20},
    {label:'主播',inputId:'anchorTopLimit',titleId:'anchorTopTitle',bodyId:'anchorTableBody',defaultLimit:10}
  ].map(spec=>({...spec,input:document.getElementById(spec.inputId),title:document.getElementById(spec.titleId),rows:[...document.querySelectorAll(`#${spec.bodyId} tr`)]}));

  if(data.platform.length){scopeSelect.add(new Option('平台 DAU（官方去重口径）','platform'));}
  scopeSelect.add(new Option('内容生态 DAU（品类合计）','total'));
  scopeSelect.add(new Option('内容生态流水（品类合计）','revenue'));
  scopeSelect.value=state.scope;

  function scopeDates(){
    if(state.scope!=='platform'&&state.dimension==='anchor'&&data.anchorDates.length)return data.anchorDates;
    return data.dates;
  }
  function availableRange(){
    const dates=scopeDates();
    return {start:dates[0]||data.availableStart,end:dates[dates.length-1]||data.availableEnd};
  }
  function dateWindow(){
    const available=availableRange();
    let start=available.start,end=available.end;
    if(state.range==='custom'){
      start=state.customStart||available.start;
      end=state.customEnd||available.end;
      if(start<available.start)start=available.start;
      if(end>available.end)end=available.end;
      if(start>end)start=end;
    }else if(state.range!=='all'){
      const days=Number(state.range)||30;
      start=shiftDay(available.end,-(days-1));
      if(start<available.start)start=available.start;
    }
    return {start,end};
  }
  function updateDateControls(){
    const available=availableRange(),windowRange=dateWindow();
    for(const input of [startDateInput,endDateInput]){
      input.min=available.start;input.max=available.end;input.disabled=state.range!=='custom';
    }
    startDateInput.value=windowRange.start;endDateInput.value=windowRange.end;
    state.customStart=windowRange.start;state.customEnd=windowRange.end;
  }
  function fuzzyMatch(value,query){
    const text=String(value||'').toLocaleLowerCase();const needle=String(query||'').trim().toLocaleLowerCase();
    if(!needle||text.includes(needle))return true;
    let cursor=0;for(const char of text){if(char===needle[cursor])cursor+=1;if(cursor===needle.length)return true;}
    return false;
  }
  function matchScore(option,query){
    const needle=String(query||'').trim().toLocaleLowerCase();if(!needle)return 0;
    const label=String(option.label||'').toLocaleLowerCase(),detail=String(option.detail||'').toLocaleLowerCase();
    if(label===needle)return 0;
    if(label.startsWith(needle))return 1;
    if(label.includes(needle))return 2;
    if(detail.includes(needle))return 3;
    return 4;
  }
  function objectOptions(){
    if(state.scope==='platform')return [{value:'all',label:'平台整体',detail:'官方去重口径'}];
    if(state.dimension==='group')return [{value:'all',label:'全部内容大类',detail:'内容生态合计'},...data.groups.map(group=>({value:String(group.id),label:group.name,detail:`内容大类 ${group.id}`}))];
    if(state.dimension==='category')return [{value:'all',label:'全部品类',detail:'内容生态合计'},...data.categories.map((category,index)=>({value:String(index),label:category.name,detail:data.groups[Number(category.group)]?.name||'未匹配'}))];
    if(state.dimension==='anchor')return [{value:'all',label:'全部异动 Top50 主播',detail:'按当前完整周 DAU 变化排序'},...data.anchorOptions.map((anchor,index)=>({value:String(index),label:anchor.name,detail:anchor.roomid?`RoomID ${anchor.roomid}`:`UID ${anchor.id}`}))];
    return [{value:'all',label:'内容生态整体',detail:'全部品类合计'}];
  }
  function selectedValues(){return state.selected.has('all')?['all']:[...state.selected];}
  function updateObjectCount(){
    const selected=[...state.selected].filter(value=>value!=='all');
    objectCount.textContent=selected.length?`已选 ${selected.length} 个`:'全部';
  }
  function renderObjectOptions(){
    const disabled=state.scope==='platform'||!['group','category','anchor'].includes(state.dimension);
    objectSearch.disabled=disabled;selectVisibleButton.disabled=disabled;resetObjectsButton.disabled=disabled;
    if(disabled){objectList.innerHTML='<div class="visualization-empty" style="min-height:54px">当前分析范围不使用下钻对象</div>';updateObjectCount();return;}
    const options=objectOptions();const visible=options.filter(option=>option.value==='all'||fuzzyMatch(`${option.label} ${option.detail}`,state.search)).sort((a,b)=>{if(a.value==='all')return -1;if(b.value==='all')return 1;return matchScore(a,state.search)-matchScore(b,state.search);});
    objectList.innerHTML=visible.length?visible.map(option=>{
      const checked=state.selected.has('all')?option.value==='all':state.selected.has(option.value);
      return `<label class="object-option"><input type="checkbox" data-object-value="${esc(option.value)}" ${checked?'checked':''}><span title="${esc(option.label)}">${esc(option.label)}</span><small>${esc(option.detail)}</small></label>`;
    }).join(''):'<div class="visualization-empty" style="min-height:54px">没有匹配的对象</div>';
    updateObjectCount();
  }
  function resetObjectSelection(){
    state.selected=new Set(['all']);state.search='';objectSearch.value='';renderObjectOptions();
  }
  function populateObjectValues(){
    resetObjectSelection();
  }
  function updateDrillControls(resetObjects=true){
    if(state.scope==='platform'){
      state.dimension='none';dimensionSelect.value='none';dimensionSelect.disabled=true;
    }else{
      dimensionSelect.disabled=false;
      if(state.dimension==='none')state.dimension='group';
      dimensionSelect.value=state.dimension;
    }
    if(resetObjects)populateObjectValues();else renderObjectOptions();
    updateDateControls();
  }
  function targetDateAt(row){
    return state.dimension==='anchor'?data.anchorDates[row[0]]:data.dates[row[0]];
  }
  function targetValueAt(row){
    if(state.dimension==='anchor')return Number((state.scope==='revenue'?row[3]:row[2])||0);
    return Number((state.scope==='revenue'?row[4]:row[3])||0);
  }
  function scopeRows(){
    const range=dateWindow();
    if(state.scope==='platform')return [];
    if(state.dimension==='anchor')return data.anchorRows.filter(row=>{const dt=data.anchorDates[row[0]];return dt>=range.start&&dt<=range.end;});
    return data.rows.filter(row=>{const dt=data.dates[row[0]];return dt>=range.start&&dt<=range.end;});
  }
  function addBucket(map,key,date,value){
    const bucket=map.get(key)||{sum:0,days:new Set()};bucket.sum+=value;bucket.days.add(date);map.set(key,bucket);
  }
  function aggregateMain(){
    const range=dateWindow();
    if(state.scope==='platform'){
      const buckets=new Map();
      for(const [dt,value] of data.platform){if(dt<range.start||dt>range.end)continue;addBucket(buckets,bucketKey(dt,state.granularity),dt,value);}
      return [...buckets.entries()].sort((a,b)=>a[0].localeCompare(b[0])).map(([key,item])=>({key,label:bucketLabel(key,state.granularity),value:item.sum/Math.max(item.days.size,1)}));
    }
    const buckets=new Map();
    for(const row of scopeRows()){const dt=targetDateAt(row);addBucket(buckets,bucketKey(dt,state.granularity),dt,targetValueAt(row));}
    return [...buckets.entries()].sort((a,b)=>a[0].localeCompare(b[0])).map(([key,item])=>({key,label:bucketLabel(key,state.granularity),value:item.sum/Math.max(item.days.size,1)}));
  }
  function selectedComparisonOptions(){
    if(state.scope==='platform'||state.dimension==='none'||state.selected.has('all'))return [];
    return objectOptions().filter(option=>option.value!=='all'&&state.selected.has(option.value)).map((option,index)=>({...option,color:palette[index%palette.length]}));
  }
  function aggregateComparison(){
    const components=selectedComparisonOptions();
    if(!components.length)return null;
    const range=dateWindow();const seriesMaps=new Map(components.map(item=>[item.value,new Map()]));
    if(state.dimension==='anchor'){
      for(const row of data.anchorRows){const dt=data.anchorDates[row[0]];if(dt<range.start||dt>range.end)continue;const value=String(row[1]);const buckets=seriesMaps.get(value);if(buckets)addBucket(buckets,bucketKey(dt,state.granularity),dt,targetValueAt(row));}
    }else{
      for(const row of data.rows){const dt=data.dates[row[0]];if(dt<range.start||dt>range.end)continue;const value=state.dimension==='group'?String(row[2]):String(row[1]);const buckets=seriesMaps.get(value);if(buckets)addBucket(buckets,bucketKey(dt,state.granularity),dt,targetValueAt(row));}
    }
    const allKeys=[...new Set([...seriesMaps.values()].flatMap(map=>[...map.keys()]))].sort();
    const labels=allKeys.map(key=>({key,label:bucketLabel(key,state.granularity)}));
    const series=components.map(component=>{
      const buckets=seriesMaps.get(component.value)||new Map();
      return {...component,points:allKeys.map(key=>{const item=buckets.get(key);return {key,value:item?item.sum/Math.max(item.days.size,1):0,present:Boolean(item)};})};
    });
    return {labels,series};
  }
  function componentForRow(row){
    if(state.scope==='total'&&state.dimension==='anchor')return {kind:'anchor',drillValue:String(row[1])};
    if(state.scope==='total'&&state.dimension==='group'&&state.drill==='all')return {kind:'group',drillValue:String(row[2])};
    return {kind:'category',drillValue:String(row[1])};
  }
  function componentLabel(kind,value){
    if(kind==='anchor')return data.anchorOptions[Number(value)]?.name||`主播 ${value}`;
    if(kind==='group')return data.groups[Number(value)]?.name||'未匹配';
    return data.categories[Number(value)]?.name||'未知品类';
  }
  function aggregateStacks(){
    const comparison=aggregateComparison();
    if(comparison){
      return comparison.labels.map((label,index)=>{
        const parts=comparison.series.map(item=>({id:`${item.value}`,kind:null,drillValue:'all',label:item.label,value:item.points[index].value,color:item.color}));
        return {key:label.key,label:label.label,total:parts.reduce((sum,item)=>sum+item.value,0),parts};
      });
    }
    if(state.scope==='platform'){
      return aggregateMain().map(item=>({key:item.key,label:item.label,total:item.value,parts:[{id:'platform',kind:null,drillValue:'all',label:'平台 DAU（官方去重）',value:item.value,color:palette[0]}]}));
    }
    const rows=scopeRows();const totals=new Map();
    for(const row of rows){const component=componentForRow(row);const key=`${component.kind}:${component.drillValue}`;totals.set(key,(totals.get(key)||0)+targetValueAt(row));}
    const keep=new Set([...totals.entries()].sort((a,b)=>b[1]-a[1]).slice(0,8).map(item=>item[0]));
    const buckets=new Map();
    for(const row of rows){
      const component=componentForRow(row);const rawKey=`${component.kind}:${component.drillValue}`;const componentKey=keep.has(rawKey)?rawKey:'other';
      const entry={id:componentKey,kind:keep.has(rawKey)?component.kind:null,drillValue:keep.has(rawKey)?component.drillValue:'all',label:keep.has(rawKey)?componentLabel(component.kind,component.drillValue):'其他'};
      const key=bucketKey(data.dates[row[0]],state.granularity);
      const bucket=buckets.get(key)||{label:bucketLabel(key,state.granularity),values:new Map(),total:0};
      const value=targetValueAt(row);const part=bucket.values.get(componentKey)||{...entry,value:0};part.value+=value;bucket.values.set(componentKey,part);bucket.total+=value;buckets.set(key,bucket);
    }
    return [...buckets.entries()].sort((a,b)=>a[0].localeCompare(b[0])).map(([key,bucket])=>({key,label:bucket.label,total:bucket.total,parts:[...bucket.values.values()].sort((a,b)=>b.value-a.value)}));
  }
  function seriesLabel(){return state.scope==='platform'?'平台 DAU':state.scope==='revenue'?(state.dimension==='anchor'?'主播流水':'内容生态流水'):(state.dimension==='anchor'?'主播 DAU':'内容生态 DAU');}
  function svgFrame(content,height=330){
    return `<svg viewBox="0 0 960 ${height}" role="img" aria-label="自由分析 ${esc(seriesLabel())} 图表"><defs><linearGradient id="barGradient" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#62a9ff"/><stop offset="1" stop-color="#2878df"/></linearGradient></defs>${content}</svg>`;
  }
  function axisConfig(values,h=330,p={l:72,r:22,t:24,b:48}){
    const min=Math.min(...values,0),max=Math.max(...values,1),span=max-min||1;
    const x=index=>p.l+index*(960-p.l-p.r)/Math.max(values.length-1,1),y=value=>p.t+(max-value)/span*(h-p.t-p.b);
    return {w:960,h,p,min,max,span,x,y};
  }
  function legendMarkup(components){return components.map(item=>`<span><i style="background:${item.color}"></i>${esc(item.label)}</span>`).join('');}
  function drawLine(series){
    if(!series.length)return '<div class="visualization-empty">当前口径无可展示数据</div>';
    const h=330,p={l:72,r:22,t:24,b:48},values=series.map(item=>item.value),cfg=axisConfig(values,h,p),{x,y,min,max,span}=cfg;
    const grid=Array.from({length:5},(_,index)=>{const value=max-span*index/4,pos=y(value);return `<line class="grid" x1="${p.l}" x2="${960-p.r}" y1="${pos}" y2="${pos}"/><text class="axis" x="${p.l-8}" y="${pos+4}" text-anchor="end">${fmt(value)}</text>`;}).join('');
    const path=series.map((item,index)=>`${index?'L':'M'}${x(index)},${y(item.value)}`).join(' ');
    const dots=series.map((item,index)=>{const text=`${item.label} · ${seriesLabel()}：${fmt(item.value)}`;return `<circle class="dot-hit" cx="${x(index)}" cy="${y(item.value)}" r="13" data-tooltip="${esc(text)}"><title>${esc(text)}</title></circle><circle class="dot" cx="${x(index)}" cy="${y(item.value)}" r="4" pointer-events="none"/>`;}).join('');
    const ticks=new Set(tickIndexes(series.length,8));const labels=series.map((item,index)=>ticks.has(index)?`<text class="axis" x="${x(index)}" y="${h-12}" text-anchor="${index===0?'start':index===series.length-1?'end':'middle'}">${esc(item.label)}</text>`:'').join('');
    return svgFrame(grid+`<path class="line-path" d="${path}" style="stroke:${palette[0]}" pointer-events="none"/>`+dots+labels,h);
  }
  function drawBars(series){
    if(!series.length)return '<div class="visualization-empty">当前口径无可展示数据</div>';
    const h=330,p={l:72,r:22,t:24,b:48},max=Math.max(...series.map(item=>item.value),1),bw=(960-p.l-p.r)/Math.max(series.length,1)*.62;
    const grid=Array.from({length:5},(_,index)=>{const value=max*(4-index)/4,pos=p.t+index*(h-p.t-p.b)/4;return `<line class="grid" x1="${p.l}" x2="${960-p.r}" y1="${pos}" y2="${pos}"/><text class="axis" x="${p.l-8}" y="${pos+4}" text-anchor="end">${fmt(value)}</text>`;}).join('');
    const bars=series.map((item,index)=>{const cx=p.l+(index+.5)*(960-p.l-p.r)/Math.max(series.length,1);const barH=(h-p.t-p.b)*item.value/max;const text=`${item.label} · ${seriesLabel()}：${fmt(item.value)}`;return `<rect class="bar" x="${cx-bw/2}" y="${h-p.b-barH}" width="${bw}" height="${Math.max(barH,1)}" data-tooltip="${esc(text)}"><title>${esc(text)}</title></rect>`;}).join('');
    const ticks=new Set(tickIndexes(series.length,8));const labels=series.map((item,index)=>ticks.has(index)?`<text class="axis" x="${p.l+(index+.5)*(960-p.l-p.r)/Math.max(series.length,1)}" y="${h-12}" text-anchor="middle">${esc(item.label)}</text>`:'').join('');
    return svgFrame(grid+bars+labels,h);
  }
  function drawMultiLine(comparison){
    if(!comparison?.labels?.length)return '<div class="visualization-empty">请选择至少一个对比对象</div>';
    const h=360,p={l:72,r:22,t:32,b:58},labels=comparison.labels,allValues=comparison.series.flatMap(item=>item.points.map(point=>point.value));
    const cfg=axisConfig(allValues,h,p),{x,y,min,max,span}=cfg;
    const grid=Array.from({length:5},(_,index)=>{const value=max-span*index/4,pos=y(value);return `<line class="grid" x1="${p.l}" x2="${960-p.r}" y1="${pos}" y2="${pos}"/><text class="axis" x="${p.l-8}" y="${pos+4}" text-anchor="end">${fmt(value)}</text>`;}).join('');
    const paths=comparison.series.map(item=>{const path=item.points.map((point,index)=>`${index?'L':'M'}${x(index)},${y(point.value)}`).join(' ');return `<path class="line-path" d="${path}" style="stroke:${item.color}" pointer-events="none"/>`;}).join('');
    const dots=comparison.series.map(item=>item.points.map((point,index)=>{if(!point.present)return '';const text=`${item.label} · ${labels[index].label} · ${seriesLabel()}：${fmt(point.value)}`;return `<circle class="dot-hit" cx="${x(index)}" cy="${y(point.value)}" r="11" data-tooltip="${esc(text)}"><title>${esc(text)}</title></circle><circle class="dot" cx="${x(index)}" cy="${y(point.value)}" r="3.4" style="stroke:${item.color}" pointer-events="none"/>`;}).join('')).join('');
    const ticks=new Set(tickIndexes(labels.length,8));const labelMarkup=labels.map((item,index)=>ticks.has(index)?`<text class="axis" x="${x(index)}" y="${h-16}" text-anchor="${index===0?'start':index===labels.length-1?'end':'middle'}">${esc(item.label)}</text>`:'').join('');
    return svgFrame(grid+paths+dots+labelMarkup,h);
  }
  function drawMultiBars(comparison){
    if(!comparison?.labels?.length)return '<div class="visualization-empty">请选择至少一个对比对象</div>';
    const h=360,p={l:72,r:22,t:32,b:58},labels=comparison.labels,max=Math.max(...comparison.series.flatMap(item=>item.points.map(point=>point.value)),1);
    const grid=Array.from({length:5},(_,index)=>{const value=max*(4-index)/4,pos=p.t+index*(h-p.t-p.b)/4;return `<line class="grid" x1="${p.l}" x2="${960-p.r}" y1="${pos}" y2="${pos}"/><text class="axis" x="${p.l-8}" y="${pos+4}" text-anchor="end">${fmt(value)}</text>`;}).join('');
    const slot=(960-p.l-p.r)/Math.max(labels.length,1),groupWidth=Math.min(slot*.78,54),barWidth=Math.max(2,groupWidth/Math.max(comparison.series.length,1)-2);
    const bars=labels.map((label,index)=>{const left=p.l+index*slot+(slot-groupWidth)/2;return comparison.series.map((item,seriesIndex)=>{const value=item.points[index]?.value||0,barH=(h-p.t-p.b)*value/max,xPos=left+seriesIndex*(barWidth+2),text=`${item.label} · ${label.label} · ${seriesLabel()}：${fmt(value)}`;return `<rect class="bar" style="fill:${item.color}" x="${xPos}" y="${h-p.b-barH}" width="${barWidth}" height="${Math.max(barH,1)}" data-tooltip="${esc(text)}"><title>${esc(text)}</title></rect>`;}).join('');}).join('');
    const ticks=new Set(tickIndexes(labels.length,8));const labelMarkup=labels.map((item,index)=>ticks.has(index)?`<text class="axis" x="${p.l+(index+.5)*slot}" y="${h-16}" text-anchor="middle">${esc(item.label)}</text>`:'').join('');
    return svgFrame(grid+bars+labelMarkup,h);
  }
  function drawStacks(buckets){
    if(!buckets?.length)return drawBars(aggregateMain());
    const h=330,p={l:58,r:22,t:24,b:48},slot=(960-p.l-p.r)/Math.max(buckets.length,1),bw=Math.min(54,slot*.58);
    const componentSet=new Map();for(const bucket of buckets)for(const part of bucket.parts)componentSet.set(part.id,part);
    const components=[...componentSet.entries()].map(([id,part],index)=>({...part,id,color:part.color||palette[index%palette.length]})),colors=new Map(components.map(item=>[item.id,item.color]));
    const grid=Array.from({length:5},(_,index)=>{const value=100-index*25,pos=p.t+index*(h-p.t-p.b)/4;return `<line class="grid" x1="${p.l}" x2="${960-p.r}" y1="${pos}" y2="${pos}"/><text class="axis" x="${p.l-8}" y="${pos+4}" text-anchor="end">${value}%</text>`;}).join('');
    const bars=buckets.map((bucket,index)=>{let cursor=h-p.b;const cx=p.l+(index+.5)*slot;return bucket.parts.map(part=>{const share=bucket.total?part.value/bucket.total:0,height=share*(h-p.t-p.b);cursor-=height;const action=part.kind?` data-drill-dim="${part.kind}" data-drill-value="${part.drillValue}"` : '';const text=`${bucket.label} · ${part.label}：${fmt(part.value)}（${(share*100).toFixed(1)}%）`;return `<rect class="stack-segment"${action} fill="${colors.get(part.id)}" x="${cx-bw/2}" y="${cursor}" width="${bw}" height="${Math.max(height,.5)}" rx="4" data-tooltip="${esc(text)}"><title>${esc(text)}</title></rect>`;}).join('');}).join('');
    const ticks=new Set(tickIndexes(buckets.length,8));const labels=buckets.map((bucket,index)=>ticks.has(index)?`<text class="axis" x="${p.l+(index+.5)*slot}" y="${h-12}" text-anchor="middle">${esc(bucket.label)}</text>`:'').join('');
    legendHost.innerHTML=components.map(item=>`<span><i style="background:${item.color}"></i>${esc(item.label)}</span>`).join('');return svgFrame(grid+bars+labels,h);
  }
  function scopeTrail(){
    const root={label:'大盘',dimension:'none',drill:'all'};
    const comparison=aggregateComparison();
    if(state.scope==='platform')return [root,{label:'平台 DAU（官方）',dimension:'none',drill:'all'}];
    if(state.scope==='revenue')return comparison?[root,{label:'内容生态流水',dimension:'group',drill:'all'},{label:`${dimensionSelect.selectedOptions[0]?.textContent||'对象'}对比 · 已选 ${comparison.series.length} 个`,dimension:state.dimension,drill:'all'}]:[root,{label:'内容生态流水',dimension:'none',drill:'all'}];
    if(comparison)return [root,{label:'内容生态 DAU',dimension:'group',drill:'all'},{label:`${dimensionSelect.selectedOptions[0]?.textContent||'对象'}对比 · 已选 ${comparison.series.length} 个`,dimension:state.dimension,drill:'all'}];
    if(state.scope==='total'&&state.dimension==='group'&&state.drill!=='all')return [root,{label:'内容生态 DAU',dimension:'group',drill:'all'},{label:componentLabel('group',state.drill),dimension:'group',drill:state.drill}];
    if(state.scope==='total'&&state.dimension==='category'&&state.drill!=='all'){
      const category=data.categories[Number(state.drill)];return [root,{label:'内容生态 DAU',dimension:'group',drill:'all'},{label:componentLabel('group',String(category.group)),dimension:'group',drill:String(category.group)},{label:category.name,dimension:'category',drill:state.drill}];
    }
    return [root,{label:'内容生态 DAU',dimension:'none',drill:'all'}];
  }
  function applyDrill(dimension,drill){
    state.scope='total';scopeSelect.value='total';state.dimension=dimension==='none'?'group':dimension;state.range='all';rangeSelect.value='all';state.selected=new Set([dimension==='none'?'all':String(drill)]);state.drill=String(drill);updateDrillControls(false);render();
  }
  function hideTooltip(){tooltip.classList.remove('visible');}
  function showTooltip(text,event){
    tooltip.textContent=text;tooltip.classList.add('visible');
    const margin=14,padding=12;let left=event.clientX+margin,top=event.clientY+margin;
    const width=tooltip.offsetWidth,height=tooltip.offsetHeight;
    if(left+width>innerWidth-padding)left=event.clientX-width-margin;
    if(top+height>innerHeight-padding)top=event.clientY-height-margin;
    tooltip.style.left=`${Math.max(padding,left)}px`;tooltip.style.top=`${Math.max(padding,top)}px`;
  }
  function render(){
    hideTooltip();legendHost.innerHTML='';
    const trail=scopeTrail();crumbHost.innerHTML=trail.map((item,index)=>`<button type="button" data-scope-dimension="${item.dimension}" data-scope-drill="${item.drill}">${esc(item.label)}</button>${index<trail.length-1?'<span>›</span>':''}`).join('');
    const comparison=aggregateComparison();
    if(state.chartType==='stack')chartHost.innerHTML=drawStacks(aggregateStacks());
    else if(comparison){legendHost.innerHTML=legendMarkup(comparison.series);chartHost.innerHTML=state.chartType==='bar'?drawMultiBars(comparison):drawMultiLine(comparison);}
    else{const series=aggregateMain();chartHost.innerHTML=state.chartType==='bar'?drawBars(series):drawLine(series);}
  }
  function applyRowLimit(spec){
    if(!spec.input||!spec.title)return;
    const max=Math.max(1,Math.min(50,spec.rows.length));
    let limit=Math.round(Number(spec.input.value)||spec.defaultLimit);limit=Math.max(1,Math.min(max,limit));spec.input.value=String(limit);spec.title.textContent=`${spec.label} Top${limit}`;
    spec.rows.forEach((row,index)=>{row.hidden=index>=limit;});
  }
  function applyRowLimits(){rowLimitSpecs.forEach(applyRowLimit);}

  objectList.addEventListener('change',event=>{
    const input=event.target.closest('[data-object-value]');if(!input)return;
    const value=input.dataset.objectValue;
    if(value==='all')state.selected=new Set(['all']);
    else{
      state.selected.delete('all');
      if(input.checked)state.selected.add(value);else state.selected.delete(value);
      if(state.selected.size>8)state.selected.delete(value);
      if(!state.selected.size)state.selected=new Set(['all']);
    }
    renderObjectOptions();render();
  });
  objectSearch.addEventListener('input',()=>{state.search=objectSearch.value;renderObjectOptions();});
  selectVisibleButton.addEventListener('click',()=>{
    const visible=objectOptions().filter(option=>option.value!=='all'&&fuzzyMatch(`${option.label} ${option.detail}`,state.search)).sort((a,b)=>matchScore(a,state.search)-matchScore(b,state.search)).slice(0,8);
    state.selected=new Set(visible.length?visible.map(option=>option.value):['all']);renderObjectOptions();render();
  });
  resetObjectsButton.addEventListener('click',()=>{resetObjectSelection();render();});
  scopeSelect.addEventListener('change',()=>{state.scope=scopeSelect.value;state.dimension=state.scope==='platform'?'none':'group';state.range='all';rangeSelect.value='all';updateDrillControls();render();});
  dimensionSelect.addEventListener('change',()=>{state.dimension=dimensionSelect.value;state.range='all';rangeSelect.value='all';updateDrillControls();render();});
  granSelect.addEventListener('change',()=>{state.granularity=granSelect.value;render();});
  rangeSelect.addEventListener('change',()=>{state.range=rangeSelect.value;updateDateControls();render();});
  startDateInput.addEventListener('change',()=>{state.range='custom';rangeSelect.value='custom';state.customStart=startDateInput.value;if(state.customEnd<state.customStart)state.customEnd=state.customStart;updateDateControls();render();});
  endDateInput.addEventListener('change',()=>{state.range='custom';rangeSelect.value='custom';state.customEnd=endDateInput.value;if(state.customStart>state.customEnd)state.customStart=state.customEnd;updateDateControls();render();});
  document.querySelectorAll('#visualizationChartType [data-chart-type]').forEach(button=>button.addEventListener('click',()=>{state.chartType=button.dataset.chartType;document.querySelectorAll('#visualizationChartType [data-chart-type]').forEach(item=>item.classList.toggle('active',item===button));render();}));
  chartHost.addEventListener('click',event=>{const target=event.target.closest('[data-drill-dim]');if(target)applyDrill(target.dataset.drillDim,target.dataset.drillValue);});
  chartHost.addEventListener('pointermove',event=>{const target=event.target.closest('[data-tooltip]');if(target)showTooltip(target.dataset.tooltip,event);else hideTooltip();});
  chartHost.addEventListener('pointerleave',hideTooltip);
  crumbHost.addEventListener('click',event=>{const button=event.target.closest('[data-scope-dimension]');if(button)applyDrill(button.dataset.scopeDimension,button.dataset.scopeDrill);});
  rowLimitSpecs.forEach(spec=>{spec.input?.addEventListener('input',applyRowLimits);spec.input?.addEventListener('change',applyRowLimits);});
  window.__visualizationDebug={state,aggregateMain,aggregateStacks,aggregateComparison,render,applyRowLimits,getSelected:()=>selectedValues(),targetValueAt,tickIndexes,dataLength:data.rows.length,anchorDataLength:data.anchorRows.length,revenueDataLength:data.rows.filter(row=>row.length>4).length,anchorRevenueDataLength:data.anchorRows.filter(row=>row.length>3).length};
  state.drill='all';updateDrillControls();applyRowLimits();window.__visualizationReady=true;render();
})();
