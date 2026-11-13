-- Presto独立单日对账；直接从源事实计数，不复用Spark CTE或grouping sets。
select
  count(*) as exposure_cnt,
  count(distinct cast(yyuid as varchar)) as uid_cnt
from gamelive.dwd_huya_event
where dt = '2026-11-09'
  and stime >= '2026-11-09 00:00:00'
  and stime < '2026-11-10 00:00:00'
  and eventid = 'show/activity_layer'
  and json_extract_scalar(ext['prop'], '$.material_id') in (
    '14559','14491','14481','14479','14477','14475',
    '14473','14471','14469','14521','14519','14517'
  )
  and coalesce(lower(trim(cast(yyuid as varchar))), '')
      not in ('0','','null','other','-','-1')
