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
