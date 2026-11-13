-- Presto小范围字段定位：仅11月7日；同时核查ID落在eventid或旧曝光事件的material_id。
select
  eventid,
  ety,
  json_extract_scalar(ext['prop'], '$.material_id') as material_id,
  stime
from gamelive.dwd_huya_event
where dt = '2026-11-07'
  and stime >= '2026-11-07 00:00:00'
  and stime < '2026-11-08 00:00:00'
  and (
    eventid in ('14559','14491','14481','14479','14477','14475','14473','14471','14469','14521','14519','14517')
    or (
      eventid = 'show/activity_layer'
      and json_extract_scalar(ext['prop'], '$.material_id') in ('14559','14491','14481','14479','14477','14475','14473','14471','14469','14521','14519','14517')
    )
  )
limit 5
