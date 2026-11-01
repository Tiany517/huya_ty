-- Run only after the corrected ETL has refreshed the target table.
-- Presto checks for invalid rates and calendar coverage of the event sources.
-- BIGDATA MCP runs one statement per request; execute the three statements separately.

select
  count(*) as row_cnt,
  sum(case when danmu_7d_retain_user_cnt > danmu_base_user_cnt then 1 else 0 end) as invalid_danmu_d7_rows,
  sum(case when danmu_14d_retain_user_cnt > danmu_base_user_cnt then 1 else 0 end) as invalid_danmu_d14_rows,
  sum(case when danmu_30d_retain_user_cnt > danmu_base_user_cnt then 1 else 0 end) as invalid_danmu_d30_rows,
  sum(case when gift_7d_retain_user_cnt > gift_base_user_cnt then 1 else 0 end) as invalid_gift_d7_rows,
  sum(case when gift_14d_retain_user_cnt > gift_base_user_cnt then 1 else 0 end) as invalid_gift_d14_rows,
  sum(case when gift_30d_retain_user_cnt > gift_base_user_cnt then 1 else 0 end) as invalid_gift_d30_rows
from zhgametemp.zty_huya_xingxiu_subcategory_monthly_retention_dau_v1;

select
  mth,
  sub_category,
  danmu_base_user_cnt,
  danmu_7d_retained_rate,
  danmu_14d_retained_rate,
  danmu_30d_retained_rate,
  gift_base_user_cnt,
  gift_7d_retained_rate,
  gift_14d_retained_rate,
  gift_30d_retained_rate
from zhgametemp.zty_huya_xingxiu_subcategory_monthly_retention_dau_v1
where sub_category = '星秀-整体'
order by mth;

with category_dim as (
  select
    gid,
    max(game_full_name) as game_name
  from gamelive.to_main_games_day
  where dt = '2026-10-29'
    and game_full_name = '星秀'
  group by gid
),
danmu_coverage as (
  select
    'danmu' as source_name,
    min(d.dt) as min_dt,
    max(d.dt) as max_dt,
    count(distinct d.dt) as observed_days,
    date_diff('day', min(cast(d.dt as date)), max(cast(d.dt as date))) + 1 as expected_days
  from gamelive.gamelive_huya_danmu_log d
  inner join category_dim c
    on d.live_gameid = c.gid
  where d.dt between '2025-01-01' and '2026-10-29'
    and d.passed = '0'
),
gift_coverage as (
  select
    'gift' as source_name,
    min(dt) as min_dt,
    max(dt) as max_dt,
    count(distinct dt) as observed_days,
    date_diff('day', min(cast(dt as date)), max(cast(dt as date))) + 1 as expected_days
  from gamelive.dws_huya_revenue_detail_d_i
  where dt between '2025-01-01' and '2026-10-29'
    and live_platform = '虎牙'
    and consume_order_type = '礼物'
    and is_free_item = 0
    and user_consume_amount > 0
    and game_name = '星秀'
)
select
  source_name,
  min_dt,
  max_dt,
  observed_days,
  expected_days,
  expected_days - observed_days as missing_days
from (
  select * from danmu_coverage
  union all
  select * from gift_coverage
)
order by source_name;
