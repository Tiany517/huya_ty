-- Spark SQL
-- 口径说明：
-- 1. 品类：户外（gameid = 2165）
-- 2. 时间：2026-01-01 至 2026-07-26；留存相关 cohort 截止到 2026-07-20
-- 3. 仅保留指定公会：
--    集梦传媒、迷簏、95传媒、【大海星辰】、尖勾传媒、钱小佳公会、阿布传媒、401公会、能心
-- 4. 输出：每月、每公会，按主播月流水倒排 Top10 主播明细
-- 5. 主播行上的留存 / 拉新 / 回流指标，全部按 month + cname + ayyuid 计算

with target_guild as (
  select '集梦传媒' as cname union all
  select '迷簏' union all
  select '95传媒' union all
  select '【大海星辰】' union all
  select '尖勾传媒' union all
  select '钱小佳公会' union all
  select '阿布传媒' union all
  select '401公会' union all
  select '能心'
),

anchor_first_live as (
  select
    ayyuid,
    min(substr(dt, 1, 7)) as first_live_month
  from gamelive.dm_huya_ayyuid_detail_day
  where dt between '2024-01-01' and '2026-07-26'
    and gameid = '2165'
    and live_hours_only_live > 0
  group by ayyuid
),

anchor_live_month as (
  select
    substr(a.dt, 1, 7) as month,
    a.ayyuid,
    max(a.nickname) as nickname,
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
    l.nickname,
    l.cname,
    l.live_hours,
    case
      when to_date(concat(f.first_live_month, '-01'))
           between add_months(to_date(concat(l.month, '-01')), -2)
               and to_date(concat(l.month, '-01'))
      then 1 else 0
    end as is_recent_3m_anchor
  from anchor_live_month l
  left join anchor_first_live f
    on l.ayyuid = f.ayyuid
  inner join target_guild g
    on l.cname = g.cname
),

anchor_month_revenue_user as (
  select
    substr(p.dt, 1, 7) as month,
    p.creator_uid as ayyuid,
    p.ext['ukey'] as user_ukey,
    sum(p.user_consume_amount) as user_consume_amt
  from zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i p
  where p.dt between '2026-01-01' and '2026-07-26'
    and p.game_id = 2165
    and p.game_label = '娱乐'
    and p.user_consume_amount > 0
    and p.ext['ukey'] is not null
  group by
    substr(p.dt, 1, 7),
    p.creator_uid,
    p.ext['ukey']
),

anchor_month_revenue as (
  select
    month,
    ayyuid,
    count(distinct user_ukey) as pay_user_cnt,
    sum(user_consume_amt) as consume_amt
  from anchor_month_revenue_user
  group by
    month,
    ayyuid
),

anchor_month_base as (
  select
    t.month,
    t.cname,
    t.ayyuid,
    t.nickname,
    t.live_hours,
    t.is_recent_3m_anchor,
    coalesce(r.consume_amt, 0) as consume_amt,
    coalesce(r.pay_user_cnt, 0) as pay_user_cnt,
    case
      when coalesce(r.pay_user_cnt, 0) > 0
      then coalesce(r.consume_amt, 0) * 1.0000 / r.pay_user_cnt
    end as anchor_arppu
  from anchor_month_tag t
  left join anchor_month_revenue r
    on t.month = r.month
   and t.ayyuid = r.ayyuid
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

retention_month_anchor as (
  select
    month,
    cname,
    ayyuid,
    count(distinct user_ukey) as anchor_d7_base_user_cnt,
    count(distinct case when is_d7_retained = 1 then user_ukey end) as anchor_d7_retained_user_cnt
  from retention_user
  group by
    month,
    cname,
    ayyuid
),

laxin_huiliu_raw as (
  select distinct
    a.dt as cohort_date,
    substr(a.dt, 1, 7) as month,
    a.luid as ayyuid,
    a.user_ukey,
    '拉新' as user_type
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a
  where a.dt between '2026-01-01' and '2026-07-20'
    and a.game_id = 2165
    and a.user_ukey is not null
    and a.luid is not null
    and a.guiyin_tag <> 'mailiang'

  union all

  select distinct
    a.dt as cohort_date,
    substr(a.dt, 1, 7) as month,
    a.luid as ayyuid,
    a.user_ukey,
    '回流' as user_type
  from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1 a
  where a.dt between '2026-01-01' and '2026-07-20'
    and a.game_id = 2165
    and a.user_ukey is not null
    and a.luid is not null
),

laxin_huiliu_user_tag as (
  select
    u.month,
    t.cname,
    u.ayyuid,
    t.is_recent_3m_anchor,
    u.user_type,
    u.user_ukey,
    min(u.cohort_date) as cohort_date
  from laxin_huiliu_raw u
  inner join anchor_month_tag t
    on u.month = t.month
   and u.ayyuid = t.ayyuid
  group by
    u.month,
    t.cname,
    u.ayyuid,
    t.is_recent_3m_anchor,
    u.user_type,
    u.user_ukey
),

laxin_huiliu_retention_user as (
  select
    u.month,
    u.cname,
    u.ayyuid,
    u.is_recent_3m_anchor,
    u.user_type,
    u.user_ukey,
    max(case
      when a.dt = date_format(date_add(to_date(u.cohort_date), 6), 'yyyy-MM-dd')
      then 1 else 0
    end) as is_d7_retained
  from laxin_huiliu_user_tag u
  left join active_day a
    on u.user_ukey = a.user_ukey
   and a.dt = date_format(date_add(to_date(u.cohort_date), 6), 'yyyy-MM-dd')
  group by
    u.month,
    u.cname,
    u.ayyuid,
    u.is_recent_3m_anchor,
    u.user_type,
    u.user_ukey
),

laxin_huiliu_month_anchor as (
  select
    month,
    cname,
    ayyuid,
    count(distinct case when user_type = '拉新' then user_ukey end) as anchor_laxin_user_cnt,
    count(distinct case when user_type = '回流' then user_ukey end) as anchor_huiliu_user_cnt,
    count(distinct user_ukey) as anchor_laxin_huiliu_user_cnt,
    count(distinct case when user_type = '拉新' and is_d7_retained = 1 then user_ukey end) as anchor_laxin_d7_retained_user_cnt,
    count(distinct case when user_type = '回流' and is_d7_retained = 1 then user_ukey end) as anchor_huiliu_d7_retained_user_cnt
  from laxin_huiliu_retention_user
  group by
    month,
    cname,
    ayyuid
),

anchor_month_detail as (
  select
    b.month,
    b.cname as guild_name,
    b.ayyuid,
    b.nickname,
    b.is_recent_3m_anchor,
    b.live_hours,
    b.consume_amt,
    b.pay_user_cnt,
    b.anchor_arppu,
    r.anchor_d7_base_user_cnt,
    r.anchor_d7_retained_user_cnt,
    case
      when coalesce(r.anchor_d7_base_user_cnt, 0) > 0
      then r.anchor_d7_retained_user_cnt * 1.0000 / r.anchor_d7_base_user_cnt
    end as anchor_d7_retention_rate,
    lh.anchor_laxin_user_cnt,
    lh.anchor_huiliu_user_cnt,
    lh.anchor_laxin_huiliu_user_cnt,
    case
      when coalesce(lh.anchor_laxin_user_cnt, 0) > 0
      then lh.anchor_laxin_d7_retained_user_cnt * 1.0000 / lh.anchor_laxin_user_cnt
    end as anchor_laxin_d7_retention_rate,
    case
      when coalesce(lh.anchor_huiliu_user_cnt, 0) > 0
      then lh.anchor_huiliu_d7_retained_user_cnt * 1.0000 / lh.anchor_huiliu_user_cnt
    end as anchor_huiliu_d7_retention_rate
  from anchor_month_base b
  left join retention_month_anchor r
    on b.month = r.month
   and b.cname = r.cname
   and b.ayyuid = r.ayyuid
  left join laxin_huiliu_month_anchor lh
    on b.month = lh.month
   and b.cname = lh.cname
   and b.ayyuid = lh.ayyuid
),

anchor_top10 as (
  select
    d.month,
    d.guild_name,
    d.ayyuid,
    d.nickname,
    d.is_recent_3m_anchor,
    d.live_hours,
    d.consume_amt,
    d.pay_user_cnt,
    d.anchor_arppu,
    d.anchor_d7_base_user_cnt,
    d.anchor_d7_retained_user_cnt,
    d.anchor_d7_retention_rate,
    d.anchor_laxin_user_cnt,
    d.anchor_huiliu_user_cnt,
    d.anchor_laxin_huiliu_user_cnt,
    d.anchor_laxin_d7_retention_rate,
    d.anchor_huiliu_d7_retention_rate,
    row_number() over (
      partition by d.month, d.guild_name
      order by d.consume_amt desc, d.pay_user_cnt desc, d.ayyuid
    ) as revenue_rank_in_guild_month
  from anchor_month_detail d
)

select
  t.month,
  t.guild_name,
  t.revenue_rank_in_guild_month,
  t.ayyuid,
  t.nickname,
  case when t.is_recent_3m_anchor = 1 then '近3个月新主播' else '老主播' end as anchor_type,
  t.live_hours,
  t.consume_amt as anchor_consume_amt,
  t.pay_user_cnt as anchor_pay_user_cnt,
  t.anchor_arppu as anchor_arppu,
  t.anchor_d7_base_user_cnt,
  t.anchor_d7_retained_user_cnt,
  t.anchor_d7_retention_rate,
  t.anchor_laxin_user_cnt,
  t.anchor_huiliu_user_cnt,
  t.anchor_laxin_huiliu_user_cnt,
  t.anchor_laxin_d7_retention_rate,
  t.anchor_huiliu_d7_retention_rate
from anchor_top10 t
where t.revenue_rank_in_guild_month <= 10
order by
  t.month,
  t.guild_name,
  t.revenue_rank_in_guild_month;
