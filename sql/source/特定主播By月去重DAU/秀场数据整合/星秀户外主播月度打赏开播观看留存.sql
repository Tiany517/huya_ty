-- 口径说明：
-- 1. 时间：2026-01-01 至 2026-07-26；7月按已有分区只统计到7月26日。
-- 2. 游戏：1663=星秀，2165=户外。
-- 3. 粒度：月份 + game_id + 主播ayyuid。
-- 4. 日均打赏用户数/金额/开播时长/观看DAU：除以该game_id当月已有分区天数，7月为26天。
-- 5. 大R：同一自然月、同一主播、同一game_id下，用户打赏金额 > 10000 的用户数。
-- 6. 观看用户7日留存：用户在该主播该月首个观看日 + 6 天当天APP活跃；因分区到2026-07-26，7月留存cohort只取到2026-07-20。

with anchor_info as (
  select
    uid,
    max(nick) as nickname
  from gamelive.dim_huya_ayyuid_info
  where dt >= '2024-01-01'
  group by uid
),

month_days as (
  select
    substr(dt, 1, 7) as month,
    gameid as game_id,
    count(distinct dt) as observed_days
  from gamelive.dm_huya_ayyuid_detail_day
  where dt between '2026-01-01' and '2026-07-26'
    and gameid in (1663, 2165)
  group by substr(dt, 1, 7), gameid
),

anchor_live_month as (
  select
    substr(dt, 1, 7) as month,
    gameid as game_id,
    max(game_name) as game_name,
    ayyuid,
    max(nickname) as live_nickname,
    sum(live_hours_only_live) as total_live_hours
  from gamelive.dm_huya_ayyuid_detail_day
  where dt between '2026-01-01' and '2026-07-26'
    and gameid in (1663, 2165)
  group by substr(dt, 1, 7), gameid, ayyuid
),

revenue_user_day as (
  select
    p.dt,
    substr(p.dt, 1, 7) as month,
    p.game_id,
    max(p.game_name) as game_name,
    p.creator_uid as ayyuid,
    p.ext['ukey'] as user_ukey,
    sum(p.user_consume_amount) as consume_amt
  from zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i p
  where p.dt between '2026-01-01' and '2026-07-26'
    and p.user_consume_amount > 0
    and p.game_label = '娱乐'
    and p.game_id in (1663, 2165)
  group by p.dt, substr(p.dt, 1, 7), p.game_id, p.creator_uid, p.ext['ukey']
),

revenue_anchor_day as (
  select
    dt,
    month,
    game_id,
    max(game_name) as game_name,
    ayyuid,
    count(distinct user_ukey) as pay_user_cnt,
    sum(consume_amt) as consume_amt
  from revenue_user_day
  group by dt, month, game_id, ayyuid
),

revenue_user_month as (
  select
    month,
    game_id,
    max(game_name) as game_name,
    ayyuid,
    user_ukey,
    sum(consume_amt) as month_consume_amt
  from revenue_user_day
  group by month, game_id, ayyuid, user_ukey
),

revenue_anchor_month as (
  select
    month,
    game_id,
    max(game_name) as game_name,
    ayyuid,
    sum(pay_user_cnt) as daily_pay_user_cnt_sum,
    sum(consume_amt) as total_consume_amt
  from revenue_anchor_day
  group by month, game_id, ayyuid
),

revenue_user_month_agg as (
  select
    month,
    game_id,
    max(game_name) as game_name,
    ayyuid,
    count(distinct user_ukey) as month_pay_user_cnt,
    count(distinct case when month_consume_amt > 10000 then user_ukey end) as big_r_user_cnt
  from revenue_user_month
  group by month, game_id, ayyuid
),

watch_user_day as (
  select
    w.dt,
    substr(w.dt, 1, 7) as month,
    w.game_id,
    max(w.game_name) as game_name,
    w.creator_uid as ayyuid,
    max(w.creator_nick) as watch_nickname,
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
  group by w.dt, substr(w.dt, 1, 7), w.game_id, w.creator_uid, w.user_ukey
),

watch_anchor_month as (
  select
    month,
    game_id,
    max(game_name) as game_name,
    ayyuid,
    max(watch_nickname) as watch_nickname,
    sum(daily_watch_user_cnt) as daily_watch_user_cnt_sum,
    sum(watch_duration) as total_watch_duration,
    count(distinct user_ukey) as month_watch_user_cnt
  from (
    select
      dt,
      month,
      game_id,
      max(game_name) as game_name,
      ayyuid,
      max(watch_nickname) as watch_nickname,
      count(distinct user_ukey) as daily_watch_user_cnt,
      sum(watch_duration) as watch_duration,
      user_ukey
    from watch_user_day
    group by dt, month, game_id, ayyuid, user_ukey
  ) t
  group by month, game_id, ayyuid
),

retention_base as (
  select
    month,
    game_id,
    max(game_name) as game_name,
    ayyuid,
    user_ukey,
    min(dt) as cohort_date
  from watch_user_day
  where dt between '2026-01-01' and '2026-07-20'
  group by month, game_id, ayyuid, user_ukey
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

retention_month as (
  select
    b.month,
    b.game_id,
    max(b.game_name) as game_name,
    b.ayyuid,
    count(distinct b.user_ukey) as d7_retention_base_user_cnt,
    count(distinct case when a.user_ukey is not null then b.user_ukey end) as d7_retained_user_cnt
  from retention_base b
  left join active_day a
    on b.user_ukey = a.user_ukey
   and a.dt = date_format(date_add('day', 6, date_parse(b.cohort_date, '%Y-%m-%d')), '%Y-%m-%d')
  group by b.month, b.game_id, b.ayyuid
),

month_anchor_key as (
  select month, game_id, ayyuid from anchor_live_month
  union
  select month, game_id, ayyuid from revenue_anchor_month
  union
  select month, game_id, ayyuid from revenue_user_month_agg
  union
  select month, game_id, ayyuid from watch_anchor_month
)

select
  k.month,
  k.game_id,
  coalesce(l.game_name, r.game_name, ru.game_name, w.game_name, case when k.game_id = 1663 then '星秀' else '户外' end) as game_name,
  k.ayyuid,
  coalesce(l.live_nickname, w.watch_nickname, a.nickname) as nickname,
  m.observed_days,

  coalesce(r.daily_pay_user_cnt_sum, 0) * 1.0000 / nullif(m.observed_days, 0) as avg_daily_pay_user_cnt,
  coalesce(r.total_consume_amt, 0) * 1.0000 / nullif(m.observed_days, 0) as avg_daily_consume_amt,
  coalesce(l.total_live_hours, 0) * 1.0000 / nullif(m.observed_days, 0) as avg_daily_live_hours,

  coalesce(ru.big_r_user_cnt, 0) as big_r_user_cnt,
  coalesce(w.total_watch_duration, 0) as total_watch_duration,
  coalesce(w.daily_watch_user_cnt_sum, 0) * 1.0000 / nullif(m.observed_days, 0) as avg_watch_dau,
  coalesce(w.month_watch_user_cnt, 0) as month_watch_user_cnt,

  coalesce(ret.d7_retention_base_user_cnt, 0) as d7_retention_base_user_cnt,
  coalesce(ret.d7_retained_user_cnt, 0) as d7_retained_user_cnt,
  coalesce(ret.d7_retained_user_cnt, 0) * 1.0000
    / nullif(coalesce(ret.d7_retention_base_user_cnt, 0), 0) as d7_retention_rate,

  coalesce(r.total_consume_amt, 0) as total_consume_amt,
  coalesce(ru.month_pay_user_cnt, 0) as month_pay_user_cnt,
  coalesce(r.total_consume_amt, 0) * 1.0000
    / nullif(coalesce(ru.month_pay_user_cnt, 0), 0) as avg_consume_amt_per_pay_user,
  coalesce(r.total_consume_amt, 0) * 1.0000
    / nullif(coalesce(w.month_watch_user_cnt, 0), 0) as avg_consume_amt_per_watch_user
from month_anchor_key k
left join month_days m
  on k.month = m.month
 and k.game_id = m.game_id
left join anchor_live_month l
  on k.month = l.month
 and k.game_id = l.game_id
 and k.ayyuid = l.ayyuid
left join revenue_anchor_month r
  on k.month = r.month
 and k.game_id = r.game_id
 and k.ayyuid = r.ayyuid
left join revenue_user_month_agg ru
  on k.month = ru.month
 and k.game_id = ru.game_id
 and k.ayyuid = ru.ayyuid
left join watch_anchor_month w
  on k.month = w.month
 and k.game_id = w.game_id
 and k.ayyuid = w.ayyuid
left join retention_month ret
  on k.month = ret.month
 and k.game_id = ret.game_id
 and k.ayyuid = ret.ayyuid
left join anchor_info a
  on k.ayyuid = a.uid
order by k.month, k.game_id, total_consume_amt desc;
