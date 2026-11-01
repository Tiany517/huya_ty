-- 数据源：zhgametemp.zty_jingpin_user_activity_1029_v1
-- 输出粒度：月份 + pcode + r_category
-- D7、D14、D30分别对应精确的T+6、T+13、T+29。
-- 三个留存指标统一使用同时具备T+6、T+13、T+29分区的cohort日期。
-- 打赏用户口径：gift_cnt > 0且gift_value > 0。

with available_days as (
  select distinct dt
  from zhgametemp.zty_jingpin_user_activity_1029_v1
  where dt between '2025-01-01' and '2026-12-31'
),

user_day as (
  select
    dt,
    pcode,
    r_category,
    user_id,
    case when sum(danmu_cnt) > 0 then 1 else 0 end as is_danmu,
    case when sum(gift_cnt) > 0 and sum(gift_value) > 0 then 1 else 0 end as is_gift,
    sum(danmu_cnt) as danmu_cnt,
    sum(gift_cnt) as gift_cnt,
    sum(gift_value) as gift_value
  from zhgametemp.zty_jingpin_user_activity_1029_v1
  where dt between '2025-01-01' and '2026-12-31'
  group by dt, pcode, r_category, user_id
),

daily_flow as (
  select
    substr(dt, 1, 7) as mth,
    dt,
    pcode,
    r_category,
    sum(gift_cnt) as gift_cnt,
    sum(gift_value) as gift_value,
    sum(danmu_cnt) as danmu_cnt,
    count(distinct case when is_danmu = 1 then user_id end) as danmu_user_cnt,
    count(distinct case when is_gift = 1 then user_id end) as pay_user_cnt
  from user_day
  group by substr(dt, 1, 7), dt, pcode, r_category
),

monthly_flow as (
  select
    mth,
    pcode,
    r_category,
    sum(gift_cnt) as total_gift_cnt,
    sum(gift_value) as total_gift_value,
    sum(danmu_cnt) as total_danmu_cnt,
    avg(danmu_user_cnt) as avg_daily_danmu_user_cnt,
    avg(pay_user_cnt) as avg_daily_pay_user_cnt
  from daily_flow
  group by mth, pcode, r_category
),

daily_set as (
  select
    a.mth,
    a.dt,
    a.pcode,
    a.r_category,
    a.user_id,
    a.is_danmu,
    a.is_gift,
    coalesce(r7.is_danmu, 0) as is_7d_danmu_retained_user,
    coalesce(r7.is_gift, 0) as is_7d_gift_retained_user,
    coalesce(r14.is_danmu, 0) as is_14d_danmu_retained_user,
    coalesce(r14.is_gift, 0) as is_14d_gift_retained_user,
    coalesce(r30.is_danmu, 0) as is_30d_danmu_retained_user,
    coalesce(r30.is_gift, 0) as is_30d_gift_retained_user
  from (
    select
      substr(dt, 1, 7) as mth,
      dt,
      pcode,
      r_category,
      user_id,
      is_danmu,
      is_gift,
      date_format(date_add('day', 6, date_parse(dt, '%Y-%m-%d')), '%Y-%m-%d') as target_7_dt,
      date_format(date_add('day', 13, date_parse(dt, '%Y-%m-%d')), '%Y-%m-%d') as target_14_dt,
      date_format(date_add('day', 29, date_parse(dt, '%Y-%m-%d')), '%Y-%m-%d') as target_30_dt
    from user_day
  ) a
  inner join available_days ad7 on ad7.dt = a.target_7_dt
  inner join available_days ad14 on ad14.dt = a.target_14_dt
  inner join available_days ad30 on ad30.dt = a.target_30_dt
  left join user_day r7 on r7.dt = a.target_7_dt and r7.pcode = a.pcode and r7.r_category = a.r_category and r7.user_id = a.user_id
  left join user_day r14 on r14.dt = a.target_14_dt and r14.pcode = a.pcode and r14.r_category = a.r_category and r14.user_id = a.user_id
  left join user_day r30 on r30.dt = a.target_30_dt and r30.pcode = a.pcode and r30.r_category = a.r_category and r30.user_id = a.user_id
),

monthly_set as (
  select
    mth,
    pcode,
    r_category,
    count(distinct dt) as cohort_days,
    sum(is_danmu) as danmu_base_user_cnt,
    sum(if(is_danmu = 1 and is_7d_danmu_retained_user = 1, 1, 0)) as danmu_7d_retain_user_cnt,
    sum(if(is_danmu = 1 and is_14d_danmu_retained_user = 1, 1, 0)) as danmu_14d_retain_user_cnt,
    sum(if(is_danmu = 1 and is_30d_danmu_retained_user = 1, 1, 0)) as danmu_30d_retain_user_cnt,
    sum(is_gift) as gift_base_user_cnt,
    sum(if(is_gift = 1 and is_7d_gift_retained_user = 1, 1, 0)) as gift_7d_retain_user_cnt,
    sum(if(is_gift = 1 and is_14d_gift_retained_user = 1, 1, 0)) as gift_14d_retain_user_cnt,
    sum(if(is_gift = 1 and is_30d_gift_retained_user = 1, 1, 0)) as gift_30d_retain_user_cnt
  from daily_set
  group by mth, pcode, r_category
),

category_watch_info as (
  select
    mth,
    pcode,
    r_category,
    avg(watch_mins) as daily_watch_mins
  from (
    select
      dt,
      substr(dt, 1, 7) as mth,
      case when pcode in ('douyin_web', 'douyin') then 'douyin' else pcode end as pcode,
      r_category,
      sum(watch_min) as watch_mins
    from zhgametemp.yty_jingpin_anchor_vaild_dau
    where dt >= '2025-01-01' and dt <= '2026-12-31'
    group by dt, substr(dt, 1, 7), case when pcode in ('douyin_web', 'douyin') then 'douyin' else pcode end, r_category
  ) watch_daily
  group by mth, pcode, r_category
)

select
  a.mth,
  a.pcode,
  a.r_category,
  c.daily_watch_mins,
  b.total_gift_cnt,
  b.total_gift_value,
  b.total_danmu_cnt,
  b.avg_daily_danmu_user_cnt,
  b.avg_daily_pay_user_cnt,
  a.cohort_days,
  a.danmu_base_user_cnt,
  a.danmu_7d_retain_user_cnt,
  cast(a.danmu_7d_retain_user_cnt as double) / nullif(a.danmu_base_user_cnt, 0) as danmu_7d_retained_rate,
  a.danmu_14d_retain_user_cnt,
  cast(a.danmu_14d_retain_user_cnt as double) / nullif(a.danmu_base_user_cnt, 0) as danmu_14d_retained_rate,
  a.danmu_30d_retain_user_cnt,
  cast(a.danmu_30d_retain_user_cnt as double) / nullif(a.danmu_base_user_cnt, 0) as danmu_30d_retained_rate,
  a.gift_base_user_cnt,
  a.gift_7d_retain_user_cnt,
  cast(a.gift_7d_retain_user_cnt as double) / nullif(a.gift_base_user_cnt, 0) as gift_7d_retained_rate,
  a.gift_14d_retain_user_cnt,
  cast(a.gift_14d_retain_user_cnt as double) / nullif(a.gift_base_user_cnt, 0) as gift_14d_retained_rate,
  a.gift_30d_retain_user_cnt,
  cast(a.gift_30d_retain_user_cnt as double) / nullif(a.gift_base_user_cnt, 0) as gift_30d_retained_rate
from monthly_set a
left join monthly_flow b on a.mth = b.mth and a.pcode = b.pcode and a.r_category = b.r_category
left join category_watch_info c on a.mth = c.mth and a.pcode = c.pcode and a.r_category = c.r_category
order by a.mth, a.pcode, b.total_gift_value desc;
