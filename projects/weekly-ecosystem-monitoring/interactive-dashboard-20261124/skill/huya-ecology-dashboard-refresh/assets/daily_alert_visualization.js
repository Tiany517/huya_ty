(async () => {
  'use strict';
  window.__visualizationScriptStarted = true;
  const palette=['#2878df','#55b7a3','#f2a65a','#e76f9a','#8d7cf3','#62a7d8','#95c85f','#cf7db9','#7b8da8'];
  const state={scope:__DEFAULT_SCOPE__,dimension:'none',drill:'all',granularity:'day',chartType:'line',range:'all'};
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
  const dimensionSelect=document.getElementById('visualizationDimension');
  const drillSelect=document.getElementById('visualizationDrillValue');
  const granSelect=document.getElementById('visualizationGranularity');
  const rangeSelect=document.getElementById('visualizationRange');
  const chartHost=document.getElementById('visualizationChart');
  const legendHost=document.getElementById('visualizationLegend');
  const crumbHost=document.getElementById('visualizationBreadcrumb');
  const tooltip=document.getElementById('visualizationTooltip');
  const anchorLimitInput=document.getElementById('anchorTopLimit');
  const anchorTitle=document.getElementById('anchorTopTitle');
  const anchorTableRows=anchorLimitInput?[...document.querySelectorAll('#anchorTableBody tr')]:[];

  if(data.platform.length){scopeSelect.add(new Option('平台 DAU（官方去重口径）','platform'));}
  scopeSelect.add(new Option('内容生态 DAU（品类合计）','total'));
  scopeSelect.value=state.scope;

  function cutoffDate(){
    if(state.range==='all')return data.availableStart;
    const end=dateMs(data.reportDate);const days=Number(state.range);return iso(end-days*86400000);
  }
  function populateDrillValues(){
    drillSelect.innerHTML='';
    if(state.scope==='platform'){
      drillSelect.add(new Option('平台整体','all'));state.drill='all';drillSelect.disabled=true;return;
    }
    drillSelect.disabled=false;
    if(state.dimension==='group'){
      drillSelect.add(new Option('全部内容大类','all'));
      for(const group of data.groups)drillSelect.add(new Option(group.name,String(group.id)));
    }else if(state.dimension==='category'){
      drillSelect.add(new Option('全部品类','all'));
      for(const group of data.groups){
        const optgroup=document.createElement('optgroup');optgroup.label=group.name;
        data.categories.forEach((category,index)=>{if(category.group===Number(group.id))optgroup.append(new Option(category.name,String(index)));});
        if(optgroup.children.length)drillSelect.append(optgroup);
      }
    }else{
      drillSelect.add(new Option('内容生态整体','all'));state.drill='all';
    }
    if(![...drillSelect.options].some(option=>option.value===state.drill))state.drill='all';
    drillSelect.value=state.drill;
  }
  function updateDrillControls(){
    if(state.scope==='platform'){
      state.dimension='none';dimensionSelect.value='none';dimensionSelect.disabled=true;
    }else{
      dimensionSelect.disabled=false;
      if(state.dimension==='none')state.dimension='group';
      dimensionSelect.value=state.dimension;
    }
    populateDrillValues();
  }
  function scopeRows(){
    if(state.scope==='platform')return [];
    const cutoff=cutoffDate();
    let rows=data.rows.filter(row=>data.dates[row[0]]>=cutoff);
    if(state.dimension==='group'&&state.drill!=='all')rows=rows.filter(row=>row[2]===Number(state.drill));
    if(state.dimension==='category'&&state.drill!=='all')rows=rows.filter(row=>row[1]===Number(state.drill));
    return rows;
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
  function componentForRow(row){
    if(state.scope==='total'&&state.dimension==='group'&&state.drill==='all')return {kind:'group',drillValue:String(row[2])};
    return {kind:'category',drillValue:String(row[1])};
  }
  function componentLabel(kind,value){
    if(kind==='group')return data.groups[Number(value)]?.name||'未匹配';
    return data.categories[Number(value)]?.name||'未知品类';
  }
  function aggregateStacks(){
    if(state.scope==='platform'){
      return aggregateMain().map(item=>({key:item.key,label:item.label,total:item.value,parts:[{id:'platform',kind:null,drillValue:'all',label:'平台 DAU（官方去重）',value:item.value}]}));
    }
    const rows=scopeRows();const totals=new Map();
    for(const row of rows){const component=componentForRow(row);const key=`${component.kind}:${component.drillValue}`;totals.set(key,(totals.get(key)||0)+row[3]);}
    const keep=new Set([...totals.entries()].sort((a,b)=>b[1]-a[1]).slice(0,8).map(item=>item[0]));
    const buckets=new Map();
    for(const row of rows){
      const component=componentForRow(row);const rawKey=`${component.kind}:${component.drillValue}`;const componentKey=keep.has(rawKey)?rawKey:'other';
      const entry={id:componentKey,kind:keep.has(rawKey)?component.kind:null,drillValue:keep.has(rawKey)?component.drillValue:'all',label:keep.has(rawKey)?componentLabel(component.kind,component.drillValue):'其他'};
      const key=bucketKey(data.dates[row[0]],state.granularity);
      const bucket=buckets.get(key)||{label:bucketLabel(key,state.granularity),values:new Map(),total:0};
      const part=bucket.values.get(componentKey)||{...entry,value:0};part.value+=row[3];bucket.values.set(componentKey,part);bucket.total+=row[3];buckets.set(key,bucket);
    }
    return [...buckets.entries()].sort((a,b)=>a[0].localeCompare(b[0])).map(([key,bucket])=>({key,label:bucket.label,total:bucket.total,parts:[...bucket.values.values()].sort((a,b)=>b.value-a.value)}));
  }
  function seriesLabel(){return state.scope==='platform'?'平台 DAU':state.dimension==='none'?'内容生态 DAU':'内容生态 DAU（已下钻）';}
  function svgFrame(content,height=330){
    return `<svg viewBox="0 0 960 ${height}" role="img" aria-label="自由分析 DAU 图表"><defs><linearGradient id="barGradient" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#62a9ff"/><stop offset="1" stop-color="#2878df"/></linearGradient></defs>${content}</svg>`;
  }
  function drawLine(series){
    if(!series.length)return '<div class="visualization-empty">当前口径无可展示数据</div>';
    const w=960,h=330,p={l:72,r:22,t:24,b:48},values=series.map(item=>item.value),min=Math.min(...values,0),max=Math.max(...values,1),span=max-min||1;
    const x=index=>p.l+index*(w-p.l-p.r)/Math.max(series.length-1,1),y=value=>p.t+(max-value)/span*(h-p.t-p.b);
    const grid=Array.from({length:5},(_,index)=>{const value=max-span*index/4,pos=y(value);return `<line class="grid" x1="${p.l}" x2="${w-p.r}" y1="${pos}" y2="${pos}"/><text class="axis" x="${p.l-8}" y="${pos+4}" text-anchor="end">${fmt(value)}</text>`;}).join('');
    const path=series.map((item,index)=>`${index?'L':'M'}${x(index)},${y(item.value)}`).join(' ');
    const dots=series.map((item,index)=>{const text=`${item.label} · ${seriesLabel()}：${fmt(item.value)}`;return `<circle class="dot-hit" cx="${x(index)}" cy="${y(item.value)}" r="13" data-tooltip="${esc(text)}"><title>${esc(text)}</title></circle><circle class="dot" cx="${x(index)}" cy="${y(item.value)}" r="4" pointer-events="none"/>`;}).join('');
    const step=Math.max(1,Math.ceil(series.length/10));const labels=series.map((item,index)=>index%step===0||index===series.length-1?`<text class="axis" x="${x(index)}" y="${h-12}" text-anchor="${index===0?'start':index===series.length-1?'end':'middle'}">${esc(item.label)}</text>`:'').join('');
    return svgFrame(grid+`<path class="line-path" d="${path}" pointer-events="none"/>`+dots+labels);
  }
  function drawBars(series){
    if(!series.length)return '<div class="visualization-empty">当前口径无可展示数据</div>';
    const w=960,h=330,p={l:72,r:22,t:24,b:48},values=series.map(item=>item.value),max=Math.max(...values,1),bw=(w-p.l-p.r)/Math.max(series.length,1)*0.62;
    const grid=Array.from({length:5},(_,index)=>{const value=max*(4-index)/4,pos=p.t+index*(h-p.t-p.b)/4;return `<line class="grid" x1="${p.l}" x2="${w-p.r}" y1="${pos}" y2="${pos}"/><text class="axis" x="${p.l-8}" y="${pos+4}" text-anchor="end">${fmt(value)}</text>`;}).join('');
    const bars=series.map((item,index)=>{const cx=p.l+(index+.5)*(w-p.l-p.r)/Math.max(series.length,1);const barH=(h-p.t-p.b)*item.value/max;const text=`${item.label} · ${seriesLabel()}：${fmt(item.value)}`;return `<rect class="bar" x="${cx-bw/2}" y="${h-p.b-barH}" width="${bw}" height="${Math.max(barH,1)}" data-tooltip="${esc(text)}"><title>${esc(text)}</title></rect>`;}).join('');
    const step=Math.max(1,Math.ceil(series.length/10));const labels=series.map((item,index)=>index%step===0||index===series.length-1?`<text class="axis" x="${p.l+(index+.5)*(w-p.l-p.r)/Math.max(series.length,1)}" y="${h-12}" text-anchor="middle">${esc(item.label)}</text>`:'').join('');
    return svgFrame(grid+bars+labels);
  }
  function drawStacks(buckets){
    if(!buckets?.length)return drawBars(aggregateMain());
    const w=960,h=330,p={l:58,r:22,t:24,b:48},slot=(w-p.l-p.r)/Math.max(buckets.length,1),bw=Math.min(54,slot*.58);
    const componentSet=new Map();for(const bucket of buckets)for(const part of bucket.parts)componentSet.set(part.id,part);
    const components=[...componentSet.entries()].map(([id,part],index)=>({...part,id,color:palette[index%palette.length]}));const colors=new Map(components.map(item=>[item.id,item.color]));
    const grid=Array.from({length:5},(_,index)=>{const value=100-index*25,pos=p.t+index*(h-p.t-p.b)/4;return `<line class="grid" x1="${p.l}" x2="${w-p.r}" y1="${pos}" y2="${pos}"/><text class="axis" x="${p.l-8}" y="${pos+4}" text-anchor="end">${value}%</text>`;}).join('');
    const bars=buckets.map((bucket,index)=>{let cursor=h-p.b;const cx=p.l+(index+.5)*slot;return bucket.parts.map(part=>{const share=bucket.total?part.value/bucket.total:0;const height=share*(h-p.t-p.b);cursor-=height;const action=part.kind?` data-drill-dim="${part.kind}" data-drill-value="${part.drillValue}"` : '';const text=`${bucket.label} · ${part.label}：${fmt(part.value)}（${(share*100).toFixed(1)}%）`;return `<rect class="stack-segment"${action} fill="${colors.get(part.id)}" x="${cx-bw/2}" y="${cursor}" width="${bw}" height="${Math.max(height,.5)}" rx="4" data-tooltip="${esc(text)}"><title>${esc(text)}</title></rect>`;}).join('');}).join('');
    const step=Math.max(1,Math.ceil(buckets.length/10));const labels=buckets.map((bucket,index)=>index%step===0||index===buckets.length-1?`<text class="axis" x="${p.l+(index+.5)*slot}" y="${h-12}" text-anchor="middle">${esc(bucket.label)}</text>`:'').join('');
    legendHost.innerHTML=components.map(item=>`<span><i style="background:${item.color}"></i>${esc(item.label)}</span>`).join('');return svgFrame(grid+bars+labels);
  }
  function scopeTrail(){
    const root={label:'大盘',dimension:'none',drill:'all'};
    if(state.scope==='platform')return [root,{label:'平台 DAU（官方）',dimension:'none',drill:'all'}];
    if(state.scope==='total'&&state.dimension==='group'&&state.drill!=='all')return [root,{label:'内容生态 DAU',dimension:'group',drill:'all'},{label:componentLabel('group',state.drill),dimension:'group',drill:state.drill}];
    if(state.scope==='total'&&state.dimension==='category'&&state.drill!=='all'){
      const category=data.categories[Number(state.drill)];return [root,{label:'内容生态 DAU',dimension:'group',drill:'all'},{label:componentLabel('group',String(category.group)),dimension:'group',drill:String(category.group)},{label:category.name,dimension:'category',drill:state.drill}];
    }
    return [root,{label:'内容生态 DAU',dimension:'none',drill:'all'}];
  }
  function applyDrill(dimension,drill){
    state.scope='total';scopeSelect.value='total';state.dimension=dimension==='none'?'group':dimension;state.drill=dimension==='none'?'all':String(drill);updateDrillControls();render();
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
    if(state.chartType==='stack')chartHost.innerHTML=drawStacks(aggregateStacks());
    else{const series=aggregateMain();chartHost.innerHTML=state.chartType==='bar'?drawBars(series):drawLine(series);}
  }
  function applyAnchorLimit(){
    if(!anchorLimitInput||!anchorTitle)return;
    const max=Math.max(1,Math.min(50,anchorTableRows.length));
    let limit=Math.round(Number(anchorLimitInput.value)||10);limit=Math.max(1,Math.min(max,limit));anchorLimitInput.value=String(limit);anchorTitle.textContent=`主播 Top${limit}`;
    anchorTableRows.forEach((row,index)=>{row.hidden=index>=limit;});
  }
  scopeSelect.addEventListener('change',()=>{state.scope=scopeSelect.value;state.dimension=state.scope==='platform'?'none':'group';state.drill='all';updateDrillControls();render();});
  dimensionSelect.addEventListener('change',()=>{state.dimension=dimensionSelect.value;state.drill='all';updateDrillControls();render();});
  drillSelect.addEventListener('change',()=>{state.drill=drillSelect.value;render();});
  granSelect.addEventListener('change',()=>{state.granularity=granSelect.value;render();});
  rangeSelect.addEventListener('change',()=>{state.range=rangeSelect.value;render();});
  document.querySelectorAll('#visualizationChartType [data-chart-type]').forEach(button=>button.addEventListener('click',()=>{state.chartType=button.dataset.chartType;document.querySelectorAll('#visualizationChartType [data-chart-type]').forEach(item=>item.classList.toggle('active',item===button));render();}));
  chartHost.addEventListener('click',event=>{const target=event.target.closest('[data-drill-dim]');if(target)applyDrill(target.dataset.drillDim,target.dataset.drillValue);});
  chartHost.addEventListener('pointermove',event=>{const target=event.target.closest('[data-tooltip]');if(target)showTooltip(target.dataset.tooltip,event);else hideTooltip();});
  chartHost.addEventListener('pointerleave',hideTooltip);
  crumbHost.addEventListener('click',event=>{const button=event.target.closest('[data-scope-dimension]');if(button)applyDrill(button.dataset.scopeDimension,button.dataset.scopeDrill);});
  anchorLimitInput?.addEventListener('input',applyAnchorLimit);
  anchorLimitInput?.addEventListener('change',applyAnchorLimit);
  window.__visualizationDebug={state,aggregateMain,aggregateStacks,render,applyAnchorLimit,dataLength:data.rows.length};
  updateDrillControls();applyAnchorLimit();window.__visualizationReady=true;render();
})();
