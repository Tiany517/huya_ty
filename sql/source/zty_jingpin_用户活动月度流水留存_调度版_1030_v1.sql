-- 目标表：zhgametemp.zty_jingpin_user_activity_monthly_summary_1030_v1
-- 引擎：Spark
-- 调度日期：固定读取2025-01-01至2026-12-31，不使用日期宏。
-- 输出粒度：mth + pcode + r_category。
-- D7、D14、D30分别对应精确的T+6、T+13、T+29。
-- 打赏用户口径：gift_cnt > 0且gift_value > 0。

create table if not exists zhgametemp.zty_jingpin_user_activity_monthly_summary_1030_v1 (
  mth string comment '月份',
  pcode string comment '平台',
  r_category string comment '直播品类',
  daily_watch_mins double comment '月内日均观时',
  total_gift_cnt bigint comment '月打赏次数',
  total_gift_value double comment '月打赏流水',
  total_danmu_cnt bigint comment '月弹幕次数',
  avg_daily_danmu_user_cnt double comment '日均弹幕用户数',
  avg_daily_pay_user_cnt double comment '日均打赏用户数',
  cohort_days bigint comment '有效cohort天数',
  danmu_base_user_cnt bigint comment '弹幕D7D14D30共同cohort用户数',
  danmu_7d_retain_user_cnt bigint comment '弹幕D7留存用户数',
  danmu_7d_retained_rate double comment '弹幕D7留存率',
  danmu_14d_retain_user_cnt bigint comment '弹幕D14留存用户数',
  danmu_14d_retained_rate double comment '弹幕D14留存率',
  danmu_30d_retain_user_cnt bigint comment '弹幕D30留存用户数',
  danmu_30d_retained_rate double comment '弹幕D30留存率',
  gift_base_user_cnt bigint comment '打赏D7D14D30共同cohort用户数',
  gift_7d_retain_user_cnt bigint comment '打赏D7留存用户数',
  gift_7d_retained_rate double comment '打赏D7留存率',
  gift_14d_retain_user_cnt bigint comment '打赏D14留存用户数',
  gift_14d_retained_rate double comment '打赏D14留存率',
  gift_30d_retain_user_cnt bigint comment '打赏D30留存用户数',
  gift_30d_retained_rate double comment '打赏D30留存率'
)
stored as orc;

with available_days as (
  select distinct dt
  from zhgametemp.zty_jingpin_user_activity_1029_v1
  where dt between '2025-01-01' and '2026-12-31'
),

valid_cohort_days as (
  select a.dt
  from (
    select
      dt,
      max(dt) over () as max_dt
    from available_days
  ) a
  where date_add(to_date(a.dt, 'yyyy-MM-dd'), 29) <= to_date(a.max_dt, 'yyyy-MM-dd')
),

user_day as (
  select /*+ repartition(512) */
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

retention_target as (
  select date_format(date_sub(to_date(dt, 'yyyy-MM-dd'), 6), 'yyyy-MM-dd') as base_dt, pcode, r_category, user_id, 7 as retention_day, is_danmu, is_gift
  from user_day
  union all
  select date_format(date_sub(to_date(dt, 'yyyy-MM-dd'), 13), 'yyyy-MM-dd') as base_dt, pcode, r_category, user_id, 14 as retention_day, is_danmu, is_gift
  from user_day
  union all
  select date_format(date_sub(to_date(dt, 'yyyy-MM-dd'), 29), 'yyyy-MM-dd') as base_dt, pcode, r_category, user_id, 30 as retention_day, is_danmu, is_gift
  from user_day
),

retention_flags as (
  select
    base_dt,
    pcode,
    r_category,
    user_id,
    max(if(retention_day = 7 and is_danmu = 1, 1, 0)) as is_7d_danmu_retained_user,
    max(if(retention_day = 7 and is_gift = 1, 1, 0)) as is_7d_gift_retained_user,
    max(if(retention_day = 14 and is_danmu = 1, 1, 0)) as is_14d_danmu_retained_user,
    max(if(retention_day = 14 and is_gift = 1, 1, 0)) as is_14d_gift_retained_user,
    max(if(retention_day = 30 and is_danmu = 1, 1, 0)) as is_30d_danmu_retained_user,
    max(if(retention_day = 30 and is_gift = 1, 1, 0)) as is_30d_gift_retained_user
  from retention_target
  group by base_dt, pcode, r_category, user_id
),

daily_set as (
  select
    substr(a.dt, 1, 7) as mth,
    a.dt,
    a.pcode,
    a.r_category,
    a.user_id,
    a.is_danmu,
    a.is_gift,
    coalesce(f.is_7d_danmu_retained_user, 0) as is_7d_danmu_retained_user,
    coalesce(f.is_7d_gift_retained_user, 0) as is_7d_gift_retained_user,
    coalesce(f.is_14d_danmu_retained_user, 0) as is_14d_danmu_retained_user,
    coalesce(f.is_14d_gift_retained_user, 0) as is_14d_gift_retained_user,
    coalesce(f.is_30d_danmu_retained_user, 0) as is_30d_danmu_retained_user,
    coalesce(f.is_30d_gift_retained_user, 0) as is_30d_gift_retained_user
  from user_day a
  inner join valid_cohort_days vd on vd.dt = a.dt
  inner join available_days ad7 on ad7.dt = date_format(date_add(to_date(a.dt, 'yyyy-MM-dd'), 6), 'yyyy-MM-dd')
  inner join available_days ad14 on ad14.dt = date_format(date_add(to_date(a.dt, 'yyyy-MM-dd'), 13), 'yyyy-MM-dd')
  inner join available_days ad30 on ad30.dt = date_format(date_add(to_date(a.dt, 'yyyy-MM-dd'), 29), 'yyyy-MM-dd')
  left join retention_flags f on f.base_dt = a.dt and f.pcode = a.pcode and f.r_category = a.r_category and f.user_id = a.user_id
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

insert overwrite table zhgametemp.zty_jingpin_user_activity_monthly_summary_1030_v1
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
left join category_watch_info c on a.mth = c.mth and a.pcode = c.pcode and a.r_category = c.r_category;
