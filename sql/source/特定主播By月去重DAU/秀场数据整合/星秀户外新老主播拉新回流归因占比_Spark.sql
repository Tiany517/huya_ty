-- Spark SQL
-- 口径说明：
-- 1. 时间：2026-01-01 至 2026-07-26；7月按已有分区只统计到7月26日。
-- 2. 游戏：1663=星秀，2165=户外。
-- 3. 目标：衡量“由近3个月新开播主播/老主播归因的拉新、回流用户”，占当月该品类整体观看用户的比重。
-- 4. 近3个月新开播主播：主播首次开播月在当前月及往前2个月内，例如2026-07包含2026-05/06/07首次开播主播。
-- 5. 拉新/回流主播归因：直接使用拉新/回流表中的luid，不使用后续观看或打赏行为给用户归属主播。
-- 6. 用户去重：同一用户同一月同一game_id只保留一条归因记录；若同月同时拉新和回流，优先算拉新；若同类型多条记录，取最早dt，再按luid兜底排序。
-- 7. 分母total_watch_user_cnt：该月该game_id观看直播的月去重用户数。
-- 8. 输出包含新主播、老主播、全部主播三行；理论上新主播+老主播=全部主播。如不相等，说明源表同一用户同月多主播归因且去重规则需重新确认。
-- 9. 7日表现：以拉新/回流归因日期cohort_date为起点，统计cohort_date至cohort_date+6天同game_id的打赏、观时、APP活跃天数和D7留存；因分区到2026-07-26，7日表现cohort只统计到2026-07-20。

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

anchor_first_live as (
  select
    gameid as game_id,
    ayyuid as luid,
    min(substr(dt, 1, 7)) as first_live_month
  from gamelive.dm_huya_ayyuid_detail_day
  where dt between '2024-01-01' and '2026-07-26'
    and gameid in (1663, 2165)
    and live_hours_only_live > 0
  group by gameid, ayyuid
),

game_month_watch_user as (
  select
    substr(dt, 1, 7) as month,
    game_id,
    count(distinct user_ukey) as total_watch_user_cnt
  from gamelive.dws_huya_user_behavior_d_i
  where dt between '2026-01-01' and '2026-07-26'
    and game_id in (1663, 2165)
    and product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
    and data_type = 'live_watch_session'
    and live_content_type = '直播'
    and is_black_ukey = 0
    and watch_cnt > 0
    and watch_duration > 0
    and user_ukey is not null
  group by substr(dt, 1, 7), game_id
),

laxin_huiliu_raw as (
  select distinct
    a.dt as cohort_date,
    substr(a.dt, 1, 7) as month,
    a.game_id,
    a.luid,
    a.user_ukey,
    '拉新' as user_type,
    1 as user_type_priority
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a
  where a.dt between '2026-01-01' and '2026-07-26'
    and a.game_id in (1663, 2165)
    and a.user_ukey is not null
    and a.luid is not null
    and a.guiyin_tag <> 'mailiang'

  union all

  select distinct
    a.dt as cohort_date,
    substr(a.dt, 1, 7) as month,
    a.game_id,
    a.luid,
    a.user_ukey,
    '回流' as user_type,
    2 as user_type_priority
  from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1 a
  where a.dt between '2026-01-01' and '2026-07-26'
    and a.game_id in (1663, 2165)
    and a.user_ukey is not null
    and a.luid is not null
),

-- 每个用户每月每个game只保留一个拉新/回流归因主播，避免新老主播重复计数。
laxin_huiliu_user_one as (
  select
    month,
    game_id,
    luid,
    user_ukey,
    user_type,
    cohort_date
  from (
    select
      month,
      game_id,
      luid,
      user_ukey,
      user_type,
      cohort_date,
      row_number() over (
        partition by month, game_id, user_ukey
        order by user_type_priority, cohort_date, luid
      ) as rn
    from laxin_huiliu_raw
  ) t
  where rn = 1
),

laxin_huiliu_user_tag as (
  select
    u.month,
    u.game_id,
    u.luid,
    u.user_ukey,
    u.user_type,
    u.cohort_date,
    case
      when to_date(concat(f.first_live_month, '-01'))
           between add_months(to_date(concat(u.month, '-01')), -2)
               and to_date(concat(u.month, '-01'))
      then '近3个月新开播主播'
      else '老主播'
    end as anchor_type
  from laxin_huiliu_user_one u
  left join anchor_first_live f
    on u.game_id = f.game_id
   and u.luid = f.luid
),

active_day as (
  select distinct
    dt,
    user_ukey
  from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
  where dt between '2026-01-01' and '2026-07-26'
    and product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
    and is_black_ukey = 0
    and user_ukey is not null
),

watch_user_day as (
  select
    dt,
    game_id,
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
    and user_ukey is not null
  group by dt, game_id, user_ukey
),

pay_user_day as (
  select
    p.dt,
    p.game_id,
    p.ext['ukey'] as user_ukey,
    sum(p.user_consume_amount) as consume_amt
  from zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i p
  where p.dt between '2026-01-01' and '2026-07-26'
    and p.user_consume_amount > 0
    and p.game_label = '娱乐'
    and p.game_id in (1663, 2165)
    and p.ext['ukey'] is not null
  group by p.dt, p.game_id, p.ext['ukey']
),

cohort_user_7d as (
  select
    u.month,
    u.game_id,
    u.anchor_type,
    u.user_type,
    u.user_ukey,
    count(distinct a.dt) as active_days_7d,
    max(case when a.dt = date_format(date_add(to_date(u.cohort_date), 6), 'yyyy-MM-dd') then 1 else 0 end) as is_d7_retained,
    sum(coalesce(w.watch_duration, 0)) as watch_duration_7d,
    sum(coalesce(p.consume_amt, 0)) as consume_amt_7d
  from laxin_huiliu_user_tag u
  left join active_day a
    on u.user_ukey = a.user_ukey
   and a.dt between u.cohort_date and date_format(date_add(to_date(u.cohort_date), 6), 'yyyy-MM-dd')
  left join watch_user_day w
    on u.user_ukey = w.user_ukey
   and u.game_id = w.game_id
   and w.dt between u.cohort_date and date_format(date_add(to_date(u.cohort_date), 6), 'yyyy-MM-dd')
  left join pay_user_day p
    on u.user_ukey = p.user_ukey
   and u.game_id = p.game_id
   and p.dt between u.cohort_date and date_format(date_add(to_date(u.cohort_date), 6), 'yyyy-MM-dd')
  where u.cohort_date between '2026-01-01' and '2026-07-20'
  group by u.month, u.game_id, u.anchor_type, u.user_type, u.user_ukey
),

metric_by_anchor_type as (
  select
    month,
    game_id,
    anchor_type,
    count(distinct case when user_type = '拉新' then user_ukey end) as laxin_user_cnt,
    count(distinct case when user_type = '回流' then user_ukey end) as huiliu_user_cnt,
    count(distinct user_ukey) as laxin_huiliu_user_cnt,
    sum(case when user_type = '拉新' then consume_amt_7d else 0 end) as laxin_consume_amt_7d,
    sum(case when user_type = '回流' then consume_amt_7d else 0 end) as huiliu_consume_amt_7d,
    sum(case when user_type = '拉新' then watch_duration_7d else 0 end) as laxin_watch_duration_7d,
    sum(case when user_type = '回流' then watch_duration_7d else 0 end) as huiliu_watch_duration_7d,
    avg(case when user_type = '拉新' then active_days_7d end) as laxin_avg_active_days_7d,
    avg(case when user_type = '回流' then active_days_7d end) as huiliu_avg_active_days_7d,
    count(distinct case when user_type = '拉新' and is_d7_retained = 1 then user_ukey end) as laxin_d7_retained_user_cnt,
    count(distinct case when user_type = '回流' and is_d7_retained = 1 then user_ukey end) as huiliu_d7_retained_user_cnt
  from cohort_user_7d
  group by month, game_id, anchor_type

  union all

  select
    month,
    game_id,
    '全部主播' as anchor_type,
    count(distinct case when user_type = '拉新' then user_ukey end) as laxin_user_cnt,
    count(distinct case when user_type = '回流' then user_ukey end) as huiliu_user_cnt,
    count(distinct user_ukey) as laxin_huiliu_user_cnt,
    sum(case when user_type = '拉新' then consume_amt_7d else 0 end) as laxin_consume_amt_7d,
    sum(case when user_type = '回流' then consume_amt_7d else 0 end) as huiliu_consume_amt_7d,
    sum(case when user_type = '拉新' then watch_duration_7d else 0 end) as laxin_watch_duration_7d,
    sum(case when user_type = '回流' then watch_duration_7d else 0 end) as huiliu_watch_duration_7d,
    avg(case when user_type = '拉新' then active_days_7d end) as laxin_avg_active_days_7d,
    avg(case when user_type = '回流' then active_days_7d end) as huiliu_avg_active_days_7d,
    count(distinct case when user_type = '拉新' and is_d7_retained = 1 then user_ukey end) as laxin_d7_retained_user_cnt,
    count(distinct case when user_type = '回流' and is_d7_retained = 1 then user_ukey end) as huiliu_d7_retained_user_cnt
  from cohort_user_7d
  group by month, game_id
)

select
  m.month,
  m.game_id,
  case when m.game_id = 1663 then '星秀' else '户外' end as game_name,
  m.anchor_type,
  d.observed_days,
  w.total_watch_user_cnt,

  m.laxin_user_cnt,
  case when w.total_watch_user_cnt > 0 then m.laxin_user_cnt * 1.0000 / w.total_watch_user_cnt end as laxin_user_share_of_total_watch_user,
  m.huiliu_user_cnt,
  case when w.total_watch_user_cnt > 0 then m.huiliu_user_cnt * 1.0000 / w.total_watch_user_cnt end as huiliu_user_share_of_total_watch_user,
  m.laxin_huiliu_user_cnt,
  case when w.total_watch_user_cnt > 0 then m.laxin_huiliu_user_cnt * 1.0000 / w.total_watch_user_cnt end as laxin_huiliu_user_share_of_total_watch_user,

  m.laxin_consume_amt_7d,
  case when m.laxin_user_cnt > 0 then m.laxin_consume_amt_7d * 1.0000 / m.laxin_user_cnt end as laxin_avg_consume_amt_7d_per_user,
  m.huiliu_consume_amt_7d,
  case when m.huiliu_user_cnt > 0 then m.huiliu_consume_amt_7d * 1.0000 / m.huiliu_user_cnt end as huiliu_avg_consume_amt_7d_per_user,

  m.laxin_watch_duration_7d,
  case when m.laxin_user_cnt > 0 then m.laxin_watch_duration_7d * 1.0000 / m.laxin_user_cnt end as laxin_avg_watch_duration_7d_per_user,
  m.huiliu_watch_duration_7d,
  case when m.huiliu_user_cnt > 0 then m.huiliu_watch_duration_7d * 1.0000 / m.huiliu_user_cnt end as huiliu_avg_watch_duration_7d_per_user,

  m.laxin_avg_active_days_7d,
  case when m.laxin_user_cnt > 0 then m.laxin_d7_retained_user_cnt * 1.0000 / m.laxin_user_cnt end as laxin_d7_retention_rate,
  m.huiliu_avg_active_days_7d,
  case when m.huiliu_user_cnt > 0 then m.huiliu_d7_retained_user_cnt * 1.0000 / m.huiliu_user_cnt end as huiliu_d7_retention_rate
from metric_by_anchor_type m
left join game_month_watch_user w
  on m.month = w.month
 and m.game_id = w.game_id
left join month_days d
  on m.month = d.month
 and m.game_id = d.game_id
order by
  m.month,
  m.game_id,
  case
    when m.anchor_type = '全部主播' then 1
    when m.anchor_type = '近3个月新开播主播' then 2
    else 3
  end;
