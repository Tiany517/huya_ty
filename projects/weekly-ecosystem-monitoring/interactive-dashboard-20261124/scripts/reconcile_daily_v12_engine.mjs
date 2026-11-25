import fs from 'node:fs';
import zlib from 'node:zlib';
import assert from 'node:assert/strict';
import {createEngine} from '../assets/daily_v12_engine.mjs';
const html=fs.readFileSync(process.argv[2],'utf8'),report=JSON.parse(fs.readFileSync(process.argv[3],'utf8'));
const data=JSON.parse(zlib.gunzipSync(Buffer.from(html.match(/id="v12-data">(.*?)<\/script>/s)[1],'base64'))),engine=createEngine(data);
const checked=report.engineExpectations.map(x=>{const actual=engine.aggregate(x.scope,x.metric,x.start,x.end).rows.find(r=>String(r.id)===String(x.id))?.value;assert.ok(actual!=null&&Math.abs(actual-x.value)<=Math.max(.000001,Math.abs(x.value)*1e-12),JSON.stringify({x,actual}));return {...x,actual,passed:true}});
report.engineReconciliation={status:'passed',checks:checked};fs.writeFileSync(process.argv[3],JSON.stringify(report,null,2));console.log('Independent Python export aggregates vs JS engine: '+checked.length+' passed');
