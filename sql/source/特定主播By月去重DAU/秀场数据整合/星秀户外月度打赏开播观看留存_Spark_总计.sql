-- Spark SQL
-- 口径说明：
-- 1. 时间：2026-01-01 至 2026-07-26；7月按已有分区只统计到7月26日。
-- 2. 游戏：1663=星秀，2165=户外。
-- 3. 粒度：月份 + game_id，不输出主播粒度。
-- 4. 全部指标均按month + game_id直接计算，不切主播粒度。
-- 5. 观看用户7日留存：用户在该game_id该月首个观看日 + 6 天当天APP活跃；因分区到2026-07-26，7月留存cohort只取到2026-07-20。
-- 6. 7日平均活跃天数：同一批留存分母用户，在首观看日起7天窗口内的APP活跃天数均值。

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

live_month_total as (
  select
    substr(dt, 1, 7) as month,
    gameid as game_id,
    max(game_name) as game_name,
    sum(live_hours_only_live) as total_live_hours
  from gamelive.dm_huya_ayyuid_detail_day
  where dt between '2026-01-01' and '2026-07-26'
    and gameid in (1663, 2165)
  group by substr(dt, 1, 7), gameid
),

revenue_user_day as (
  select
    p.dt,
    substr(p.dt, 1, 7) as month,
    p.game_id,
    max(p.game_name) as game_name,
    p.ext['ukey'] as user_ukey,
    sum(p.user_consume_amount) as consume_amt
  from zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i p
  where p.dt between '2026-01-01' and '2026-07-26'
    and p.user_consume_amount > 0
    and p.game_label = '娱乐'
    and p.game_id in (1663, 2165)
  group by p.dt, substr(p.dt, 1, 7), p.game_id, p.ext['ukey']
),

revenue_game_day as (
  select
    dt,
    month,
    game_id,
    max(game_name) as game_name,
    count(distinct user_ukey) as pay_user_cnt,
    sum(consume_amt) as consume_amt
  from revenue_user_day
  group by dt, month, game_id
),

revenue_user_month as (
  select
    month,
    game_id,
    max(game_name) as game_name,
    user_ukey,
    sum(consume_amt) as month_consume_amt
  from revenue_user_day
  group by month, game_id, user_ukey
),

revenue_game_month as (
  select
    month,
    game_id,
    max(game_name) as game_name,
    sum(pay_user_cnt) as daily_pay_user_cnt_sum,
    sum(consume_amt) as total_consume_amt
  from revenue_game_day
  group by month, game_id
),

revenue_user_month_agg as (
  select
    month,
    game_id,
    max(game_name) as game_name,
    count(distinct user_ukey) as month_pay_user_cnt,
    count(distinct case when month_consume_amt > 10000 then user_ukey end) as big_r_user_cnt
  from revenue_user_month
  group by month, game_id
),

watch_user_day as (
  select
    w.dt,
    substr(w.dt, 1, 7) as month,
    w.game_id,
    max(w.game_name) as game_name,
    w.user_ukey,
    sum(w.watch_duration) as watch_duration
  from gamelive.dws_huya_user_behavior_d_i w
  where w.dt between '2026-01-01' and '2026-07-26'
    and w.game_id in (1663, 2165)
    and w.product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
    and w.data_type = 'live_watch_session'
    and w.live_content_type = '直播'
    and w.is_black_ukey = 0
    and w.watch_cnt > 0
    and w.watch_duration > 0
  group by w.dt, substr(w.dt, 1, 7), w.game_id, w.user_ukey
),

watch_game_day as (
  select
    dt,
    month,
    game_id,
    max(game_name) as game_name,
    count(distinct user_ukey) as daily_watch_user_cnt,
    sum(watch_duration) as watch_duration
  from watch_user_day
  group by dt, month, game_id
),

watch_game_month as (
  select
    month,
    game_id,
    max(game_name) as game_name,
    sum(daily_watch_user_cnt) as daily_watch_user_cnt_sum,
    sum(watch_duration) as total_watch_duration
  from watch_game_day
  group by month, game_id
),

watch_user_month_agg as (
  select
    month,
    game_id,
    max(game_name) as game_name,
    count(distinct user_ukey) as month_watch_user_cnt
  from watch_user_day
  group by month, game_id
),

retention_base as (
  select
    month,
    game_id,
    max(game_name) as game_name,
    user_ukey,
    min(dt) as cohort_date
  from watch_user_day
  where dt between '2026-01-01' and '2026-07-20'
  group by month, game_id, user_ukey
),

active_day as (
  select distinct
    dt,
    user_ukey
  from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
  where dt between '2026-01-01' and '2026-07-26'
    and product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
    and is_black_ukey = 0
),

retention_user_7d as (
  select
    b.month,
    b.game_id,
    max(b.game_name) as game_name,
    b.user_ukey,
    count(distinct a.dt) as active_days_7d,
    max(
      case
        when a.dt = date_format(date_add(to_date(b.cohort_date), 6), 'yyyy-MM-dd') then 1
        else 0
      end
    ) as is_d7_retained
  from retention_base b
  left join active_day a
    on b.user_ukey = a.user_ukey
   and a.dt between b.cohort_date and date_format(date_add(to_date(b.cohort_date), 6), 'yyyy-MM-dd')
  group by b.month, b.game_id, b.user_ukey
),

retention_month_total as (
  select
    month,
    game_id,
    max(game_name) as game_name,
    count(distinct user_ukey) as d7_retention_base_user_cnt,
    count(distinct case when is_d7_retained = 1 then user_ukey end) as d7_retained_user_cnt,
    sum(active_days_7d) as active_days_7d_sum,
    avg(active_days_7d) as avg_active_days_7d
  from retention_user_7d
  group by month, game_id
),

month_game_key as (
  select month, game_id from live_month_total
  union
  select month, game_id from revenue_game_month
  union
  select month, game_id from revenue_user_month_agg
  union
  select month, game_id from watch_game_month
  union
  select month, game_id from watch_user_month_agg
  union
  select month, game_id from retention_month_total
)

select
  k.month,
  k.game_id,
  coalesce(l.game_name, r.game_name, ru.game_name, w.game_name, wu.game_name, ret.game_name, case when k.game_id = 1663 then '星秀' else '户外' end) as game_name,
  m.observed_days,

  case when m.observed_days > 0 then coalesce(r.daily_pay_user_cnt_sum, 0) * 1.0000 / m.observed_days end as avg_daily_pay_user_cnt,
  case when m.observed_days > 0 then coalesce(r.total_consume_amt, 0) * 1.0000 / m.observed_days end as avg_daily_consume_amt,
  case when m.observed_days > 0 then coalesce(l.total_live_hours, 0) * 1.0000 / m.observed_days end as avg_daily_live_hours,

  coalesce(ru.big_r_user_cnt, 0) as big_r_user_cnt,
  coalesce(w.total_watch_duration, 0) as total_watch_duration,
  case when m.observed_days > 0 then coalesce(w.daily_watch_user_cnt_sum, 0) * 1.0000 / m.observed_days end as avg_watch_dau,
  coalesce(wu.month_watch_user_cnt, 0) as month_watch_user_cnt,

  coalesce(ret.d7_retention_base_user_cnt, 0) as d7_retention_base_user_cnt,
  coalesce(ret.d7_retained_user_cnt, 0) as d7_retained_user_cnt,
  coalesce(ret.active_days_7d_sum, 0) as active_days_7d_sum,
  ret.avg_active_days_7d,
  case
    when coalesce(ret.d7_retention_base_user_cnt, 0) > 0
    then ret.d7_retained_user_cnt * 1.0000 / ret.d7_retention_base_user_cnt
  end as d7_retention_rate,

  coalesce(r.total_consume_amt, 0) as total_consume_amt,
  coalesce(ru.month_pay_user_cnt, 0) as month_pay_user_cnt,
  case
    when coalesce(ru.month_pay_user_cnt, 0) > 0
    then coalesce(r.total_consume_amt, 0) * 1.0000 / ru.month_pay_user_cnt
  end as avg_consume_amt_per_pay_user,
  case
    when coalesce(wu.month_watch_user_cnt, 0) > 0
    then coalesce(r.total_consume_amt, 0) * 1.0000 / wu.month_watch_user_cnt
  end as avg_consume_amt_per_watch_user
from month_game_key k
left join month_days m
  on k.month = m.month
 and k.game_id = m.game_id
left join live_month_total l
  on k.month = l.month
 and k.game_id = l.game_id
left join revenue_game_month r
  on k.month = r.month
 and k.game_id = r.game_id
left join revenue_user_month_agg ru
  on k.month = ru.month
 and k.game_id = ru.game_id
left join watch_game_month w
  on k.month = w.month
 and k.game_id = w.game_id
left join watch_user_month_agg wu
  on k.month = wu.month
 and k.game_id = wu.game_id
left join retention_month_total ret
  on k.month = ret.month
 and k.game_id = ret.game_id
order by k.month, k.game_id;
