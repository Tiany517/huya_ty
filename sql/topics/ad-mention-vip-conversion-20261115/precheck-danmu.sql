-- 五日探索预检：沿用原过滤，检查原始time是否可解析、日期语义和广告用户规模。
with base as (
 select dt,cast(luid as varchar) as uid,cast(time as varchar) as raw_time,
 coalesce(nullif(trim(askscontent),''),nullif(trim(scontent),'')) as content
 from gamelive.gamelive_huya_danmu_log
 where dt in ('2025-01-01','2025-06-01','2026-01-01','2026-08-31','2026-11-14')
 and passed='0' and lpid is not null
 and coalesce(lower(trim(cast(luid as varchar))),'') not in ('0','','null','other','-','-1')
)
select dt,count(*) as ad_rows,count(distinct uid) as ad_users,
 count_if(try_cast(raw_time as timestamp) is null) as bad_time_rows,
 count_if(substr(raw_time,1,10)<>dt) as time_dt_mismatch_rows,
 min(raw_time) as min_time,max(raw_time) as max_time
from base where content like '%广告%' group by dt order by dt
