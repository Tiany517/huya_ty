-- Spark SQL
-- 口径说明：
-- 1. 样本：2026-01-01 至 2026-07-20 期间，星秀/户外主播拉新或回流用户；7月因分区到2026-07-26，cohort只取到2026-07-20。
-- 2. 游戏：1663=星秀，2165=户外。
-- 3. 粒度：月份 + game_id + 主播luid + 用户类型(label=拉新/回流)。
-- 4. 后续表现窗口：拉新/回流当日 至 当日+6天，共7天。
-- 5. 打赏：7日内对同一game_id、同一主播的打赏金额；观时：7日内观看同一game_id、同一主播直播观时。
-- 6. 活跃/留存：APP活跃；D7留存为拉新/回流当日+6天当天活跃。

with laxin_huiliu_user_raw as (
  select distinct
    dt as cohort_date,
    substr(dt, 1, 7) as month,
    game_id,
    luid,
    luid_name,
    user_ukey,
    '拉新' as label
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
  where dt between '2026-01-01' and '2026-07-20'
    and game_id in (1663, 2165)
    and user_ukey is not null

  union all

  select distinct
    dt as cohort_date,
    substr(dt, 1, 7) as month,
    game_id,
    luid,
    luid_name,
    user_ukey,
    '回流' as label
  from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1
  where dt between '2026-01-01' and '2026-07-20'
    and game_id in (1663, 2165)
    and user_ukey is not null
),

laxin_huiliu_user as (
  select
    month,
    game_id,
    luid,
    max(luid_name) as luid_name,
    user_ukey,
    label,
    min(cohort_date) as cohort_date
  from laxin_huiliu_user_raw
  group by month, game_id, luid, user_ukey, label
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

watch_user_day as (
  select
    dt,
    game_id,
    creator_uid as luid,
    user_ukey,
    sum(watch_duration) as watch_duration
  from gamelive.dws_huya_user_behavior_d_i
  where dt between '2026-01-01' and '2026-07-26'
    and game_id in (1663, 2165)
    and product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
    and data_type = 'live_watch_session'
    and live_content_type = '直播'
    and is_black_ukey = 0
    and watch_cnt > 0
    and watch_duration > 0
  group by dt, game_id, creator_uid, user_ukey
),

pay_user_day as (
  select
    p.dt,
    p.game_id,
    p.creator_uid as luid,
    p.ext['ukey'] as user_ukey,
    sum(p.user_consume_amount) as consume_amt
  from zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i p
  where p.dt between '2026-01-01' and '2026-07-26'
    and p.user_consume_amount > 0
    and p.game_label = '娱乐'
    and p.game_id in (1663, 2165)
  group by p.dt, p.game_id, p.creator_uid, p.ext['ukey']
),

active_user_7d as (
  select
    u.month,
    u.game_id,
    u.luid,
    u.label,
    u.cohort_date,
    u.user_ukey,
    count(distinct a.dt) as active_days_7d,
    max(case when a.dt = date_format(date_add(to_date(u.cohort_date), 6), 'yyyy-MM-dd') then 1 else 0 end) as is_d7_retained
  from laxin_huiliu_user u
  left join active_day a
    on u.user_ukey = a.user_ukey
   and a.dt between u.cohort_date and date_format(date_add(to_date(u.cohort_date), 6), 'yyyy-MM-dd')
  group by u.month, u.game_id, u.luid, u.label, u.cohort_date, u.user_ukey
),

watch_user_7d as (
  select
    u.month,
    u.game_id,
    u.luid,
    u.label,
    u.cohort_date,
    u.user_ukey,
    sum(coalesce(w.watch_duration, 0)) as watch_duration_7d
  from laxin_huiliu_user u
  left join watch_user_day w
    on u.user_ukey = w.user_ukey
   and u.game_id = w.game_id
   and u.luid = w.luid
   and w.dt between u.cohort_date and date_format(date_add(to_date(u.cohort_date), 6), 'yyyy-MM-dd')
  group by u.month, u.game_id, u.luid, u.label, u.cohort_date, u.user_ukey
),

pay_user_7d as (
  select
    u.month,
    u.game_id,
    u.luid,
    u.label,
    u.cohort_date,
    u.user_ukey,
    sum(coalesce(p.consume_amt, 0)) as consume_amt_7d
  from laxin_huiliu_user u
  left join pay_user_day p
    on u.user_ukey = p.user_ukey
   and u.game_id = p.game_id
   and u.luid = p.luid
   and p.dt between u.cohort_date and date_format(date_add(to_date(u.cohort_date), 6), 'yyyy-MM-dd')
  group by u.month, u.game_id, u.luid, u.label, u.cohort_date, u.user_ukey
),

user_7d as (
  select
    u.month,
    u.game_id,
    case when u.game_id = 1663 then '星秀' else '户外' end as game_name,
    u.luid,
    u.luid_name,
    u.label,
    u.cohort_date,
    u.user_ukey,
    coalesce(a.active_days_7d, 0) as active_days_7d,
    coalesce(a.is_d7_retained, 0) as is_d7_retained,
    coalesce(w.watch_duration_7d, 0) as watch_duration_7d,
    coalesce(p.consume_amt_7d, 0) as consume_amt_7d
  from laxin_huiliu_user u
  left join active_user_7d a
    on u.month = a.month
   and u.game_id = a.game_id
   and u.luid = a.luid
   and u.label = a.label
   and u.cohort_date = a.cohort_date
   and u.user_ukey = a.user_ukey
  left join watch_user_7d w
    on u.month = w.month
   and u.game_id = w.game_id
   and u.luid = w.luid
   and u.label = w.label
   and u.cohort_date = w.cohort_date
   and u.user_ukey = w.user_ukey
  left join pay_user_7d p
    on u.month = p.month
   and u.game_id = p.game_id
   and u.luid = p.luid
   and u.label = p.label
   and u.cohort_date = p.cohort_date
   and u.user_ukey = p.user_ukey
)

select
  month,
  game_id,
  max(game_name) as game_name,
  luid,
  max(luid_name) as luid_name,
  label,
  count(distinct user_ukey) as cohort_user_cnt,

  sum(active_days_7d) as active_days_7d_sum,
  avg(active_days_7d) as avg_active_days_7d,
  count(distinct case when is_d7_retained = 1 then user_ukey end) as d7_retained_user_cnt,
  case
    when count(distinct user_ukey) > 0
    then count(distinct case when is_d7_retained = 1 then user_ukey end) * 1.0000 / count(distinct user_ukey)
  end as d7_retention_rate,

  sum(watch_duration_7d) as watch_duration_7d,
  case when count(distinct user_ukey) > 0 then sum(watch_duration_7d) * 1.0000 / count(distinct user_ukey) end as avg_watch_duration_7d_per_user,
  count(distinct case when watch_duration_7d > 0 then user_ukey end) as watch_user_cnt_7d,

  sum(consume_amt_7d) as consume_amt_7d,
  count(distinct case when consume_amt_7d > 0 then user_ukey end) as pay_user_cnt_7d,
  case when count(distinct user_ukey) > 0 then sum(consume_amt_7d) * 1.0000 / count(distinct user_ukey) end as arpu_7d,
  case
    when count(distinct case when consume_amt_7d > 0 then user_ukey end) > 0
    then sum(consume_amt_7d) * 1.0000 / count(distinct case when consume_amt_7d > 0 then user_ukey end)
  end as arppu_7d
from user_7d
group by month, game_id, luid, label
order by month, game_id, label, consume_amt_7d desc;
