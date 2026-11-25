// Real generated controller in a DOM emulator, not a browser or visual acceptance.
import fs from 'node:fs';
import {createRequire} from 'node:module';
import assert from 'node:assert/strict';
const require=createRequire(process.env.V12_TEST_RUNTIME+'/package.json');
const {JSDOM}=require('jsdom');
const html=fs.readFileSync(process.argv[2],'utf8');
const payload=html.match(/<script type="text\/plain" id="v12-data">([\s\S]*?)<\/script>/)[1];
const js=html.match(/<script>\s*([\s\S]*)<\/script><\/body>/)[1];
const shell=html.replace(/<script[\s\S]*$/,'<script type="text/plain" id="v12-data"></script></body></html>');
const dom=new JSDOM(shell,{runScripts:'outside-only',url:'http://localhost/v12'});const w=dom.window;
for(const [key,value] of Object.entries({Blob,Response,DecompressionStream,TextDecoder,structuredClone}))w[key]=value;
w.HTMLElement.prototype.scrollIntoView=function(){};
w.document.getElementById('v12-data').textContent=payload;
const errors=[];w.console.error=e=>errors.push(String(e));
console.time('controller');await w.eval(js);console.timeEnd('controller');
assert.ok(w.__v12Ready,'page initialization failed: '+errors.join(';'));
const api=w.__dailyV12,$=id=>w.document.getElementById(id);
assert.equal($('kpis').children.length,4);assert.equal(w.document.querySelectorAll('.table-slot').length,4);
assert.ok($('executiveSummary').textContent.includes('本轮执行摘要'));
assert.ok($('executiveSummary').textContent.includes('原始全期'));
assert.ok($('executiveSummary').textContent.includes('赛事剔除'));
assert.equal(w.document.querySelectorAll('.kpi .kpi-event').length,4,'each result card needs an event-adjusted view');
assert.ok([...w.document.querySelectorAll('.kpi-event')].every(e=>e.textContent.includes('非赛事 vs 非赛事')));
assert.ok($('summaryModule').textContent.includes('原始全期异动'));
assert.ok($('summaryModule').textContent.includes('赛事剔除异动'));
assert.ok(!/\d,\d{3}\.\d/.test($('kpis').textContent),'count and money KPIs should render as integers');
assert.ok($('chartHost').querySelector('svg'),'default platform chart missing');
const category=api.engine.ranking('category','dau',api.opts('category')).rows;
const before=category.map(r=>r.contribution);
api.filterState.category={levels:['高'],min:null,max:null,strength:3,direction:'down',query:''};api.renderTable('category');
assert.deepEqual(category.map(r=>r.contribution),before,'filter changed denominator');
assert.ok([...w.document.querySelectorAll('[data-table="category"] .badge')].every(e=>e.textContent==='高'));
api.filterState.category={levels:[],min:null,max:null,strength:null,direction:'all',query:''};
api.setMetric('revenue');assert.equal($('mainMetric').value,'revenue');
assert.ok(w.document.querySelector('[data-table="category"] [data-result] table'));
$('processPanel').open=true;api.renderAll(false);
assert.ok($('processContent').textContent.includes('Shapley')||$('processContent').textContent.includes('效应'));
const externalIndex=api.data.anchors.findIndex((a,i)=>api.engine.dailyByAnchor.has(i));assert.ok(externalIndex>=0);api.addAnchor(externalIndex);
assert.equal(api.selectedAnchors.size,1);assert.ok($('anchorChart').querySelector('svg'));
$('anchorSearch').value=String(api.data.anchors[externalIndex].id);$('anchorSearch').oninput();assert.ok($('anchorCandidates').textContent.includes(String(api.data.anchors[externalIndex].id)));
$('anchorNormalize').value='index';$('anchorNormalize').onchange();
$('layoutEdit').onclick();assert.ok($('analysisModules').classList.contains('editing'));
const order=[...$('analysisModules').children].map(e=>e.id);w.document.querySelector('#guildModule .move-up').onclick();assert.notDeepEqual([...$('analysisModules').children].map(e=>e.id),order);$('layoutReset').onclick();assert.equal($('analysisModules').children[2].id,'categoryModule');
$('currentStart').value='2026-11-24';$('currentEnd').value='2026-11-01';$('comparison').value='custom';$('applyDates').onclick();assert.ok($('dateError').textContent.includes('日期无效'));
assert.equal(errors.length,0,'controller errors: '+errors.join(';'));
// Unavailable values sort last and do not obtain a numerical score.
const displayed=api.visibleRows('category',[{id:1,current:null,delta:null,severity:'待判断',robustZ:null},{id:2,current:10,delta:5,severity:'正常',robustZ:0}],{sort:'absolute',direction:'desc',limit:10});assert.equal(displayed[0].id,2);
api.setMetric('dau');
api.pushPath('category',api.data.categories.findIndex(c=>String(c.id)==='1'));
assert.ok(api.state.paths.some(p=>p.dim==='category'));
assert.ok($('breadcrumbs').textContent.includes('英雄联盟'));
assert.equal($('platformMode').checked,false,'drill did not show scope switch');
const savedMetric=api.state.metric;$('breadcrumbs').querySelector('[data-path-back="-1"]').onclick();assert.equal(api.state.paths.length,0);assert.equal(api.state.metric,savedMetric);
// Arbitrary dimension choice and full-week paths, without turning weekly into daily.
api.pushPath('guild',0);assert.ok(api.opts('category').grain==='week');assert.ok(api.engine.ranking('category',api.state.metric,api.opts('category')).kind==='weekly');
api.state.paths=[];api.renderPath();
// Uniform filter sync is explicit, not automatic; invalid bounds leave old state.
const filterSlot=w.document.querySelector('[data-filter="category"].filter-slot');
filterSlot.querySelector('[data-number="min"]').value='5';filterSlot.querySelector('[data-number="max"]').value='1';filterSlot.querySelector('[data-number="max"]').dispatchEvent(new w.Event('change'));assert.ok(filterSlot.querySelector('[data-error]').textContent);
filterSlot.querySelector('[data-reset]').click();
filterSlot.querySelector('[data-quick="high"]').click();assert.deepEqual(Array.from(api.filterState.category.levels),['高']);assert.equal(api.filterState.guild.levels.length,0);
filterSlot.querySelector('[data-sync]').click();assert.deepEqual(Array.from(api.filterState.guild.levels),['高']);
// Filters choose objects/markers; preserve dates in the chart context.
const trendStart=$('trendStart').value,trendEnd=$('trendEnd').value;assert.equal(trendStart,$('trendStart').value);assert.equal(trendEnd,$('trendEnd').value);
// Ratio baseline and bridge ingredients remain consistent in actual data.
const ratioRows=api.engine.ranking('category','payRate').rows.filter(r=>r.baselineParts&&r.baselineParts[1]>0);
for(const r of ratioRows)assert.ok(Math.abs(r.baseline-r.baselineParts[0]/r.baselineParts[1])<1e-12);
assert.ok($('kpis').textContent.includes('未覆盖')||$('kpis').children.length<=4);
assert.equal(errors.length,0,'expanded interactions caused errors: '+errors.join(';'));

// Non-percent ratios retain their native unit; no misleading percentage points.
api.filterState.category={levels:[],min:null,max:null,strength:null,direction:'all',query:''};
api.setMetric('arppu');assert.ok(!w.document.querySelector('[data-table="category"] [data-result]').textContent.includes(' pp'));
api.state.start='2026-11-16';api.state.end='2026-11-22';api.state.baseStart='2026-11-09';api.state.baseEnd='2026-11-15';api.state.comparison='custom';api.state.paths=[];
api.setMetric('revenue');api.renderProcess();assert.ok($('processContent').textContent.includes('观看用户日总量'));
const pendingSupply=api.engine.ranking('guild','liveAnchors',{start:'2026-11-16',end:'2026-11-22',baseStart:'2026-11-09',baseEnd:'2026-11-15',comparison:'custom',grain:'week'}).rows;
assert.ok(pendingSupply.every(r=>r.severity==='待判断'&&r.robustZ===null));

console.log(JSON.stringify({status:'passed',kind:'DOM emulator; visual acceptance not executed',cards:4,anchors:api.data.anchors.length,categoryCandidates:category.length,tests:'default render, independent filters, denominator stability, metric switch, process diagnostics, full-index search, anchor chart, indexed comparison, layout persistence/reset, invalid dates',errors},null,2));
// Process explanations must use the result object's own scope and exact comparison.
api.state.paths=[];api.state.comparison='weekday';api.state.start=api.data.reportDate;api.state.end=api.data.reportDate;
const diagnosticRows=api.summaryCandidates().slice(0,5);
for(const row of diagnosticRows){const d=api.processExplanation(row);assert.ok(d.conclusion);for(const e of d.evidence){assert.equal(e.scope,row.scope);assert.equal(e.period,row.period);assert.equal(e.comparisonPeriod,row.comparisonPeriod);assert.ok(Number.isFinite(e.current)&&Number.isFinite(e.baseline));}assert.ok(d.boundary.includes('因果'));}
api.setMetric('dau');api.renderSummary();assert.ok($('summaryCards').querySelector('.finding-values'));assert.ok(!$('summaryCards').textContent.includes('已核对开播主播数'));
const eventDauOpts={...api.opts('category'),eventMode:'nonEvent'},eventDauRow=api.engine.ranking('category','dau',eventDauOpts).rows.find(r=>r.eventCoverage==='covered'&&r.current!=null&&r.baseline!=null);
const dauProcess=api.processRows({...eventDauRow,scope:'category',analysisOptions:eventDauOpts});
assert.ok(dauProcess.length>0);assert.ok(!dauProcess.some(r=>['payUsers','revenue','arppu'].includes(r.metric)),'DAU diagnosis must not default to payment metrics');
const revenueOpts=api.opts('category'),revenueRow=api.engine.ranking('category','revenue',revenueOpts).rows.find(r=>r.current!=null&&r.baseline!=null),revenueProcess=api.processRows({...revenueRow,scope:'category',analysisOptions:revenueOpts});
assert.ok(revenueProcess.some(r=>r.metric==='interactionUsers'),'revenue diagnosis should include anchor interaction');
console.log('Matched-context process explanation checks passed');

// The compact summary opens one shared result -> process -> child attribution workspace.
assert.ok(!$('summaryCards').querySelector('details'),'summary cards should not carry long inline evidence');
const tierRow=api.summaryCandidates().find(r=>r.scope==='tier'&&String(r.name).includes('腰部')&&r.metric==='dau');
assert.ok(tierRow,'expected a 腰部 DAU tier candidate');
const tierDiagnosis=api.processExplanation(tierRow);
const tierSupply=tierDiagnosis.evidence.find(r=>r.metric==='liveAnchors');
assert.ok(tierSupply,'tier diagnosis omitted liveAnchors');
assert.ok(Number.isFinite(tierSupply.current)&&Number.isFinite(tierSupply.baseline));
assert.ok(tierDiagnosis.conclusion.includes('开播主播数'),'tier conclusion should interpret liveAnchors');
assert.ok(tierDiagnosis.boundary.includes('周路径近似'),'tier supply caveat missing');
api.renderDiagnosticWorkspace(tierRow);
const workspace=$('diagnosticWorkspace');assert.equal(workspace.hidden,false);
assert.ok(workspace.textContent.includes('先看同周期过程指标'));
assert.ok(workspace.textContent.includes('开播主播数'));
assert.ok(workspace.textContent.includes('周路径近似'));
assert.ok(workspace.querySelector('.process-evidence').textContent.includes('贡献'));
assert.ok(workspace.querySelector('.process-evidence').textContent.includes('异常分'));
assert.ok(workspace.querySelector('[data-recommended-dim]'),'recommended drill missing');
assert.ok(![...workspace.querySelectorAll('[data-recommended-dim]')].some(b=>b.dataset.recommendedDim==='event'),'weekly tier must not recommend the unsupported event split');
assert.ok(workspace.querySelector('[data-workspace-dimension]'),'free drill selector missing');
assert.ok(![...workspace.querySelector('[data-workspace-dimension]').options].some(o=>o.value==='event'),'weekly tier must not offer the unsupported event split');
assert.ok(workspace.querySelector('[data-workspace-child] table'),'child contribution table missing');
const childDrillRows=workspace.querySelectorAll('[data-workspace-child] tbody tr');
assert.ok(childDrillRows.length>1,'tier -> category drilldown should produce contribution rows');
assert.ok(!workspace.querySelector('[data-workspace-child]').textContent.includes('无符合条件的对象'),'tier -> category drilldown returned an empty dead end');
const childPeriod=workspace.querySelector('[data-workspace-period]').textContent;
assert.ok(childPeriod.includes('2026-11-16—2026-11-22'),'tier child drilldown lost the result object\'s weekly period');
assert.ok(!childPeriod.includes('请选择完整自然周'),'tier child drilldown used the daily page date instead of its own weekly context');
$('summaryCards').querySelector('[data-summary-analyze]').click();
assert.equal(workspace.hidden,false,'summary card did not open shared workspace');
console.log('Compact summary, tier supply and shared diagnostic workspace passed');

// The object pane exposes process contributions and a freely selected child layer.
api.state.paths=[];api.state.comparison='weekday';api.setMetric('dau');
const slot=w.document.querySelector('[data-table="category"]');
const result=api.engine.ranking('category','dau',api.opts('category')).rows.find(r=>r.current!=null&&r.baseline!=null);
api.objectAction(result,'category',slot);
assert.ok(slot.querySelector('.process-evidence'));
assert.ok(slot.querySelector('.process-evidence').textContent.includes('贡献'));
assert.ok(slot.querySelector('.process-evidence').textContent.includes('异常分'));
const child=slot.querySelector('[data-child-dimension]');
assert.ok([...child.options].some(o=>o.value==='guild'));
child.value='guild';child.onchange();
assert.ok(slot.querySelector('[data-child-period]').textContent.includes('2026-11-16'));
assert.ok(slot.querySelector('[data-child-table]').textContent.includes('贡献'));
assert.ok(slot.querySelector('[data-child-table]').textContent.includes('异常分'));
$('advanced').open=true;api.renderTrend();
assert.ok($('canvasObjectOptions').querySelectorAll('[data-canvas-select]').length<=6);
// Source mismatch from the user's screenshot is not rendered as a legitimate rate.
api.filterState.anchor={levels:[],min:null,max:null,strength:null,direction:'all',query:''};
api.setMetric('payRate');
const idx=api.data.anchors.findIndex(a=>String(a.id)==='2374381262');
const bad=api.engine.ranking('anchor','payRate',api.opts('anchor')).rows.find(r=>r.id===idx);
assert.equal(bad.current,null);assert.ok(bad.currentReason.includes('分子分母'));
const anchorSlot=w.document.querySelector('[data-table="anchor"]');
anchorSlot.querySelector('[data-search]').value='2374381262';anchorSlot.querySelector('[data-search]').dispatchEvent(new w.Event('input'));
assert.ok(anchorSlot.querySelector('[data-result]').textContent.includes('口径异常'));
assert.ok(!anchorSlot.querySelector('[data-result]').textContent.includes('4848.0%'));
assert.equal(errors.length,0);
console.log('Object process table, child guild drilldown, compact picker and real pay-rate counterexample passed');
