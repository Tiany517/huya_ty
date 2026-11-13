-- Presto；逐日同时限定源dt与同日服务器时间；不限制atime，不新增UID过滤。
select
  dt,
  count(*) as exposure_cnt,
  count(distinct yyuid) as uid_cnt,
  min(stime) as min_stime,
  max(stime) as max_stime
from gamelive.dwd_huya_event
where dt between '2026-11-01' and '2026-11-12'
  and stime >= concat(dt, ' 00:00:00')
  and stime < concat(cast(date_add('day', 1, cast(dt as date)) as varchar), ' 00:00:00')
  and ety = 'custom_event'
  and eventid = 'show/activity_layer'
  and json_extract_scalar(ext['prop'], '$.material_id') = '14569'
group by dt
order by dt
