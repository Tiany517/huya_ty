(async () => {
  'use strict';
  window.__visualizationScriptStarted = true;
  const palette=['#2878df','#55b7a3','#f2a65a','#e76f9a','#8d7cf3','#62a7d8','#95c85f','#cf7db9','#7b8da8'];
  const state={scope:__DEFAULT_SCOPE__,granularity:'day',chartType:'line',range:'all'};
  const fmt=value=>Number(value||0).toLocaleString('zh-CN',{maximumFractionDigits:0});
  const esc=value=>String(value??'').replace(/[&<>"']/g,ch=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
  const dateMs=value=>Date.parse(value+'T00:00:00Z');
  const iso=value=>new Date(value).toISOString().slice(0,10);
  function bucketKey(dt,granularity){
    const d=new Date(dt+'T00:00:00Z');
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
  async function loadData(){
    const encoded=document.getElementById('visualization-data-gzip').textContent.trim();
    const compressed=Uint8Array.from(atob(encoded),ch=>ch.charCodeAt(0));
    return JSON.parse(await new Response(new Blob([compressed]).stream().pipeThrough(new DecompressionStream('gzip'))).text());
  }
  const data=await loadData();
  const scopeSelect=document.getElementById('visualizationScope');
  const granSelect=document.getElementById('visualizationGranularity');
  const rangeSelect=document.getElementById('visualizationRange');
  const chartHost=document.getElementById('visualizationChart');
  const legendHost=document.getElementById('visualizationLegend');
  const crumbHost=document.getElementById('visualizationBreadcrumb');
  if(data.platform.length){const option=document.createElement('option');option.value='platform';option.textContent='平台 DAU（官方去重口径）';scopeSelect.append(option);}
  const totalOption=document.createElement('option');totalOption.value='total';totalOption.textContent='内容生态 DAU（品类合计）';scopeSelect.append(totalOption);
  for(const group of data.groups){const option=document.createElement('option');option.value=`group:${group.id}`;option.textContent=`内容大类 · ${group.name}`;scopeSelect.append(option);}
  for(const group of data.groups){
    const optgroup=document.createElement('optgroup');optgroup.label=`品类 · ${group.name}`;
    data.categories.forEach((category,index)=>{if(category.group!==Number(group.id))return;const option=document.createElement('option');option.value=`category:${index}`;option.textContent=category.name;optgroup.append(option);});
    if(optgroup.children.length)scopeSelect.append(optgroup);
  }
  scopeSelect.value=data.defaultScope;
  function cutoffDate(){
    if(state.range==='all')return data.availableStart;
    const end=dateMs(data.reportDate);const days=Number(state.range);return iso(end-days*86400000);
  }
  function scopeRows(){
    const cutoff=cutoffDate();
    if(state.scope==='platform')return [];
    if(state.scope==='total')return data.rows.filter(row=>data.dates[row[0]]>=cutoff);
    if(state.scope.startsWith('group:')){const group=Number(state.scope.split(':')[1]);return data.rows.filter(row=>row[2]===group&&data.dates[row[0]]>=cutoff);}
    const category=Number(state.scope.split(':')[1]);return data.rows.filter(row=>row[1]===category&&data.dates[row[0]]>=cutoff);
  }
  function aggregateMain(){
    if(state.scope==='platform'){
      const cutoff=cutoffDate();const buckets=new Map();
      for(const [dt,value] of data.platform){if(dt<cutoff||dt>data.reportDate)continue;const key=bucketKey(dt,state.granularity);const item=buckets.get(key)||{sum:0,days:new Set()};item.sum+=value;item.days.add(dt);buckets.set(key,item);}
      return [...buckets.entries()].sort((a,b)=>a[0].localeCompare(b[0])).map(([key,item])=>({key,label:bucketLabel(key,state.granularity),value:item.sum/Math.max(item.days.size,1)}));
    }
    const buckets=new Map();
    for(const row of scopeRows()){const key=bucketKey(data.dates[row[0]],state.granularity);const item=buckets.get(key)||{sum:0,days:new Set()};item.sum+=row[3];item.days.add(data.dates[row[0]]);buckets.set(key,item);}
    return [...buckets.entries()].sort((a,b)=>a[0].localeCompare(b[0])).map(([key,item])=>({key,label:bucketLabel(key,state.granularity),value:item.sum/Math.max(item.days.size,1)}));
  }
  function categoryTotals(rows){
    const totals=new Map();for(const row of rows){const key=state.scope.startsWith('group:')?row[1]:row[2];totals.set(key,(totals.get(key)||0)+row[3]);}return totals;
  }
  function aggregateStacks(){
    let rows=scopeRows();
    if(state.scope==='platform'){
      return aggregateMain().map(item=>({key:item.key,label:item.label,total:item.value,parts:[{id:'platform',label:'平台 DAU（官方去重）',value:item.value}]}));
    }
    const totals=categoryTotals(rows);const ranked=[...totals.entries()].sort((a,b)=>b[1]-a[1]);const limit=8;const keep=new Set(ranked.slice(0,limit).map(item=>item[0]));
    const series=new Map();const buckets=new Map();
    function labelFor(key){
      if(state.scope.startsWith('group:'))return data.categories[key]?.name||'未知品类';
      return data.groups[key]?.name||'未匹配';
    }
    for(const row of rows){
      const rawKey=state.scope.startsWith('group:')?row[1]:row[2];const component=keep.has(rawKey)?rawKey:'other';const label=component==='other'?'其他':labelFor(rawKey);const key=bucketKey(data.dates[row[0]],state.granularity);
      const bucket=buckets.get(key)||{label:bucketLabel(key,state.granularity),values:new Map(),total:0};const entry=bucket.values.get(component)||{label,value:0};entry.value+=row[3];bucket.values.set(component,entry);bucket.total+=row[3];buckets.set(key,bucket);
    }
    return [...buckets.entries()].sort((a,b)=>a[0].localeCompare(b[0])).map(([key,bucket])=>({key,label:bucket.label,total:bucket.total,parts:[...bucket.values.entries()].map(([id,item])=>({id:String(id),label:item.label,value:item.value})).sort((a,b)=>b.value-a.value)}));
  }
  function svgFrame(content,height=330){
    return `<svg viewBox="0 0 960 ${height}" role="img" aria-label="自由分析 DAU 图表"><defs><linearGradient id="barGradient" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#62a9ff"/><stop offset="1" stop-color="#2878df"/></linearGradient></defs>${content}</svg>`;
  }
  function drawLine(series){
    if(!series.length)return '<div class="visualization-empty">当前口径无可展示数据</div>';
    const w=960,h=330,p={l:72,r:22,t:24,b:48},values=series.map(item=>item.value),min=Math.min(...values,0),max=Math.max(...values,1),span=max-min||1;
    const x=index=>p.l+index*(w-p.l-p.r)/Math.max(series.length-1,1),y=value=>p.t+(max-value)/span*(h-p.t-p.b);
    const grid=Array.from({length:5},(_,index)=>{const value=max-span*index/4,pos=y(value);return `<line class="grid" x1="${p.l}" x2="${w-p.r}" y1="${pos}" y2="${pos}"/><text class="axis" x="${p.l-8}" y="${pos+4}" text-anchor="end">${fmt(value)}</text>`;}).join('');
    const path=series.map((item,index)=>`${index?'L':'M'}${x(index)},${y(item.value)}`).join(' ');
    const dots=series.map((item,index)=>`<circle class="dot" cx="${x(index)}" cy="${y(item.value)}" r="4"><title>${esc(item.label)}：${fmt(item.value)}</title></circle>`).join('');
    const step=Math.max(1,Math.ceil(series.length/10));const labels=series.map((item,index)=>index%step===0||index===series.length-1?`<text class="axis" x="${x(index)}" y="${h-12}" text-anchor="${index===0?'start':index===series.length-1?'end':'middle'}">${esc(item.label)}</text>`:'').join('');
    return svgFrame(grid+`<path class="line-path" d="${path}"/>`+dots+labels);
  }
  function drawBars(series){
    if(!series.length)return '<div class="visualization-empty">当前口径无可展示数据</div>';
    const w=960,h=330,p={l:72,r:22,t:24,b:48},values=series.map(item=>item.value),max=Math.max(...values,1),bw=(w-p.l-p.r)/Math.max(series.length,1)*0.62;
    const grid=Array.from({length:5},(_,index)=>{const value=max*(4-index)/4,pos=p.t+index*(h-p.t-p.b)/4;return `<line class="grid" x1="${p.l}" x2="${w-p.r}" y1="${pos}" y2="${pos}"/><text class="axis" x="${p.l-8}" y="${pos+4}" text-anchor="end">${fmt(value)}</text>`;}).join('');
    const bars=series.map((item,index)=>{const cx=p.l+(index+.5)*(w-p.l-p.r)/Math.max(series.length,1);const barH=(h-p.t-p.b)*item.value/max;return `<rect class="bar" x="${cx-bw/2}" y="${h-p.b-barH}" width="${bw}" height="${Math.max(barH,1)}"><title>${esc(item.label)}：${fmt(item.value)}</title></rect>`;}).join('');
    const step=Math.max(1,Math.ceil(series.length/10));const labels=series.map((item,index)=>index%step===0||index===series.length-1?`<text class="axis" x="${p.l+(index+.5)*(w-p.l-p.r)/Math.max(series.length,1)}" y="${h-12}" text-anchor="middle">${esc(item.label)}</text>`:'').join('');
    return svgFrame(grid+bars+labels);
  }
  function drawStacks(buckets){
    if(!buckets?.length)return drawBars(aggregateMain());
    const w=960,h=330,p={l:58,r:22,t:24,b:48},slot=(w-p.l-p.r)/Math.max(buckets.length,1),bw=Math.min(54,slot*.58);
    const componentSet=new Map();for(const bucket of buckets)for(const part of bucket.parts)componentSet.set(part.id,part.label);
    const components=[...componentSet.entries()].map(([id,label],index)=>({id,label,color:palette[index%palette.length]}));const colors=new Map(components.map(item=>[item.id,item.color]));
    const grid=Array.from({length:5},(_,index)=>{const value=100-index*25,pos=p.t+index*(h-p.t-p.b)/4;return `<line class="grid" x1="${p.l}" x2="${w-p.r}" y1="${pos}" y2="${pos}"/><text class="axis" x="${p.l-8}" y="${pos+4}" text-anchor="end">${value}%</text>`;}).join('');
    const bars=buckets.map((bucket,index)=>{let cursor=h-p.b;const cx=p.l+(index+.5)*slot;return bucket.parts.map(part=>{const share=bucket.total?part.value/bucket.total:0;const height=share*(h-p.t-p.b);cursor-=height;const drillId=part.id==='other'?null:part.id;const action=drillId===null?'':state.scope==='total'?` data-drill-group="${drillId}"`:state.scope.startsWith('group:')?` data-drill-category="${drillId}"`:'';return `<rect class="stack-segment" ${action} fill="${colors.get(part.id)}" x="${cx-bw/2}" y="${cursor}" width="${bw}" height="${Math.max(height,.5)}" rx="4"><title>${esc(bucket.label)} · ${esc(part.label)}：${fmt(part.value)}（${(share*100).toFixed(1)}%）</title></rect>`;}).join('');}).join('');
    const step=Math.max(1,Math.ceil(buckets.length/10));const labels=buckets.map((bucket,index)=>index%step===0||index===buckets.length-1?`<text class="axis" x="${p.l+(index+.5)*slot}" y="${h-12}" text-anchor="middle">${esc(bucket.label)}</text>`:'').join('');
    legendHost.innerHTML=components.map(item=>`<span><i style="background:${item.color}"></i>${esc(item.label)}</span>`).join('');return svgFrame(grid+bars+labels);
  }
  function scopeTrail(){
    if(state.scope==='platform')return [{label:'大盘',scope:'platform'},{label:'平台 DAU（官方）',scope:'platform'}];
    if(state.scope==='total')return [{label:'大盘',scope:'total'},{label:'内容生态 DAU',scope:'total'}];
    if(state.scope.startsWith('group:')){const id=state.scope.split(':')[1];return [{label:'大盘',scope:'total'},{label:data.groups[id]?.name||'内容大类',scope:state.scope}];}
    const index=Number(state.scope.split(':')[1]),category=data.categories[index];return [{label:'大盘',scope:'total'},{label:data.groups[category.group]?.name||'内容大类',scope:`group:${category.group}`},{label:category.name,scope:state.scope}];
  }
  function render(){
    legendHost.innerHTML='';
    crumbHost.innerHTML=scopeTrail().map((item,index)=>`<button type="button" data-scope-jump="${item.scope}">${esc(item.label)}</button>${index<scopeTrail().length-1?'<span>›</span>':''}`).join('');
    if(state.chartType==='stack')chartHost.innerHTML=drawStacks(aggregateStacks());
    else{const series=aggregateMain();chartHost.innerHTML=state.chartType==='bar'?drawBars(series):drawLine(series);}
  }
  scopeSelect.addEventListener('change',()=>{state.scope=scopeSelect.value;render();});
  granSelect.addEventListener('change',()=>{state.granularity=granSelect.value;render();});
  rangeSelect.addEventListener('change',()=>{state.range=rangeSelect.value;render();});
  document.querySelectorAll('#visualizationChartType [data-chart-type]').forEach(button=>button.addEventListener('click',()=>{state.chartType=button.dataset.chartType;document.querySelectorAll('#visualizationChartType [data-chart-type]').forEach(item=>item.classList.toggle('active',item===button));render();}));
  chartHost.addEventListener('click',event=>{const group=event.target.closest('[data-drill-group]');const category=event.target.closest('[data-drill-category]');if(group){state.scope=`group:${group.dataset.drillGroup}`;scopeSelect.value=state.scope;render();}else if(category){state.scope=`category:${category.dataset.drillCategory}`;scopeSelect.value=state.scope;render();}});
  crumbHost.addEventListener('click',event=>{const button=event.target.closest('[data-scope-jump]');if(!button)return;state.scope=button.dataset.scopeJump;scopeSelect.value=state.scope;render();});
  window.__visualizationDebug={state,aggregateMain,aggregateStacks,render,dataLength:data.rows.length};
  window.__visualizationReady=true;
  render();
})();
