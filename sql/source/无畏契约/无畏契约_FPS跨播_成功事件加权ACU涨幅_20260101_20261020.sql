-- 目的：计算FPS跨播事件中“仅成功事件”的平均加权ACU涨幅。
-- 口径：事件等权，不做主播等权；成功事件定义为加权ACU涨幅>0。
-- 时间：2026-01-01 至 2026-10-20。
-- 前置表：
--   zhgametemp.wwqy_cross_event60_weighted_events_20261022
--   zhgametemp.wwqy_cross_event60_weighted_anchor_20261022
-- 引擎：Spark。

create table zhgametemp.wwqy_cross_event60_weighted_acu_success_event_20261022 as
with ev as (
  select
    e.luid,
    e.cross_dt,
    a.acu_type,
    e.acu_growth_pct
  from zhgametemp.wwqy_cross_event60_weighted_events_20261022 e
  inner join zhgametemp.wwqy_cross_event60_weighted_anchor_20261022 a
    on e.luid = a.luid
  where a.is_fps_game = 1
),
tier_calc as (
  select
    acu_type as scope,
    count(*) as cross_event_cnt,
    sum(case when acu_growth_pct > 0 then 1 else 0 end) as success_event_cnt,
    avg(case when acu_growth_pct > 0 then acu_growth_pct end) as success_only_acu_growth_pct
  from ev
  group by acu_type
),
overall_calc as (
  select
    'FPS全体' as scope,
    count(*) as cross_event_cnt,
    sum(case when acu_growth_pct > 0 then 1 else 0 end) as success_event_cnt,
    avg(case when acu_growth_pct > 0 then acu_growth_pct end) as success_only_acu_growth_pct
  from ev
),
final_calc as (
  select * from tier_calc
  union all
  select * from overall_calc
)
select
  scope,
  cross_event_cnt,
  success_event_cnt,
  round(100.0 * success_event_cnt / nullif(cross_event_cnt, 0), 2) as success_rate_pct,
  round(success_only_acu_growth_pct, 2) as success_only_acu_growth_pct,
  round(
    100.0 * (success_event_cnt / nullif(cross_event_cnt, 0))
    * (success_only_acu_growth_pct / 100.0),
    2
  ) as probability_adjusted_expected_acu_growth_pct,
  round(
    1.0
    + (success_event_cnt / nullif(cross_event_cnt, 0))
      * (success_only_acu_growth_pct / 100.0),
    4
  ) as probability_adjusted_acu_factor
from final_calc;

-- 新增观时测算：
--   若使用“成功率 × 成功后平均涨幅”的期望系数：
--   新增观时（人·小时）
--   = 基线ACU × probability_adjusted_acu_factor × 新增直播小时
--
--   该公式等价于假设未成功事件的ACU涨幅为0；
--   若失败事件会带来ACU下降，应使用包含负增长分支的期望涨幅。
