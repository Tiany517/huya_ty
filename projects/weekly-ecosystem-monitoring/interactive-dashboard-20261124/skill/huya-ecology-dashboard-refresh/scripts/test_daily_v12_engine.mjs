import assert from 'node:assert/strict';
import {classify,contributions,shapley,completeBucket,createEngine,shift,days} from '../assets/daily_v12_engine.mjs';
assert.equal(classify('dau',100000,[100000,100000,100000,100000]).severity,'正常');
assert.equal(classify('dau',100000,[1,null,2,3]).severity,'待判断');
assert.equal(classify('interactionRate',.1,[.1,.1,.1,.1]).severity,'待判断');
assert.equal(classify('dau',70000,[100000,100000,100000,100000]).severity,'高');
assert.ok(classify('dau',70000,[100000,100000,100000,100000]).robustZ<0);
assert.equal(contributions([{delta:0},{delta:0}],'dau')[0].contribution,null);
const c=contributions([{delta:-100},{delta:99}],'dau');assert.ok(Math.abs(c.reduce((s,r)=>s+Math.abs(r.contribution),0)-1)<1e-12);
const bridge=shapley([100,.1,10],[120,.08,15]);assert.ok(Math.abs(bridge.residual)<1e-9);assert.ok(Math.abs(bridge.effects.reduce((a,b)=>a+b,0)-(144-100))<1e-9);assert.equal(shapley([0,1,2],[1,2,3]),null);
assert.ok(completeBucket('2026-11-16','2026-11-22','week'));assert.ok(!completeBucket('2026-11-17','2026-11-22','week'));
assert.ok(completeBucket('2026-10-01','2026-10-31','month'));assert.ok(!completeBucket('2026-10-01','2026-10-30','month'));
const dates=days('2026-10-01','2026-11-24'),fields=['dau','revenue','payUsers','attributionUsers','liveAnchors'];
const payload={dates,categoryMetrics:fields,categories:[{id:'1',name:'A',group:0},{id:'2',name:'B',group:0}],groups:['游戏'],guilds:['G'],anchors:[],anchorDailyColumns:[],anchorColumns:[],weeks:[],weekRanges:{},anchorWeekly:[],anchorDaily:[],categoryRows:dates.flatMap((d,i)=>[[i,0,100,1000,10,20,2],[i,1,d==='2026-11-24'?90:100,d==='2026-11-24'?2000:1000,10,20,2]]),reportDate:'2026-11-24'};
const e=createEngine(payload),rank=e.ranking('category','revenue');assert.equal(rank.rows.length,2);assert.equal(rank.rows.find(r=>r.id===1).delta,1000);assert.equal(rank.rows.find(r=>r.id===1).contribution,1);assert.equal(e.ranking('category','dau').rows.find(r=>r.id===1).delta,-10);
const x=e.aggregate('category','payRate','2026-11-23','2026-11-24').rows.find(r=>r.id===1);assert.equal(x.value,20/190);
assert.ok(e.ranking('guild','dau').unsupported);

// Event exclusion removes each category's top-event dates from BOTH periods and
// compares non-event days without filling missing dates.
const eventPayload={...payload,eventDays:{'1':['2026-11-24'],'2':[]},categoryRows:payload.categoryRows.map(r=>dates[r[0]]==='2026-11-24'&&r[1]===0?[...r.slice(0,2),90,...r.slice(3)]:r)};
const eventEngine=createEngine(eventPayload);
const eventOpts={start:'2026-11-23',end:'2026-11-24',comparison:'custom',baseStart:'2026-11-16',baseEnd:'2026-11-17',eventMode:'nonEvent'};
const rawEventRow=eventEngine.ranking('category','dau',{...eventOpts,eventMode:'all'}).rows.find(r=>r.id===0);
const cleanEventRow=eventEngine.ranking('category','dau',eventOpts).rows.find(r=>r.id===0);
assert.equal(rawEventRow.current,95);
assert.equal(cleanEventRow.current,100);
assert.equal(cleanEventRow.baseline,100);
assert.equal(cleanEventRow.eventCoverage,'covered');
assert.deepEqual(cleanEventRow.eventExcludedDates,['2026-11-24']);
assert.equal(eventEngine.eventDaysFor(0,'2026-11-23','2026-11-24').length,1);
assert.equal(eventEngine.eventCoverage(1),'covered');
const missing={...payload,categoryRows:payload.categoryRows.filter(r=>!(dates[r[0]]==='2026-11-17'&&r[1]===1))};assert.equal(createEngine(missing).ranking('category','dau').rows.find(r=>r.id===1).severity,'待判断');
// Compare ratios from the SAME median numerator/denominator used by the bridge.
const varying={...payload,categoryRows:payload.categoryRows.map(r=>{const copy=[...r];if(r[1]===0){const vals={'2026-11-17':[10,1],'2026-11-10':[100,2],'2026-11-03':[200,20],'2026-10-27':[1000,500]};const v=vals[dates[r[0]]];if(v){copy[2]=v[0];copy[4]=v[1]}}return copy})};
const ratioRow=createEngine(varying).ranking('category','payRate').rows.find(r=>r.id===0);
assert.equal(ratioRow.baseline,ratioRow.baselineParts[0]/ratioRow.baselineParts[1]);
// Summed counts must not silently include nonmatching days for ratio ingredients.
const unavailable=classify('arppu',10,[9,10,11,12]);assert.equal(unavailable.severity,'待判断');
// Missing series data never sorts above a valid change just because abs(-Infinity).
console.log('V1.2 engine tests passed: rating gates, denominator closure, ratio weighting, Shapley, missing dates and weekly coverage');

assert.equal(contributions([{currentParts:[100,10],baselineParts:[80,10]}],'arppu')[0].contributionKind,'结构比率差');
assert.equal(contributions([{currentParts:[1,10],baselineParts:[2,10]}],'payRate')[0].contributionKind,'结构百分点');

// Counterexample: one invalid day/path must invalidate the object, not disappear
// from the denominator or be clipped into a plausible rate.
const badRatio={...payload,categoryRows:payload.categoryRows.map(r=>{const x=[...r];if(r[1]===0&&dates[r[0]]==='2026-11-24'){x[2]=98;x[4]=4751}return x})};
const invalid=createEngine(badRatio).ranking('category','payRate').rows.find(r=>r.id===0);
assert.equal(invalid.current,null);assert.equal(invalid.delta,null);assert.equal(invalid.contribution,null);assert.ok(invalid.currentReason.includes('分子分母'));
assert.equal(invalid.robustZ,null);assert.ok(invalid.scoreReason.includes('校准'));
const mixed=createEngine(badRatio).aggregate('category','payRate','2026-11-23','2026-11-24').rows.find(r=>r.id===0);
assert.equal(mixed.value,null);assert.equal(mixed.complete,false);
const badBaseline={...payload,categoryRows:payload.categoryRows.map(r=>{const x=[...r];if(r[1]===0&&dates[r[0]]==='2026-11-17'){x[2]=98;x[4]=4751}return x})};
const invalidBase=createEngine(badBaseline).ranking('category','payRate').rows.find(r=>r.id===0);
assert.equal(invalidBase.baseline,null);assert.ok(invalidBase.baselineReason.includes('分子分母'));
console.log('Invalid pay-rate source rows and mixed valid/invalid windows are blocked with reasons');

// Regression: Map.get does not accept an object-style default. The first weekly
// anchor in a tier must start from 0 instead of poisoning the whole supply mean with NaN.
const weeklyRow=(week,anchor,liveDays)=>{const r=Array(17).fill(0);r[0]=week;r[1]=0;r[2]=0;r[3]=0;r[4]=anchor;r[9]=3500;r[10]=7;r[11]=700;r[12]=100;r[16]=liveDays;return r};
const weekly={...payload,weeks:[0,1],weekRanges:{0:{start:'2026-11-09',end:'2026-11-15'},1:{start:'2026-11-16',end:'2026-11-22'}},anchorWeekly:[weeklyRow(0,0,6),weeklyRow(0,1,0),weeklyRow(1,0,7),weeklyRow(1,1,2)]};
const weeklyEngine=createEngine(weekly);
const weeklyCurrent=weeklyEngine.aggregate('tier','liveAnchors','2026-11-16','2026-11-22',[]).rows.find(r=>r.id==='腰部');
const weeklyBaseline=weeklyEngine.aggregate('tier','liveAnchors','2026-11-09','2026-11-15',[]).rows.find(r=>r.id==='腰部');
assert.equal(weeklyCurrent.value,9/7);
assert.equal(weeklyBaseline.value,6/7);
console.log('Weekly tier liveAnchors dedupe starts from a finite zero');

// Micro attribution uses each anchor's weekly max-DAU category/guild path and
// removes that path's event days from both periods. It never fills absent days.
const microDates=['2026-11-09','2026-11-10','2026-11-11','2026-11-12','2026-11-16','2026-11-17','2026-11-18','2026-11-19'];
const microWeek=(week,anchor,category,guild,dau)=>{const r=Array(17).fill(0);r[0]=week;r[1]=category;r[2]=0;r[3]=guild;r[4]=anchor;r[5]=dau;r[9]=3500;r[10]=7;r[16]=7;return r};
const microDaily=(date,anchor,dau,interaction,isLive=1)=>[date,anchor,dau,100,10,20,5,20,interaction,isLive];
const microPayload={...payload,dates:microDates,categories:[{id:'1',name:'品类A',group:0},{id:'2',name:'品类B',group:0},{id:'3',name:'未覆盖品类',group:0}],guilds:['公会一','公会二'],anchors:[{id:'u1',name:'主播A',roomid:'r1'},{id:'u2',name:'主播B',roomid:'r2'},{id:'u3',name:'主播C',roomid:'r3'}],anchorDailyColumns:['date','anchor','dau','revenue','payUsers','viewMinutes','attributionUsers','interactionCount','interactionUsers','isLive'],anchorColumns:['week','category','group','guild','anchor','dau','revenue','payUsers','live','acuSum','acuDays','viewMinutes','viewDays','attributionUsers','interactionCount','interactionUsers','liveDays'],weeks:['2026W46','2026W47'],weekRanges:{'2026W46':{start:'2026-11-09',end:'2026-11-15'},'2026W47':{start:'2026-11-16',end:'2026-11-22'}},anchorWeekly:[microWeek(0,0,0,0,300),microWeek(0,1,0,0,300),microWeek(0,2,2,1,300),microWeek(1,0,0,0,200),microWeek(1,1,0,0,400),microWeek(1,2,2,1,200)],anchorDaily:[...['2026-11-09','2026-11-10','2026-11-11','2026-11-12'].map(d=>microDaily(d,0,300,30)).map(r=>{if(['2026-11-10','2026-11-12'].includes(r[0]))r[9]=0;return r}),...['2026-11-16','2026-11-17','2026-11-18','2026-11-19'].map(d=>microDaily(d,0,200,20)).map(r=>{if(r[0]==='2026-11-18')r[9]=0;return r}),...['2026-11-09','2026-11-10','2026-11-11','2026-11-12'].map(d=>microDaily(d,1,300,30)),...['2026-11-16','2026-11-17','2026-11-18','2026-11-19'].map(d=>microDaily(d,1,400,40)),...['2026-11-09','2026-11-10','2026-11-11','2026-11-12'].map(d=>microDaily(d,2,300,30)),...['2026-11-16','2026-11-17','2026-11-18','2026-11-19'].map(d=>microDaily(d,2,200,20))],eventDays:{'1':['2026-11-17'],'2':[]},reportDate:'2026-11-19'};
const microEngine=createEngine(microPayload),microAnchor=microEngine.anchorEventWeeklyComparison('dau');
assert.equal(microAnchor.curWeek,'2026W47');assert.equal(microAnchor.baseWeek,'2026W46');
const anchorA=microAnchor.rows.find(r=>r.name==='主播A'),anchorB=microAnchor.rows.find(r=>r.name==='主播B');
assert.equal(anchorA.current,200);assert.equal(anchorA.baseline,300);assert.equal(anchorA.delta,-100);
assert.equal(anchorA.currentDays,3);assert.equal(anchorA.baselineDays,4);assert.equal(anchorA.currentLiveDays,2);
assert.equal(anchorB.delta,100);assert.ok(!microAnchor.rows.some(r=>r.name==='主播C'),'event-unknown categories must not enter calibrated micro attribution');
const microGuild=microEngine.guildEventWeeklyComparison('dau');assert.equal(microGuild.rows.find(r=>r.name==='公会一').delta,0);
console.log('Anchor and guild event-adjusted weekly attribution passed');
