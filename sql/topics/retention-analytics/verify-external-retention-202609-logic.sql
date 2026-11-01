-- Source-only executable check for the external 1030 retention architecture.
-- Build one September Valorant-category cohort, independently rebuild its user-day
-- denominators, and prove that D7/D14/D30 expansion does not multiply the base.
-- The category filter keeps this Presto check below the per-node memory limit while
-- preserving the same grain and expansion logic as the full pipeline.

with normalized_source as (
  select
    dt,
    case
      when lower(cast(pcode as varchar)) = 'douyin_web' then 'douyin'
      else lower(cast(pcode as varchar))
    end as pcode,
    r_category,
    user_id,
    danmu_cnt,
    gift_cnt,
    gift_value
  from zhgametemp.zty_jingpin_user_activity_1029_v1
  where dt between '2026-09-01' and '2026-10-29'
    and r_category in ('无畏契约', '无畏契约：源能行动')
),

user_day as (
  select
    dt,
    pcode,
    r_category,
    user_id,
    max(if(danmu_cnt > 0, 1, 0)) as is_danmu,
    max(if(gift_cnt > 0 and gift_value > 0, 1, 0)) as is_gift
  from normalized_source
  group by dt, pcode, r_category, user_id
),

available_days as (
  select distinct dt from user_day
),

retention_target as (
  select
    date_format(date_add('day', -6, date_parse(dt, '%Y-%m-%d')), '%Y-%m-%d') as base_dt,
    pcode,
    r_category,
    user_id,
    7 as retention_day,
    is_danmu,
    is_gift
  from user_day

  union all

  select
    date_format(date_add('day', -13, date_parse(dt, '%Y-%m-%d')), '%Y-%m-%d') as base_dt,
    pcode,
    r_category,
    user_id,
    14 as retention_day,
    is_danmu,
    is_gift
  from user_day

  union all

  select
    date_format(date_add('day', -29, date_parse(dt, '%Y-%m-%d')), '%Y-%m-%d') as base_dt,
    pcode,
    r_category,
    user_id,
    30 as retention_day,
    is_danmu,
    is_gift
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
    a.pcode,
    a.r_category,
    a.is_danmu,
    a.is_gift,
    coalesce(f.is_7d_danmu_retained_user, 0) as is_7d_danmu_retained_user,
    coalesce(f.is_7d_gift_retained_user, 0) as is_7d_gift_retained_user,
    coalesce(f.is_14d_danmu_retained_user, 0) as is_14d_danmu_retained_user,
    coalesce(f.is_14d_gift_retained_user, 0) as is_14d_gift_retained_user,
    coalesce(f.is_30d_danmu_retained_user, 0) as is_30d_danmu_retained_user,
    coalesce(f.is_30d_gift_retained_user, 0) as is_30d_gift_retained_user
  from user_day a
  inner join available_days ad7
    on ad7.dt = date_format(date_add('day', 6, date_parse(a.dt, '%Y-%m-%d')), '%Y-%m-%d')
  inner join available_days ad14
    on ad14.dt = date_format(date_add('day', 13, date_parse(a.dt, '%Y-%m-%d')), '%Y-%m-%d')
  inner join available_days ad30
    on ad30.dt = date_format(date_add('day', 29, date_parse(a.dt, '%Y-%m-%d')), '%Y-%m-%d')
  left join retention_flags f
    on f.base_dt = a.dt
   and f.pcode = a.pcode
   and f.r_category = a.r_category
   and f.user_id = a.user_id
  where a.dt between '2026-09-01' and '2026-09-30'
),

expanded_monthly as (
  select
    mth,
    pcode,
    r_category,
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

independent_base as (
  select
    substr(dt, 1, 7) as mth,
    pcode,
    r_category,
    sum(is_danmu) as danmu_base_user_cnt,
    sum(is_gift) as gift_base_user_cnt
  from user_day
  where dt between '2026-09-01' and '2026-09-30'
  group by substr(dt, 1, 7), pcode, r_category
),

reconciled as (
  select
    coalesce(e.mth, b.mth) as mth,
    coalesce(e.pcode, b.pcode) as pcode,
    coalesce(e.r_category, b.r_category) as r_category,
    coalesce(e.danmu_base_user_cnt, 0) as expanded_danmu_base,
    coalesce(b.danmu_base_user_cnt, 0) as independent_danmu_base,
    coalesce(e.gift_base_user_cnt, 0) as expanded_gift_base,
    coalesce(b.gift_base_user_cnt, 0) as independent_gift_base,
    coalesce(e.danmu_7d_retain_user_cnt, 0) as danmu_7d_retain_user_cnt,
    coalesce(e.danmu_14d_retain_user_cnt, 0) as danmu_14d_retain_user_cnt,
    coalesce(e.danmu_30d_retain_user_cnt, 0) as danmu_30d_retain_user_cnt,
    coalesce(e.gift_7d_retain_user_cnt, 0) as gift_7d_retain_user_cnt,
    coalesce(e.gift_14d_retain_user_cnt, 0) as gift_14d_retain_user_cnt,
    coalesce(e.gift_30d_retain_user_cnt, 0) as gift_30d_retain_user_cnt
  from expanded_monthly e
  full outer join independent_base b
    on e.mth = b.mth
   and e.pcode = b.pcode
   and e.r_category = b.r_category
)

select
  count(*) as groups,
  sum(if(expanded_danmu_base <> independent_danmu_base, 1, 0)) as danmu_base_mismatch_groups,
  sum(if(expanded_gift_base <> independent_gift_base, 1, 0)) as gift_base_mismatch_groups,
  sum(expanded_danmu_base) as expanded_danmu_base_sum,
  sum(independent_danmu_base) as independent_danmu_base_sum,
  sum(expanded_gift_base) as expanded_gift_base_sum,
  sum(independent_gift_base) as independent_gift_base_sum,
  sum(if(danmu_7d_retain_user_cnt > expanded_danmu_base
        or danmu_14d_retain_user_cnt > expanded_danmu_base
        or danmu_30d_retain_user_cnt > expanded_danmu_base, 1, 0)) as invalid_danmu_rows,
  sum(if(gift_7d_retain_user_cnt > expanded_gift_base
        or gift_14d_retain_user_cnt > expanded_gift_base
        or gift_30d_retain_user_cnt > expanded_gift_base, 1, 0)) as invalid_gift_rows
from reconciled;
