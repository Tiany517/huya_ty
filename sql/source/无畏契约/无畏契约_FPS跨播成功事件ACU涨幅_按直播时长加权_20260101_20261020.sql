-- 目的：在按直播时长加权日ACU、60分钟有效日、剔除三角洲/CS2大赛日的基础上，
--       同时保留：
--       1. 全部事件的含正负平均加权ACU涨幅；
--       2. 仅成功事件的平均加权ACU涨幅；
--       3. 事件层与主播层的增长成功率。
-- 时间：2026-01-01 至 2026-10-20。
-- 成功事件：acu_growth_pct > 0；0增长和负增长均不算成功。
-- 引擎：Spark。

-- 1. 主播层：全部事件平均、仅正增长事件平均、主播内的成功事件数
create table zhgametemp.wwqy_cross_event60_weighted_positive_acu_anchor_20261022 as
with event_calc as (
    select
        e.luid,
        max(e.snick) as anchor_nickname,
        count(*) as cross_event_cnt,
        count(e.acu_growth_pct) as valid_acu_event_cnt,
        sum(case when e.acu_growth_pct > 0 then 1 else 0 end) as acu_growth_event_cnt,
        avg(e.acu_growth_pct) as avg_all_event_acu_growth_pct,
        avg(case when e.acu_growth_pct > 0 then e.acu_growth_pct end) as avg_positive_event_acu_growth_pct
    from zhgametemp.wwqy_cross_event60_weighted_events_20261022 e
    group by e.luid
)
select
    a.luid,
    a.anchor_nickname,
    a.yearly_avg_acu,
    a.main_game_id,
    a.main_game_name,
    a.acu_type,
    a.is_fps_game,
    e.cross_event_cnt,
    e.acu_growth_event_cnt,
    round(100.0 * e.acu_growth_event_cnt / nullif(e.valid_acu_event_cnt, 0), 2) as acu_growth_event_rate_pct,
    round(e.avg_all_event_acu_growth_pct, 2) as avg_all_event_acu_growth_pct,
    round(e.avg_positive_event_acu_growth_pct, 2) as avg_positive_event_acu_growth_pct
from zhgametemp.wwqy_cross_event60_weighted_anchor_20261022 a
inner join event_calc e on a.luid = e.luid;

-- 2. FPS分层汇总：事件等权、主播等权和成功事件条件均值
create table zhgametemp.wwqy_cross_event60_weighted_positive_acu_tier_20261022 as
with ev as (
    select
        e.luid,
        e.acu_growth_pct,
        a.acu_type
    from zhgametemp.wwqy_cross_event60_weighted_events_20261022 e
    inner join zhgametemp.wwqy_cross_event60_weighted_positive_acu_anchor_20261022 a
        on e.luid = a.luid
    where a.is_fps_game = 1
),
event_tier as (
    select
        acu_type as scope,
        count(*) as event_cnt,
        sum(case when acu_growth_pct > 0 then 1 else 0 end) as positive_event_cnt,
        100.0 * sum(case when acu_growth_pct > 0 then 1 else 0 end) / count(*) as event_success_rate_pct,
        avg(acu_growth_pct) as event_equal_all_avg_pct,
        avg(case when acu_growth_pct > 0 then acu_growth_pct end) as event_equal_positive_avg_pct
    from ev
    group by acu_type
),
event_overall as (
    select
        'FPS全体' as scope,
        count(*) as event_cnt,
        sum(case when acu_growth_pct > 0 then 1 else 0 end) as positive_event_cnt,
        100.0 * sum(case when acu_growth_pct > 0 then 1 else 0 end) / count(*) as event_success_rate_pct,
        avg(acu_growth_pct) as event_equal_all_avg_pct,
        avg(case when acu_growth_pct > 0 then acu_growth_pct end) as event_equal_positive_avg_pct
    from ev
),
anchor_tier as (
    select
        acu_type as scope,
        count(*) as anchor_cnt,
        sum(case when acu_growth_event_cnt > 0 then 1 else 0 end) as positive_anchor_cnt,
        100.0 * sum(case when acu_growth_event_cnt > 0 then 1 else 0 end) / count(*) as anchor_success_rate_pct,
        avg(avg_all_event_acu_growth_pct) as anchor_equal_all_avg_pct,
        avg(avg_positive_event_acu_growth_pct) as anchor_equal_positive_avg_pct
    from zhgametemp.wwqy_cross_event60_weighted_positive_acu_anchor_20261022
    where is_fps_game = 1
    group by acu_type
),
anchor_overall as (
    select
        'FPS全体' as scope,
        count(*) as anchor_cnt,
        sum(case when acu_growth_event_cnt > 0 then 1 else 0 end) as positive_anchor_cnt,
        100.0 * sum(case when acu_growth_event_cnt > 0 then 1 else 0 end) / count(*) as anchor_success_rate_pct,
        avg(avg_all_event_acu_growth_pct) as anchor_equal_all_avg_pct,
        avg(avg_positive_event_acu_growth_pct) as anchor_equal_positive_avg_pct
    from zhgametemp.wwqy_cross_event60_weighted_positive_acu_anchor_20261022
    where is_fps_game = 1
),
events_all as (
    select * from event_tier
    union all
    select * from event_overall
),
anchors_all as (
    select * from anchor_tier
    union all
    select * from anchor_overall
)
select
    e.scope,
    a.anchor_cnt,
    a.positive_anchor_cnt,
    round(a.anchor_success_rate_pct, 2) as anchor_success_rate_pct,
    e.event_cnt,
    e.positive_event_cnt,
    round(e.event_success_rate_pct, 2) as event_success_rate_pct,
    round(e.event_equal_all_avg_pct, 2) as event_equal_all_avg_pct,
    round(e.event_equal_positive_avg_pct, 2) as event_equal_positive_avg_pct,
    round(e.event_success_rate_pct / 100.0 * e.event_equal_positive_avg_pct, 2) as event_zero_failure_expected_growth_pct,
    round(a.anchor_equal_all_avg_pct, 2) as anchor_equal_all_avg_pct,
    round(a.anchor_equal_positive_avg_pct, 2) as anchor_equal_positive_avg_pct
from events_all e
inner join anchors_all a on e.scope = a.scope;
