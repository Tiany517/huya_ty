-- Run only after rebuilding zhgametemp.zty_jingpin_user_activity_monthly_summary_1030_v1.
-- Independent check: rebuild the common cohort denominator from base user-day grain,
-- then reconcile it exactly with the target table by month, platform, and category.
-- BIGDATA MCP runs one statement per request; execute separately.

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
  where dt between '2025-01-01' and '2026-09-30'
),

independent_user_day as (
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

independent_base as (
  select
    substr(dt, 1, 7) as mth,
    pcode,
    r_category,
    count(distinct dt) as cohort_days,
    sum(is_danmu) as danmu_base_user_cnt,
    sum(is_gift) as gift_base_user_cnt
  from independent_user_day
  group by substr(dt, 1, 7), pcode, r_category
),

target as (
  select
    mth,
    pcode,
    r_category,
    cohort_days,
    danmu_base_user_cnt,
    gift_base_user_cnt
  from zhgametemp.zty_jingpin_user_activity_monthly_summary_1030_v1
  where mth <= '2026-09'
),

reconciled as (
  select
    coalesce(b.mth, t.mth) as mth,
    coalesce(b.pcode, t.pcode) as pcode,
    coalesce(b.r_category, t.r_category) as r_category,
    b.cohort_days as source_cohort_days,
    t.cohort_days as target_cohort_days,
    b.danmu_base_user_cnt as source_danmu_base_user_cnt,
    t.danmu_base_user_cnt as target_danmu_base_user_cnt,
    b.gift_base_user_cnt as source_gift_base_user_cnt,
    t.gift_base_user_cnt as target_gift_base_user_cnt
  from independent_base b
  full outer join target t
    on b.mth = t.mth
   and b.pcode = t.pcode
   and b.r_category = t.r_category
)

select
  count(*) as total_groups,
  sum(if(source_cohort_days is not null and target_cohort_days is not null, 1, 0)) as matched_groups,
  sum(if(source_cohort_days is not null and target_cohort_days is null, 1, 0)) as source_only_groups,
  sum(if(source_cohort_days is null and target_cohort_days is not null, 1, 0)) as target_only_groups,
  sum(if(coalesce(source_cohort_days, 0) <> coalesce(target_cohort_days, 0), 1, 0)) as cohort_days_mismatch_groups,
  sum(if(coalesce(source_danmu_base_user_cnt, 0) <> coalesce(target_danmu_base_user_cnt, 0), 1, 0)) as danmu_base_mismatch_groups,
  sum(if(coalesce(source_gift_base_user_cnt, 0) <> coalesce(target_gift_base_user_cnt, 0), 1, 0)) as gift_base_mismatch_groups,
  sum(coalesce(source_danmu_base_user_cnt, 0)) as source_danmu_base_sum,
  sum(coalesce(target_danmu_base_user_cnt, 0)) as target_danmu_base_sum,
  sum(coalesce(source_gift_base_user_cnt, 0)) as source_gift_base_sum,
  sum(coalesce(target_gift_base_user_cnt, 0)) as target_gift_base_sum
from reconciled;

select
  count(*) as row_cnt,
  sum(if(danmu_7d_retain_user_cnt > danmu_base_user_cnt
        or danmu_14d_retain_user_cnt > danmu_base_user_cnt
        or danmu_30d_retain_user_cnt > danmu_base_user_cnt, 1, 0)) as invalid_danmu_numerator_rows,
  sum(if(gift_7d_retain_user_cnt > gift_base_user_cnt
        or gift_14d_retain_user_cnt > gift_base_user_cnt
        or gift_30d_retain_user_cnt > gift_base_user_cnt, 1, 0)) as invalid_gift_numerator_rows,
  sum(if(danmu_base_user_cnt > 0 and (
       abs(cast(danmu_7d_retain_user_cnt as double) / danmu_base_user_cnt - danmu_7d_retained_rate) > 0.000000001
    or abs(cast(danmu_14d_retain_user_cnt as double) / danmu_base_user_cnt - danmu_14d_retained_rate) > 0.000000001
    or abs(cast(danmu_30d_retain_user_cnt as double) / danmu_base_user_cnt - danmu_30d_retained_rate) > 0.000000001
  ), 1, 0)) as inconsistent_danmu_rate_rows,
  sum(if(gift_base_user_cnt > 0 and (
       abs(cast(gift_7d_retain_user_cnt as double) / gift_base_user_cnt - gift_7d_retained_rate) > 0.000000001
    or abs(cast(gift_14d_retain_user_cnt as double) / gift_base_user_cnt - gift_14d_retained_rate) > 0.000000001
    or abs(cast(gift_30d_retain_user_cnt as double) / gift_base_user_cnt - gift_30d_retained_rate) > 0.000000001
  ), 1, 0)) as inconsistent_gift_rate_rows
from zhgametemp.zty_jingpin_user_activity_monthly_summary_1030_v1;
