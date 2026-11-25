/** Pure display filtering: never recompute ratings, dates or contribution denominators. */
export const LEVELS = ['高','中','低','正常','待判断'];
export function normalizeFilter(value={}) {
  const numeric=(v,label)=>{
    if(v==null||v==='')return null;
    const n=Number(v);if(!Number.isFinite(n))throw new Error(label+'必须是有限数值');return n;
  };
  const min=numeric(value.min,'最小异常分'),max=numeric(value.max,'最大异常分'),strength=numeric(value.strength,'异常强度');
  if(min!=null&&max!=null&&min>max)throw new Error('最小异常分不能大于最大异常分');
  if(strength!=null&&strength<0)throw new Error('异常强度不能小于0');
  const levels=[...new Set(value.levels||[])];
  if(levels.some(v=>!LEVELS.includes(v)))throw new Error('未知异常等级');
  const direction=value.direction||'all';if(!['all','up','down','flat'].includes(direction))throw new Error('未知变化方向');
  return {levels,min,max,strength,direction,query:String(value.query||'').trim().toLocaleLowerCase()};
}
export function levelOf(row){return row.severity==='待核验'||!row.severity?'待判断':row.severity;}
export function scoreOf(row){return row.robustZ==null||!Number.isFinite(Number(row.robustZ))?null:Number(row.robustZ);}
export function matches(row,filter={}) {
  const f=normalizeFilter(filter),score=scoreOf(row);
  if(f.levels.length&&!f.levels.includes(levelOf(row)))return false;
  if((f.min!=null||f.max!=null||f.strength!=null)&&score==null)return false;
  if(f.min!=null&&score<f.min||f.max!=null&&score>f.max||f.strength!=null&&Math.abs(score)<f.strength)return false;
  if(f.direction==='up'&&!(row.delta>0)||f.direction==='down'&&!(row.delta<0)||f.direction==='flat'&&row.delta!==0)return false;
  return !f.query||[row.name,row.path,row.group].join(' ').toLocaleLowerCase().includes(f.query);
}
export function filterRows(rows,filter){normalizeFilter(filter);return rows.filter(row=>matches(row,filter));}
export function levelCounts(rows){return Object.fromEntries(LEVELS.map(level=>[level,rows.filter(row=>levelOf(row)===level).length]));}
