-- 目的：复查FPS跨播主播按ACU分层的成功事件、成功率及成功事件加权ACU涨幅。
-- 时间：2026-01-01 至 2026-10-20。
-- 口径：
--   1. 主品类不是无畏契约的FPS主播；
--   2. 已经识别出的真实跨播事件；
--   3. 事件等权，不对主播先平均；
--   4. 成功事件：跨播日加权ACU涨幅 > 0；
--   5. 成功后平均涨幅只使用成功事件作分母；
--   6. 概率调整期望涨幅 = 成功率 * 成功后平均涨幅；
--   7. 最终ACU系数 = 1 + 概率调整期望涨幅。
-- 引擎：Presto。

with base as (
    select
        a.luid,
        a.acu_type,
        e.cross_dt,
        e.acu_growth_pct
    from zhgametemp.wwqy_cross_event60_weighted_anchor_20261022 a
    left join zhgametemp.wwqy_cross_event60_weighted_events_20261022 e
        on a.luid = e.luid
    where a.is_fps_game = 1
),

tier_calc as (
    select
        acu_type as scope,
        count(distinct luid) as anchor_cnt,
        count(cross_dt) as cross_event_cnt,
        sum(case when acu_growth_pct > 0 then 1 else 0 end) as success_event_cnt,
        100.0 * sum(case when acu_growth_pct > 0 then 1 else 0 end)
            / nullif(count(cross_dt), 0) as success_rate_pct,
        avg(case when acu_growth_pct > 0 then acu_growth_pct end) as success_only_acu_growth_pct
    from base
    group by acu_type
),

overall_calc as (
    select
        'FPS全体' as scope,
        count(distinct luid) as anchor_cnt,
        count(cross_dt) as cross_event_cnt,
        sum(case when acu_growth_pct > 0 then 1 else 0 end) as success_event_cnt,
        100.0 * sum(case when acu_growth_pct > 0 then 1 else 0 end)
            / nullif(count(cross_dt), 0) as success_rate_pct,
        avg(case when acu_growth_pct > 0 then acu_growth_pct end) as success_only_acu_growth_pct
    from base
),

final_calc as (
    select * from tier_calc
    union all
    select * from overall_calc
)

select
    scope as acu_type,
    anchor_cnt,
    cross_event_cnt,
    success_event_cnt,
    round(success_rate_pct, 2) as success_rate_pct,
    round(success_only_acu_growth_pct, 2) as success_only_acu_growth_pct,
    round(
        success_rate_pct * success_only_acu_growth_pct / 100.0,
        2
    ) as probability_adjusted_acu_growth_pct,
    round(
        1.0 + success_rate_pct * success_only_acu_growth_pct / 10000.0,
        4
    ) as final_acu_factor
from final_calc
order by case scope
    when '头部主播' then 1
    when '腰部主播' then 2
    when '尾部主播' then 3
    else 4
end;
