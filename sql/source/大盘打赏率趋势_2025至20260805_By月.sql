with watch_user_day as (
  -- 大盘观看用户：APP 直播观看，日粒度用户去重
  select
    dt,
    substr(dt, 1, 7) as month,
    user_ukey,
    sum(watch_duration) as watch_duration
  from gamelive.dws_huya_user_behavior_d_i
  where dt between '2025-01-01' and '2026-08-05'
    and product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
    and data_type = 'live_watch_session'
    and live_content_type = '直播'
    and is_black_ukey = 0
    and watch_cnt > 0
    and watch_duration > 0
    and user_ukey is not null
  group by
    dt,
    substr(dt, 1, 7),
    user_ukey
),

pay_user_day as (
  -- 大盘打赏用户：剔除刷单后的收入明细，日粒度用户去重
  select
    dt,
    substr(dt, 1, 7) as month,
    ext['ukey'] as user_ukey,
    sum(cast(user_consume_amount as double)) as consume_amt
  from zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i
  where dt between '2025-01-01' and '2026-08-05'
    and user_consume_amount > 0
    and ext['ukey'] is not null
  group by
    dt,
    substr(dt, 1, 7),
    ext['ukey']
),

watch_day_stat as (
  -- 每日观看大盘
  select
    dt,
    month,
    count(distinct user_ukey) as watch_user_cnt,
    sum(watch_duration) as watch_duration
  from watch_user_day
  group by
    dt,
    month
),

pay_day_stat as (
  -- 每日打赏大盘
  select
    dt,
    month,
    count(distinct user_ukey) as pay_user_cnt,
    sum(consume_amt) as consume_amt
  from pay_user_day
  group by
    dt,
    month
),

daily_stat as (
  -- 日口径打赏率：每日打赏人数 / 每日观看人数
  select
    w.dt,
    w.month,
    w.watch_user_cnt,
    coalesce(p.pay_user_cnt, 0) as pay_user_cnt,
    coalesce(p.consume_amt, 0) as consume_amt,
    coalesce(p.pay_user_cnt, 0) * 1.0000
      / nullif(w.watch_user_cnt, 0) as daily_pay_rate
  from watch_day_stat w
  left join pay_day_stat p
    on w.dt = p.dt
),

watch_month_stat as (
  -- 月去重观看大盘
  select
    month,
    count(distinct user_ukey) as month_watch_user_cnt,
    sum(watch_duration) as month_watch_duration
  from watch_user_day
  group by
    month
),

pay_month_stat as (
  -- 月去重打赏大盘
  select
    month,
    count(distinct user_ukey) as month_pay_user_cnt,
    sum(consume_amt) as month_consume_amt
  from pay_user_day
  group by
    month
)

select
  w.month as `月份`,
  count(distinct d.dt) as `有观看行为天数`,

  w.month_watch_user_cnt as `月观看人数`,
  coalesce(p.month_pay_user_cnt, 0) as `月打赏人数`,
  coalesce(p.month_pay_user_cnt, 0) * 1.0000
    / nullif(w.month_watch_user_cnt, 0) as `月去重打赏率`,

  avg(d.watch_user_cnt) as `日均观看人数`,
  avg(d.pay_user_cnt) as `日均打赏人数`,
  avg(d.daily_pay_rate) as `月平均日打赏率`,

  coalesce(p.month_consume_amt, 0) as `月打赏金额`,
  coalesce(p.month_consume_amt, 0) * 1.0000
    / nullif(coalesce(p.month_pay_user_cnt, 0), 0) as `月打赏用户人均金额`,
  coalesce(p.month_consume_amt, 0) * 1.0000
    / nullif(w.month_watch_user_cnt, 0) as `月观看用户人均打赏金额`,

  w.month_watch_duration / 1000.0 / 60 as `月观看时长_分钟`,
  w.month_watch_duration / 1000.0 / 60
    / nullif(w.month_watch_user_cnt, 0) as `月观看用户人均观看时长_分钟`

from watch_month_stat w
left join pay_month_stat p
  on w.month = p.month
left join daily_stat d
  on w.month = d.month
group by
  w.month,
  w.month_watch_user_cnt,
  p.month_pay_user_cnt,
  p.month_consume_amt,
  w.month_watch_duration
order by
  `月份`;
