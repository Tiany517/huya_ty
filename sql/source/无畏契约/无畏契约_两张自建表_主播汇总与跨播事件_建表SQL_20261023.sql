-- 文件目的：提供最终分析中两张核心自建表的建表SQL。
-- 时间范围：2026-01-01 至 2026-10-20。
-- 引擎：Spark。
--
-- 前置依赖表：
--   zhgametemp.wwqy_cross_event60_weighted_anchor_day_20261022
--   zhgametemp.wwqy_cross_event60_maincat_20261022
--   zhgametemp.wwqy_cross_event60_nomatch_gamefilter_v2_anchor_20261022
--
-- 说明：
--   1. weighted_events 是“主播x跨播事件”粒度；
--   2. weighted_anchor 是“主播”粒度；
--   3. ACU涨幅采用日ACU按live_mins加权后的口径；
--   4. weighted_anchor 的年度ACU和头部/腰部/尾部标签，沿用原简单avg(acu)结果；
--   5. 跨播事件和主播内平均均为事件等权。


-- ============================================================
-- 表1：跨播事件明细
-- 表名：zhgametemp.wwqy_cross_event60_weighted_events_20261022
-- 粒度：主播 x 跨播事件，每个真实跨播事件一行
-- ============================================================
create table zhgametemp.wwqy_cross_event60_weighted_events_20261022 as
with valid_seq as (
    select
        *,
        row_number() over (
            partition by luid
            order by dt
        ) as valid_seq
    from zhgametemp.wwqy_cross_event60_weighted_anchor_day_20261022
    where day_live_minutes >= 60.0
      and is_big_match_day = 0
),
cross_pair as (
    select
        cur.dt as cross_dt,
        prev.dt as prev_valid_dt,
        cur.luid,
        cur.snick,
        cur.day_live_minutes as cross_live_minutes,
        prev.day_live_minutes as prev_live_minutes,
        cur.total_dau as cross_day_dau,
        prev.total_dau as prev_day_dau,
        cur.day_acu as cross_day_acu,
        prev.day_acu as prev_day_acu,
        cur.day_view_minutes as cross_day_view_minutes,
        prev.day_view_minutes as prev_day_view_minutes,
        cur.has_valorant as cur_has_valorant,
        prev.has_valorant as prev_has_valorant
    from valid_seq cur
    inner join valid_seq prev
        on cur.luid = prev.luid
       and cur.valid_seq = prev.valid_seq + 1
)
select
    p.cross_dt,
    p.prev_valid_dt,
    p.luid,
    p.snick,
    c.main_game_id,
    c.main_game_name,
    p.cross_live_minutes,
    p.prev_live_minutes,
    p.cross_day_dau,
    p.prev_day_dau,
    100.0 * (p.cross_day_dau - p.prev_day_dau)
        / p.prev_day_dau as dau_growth_pct,
    p.cross_day_acu,
    p.prev_day_acu,
    case
        when p.prev_day_acu > 0
        then 100.0 * (p.cross_day_acu - p.prev_day_acu)
             / p.prev_day_acu
    end as acu_growth_pct,
    p.cross_day_view_minutes,
    p.prev_day_view_minutes,
    case
        when p.prev_day_view_minutes > 0
        then 100.0
             * (p.cross_day_view_minutes - p.prev_day_view_minutes)
             / p.prev_day_view_minutes
    end as view_minutes_growth_pct
from cross_pair p
inner join zhgametemp.wwqy_cross_event60_maincat_20261022 c
    on p.luid = c.luid
where p.cur_has_valorant = 1
  and p.prev_has_valorant = 0
  and p.prev_day_dau > 0;


-- ============================================================
-- 表2：主播汇总
-- 表名：zhgametemp.wwqy_cross_event60_weighted_anchor_20261022
-- 粒度：跨播主播，每个主播一行
-- ============================================================
create table zhgametemp.wwqy_cross_event60_weighted_anchor_20261022 as
with event_avg as (
    select
        luid,
        max(snick) as anchor_nickname,
        max(main_game_id) as main_game_id,
        max(main_game_name) as main_game_name,
        count(*) as cross_event_cnt,
        count(dau_growth_pct) as valid_dau_growth_event_cnt,
        count(acu_growth_pct) as valid_acu_growth_event_cnt,
        count(view_minutes_growth_pct) as valid_view_growth_event_cnt,
        avg(dau_growth_pct) as avg_dau_growth_pct,
        avg(acu_growth_pct) as avg_acu_growth_pct,
        avg(view_minutes_growth_pct)
            as avg_view_minutes_growth_pct
    from zhgametemp.wwqy_cross_event60_weighted_events_20261022
    group by luid
)
select
    e.luid,
    e.anchor_nickname,
    y.yearly_avg_acu,
    e.main_game_id,
    e.main_game_name,
    e.cross_event_cnt,
    e.valid_dau_growth_event_cnt,
    e.valid_acu_growth_event_cnt,
    e.valid_view_growth_event_cnt,
    round(e.avg_dau_growth_pct, 2)
        as avg_dau_growth_pct,
    round(e.avg_acu_growth_pct, 2)
        as avg_acu_growth_pct,
    round(e.avg_view_minutes_growth_pct, 2)
        as avg_view_minutes_growth_pct,
    y.acu_type,
    y.is_fps_game
from event_avg e
inner join zhgametemp.wwqy_cross_event60_nomatch_gamefilter_v2_anchor_20261022 y
    on e.luid = y.luid;
