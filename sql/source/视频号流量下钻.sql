with t1 as(
  select 
    dt,
    case
      when dt between '2026-09-28' and '2026-10-04' then '上周'
      when dt between '2026-10-05' and '2026-10-11' then '本周'
    end as week,
    userid,
    usernickname,
    sum(cast(audiencecnt as bigint)) as dau,
    sum(cast(onlinetimeduration as double)) as online_duration
  from gamelive.dwd_spider_wxmcn_anchor_livedata_list_d_i a 
  where 
    dt>='2026-09-28' and dt <= '2026-10-11'
    and cast(onlinetimeduration as double) > 0 -- 开播
  -- and userid in ('sph8KVv3uxE1LY3','sphosEfxN4Ut5TO','sphReL8M8ZYdxCW','sphsmqJXgBTQvOc')
  group by 
    dt,
    userid,
    usernickname
  order by 
    dt,
    usernickname
)

select 
  week,
  userid,
  usernickname,
  avg(dau) as dau,
  count(distinct dt) as live_day_cnt,
  sum(online_duration)/count(distinct dt) as avg_live_durati0on
from t1
group by 
  week,
  userid,
  usernickname
order by
  week,
  userid,
  usernickname