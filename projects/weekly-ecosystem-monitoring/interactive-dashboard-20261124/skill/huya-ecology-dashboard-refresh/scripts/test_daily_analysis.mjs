const pages=await fetch('http://127.0.0.1:9334/json/list').then(r=>r.json());
const page=pages.find(p=>p.type==='page'&&p.url.startsWith('file:///'));
const ws=new WebSocket(page.webSocketDebuggerUrl);
await new Promise(r=>ws.addEventListener('open',r,{once:true}));
ws.send(JSON.stringify({id:1,method:'Runtime.evaluate',params:{returnByValue:true,expression:`(()=>{
const data=window.__analystAnalysis?.data;if(!data)throw Error('analysis missing');
const m=document.getElementById('analysisMetric'),o=document.getElementById('analysisOrder');
m.value='revenue';m.dispatchEvent(new Event('change'));o.value='absolute';o.dispatchEvent(new Event('change'));
const expected=data.filter(r=>r.metric==='revenue').sort((a,b)=>Math.abs(b.delta)-Math.abs(a.delta))[0];
const actual=document.querySelector('#analysisRows tr td')?.textContent;
const bridges=data.filter(r=>r.bridge);const checks={fiveMetrics:new Set(data.map(r=>r.metric)).size===5,
allCategories:data.filter(r=>r.metric==='dau').length>50,revenueRanking:actual===expected.name,
bridgeCloses:bridges.length>0&&bridges.every(r=>Math.abs(r.bridge.residual)<0.01),
boundedStreak:data.every(r=>r.streak>=0&&r.streak<=28)};
m.value='dau';o.value='loss';window.__analystAnalysis.render();
return {status:Object.values(checks).every(Boolean)?'passed':'failed',checks,records:data.length,bridges:bridges.length};})()`}}));
const result=await new Promise((resolve,reject)=>ws.addEventListener('message',e=>{const msg=JSON.parse(e.data);if(msg.id===1){if(msg.result.exceptionDetails)reject(Error(JSON.stringify(msg.result.exceptionDetails)));else resolve(msg.result.result.value);}}));
console.log(JSON.stringify(result,null,2));ws.close();if(result.status!=='passed')process.exitCode=1;
