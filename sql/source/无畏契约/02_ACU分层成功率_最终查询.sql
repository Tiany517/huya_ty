-- 引擎：Presto。
-- 读取：zhgametemp.wwqy_val_fps_cross_event_compact_20261023
-- 前提：事件表同时包含 simple_acu_growth_pct 和 weighted_acu_growth_pct。
-- 输出：ACU 分层的两套成功率、成功后平均涨幅、期望涨幅和最终 ACU 系数。

with base as (
    select
        luid,
        acu_type,
        cross_dt,
        simple_acu_growth_pct,
        weighted_acu_growth_pct
    from zhgametemp.wwqy_val_fps_cross_event_compact_20261023
    where is_fps_game = 1
),

tier_calc as (
    select
        acu_type as scope,
        count(distinct luid) as anchor_cnt,
        count(cross_dt) as cross_event_cnt,
        sum(case when simple_acu_growth_pct > 0 then 1 else 0 end)
            as simple_success_event_cnt,
        100.0 * sum(case when simple_acu_growth_pct > 0 then 1 else 0 end)
            / nullif(count(cross_dt), 0) as simple_success_rate_pct,
        avg(case when simple_acu_growth_pct > 0 then simple_acu_growth_pct end)
            as simple_success_only_avg_growth_pct,
        sum(case when weighted_acu_growth_pct > 0 then 1 else 0 end)
            as weighted_success_event_cnt,
        100.0 * sum(case when weighted_acu_growth_pct > 0 then 1 else 0 end)
            / nullif(count(cross_dt), 0) as weighted_success_rate_pct,
        avg(case when weighted_acu_growth_pct > 0 then weighted_acu_growth_pct end)
            as weighted_success_only_avg_growth_pct
    from base
    group by acu_type
),

overall_calc as (
    -- FPS 全体从全部事件重新汇总，不能对三个分层的结果再平均。
    select
        'FPS全体' as scope,
        count(distinct luid) as anchor_cnt,
        count(cross_dt) as cross_event_cnt,
        sum(case when simple_acu_growth_pct > 0 then 1 else 0 end)
            as simple_success_event_cnt,
        100.0 * sum(case when simple_acu_growth_pct > 0 then 1 else 0 end)
            / nullif(count(cross_dt), 0) as simple_success_rate_pct,
        avg(case when simple_acu_growth_pct > 0 then simple_acu_growth_pct end)
            as simple_success_only_avg_growth_pct,
        sum(case when weighted_acu_growth_pct > 0 then 1 else 0 end)
            as weighted_success_event_cnt,
        100.0 * sum(case when weighted_acu_growth_pct > 0 then 1 else 0 end)
            / nullif(count(cross_dt), 0) as weighted_success_rate_pct,
        avg(case when weighted_acu_growth_pct > 0 then weighted_acu_growth_pct end)
            as weighted_success_only_avg_growth_pct
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
    simple_success_event_cnt,
    round(simple_success_rate_pct, 2) as simple_success_rate_pct,
    round(simple_success_only_avg_growth_pct, 2) as simple_success_only_avg_growth_pct,
    round(simple_success_rate_pct * simple_success_only_avg_growth_pct / 100.0, 2)
        as simple_expected_acu_growth_pct,
    round(1.0 + simple_success_rate_pct * simple_success_only_avg_growth_pct / 10000.0, 4)
        as simple_acu_factor,
    weighted_success_event_cnt,
    round(weighted_success_rate_pct, 2) as weighted_success_rate_pct,
    round(weighted_success_only_avg_growth_pct, 2) as weighted_success_only_avg_growth_pct,
    round(weighted_success_rate_pct * weighted_success_only_avg_growth_pct / 100.0, 2)
        as weighted_expected_acu_growth_pct,
    round(1.0 + weighted_success_rate_pct * weighted_success_only_avg_growth_pct / 10000.0, 4)
        as weighted_acu_factor
from final_calc
order by case scope
    when '头部主播' then 1
    when '腰部主播' then 2
    when '尾部主播' then 3
    else 4
end;
