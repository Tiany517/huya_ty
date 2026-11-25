// Runs the actual page controller against a minimal DOM; no browser/session access.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const html=fs.readFileSync(process.argv[2],'utf8');
const packed=html.match(/id="analyst-upgrade-data">([^<]+)</)[1];
class Option {constructor(text,value){this.textContent=text;this.value=value;this.selected=false}}
class Element {
 constructor(id){this.id=id;this.value='';this.options=id==='rankGroup'?[new Option('全部','')]:[];this.textContent='';this._html='';this.handlers={}}
 add(o){this.options.push(o);if(this.options.length===1)this.value=o.value}
 set innerHTML(v){this._html=v;if(this.id==='extraCategories')this.options=[]}
 get innerHTML(){return this._html}
 get selectedOptions(){return this.options.filter(o=>o.selected)}
 addEventListener(k,fn){this.handlers[k]=fn}
}
const elements=new Map();
const defaults={rankScope:'category',rankMetric:'dau',rankMode:'standard',rankSort:'absolute',rankDirection:'desc',rankLimit:'10',extraGrain:'day',extraType:'line'};
const document={getElementById(id){if(!elements.has(id)){const e=new Element(id);e.value=defaults[id]||'';elements.set(id,e)}return elements.get(id)},querySelectorAll(){return []}};
document.getElementById('analyst-upgrade-data').textContent=packed;
const context={document,Option,Blob,Response,DecompressionStream,TextDecoder,Uint8Array,atob,window:{},console};
vm.createContext(context);
await vm.runInContext(fs.readFileSync(new URL('../assets/analyst_upgrade.js',import.meta.url),'utf8'),context);
const api=context.window.__metricUpgrade;
assert.ok(api?.ready,'controller failed to initialize');
assert.ok(document.getElementById('metricRows').innerHTML.includes('<tr>'));
for(const scope of ['category','guild','anchor','tier'])for(const metric of ['dau','revenue','interactionUsers']){
 const rows=api.data.rows.filter(r=>r.scope===scope&&r.metric===metric&&r.mode==='standard');
 assert.ok(rows.length,`${scope}/${metric} missing`);
 const gross=rows.reduce((a,r)=>a+Math.abs(r.delta),0);
 assert.ok(!gross||Math.abs(rows.reduce((a,r)=>a+Math.abs(r.contribution),0)-1)<1e-8);
 document.getElementById('rankScope').value=scope;document.getElementById('rankMetric').value=metric;api.render();
 assert.ok(document.getElementById('metricRows').innerHTML.includes('<strong>'));
}
const ca=api.data.categories.findIndex(c=>String(c.id)==='1');
for(const grain of ['day','week','month','quarter']){
 const a=api.aggregateCanvas('newUsers',[ca],'2026-09-01','2026-11-24',grain);
 assert.ok(a.length&&a.every(x=>x.value!=null&&x.days>0));
 assert.ok(a.every(x=>x.key>='2026-10'||grain==='week'&&x.key==='2026-09-28'));
 document.getElementById('extraGrain').value=grain;
 for(const type of ['line','bar','stack']){document.getElementById('extraType').value=type;api.draw();assert.ok(document.getElementById('extraChart').innerHTML.includes('<svg'))}
}
document.getElementById('rankSearch').value='__unmatched__';api.render();assert.ok(!document.getElementById('metricRows').innerHTML.includes('<strong>'));
console.log(JSON.stringify({status:'passed',rows:api.data.rows.length,findings:api.data.findings,evidence:api.data.evidence},null,2));
