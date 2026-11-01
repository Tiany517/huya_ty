-- Spark SQL
-- 口径说明：
-- 1. 时间：2026-01-01 至 2026-07-26；7月按已有分区只统计到7月26日。
-- 2. 游戏：1663=星秀，2165=户外。
-- 3. 粒度：月份 + game_id + anchor_type。
--    anchor_type包含：近3个月新开播主播、老主播、全部主播。
-- 4. 近3个月新开播主播：主播首次开播月在当前月及往前2个月内，例如2026-07包含2026-05/06/07首次开播主播。
-- 5. 用户类型：
--    拉新：当月出现在拉新表，且剔除guiyin_tag='mailiang'的买量用户；
--    回流：当月未拉新但出现在回流表；
--    老用户：当月观看该game_id该anchor_type但不属于拉新/回流。
--    若同一用户同月同时出现在拉新和回流表，优先归为拉新，避免分类型加总重复。
-- 6. 用户数：观看用户月去重；全部主播行同一用户当月只计一次，新/老主播行同一用户若分别观看两类主播，会分别计入对应行。
-- 7. 人均打赏金额：该用户类型在该anchor_type下的月打赏金额 / 该用户类型观看用户数，不是付费用户ARPPU。
-- 8. 人均观时：输出为人均日均观时，即月观看时长 / 当月已观测自然天数 / 观看用户数。
-- 9. 7日活跃和7日留存：以用户当月首次观看该game_id该anchor_type的日期为cohort_date，窗口为cohort_date至cohort_date+6天；因分区到2026-07-26，留存cohort只取到2026-07-20。
-- 10. 开播时长：输出该anchor_type下主播当月总开播时长和日均开播时长；全部主播为该game_id全部主播汇总。

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
    ayyuid,
    min(substr(dt, 1, 7)) as first_live_month
  from gamelive.dm_huya_ayyuid_detail_day
  where dt between '2024-01-01' and '2026-07-26'
    and gameid in (1663, 2165)
    and live_hours_only_live > 0
  group by gameid, ayyuid
),

anchor_live_month_base as (
  select
    substr(l.dt, 1, 7) as month,
    l.gameid as game_id,
    l.ayyuid,
    sum(l.live_hours_only_live) as live_hours
  from gamelive.dm_huya_ayyuid_detail_day l
  where l.dt between '2026-01-01' and '2026-07-26'
    and l.gameid in (1663, 2165)
    and l.live_hours_only_live > 0
  group by substr(l.dt, 1, 7), l.gameid, l.ayyuid
),

anchor_live_month_tag as (
  select
    l.month,
    l.game_id,
    l.ayyuid,
    case
      when to_date(concat(f.first_live_month, '-01'))
           between add_months(to_date(concat(l.month, '-01')), -2)
               and to_date(concat(l.month, '-01'))
      then '近3个月新开播主播'
      else '老主播'
    end as anchor_type,
    l.live_hours
  from anchor_live_month_base l
  left join anchor_first_live f
    on l.game_id = f.game_id
   and l.ayyuid = f.ayyuid
),

live_anchor_type_month as (
  select
    month,
    game_id,
    anchor_type,
    count(distinct ayyuid) as live_anchor_cnt,
    sum(live_hours) as total_live_hours
  from anchor_live_month_tag
  group by month, game_id, anchor_type

  union all

  select
    month,
    game_id,
    '全部主播' as anchor_type,
    count(distinct ayyuid) as live_anchor_cnt,
    sum(live_hours) as total_live_hours
  from anchor_live_month_tag
  group by month, game_id
),

laxin_huiliu_user_raw as (
  select distinct
    dt,
    substr(dt, 1, 7) as month,
    game_id,
    user_ukey,
    '拉新' as label
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a
  where a.dt between '2026-01-01' and '2026-07-26'
    and a.game_id in (1663, 2165)
    and a.user_ukey is not null
    and a.guiyin_tag <> 'mailiang'

  union all

  select distinct
    dt,
    substr(dt, 1, 7) as month,
    game_id,
    user_ukey,
    '回流' as label
  from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1
  where dt between '2026-01-01' and '2026-07-26'
    and game_id in (1663, 2165)
    and user_ukey is not null
),

user_month_label as (
  select
    month,
    game_id,
    user_ukey,
    case
      when max(case when label = '拉新' then 1 else 0 end) = 1 then '拉新'
      when max(case when label = '回流' then 1 else 0 end) = 1 then '回流'
      else '老用户'
    end as user_type
  from laxin_huiliu_user_raw
  group by month, game_id, user_ukey
),

watch_user_anchor_day_base as (
  select
    w.dt,
    substr(w.dt, 1, 7) as month,
    w.game_id,
    w.creator_uid as ayyuid,
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
    and w.user_ukey is not null
  group by w.dt, substr(w.dt, 1, 7), w.game_id, w.creator_uid, w.user_ukey
),

watch_user_anchor_type_day as (
  select
    w.dt,
    w.month,
    w.game_id,
    t.anchor_type,
    w.user_ukey,
    sum(w.watch_duration) as watch_duration
  from watch_user_anchor_day_base w
  left join anchor_live_month_tag t
    on w.month = t.month
   and w.game_id = t.game_id
   and w.ayyuid = t.ayyuid
  where t.anchor_type is not null
  group by w.dt, w.month, w.game_id, t.anchor_type, w.user_ukey

  union all

  select
    dt,
    month,
    game_id,
    '全部主播' as anchor_type,
    user_ukey,
    sum(watch_duration) as watch_duration
  from watch_user_anchor_day_base
  group by dt, month, game_id, user_ukey
),

watch_user_anchor_type_month as (
  select
    w.month,
    w.game_id,
    w.anchor_type,
    w.user_ukey,
    coalesce(l.user_type, '老用户') as user_type,
    sum(w.watch_duration) as watch_duration
  from watch_user_anchor_type_day w
  left join user_month_label l
    on w.month = l.month
   and w.game_id = l.game_id
   and w.user_ukey = l.user_ukey
  group by w.month, w.game_id, w.anchor_type, w.user_ukey, coalesce(l.user_type, '老用户')
),

revenue_user_anchor_day_base as (
  select
    p.dt,
    substr(p.dt, 1, 7) as month,
    p.game_id,
    p.creator_uid as ayyuid,
    p.ext['ukey'] as user_ukey,
    sum(p.user_consume_amount) as consume_amt
  from zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i p
  where p.dt between '2026-01-01' and '2026-07-26'
    and p.user_consume_amount > 0
    and p.game_label = '娱乐'
    and p.game_id in (1663, 2165)
    and p.ext['ukey'] is not null
  group by p.dt, substr(p.dt, 1, 7), p.game_id, p.creator_uid, p.ext['ukey']
),

revenue_user_anchor_type_month as (
  select
    p.month,
    p.game_id,
    t.anchor_type,
    p.user_ukey,
    sum(p.consume_amt) as consume_amt
  from revenue_user_anchor_day_base p
  left join anchor_live_month_tag t
    on p.month = t.month
   and p.game_id = t.game_id
   and p.ayyuid = t.ayyuid
  where t.anchor_type is not null
  group by p.month, p.game_id, t.anchor_type, p.user_ukey

  union all

  select
    month,
    game_id,
    '全部主播' as anchor_type,
    user_ukey,
    sum(consume_amt) as consume_amt
  from revenue_user_anchor_day_base
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
    and user_ukey is not null
),

retention_base as (
  select
    w.month,
    w.game_id,
    w.anchor_type,
    w.user_ukey,
    coalesce(l.user_type, '老用户') as user_type,
    min(w.dt) as cohort_date
  from watch_user_anchor_type_day w
  left join user_month_label l
    on w.month = l.month
   and w.game_id = l.game_id
   and w.user_ukey = l.user_ukey
  where w.dt between '2026-01-01' and '2026-07-20'
  group by w.month, w.game_id, w.anchor_type, w.user_ukey, coalesce(l.user_type, '老用户')
),

retention_user_7d as (
  select
    b.month,
    b.game_id,
    b.anchor_type,
    b.user_type,
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
  group by b.month, b.game_id, b.anchor_type, b.user_type, b.user_ukey
),

user_type_month as (
  select
    w.month,
    w.game_id,
    w.anchor_type,
    w.user_type,
    count(distinct w.user_ukey) as user_cnt,
    sum(w.watch_duration) as watch_duration,
    sum(coalesce(p.consume_amt, 0)) as consume_amt,
    count(distinct case when coalesce(p.consume_amt, 0) > 0 then w.user_ukey end) as pay_user_cnt
  from watch_user_anchor_type_month w
  left join revenue_user_anchor_type_month p
    on w.month = p.month
   and w.game_id = p.game_id
   and w.anchor_type = p.anchor_type
   and w.user_ukey = p.user_ukey
  group by w.month, w.game_id, w.anchor_type, w.user_type
),

retention_type_month as (
  select
    month,
    game_id,
    anchor_type,
    user_type,
    count(distinct user_ukey) as d7_base_user_cnt,
    count(distinct case when is_d7_retained = 1 then user_ukey end) as d7_retained_user_cnt,
    avg(active_days_7d) as avg_active_days_7d
  from retention_user_7d
  group by month, game_id, anchor_type, user_type
),

metric_type_month as (
  select
    u.month,
    u.game_id,
    u.anchor_type,
    u.user_type,
    u.user_cnt,
    u.pay_user_cnt,
    u.consume_amt,
    u.watch_duration,
    r.d7_base_user_cnt,
    r.d7_retained_user_cnt,
    r.avg_active_days_7d
  from user_type_month u
  left join retention_type_month r
    on u.month = r.month
   and u.game_id = r.game_id
   and u.anchor_type = r.anchor_type
   and u.user_type = r.user_type
),

metric_with_total as (
  select
    month,
    game_id,
    anchor_type,
    user_type,
    user_cnt,
    pay_user_cnt,
    consume_amt,
    watch_duration,
    d7_base_user_cnt,
    d7_retained_user_cnt,
    avg_active_days_7d
  from metric_type_month

  union all

  select
    month,
    game_id,
    anchor_type,
    '总计' as user_type,
    count(distinct user_ukey) as user_cnt,
    count(distinct case when coalesce(consume_amt, 0) > 0 then user_ukey end) as pay_user_cnt,
    sum(coalesce(consume_amt, 0)) as consume_amt,
    sum(watch_duration) as watch_duration,
    cast(null as bigint) as d7_base_user_cnt,
    cast(null as bigint) as d7_retained_user_cnt,
    cast(null as double) as avg_active_days_7d
  from (
    select
      w.month,
      w.game_id,
      w.anchor_type,
      w.user_ukey,
      w.watch_duration,
      p.consume_amt
    from watch_user_anchor_type_month w
    left join revenue_user_anchor_type_month p
      on w.month = p.month
     and w.game_id = p.game_id
     and w.anchor_type = p.anchor_type
     and w.user_ukey = p.user_ukey
  ) t
  group by month, game_id, anchor_type
),

retention_total as (
  select
    month,
    game_id,
    anchor_type,
    count(distinct user_ukey) as d7_base_user_cnt,
    count(distinct case when is_d7_retained = 1 then user_ukey end) as d7_retained_user_cnt,
    avg(active_days_7d) as avg_active_days_7d
  from retention_user_7d
  group by month, game_id, anchor_type
),

metric_final_long as (
  select
    m.month,
    m.game_id,
    m.anchor_type,
    m.user_type,
    m.user_cnt,
    m.pay_user_cnt,
    m.consume_amt,
    m.watch_duration,
    case when m.user_type = '总计' then rt.d7_base_user_cnt else m.d7_base_user_cnt end as d7_base_user_cnt,
    case when m.user_type = '总计' then rt.d7_retained_user_cnt else m.d7_retained_user_cnt end as d7_retained_user_cnt,
    case when m.user_type = '总计' then rt.avg_active_days_7d else m.avg_active_days_7d end as avg_active_days_7d
  from metric_with_total m
  left join retention_total rt
    on m.month = rt.month
   and m.game_id = rt.game_id
   and m.anchor_type = rt.anchor_type
   and m.user_type = '总计'
)

select
  f.month,
  f.game_id,
  case when f.game_id = 1663 then '星秀' else '户外' end as game_name,
  f.anchor_type,
  coalesce(l.live_anchor_cnt, 0) as live_anchor_cnt,
  coalesce(l.total_live_hours, 0) as total_live_hours,
  case when d.observed_days > 0 then coalesce(l.total_live_hours, 0) * 1.0000 / d.observed_days end as avg_daily_live_hours,
  d.observed_days,

  sum(case when f.user_type = '拉新' then f.user_cnt else 0 end) as laxin_user_cnt,
  sum(case when f.user_type = '回流' then f.user_cnt else 0 end) as huiliu_user_cnt,
  sum(case when f.user_type = '老用户' then f.user_cnt else 0 end) as old_user_cnt,
  sum(case when f.user_type = '总计' then f.user_cnt else 0 end) as total_user_cnt,

  sum(case when f.user_type = '拉新' then f.pay_user_cnt else 0 end) as laxin_pay_user_cnt,
  sum(case when f.user_type = '回流' then f.pay_user_cnt else 0 end) as huiliu_pay_user_cnt,
  sum(case when f.user_type = '老用户' then f.pay_user_cnt else 0 end) as old_pay_user_cnt,
  sum(case when f.user_type = '总计' then f.pay_user_cnt else 0 end) as total_pay_user_cnt,

  case when sum(case when f.user_type = '拉新' then f.user_cnt else 0 end) > 0
       then sum(case when f.user_type = '拉新' then f.consume_amt else 0 end) * 1.0000 / sum(case when f.user_type = '拉新' then f.user_cnt else 0 end) end as laxin_avg_consume_amt_per_user,
  case when sum(case when f.user_type = '回流' then f.user_cnt else 0 end) > 0
       then sum(case when f.user_type = '回流' then f.consume_amt else 0 end) * 1.0000 / sum(case when f.user_type = '回流' then f.user_cnt else 0 end) end as huiliu_avg_consume_amt_per_user,
  case when sum(case when f.user_type = '老用户' then f.user_cnt else 0 end) > 0
       then sum(case when f.user_type = '老用户' then f.consume_amt else 0 end) * 1.0000 / sum(case when f.user_type = '老用户' then f.user_cnt else 0 end) end as old_avg_consume_amt_per_user,
  case when sum(case when f.user_type = '总计' then f.user_cnt else 0 end) > 0
       then sum(case when f.user_type = '总计' then f.consume_amt else 0 end) * 1.0000 / sum(case when f.user_type = '总计' then f.user_cnt else 0 end) end as total_avg_consume_amt_per_user,

  case when d.observed_days > 0 and sum(case when f.user_type = '拉新' then f.user_cnt else 0 end) > 0
       then sum(case when f.user_type = '拉新' then f.watch_duration else 0 end) * 1.0000 / d.observed_days / sum(case when f.user_type = '拉新' then f.user_cnt else 0 end) end as laxin_avg_daily_watch_duration_per_user,
  case when d.observed_days > 0 and sum(case when f.user_type = '回流' then f.user_cnt else 0 end) > 0
       then sum(case when f.user_type = '回流' then f.watch_duration else 0 end) * 1.0000 / d.observed_days / sum(case when f.user_type = '回流' then f.user_cnt else 0 end) end as huiliu_avg_daily_watch_duration_per_user,
  case when d.observed_days > 0 and sum(case when f.user_type = '老用户' then f.user_cnt else 0 end) > 0
       then sum(case when f.user_type = '老用户' then f.watch_duration else 0 end) * 1.0000 / d.observed_days / sum(case when f.user_type = '老用户' then f.user_cnt else 0 end) end as old_avg_daily_watch_duration_per_user,
  case when d.observed_days > 0 and sum(case when f.user_type = '总计' then f.user_cnt else 0 end) > 0
       then sum(case when f.user_type = '总计' then f.watch_duration else 0 end) * 1.0000 / d.observed_days / sum(case when f.user_type = '总计' then f.user_cnt else 0 end) end as total_avg_daily_watch_duration_per_user,

  max(case when f.user_type = '拉新' then f.avg_active_days_7d end) as laxin_avg_active_days_7d,
  max(case when f.user_type = '回流' then f.avg_active_days_7d end) as huiliu_avg_active_days_7d,
  max(case when f.user_type = '老用户' then f.avg_active_days_7d end) as old_avg_active_days_7d,
  max(case when f.user_type = '总计' then f.avg_active_days_7d end) as total_avg_active_days_7d,

  case when sum(case when f.user_type = '拉新' then f.d7_base_user_cnt else 0 end) > 0
       then sum(case when f.user_type = '拉新' then f.d7_retained_user_cnt else 0 end) * 1.0000 / sum(case when f.user_type = '拉新' then f.d7_base_user_cnt else 0 end) end as laxin_d7_retention_rate,
  case when sum(case when f.user_type = '回流' then f.d7_base_user_cnt else 0 end) > 0
       then sum(case when f.user_type = '回流' then f.d7_retained_user_cnt else 0 end) * 1.0000 / sum(case when f.user_type = '回流' then f.d7_base_user_cnt else 0 end) end as huiliu_d7_retention_rate,
  case when sum(case when f.user_type = '老用户' then f.d7_base_user_cnt else 0 end) > 0
       then sum(case when f.user_type = '老用户' then f.d7_retained_user_cnt else 0 end) * 1.0000 / sum(case when f.user_type = '老用户' then f.d7_base_user_cnt else 0 end) end as old_d7_retention_rate,
  case when sum(case when f.user_type = '总计' then f.d7_base_user_cnt else 0 end) > 0
       then sum(case when f.user_type = '总计' then f.d7_retained_user_cnt else 0 end) * 1.0000 / sum(case when f.user_type = '总计' then f.d7_base_user_cnt else 0 end) end as total_d7_retention_rate
from metric_final_long f
left join month_days d
  on f.month = d.month
 and f.game_id = d.game_id
left join live_anchor_type_month l
  on f.month = l.month
 and f.game_id = l.game_id
 and f.anchor_type = l.anchor_type
group by
  f.month,
  f.game_id,
  f.anchor_type,
  d.observed_days,
  l.live_anchor_cnt,
  l.total_live_hours
order by
  f.month,
  f.game_id,
  case
    when f.anchor_type = '全部主播' then 1
    when f.anchor_type = '近3个月新开播主播' then 2
    else 3
  end;
