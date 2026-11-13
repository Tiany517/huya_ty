-- Spark；只读诊断；源为事件上报记录，输出为每日合计或日期+配置ID+ety汇总。
-- 后台ID已在11月7日源样本中确认位于prop.material_id，事件为show/activity_layer。
-- 保留全ety；仅有效登录UID；源dt与同日stime匹配，不读取atime。
with event_base as (
  select
    dt,
    cast(yyuid as string) as uid,
    ety,
    stime,
    from_json(ext['prop'], 'struct<material_id:string>') as prop
  from gamelive.dwd_huya_event
  where dt between '2026-11-01' and '2026-11-12'
    and stime >= concat(dt, ' 00:00:00')
    and stime < concat(cast(date_add(cast(dt as date), 1) as string), ' 00:00:00')
    and eventid = 'show/activity_layer'
    and coalesce(lower(trim(cast(yyuid as string))), '')
        not in ('0','','null','other','-','-1')
),
matched_event as (
  select dt, uid, ety, stime, prop.material_id as material_id
  from event_base
  where prop.material_id in (
    '14559','14491','14481','14479','14477','14475',
    '14473','14471','14469','14521','14519','14517'
  )
)
-- grouping sets只为汇总分组；每日总UV直接去重计算，不累加各配置UV。
select
  case when grouping(material_id) = 1 then 'daily_total' else 'configuration' end as row_type,
  dt,
  case when grouping(material_id) = 1 then 'ALL' else material_id end as material_id,
  case when grouping(ety) = 1 then 'ALL' else ety end as ety,
  count(*) as exposure_cnt,
  count(distinct uid) as uid_cnt,
  min(stime) as min_stime,
  max(stime) as max_stime
from matched_event
group by grouping sets ((dt, material_id, ety), (dt))
order by dt, row_type, material_id, ety
