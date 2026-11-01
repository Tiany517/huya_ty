-- 视频号 DAU 月度对比及主播增量归因
-- 数据源：gamelive.dwd_spider_wxmcn_anchor_livedata_list_d_i
-- 口径：仅保留开播行；主播日 dau=sum(cast(audiencecnt as bigint))；
--       月度日均 DAU=窗口内主播日 dau 总和/该月实际有数据天数。
-- 实际数据日：2026-08 共30天（缺08-01）、2026-09 共30天、2026-10 截至22日共22天。

with daily_anchor as (
  select
    dt,
    userid,
    max(usernickname) as usernickname,
    sum(try_cast(audiencecnt as bigint)) as dau
  from gamelive.dwd_spider_wxmcn_anchor_livedata_list_d_i
  where dt between '2026-08-01' and '2026-10-22'
    and try_cast(onlinetimeduration as double) > 0
  group by dt, userid
),
month_anchor as (
  select
    userid,
    max_by(usernickname, dt) as usernickname,
    sum(if(substr(dt, 1, 7) = '2026-08', dau, 0)) / 30.0 as avg_dau_aug,
    sum(if(substr(dt, 1, 7) = '2026-09', dau, 0)) / 30.0 as avg_dau_sep,
    sum(if(substr(dt, 1, 7) = '2026-10', dau, 0)) / 22.0 as avg_dau_oct,
    count_if(substr(dt, 1, 7) = '2026-08') as live_days_aug,
    count_if(substr(dt, 1, 7) = '2026-09') as live_days_sep,
    count_if(substr(dt, 1, 7) = '2026-10') as live_days_oct,
    sum(if(substr(dt, 1, 7) = '2026-08', dau, 0)) as total_dau_aug,
    sum(if(substr(dt, 1, 7) = '2026-09', dau, 0)) as total_dau_sep,
    sum(if(substr(dt, 1, 7) = '2026-10', dau, 0)) as total_dau_oct
  from daily_anchor
  group by userid
),
with_change as (
  select
    *,
    avg_dau_sep - avg_dau_aug as sep_vs_aug,
    avg_dau_oct - avg_dau_aug as oct_vs_aug
  from month_anchor
),
ranked as (
  select
    *,
    row_number() over(order by sep_vs_aug desc, userid) as sep_pos_rank,
    row_number() over(order by sep_vs_aug asc, userid) as sep_neg_rank,
    row_number() over(order by oct_vs_aug desc, userid) as oct_pos_rank,
    row_number() over(order by oct_vs_aug asc, userid) as oct_neg_rank
  from with_change
)
select *
from ranked
where sep_pos_rank <= 20
   or oct_pos_rank <= 20
   or sep_neg_rank <= 20
   or oct_neg_rank <= 20
order by greatest(sep_vs_aug, oct_vs_aug) desc;
