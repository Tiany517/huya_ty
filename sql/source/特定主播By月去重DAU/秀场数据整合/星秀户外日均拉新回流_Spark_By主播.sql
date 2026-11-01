-- Spark SQL
-- 口径说明：
-- 1. 时间：2026-01-01 至 2026-07-26；7月按已有分区只统计到7月26日。
-- 2. 游戏：1663=星秀，2165=户外。
-- 3. 粒度：月份 + game_id + 主播luid。
-- 4. 日均拉新/回流用户数：先按天 + 主播 + game_id 去重用户，再按月求和，除以该game_id当月已有分区天数。
-- 5. 同一用户同一天若同时出现在拉新和回流表，会分别计入拉新、回流；total_laxin_huiliu_user_cnt为拉新+回流合并后的月去重用户数。

with month_days as (
  select
    substr(dt, 1, 7) as month,
    gameid as game_id,
    count(distinct dt) as observed_days
  from gamelive.dm_huya_ayyuid_detail_day
  where dt between '2026-01-01' and '2026-07-26'
    and gameid in (1663, 2165)
  group by substr(dt, 1, 7), gameid
),

laxin_huiliu_user as (
  select distinct
    dt,
    substr(dt, 1, 7) as month,
    game_id,
    luid,
    luid_name,
    user_ukey,
    '拉新' as label
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
  where dt between '2026-01-01' and '2026-07-26'
    and game_id in (1663, 2165)
    and user_ukey is not null

  union all

  select distinct
    dt,
    substr(dt, 1, 7) as month,
    game_id,
    luid,
    luid_name,
    user_ukey,
    '回流' as label
  from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1
  where dt between '2026-01-01' and '2026-07-26'
    and game_id in (1663, 2165)
    and user_ukey is not null
),

daily_anchor as (
  select
    dt,
    month,
    game_id,
    luid,
    max(luid_name) as luid_name,
    count(distinct case when label = '拉新' then user_ukey end) as laxin_user_cnt,
    count(distinct case when label = '回流' then user_ukey end) as huiliu_user_cnt,
    count(distinct user_ukey) as laxin_huiliu_user_cnt
  from laxin_huiliu_user
  group by dt, month, game_id, luid
),

monthly_anchor_daily_sum as (
  select
    month,
    game_id,
    luid,
    max(luid_name) as luid_name,
    sum(laxin_user_cnt) as daily_laxin_user_cnt_sum,
    sum(huiliu_user_cnt) as daily_huiliu_user_cnt_sum,
    sum(laxin_huiliu_user_cnt) as daily_laxin_huiliu_user_cnt_sum
  from daily_anchor
  group by month, game_id, luid
),

monthly_anchor_uv as (
  select
    month,
    game_id,
    luid,
    max(luid_name) as luid_name,
    count(distinct case when label = '拉新' then user_ukey end) as month_laxin_user_cnt,
    count(distinct case when label = '回流' then user_ukey end) as month_huiliu_user_cnt,
    count(distinct user_ukey) as month_laxin_huiliu_user_cnt
  from laxin_huiliu_user
  group by month, game_id, luid
)

select
  a.month,
  a.game_id,
  case when a.game_id = 1663 then '星秀' else '户外' end as game_name,
  a.luid,
  coalesce(a.luid_name, u.luid_name) as luid_name,
  d.observed_days,

  case when d.observed_days > 0 then coalesce(a.daily_laxin_user_cnt_sum, 0) * 1.0000 / d.observed_days end as avg_daily_laxin_user_cnt,
  case when d.observed_days > 0 then coalesce(a.daily_huiliu_user_cnt_sum, 0) * 1.0000 / d.observed_days end as avg_daily_huiliu_user_cnt,
  case when d.observed_days > 0 then coalesce(a.daily_laxin_huiliu_user_cnt_sum, 0) * 1.0000 / d.observed_days end as avg_daily_laxin_huiliu_user_cnt,

  coalesce(u.month_laxin_user_cnt, 0) as month_laxin_user_cnt,
  coalesce(u.month_huiliu_user_cnt, 0) as month_huiliu_user_cnt,
  coalesce(u.month_laxin_huiliu_user_cnt, 0) as month_laxin_huiliu_user_cnt
from monthly_anchor_daily_sum a
left join monthly_anchor_uv u
  on a.month = u.month
 and a.game_id = u.game_id
 and a.luid = u.luid
left join month_days d
  on a.month = d.month
 and a.game_id = d.game_id
order by a.month, a.game_id, avg_daily_laxin_huiliu_user_cnt desc;
