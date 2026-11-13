select ety, product, stime, atime, json_extract_scalar(ext['prop'], '$.material_id') as material_id
from gamelive.dwd_huya_event
where dt = '2026-11-03'
  and stime >= '2026-11-03 00:00:00'
  and stime < '2026-11-04 00:00:00'
  and eventid = 'show/activity_layer'
  and json_extract_scalar(ext['prop'], '$.material_id') = '14569'
limit 5
