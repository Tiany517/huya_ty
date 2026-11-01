-- 数据源：zhgametemp.zty_jingpin_user_activity_1029_v1
-- 输出粒度：月份 + pcode + r_category
-- 流水窗口：2026-01-01 至 2026-01-31 全月
-- 7日留存：同 pcode、同 r_category、同 user_id，T日有行为，T+6日仍有同类行为
-- 月度留存采用日 cohort 加权口径：sum(各日留存用户数) / sum(各日cohort用户数)
-- 为保证1月最后一天有T+6数据，源数据读取到2026-02-06；正式复用时结束日期需顺延6天

with available_days as (
  select distinct dt
  from zhgametemp.zty_jingpin_user_activity_1029_v1
  where dt >= '2026-02-01'
    and dt < '2026-02-07'
),

user_day as (
  select
    dt,
    pcode,
    r_category,
    user_id,
    max(if(danmu_cnt > 0, 1, 0)) as is_danmu,
    max(if(gift_cnt > 0, 1, 0)) as is_gift,
    sum(danmu_cnt) as danmu_cnt,
    sum(gift_cnt) as gift_cnt,
    sum(gift_value) as gift_value
  from zhgametemp.zty_jingpin_user_activity_1029_v1
  where dt >= '2026-01-01'
    and dt < '2026-02-07'
  group by dt, pcode, r_category, user_id
),

monthly_flow as (
  select
    substr(dt, 1, 7) as month_str,
    pcode,
    r_category,
    sum(gift_value) as gift_value,
    sum(gift_cnt) as gift_cnt,
    sum(danmu_cnt) as danmu_cnt,
    count(distinct if(danmu_cnt > 0, user_id, null)) as danmu_user_cnt,
    count(distinct if(gift_cnt > 0, user_id, null)) as gift_user_cnt
  from zhgametemp.zty_jingpin_user_activity_1029_v1
  where dt >= '2026-01-01'
    and dt < '2026-02-01'
  group by substr(dt, 1, 7), pcode, r_category
),

daily_ret as (
  select
    b.month_str,
    b.dt,
    b.pcode,
    b.r_category,
    b.user_id,
    b.is_danmu,
    b.is_gift,
    coalesce(r.is_danmu, 0) as target_is_danmu,
    coalesce(r.is_gift, 0) as target_is_gift
  from (
    select
      substr(dt, 1, 7) as month_str,
      dt,
      pcode,
      r_category,
      user_id,
      is_danmu,
      is_gift,
      date_format(
        date_add('day', 6, date_parse(dt, '%Y-%m-%d')),
        '%Y-%m-%d'
      ) as target_dt
    from user_day
    where dt >= '2026-01-01'
      and dt < '2026-02-01'
  ) b
  inner join available_days ad
    on ad.dt = b.target_dt
  left join user_day r
    on r.dt = b.target_dt
   and r.pcode = b.pcode
   and r.r_category = b.r_category
   and r.user_id = b.user_id
),

monthly_ret as (
  select
    month_str,
    pcode,
    r_category,
    count(distinct dt) as cohort_days,
    sum(is_danmu) as danmu_7d_base_user_cnt,
    sum(if(is_danmu = 1 and target_is_danmu = 1, 1, 0)) as danmu_7d_retain_user_cnt,
    sum(is_gift) as gift_7d_base_user_cnt,
    sum(if(is_gift = 1 and target_is_gift = 1, 1, 0)) as gift_7d_retain_user_cnt
  from daily_ret
  group by month_str, pcode, r_category
)

select
  f.month_str,
  f.pcode,
  f.r_category,
  f.gift_value,
  f.gift_cnt,
  f.danmu_cnt,
  f.danmu_user_cnt,
  f.gift_user_cnt,
  coalesce(r.cohort_days, 0) as cohort_days,
  coalesce(r.danmu_7d_base_user_cnt, 0) as danmu_7d_base_user_cnt,
  coalesce(r.danmu_7d_retain_user_cnt, 0) as danmu_7d_retain_user_cnt,
  cast(r.danmu_7d_retain_user_cnt as double)
    / nullif(r.danmu_7d_base_user_cnt, 0) as danmu_7d_retention_rate,
  coalesce(r.gift_7d_base_user_cnt, 0) as gift_7d_base_user_cnt,
  coalesce(r.gift_7d_retain_user_cnt, 0) as gift_7d_retain_user_cnt,
  cast(r.gift_7d_retain_user_cnt as double)
    / nullif(r.gift_7d_base_user_cnt, 0) as gift_7d_retention_rate
from monthly_flow f
left join monthly_ret r
  on f.month_str = r.month_str
 and f.pcode = r.pcode
 and f.r_category = r.r_category
order by f.month_str, f.pcode, f.gift_value desc;
