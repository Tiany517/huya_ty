-- Spark SQL
-- 口径：
-- 1. 时间：2026-01-01 至 2026-07-26。
-- 2. 只看户外：gameid='2165' / game_id=2165。
-- 3. 公会：只取 dm_huya_ayyuid_detail_day.cname，空值填“无公会”。
-- 4. 近3个月新主播：主播首次开播月在当前月及往前2个月内。
-- 5. 主播人均打赏流水：先 by月 by主播 计算 流水 / 该主播打赏人数，再在 by月 by公会 层面对主播取平均。
-- 6. 7日留存率：用户当月首次观看该主播作为 cohort_date，cohort_date+6 当天 APP 活跃即留存。
-- 7. 因分区到2026-07-26，7日留存 cohort 只取到2026-07-20。

with anchor_first_live as (
  select
    ayyuid,
    min(substr(dt, 1, 7)) as first_live_month
  from gamelive.dm_huya_ayyuid_detail_day
  where dt between '2024-01-01' and '2026-07-26'
    and gameid = '2165'
    and live_hours_only_live > 0
  group by
    ayyuid
),

anchor_live_month as (
  select
    substr(a.dt, 1, 7) as month,
    a.ayyuid,
    coalesce(nullif(max(a.cname), ''), '无公会') as cname,
    sum(a.live_hours_only_live) as live_hours
  from gamelive.dm_huya_ayyuid_detail_day a
  where a.dt between '2026-01-01' and '2026-07-26'
    and a.gameid = '2165'
    and a.live_hours_only_live > 0
  group by
    substr(a.dt, 1, 7),
    a.ayyuid
),

anchor_month_tag as (
  select
    l.month,
    l.ayyuid,
    l.cname,
    case
      when to_date(concat(f.first_live_month, '-01'))
           between add_months(to_date(concat(l.month, '-01')), -2)
               and to_date(concat(l.month, '-01'))
      then 1
      else 0
    end as is_recent_3m_anchor
  from anchor_live_month l
  left join anchor_first_live f
    on l.ayyuid = f.ayyuid
),

anchor_month_revenue as (
  select
    substr(p.dt, 1, 7) as month,
    p.creator_uid as ayyuid,
    sum(p.user_consume_amount) as consume_amt,
    count(distinct p.ext['ukey']) as pay_user_cnt
  from zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i p
  where p.dt between '2026-01-01' and '2026-07-26'
    and p.game_id = 2165
    and p.game_label = '娱乐'
    and p.user_consume_amount > 0
    and p.ext['ukey'] is not null
  group by
    substr(p.dt, 1, 7),
    p.creator_uid
),

watch_user_anchor_day as (
  select
    w.dt,
    substr(w.dt, 1, 7) as month,
    w.creator_uid as ayyuid,
    w.user_ukey
  from gamelive.dws_huya_user_behavior_d_i w
  where w.dt between '2026-01-01' and '2026-07-20'
    and w.game_id = 2165
    and w.product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
    and w.data_type = 'live_watch_session'
    and w.live_content_type = '直播'
    and w.is_black_ukey = 0
    and w.watch_cnt > 0
    and w.watch_duration > 0
    and w.user_ukey is not null
  group by
    w.dt,
    substr(w.dt, 1, 7),
    w.creator_uid,
    w.user_ukey
),

retention_base as (
  select
    w.month,
    t.cname,
    w.ayyuid,
    t.is_recent_3m_anchor,
    w.user_ukey,
    min(w.dt) as cohort_date
  from watch_user_anchor_day w
  inner join anchor_month_tag t
    on w.month = t.month
   and w.ayyuid = t.ayyuid
  group by
    w.month,
    t.cname,
    w.ayyuid,
    t.is_recent_3m_anchor,
    w.user_ukey
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

retention_user as (
  select
    b.month,
    b.cname,
    b.ayyuid,
    b.is_recent_3m_anchor,
    b.user_ukey,
    max(case
      when a.dt = date_format(date_add(to_date(b.cohort_date), 6), 'yyyy-MM-dd')
      then 1 else 0
    end) as is_d7_retained
  from retention_base b
  left join active_day a
    on b.user_ukey = a.user_ukey
   and a.dt = date_format(date_add(to_date(b.cohort_date), 6), 'yyyy-MM-dd')
  group by
    b.month,
    b.cname,
    b.ayyuid,
    b.is_recent_3m_anchor,
    b.user_ukey
),

retention_month_guild as (
  select
    month,
    cname,

    count(distinct case when is_recent_3m_anchor = 1 then user_ukey end) as recent_3m_d7_base_user_cnt,
    count(distinct case when is_recent_3m_anchor = 1 and is_d7_retained = 1 then user_ukey end) as recent_3m_d7_retained_user_cnt,

    count(distinct user_ukey) as total_d7_base_user_cnt,
    count(distinct case when is_d7_retained = 1 then user_ukey end) as total_d7_retained_user_cnt
  from retention_user
  group by
    month,
    cname
),

anchor_month_base as (
  select
    t.month,
    t.cname,
    t.ayyuid,
    t.is_recent_3m_anchor,
    coalesce(r.consume_amt, 0) as consume_amt,
    coalesce(r.pay_user_cnt, 0) as pay_user_cnt,
    case
      when coalesce(r.pay_user_cnt, 0) > 0
      then coalesce(r.consume_amt, 0) * 1.0000 / r.pay_user_cnt
    end as anchor_avg_consume_amt_per_pay_user
  from anchor_month_tag t
  left join anchor_month_revenue r
    on t.month = r.month
   and t.ayyuid = r.ayyuid
),

metric_month_guild as (
  select
    month,
    cname,

    count(distinct case when is_recent_3m_anchor = 1 then ayyuid end) as recent_3m_live_anchor_cnt,
    count(distinct ayyuid) as total_live_anchor_cnt,

    sum(case when is_recent_3m_anchor = 1 then consume_amt else 0 end) as recent_3m_anchor_consume_amt,
    sum(consume_amt) as total_anchor_consume_amt,

    avg(case
      when is_recent_3m_anchor = 1 then anchor_avg_consume_amt_per_pay_user
    end) as recent_3m_anchor_avg_consume_amt_per_pay_user,

    avg(anchor_avg_consume_amt_per_pay_user) as total_anchor_avg_consume_amt_per_pay_user
  from anchor_month_base
  group by
    month,
    cname
)

select
  m.month,
  m.cname as guild_name,

  m.recent_3m_live_anchor_cnt,
  m.total_live_anchor_cnt,
  case
    when m.total_live_anchor_cnt > 0
    then m.recent_3m_live_anchor_cnt * 1.0000 / m.total_live_anchor_cnt
  end as recent_3m_live_anchor_share,

  m.recent_3m_anchor_consume_amt,
  m.total_anchor_consume_amt,

  m.recent_3m_anchor_avg_consume_amt_per_pay_user,
  m.total_anchor_avg_consume_amt_per_pay_user,

  case
    when coalesce(r.recent_3m_d7_base_user_cnt, 0) > 0
    then r.recent_3m_d7_retained_user_cnt * 1.0000 / r.recent_3m_d7_base_user_cnt
  end as recent_3m_anchor_d7_retention_rate,

  case
    when coalesce(r.total_d7_base_user_cnt, 0) > 0
    then r.total_d7_retained_user_cnt * 1.0000 / r.total_d7_base_user_cnt
  end as total_anchor_d7_retention_rate

from metric_month_guild m
left join retention_month_guild r
  on m.month = r.month
 and m.cname = r.cname
order by
  m.month,
  m.recent_3m_anchor_consume_amt desc;
