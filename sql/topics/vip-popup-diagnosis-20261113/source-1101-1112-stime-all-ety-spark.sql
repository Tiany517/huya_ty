-- Spark；不限制ety；每个源分区同时限定对应同日stime；未增加UID过滤。
with event_base as (
  -- 输入/输出：事件上报粒度；无关联、无事件去重。
  select dt, ety, yyuid, stime,
    from_json(ext['prop'], 'struct<material_id:string>') as prop
  from gamelive.dwd_huya_event
  where dt between '2026-11-01' and '2026-11-12'
    and stime >= concat(dt, ' 00:00:00')
    and stime < concat(cast(date_add(cast(dt as date), 1) as string), ' 00:00:00')
    and eventid = 'show/activity_layer'
)
select dt, ety, count(*) as exposure_cnt,
  count(distinct yyuid) as uid_cnt,
  min(stime) as min_stime, max(stime) as max_stime
from event_base
where prop.material_id = '14569'
group by dt, ety
order by dt, ety
