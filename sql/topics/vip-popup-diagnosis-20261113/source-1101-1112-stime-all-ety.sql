-- Presto；去掉ety过滤，按源分区日期与事件类型对照；每天限定同日stime。
select
  dt,
  ety,
  count(*) as exposure_cnt,
  count(distinct yyuid) as uid_cnt,
  min(stime) as min_stime,
  max(stime) as max_stime
from gamelive.dwd_huya_event
where dt between '2026-11-01' and '2026-11-12'
  and stime >= concat(dt, ' 00:00:00')
  and stime < concat(cast(date_add('day', 1, cast(dt as date)) as varchar), ' 00:00:00')
  and eventid = 'show/activity_layer'
  and json_extract_scalar(ext['prop'], '$.material_id') = '14569'
group by dt, ety
order by dt, ety
