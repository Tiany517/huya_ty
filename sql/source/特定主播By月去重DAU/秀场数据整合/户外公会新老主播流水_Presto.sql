-- Presto SQL
-- 口径：
-- 1. 时间：2026-01-01 至 2026-07-26。
-- 2. 只看户外：gameid='2165' / game_id=2165。
-- 3. 公会：只取 dm_huya_ayyuid_detail_day.cname，空值填“无公会”。
-- 4. 近3个月新主播：主播首次开播月在当前月及往前2个月内。
-- 5. 主播人均打赏流水：先 by月 by主播 计算 流水 / 该主播打赏人数，再在 by月 by公会 层面对主播取平均。

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
      when date_parse(concat(f.first_live_month, '-01'), '%Y-%m-%d')
           between date_add('month', -2, date_parse(concat(l.month, '-01'), '%Y-%m-%d'))
               and date_parse(concat(l.month, '-01'), '%Y-%m-%d')
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
)

select
  month,
  cname as guild_name,

  count(distinct case when is_recent_3m_anchor = 1 then ayyuid end) as recent_3m_live_anchor_cnt,
  count(distinct ayyuid) as total_live_anchor_cnt,

  count(distinct case when is_recent_3m_anchor = 1 then ayyuid end) * 1.0000
    / count(distinct ayyuid) as recent_3m_live_anchor_share,

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
order by
  month,
  recent_3m_anchor_consume_amt desc;
