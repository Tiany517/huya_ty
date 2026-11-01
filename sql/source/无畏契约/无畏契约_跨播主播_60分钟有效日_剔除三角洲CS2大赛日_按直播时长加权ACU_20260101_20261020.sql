-- 目的：在“60分钟有效日 + 剔除三角洲/CS2大赛日”的最终口径上，
--       将事件ACU涨幅改为“日ACU按直播时长加权”后重新计算。
-- 时间：2026-01-01 至 2026-10-20。
-- 日ACU：sum(acu * live_mins) / sum(live_mins)，其中 live_mins 为小时，
--        分子和分母单位一致，因此无需额外乘60。
-- 其他口径保持不变：
--   1. 有效日：sum(live_mins)*60>=60；
--   2. 当期和上一有效日均剔除三角洲(9449)、CS2(862)大赛日；
--   3. 跨播：当天有5937观看记录，上一有效日无5937且总DAU>0；
--   4. 主播内按事件等权平均，分层内按主播等权平均；
--   5. 年度日均ACU及头部/腰部/尾部标签仍沿用原简单 avg(acu) 口径。
-- 引擎：Spark。
--
-- 前置表：
--   zhgametemp.wwqy_cross_event60_maincat_20261022
--   zhgametemp.wwqy_cross_event60_session_day_20261022
--   zhgametemp.wwqy_fps_bigmatch_days_9449_862_gamefilter_v2_20261022
--   zhgametemp.wwqy_cross_event60_nomatch_gamefilter_v2_anchor_20261022

-- 1. 主播x日：日ACU按各游戏行直播时长加权
create table zhgametemp.wwqy_cross_event60_weighted_detail_day_20261022 as
select
    cast(d.dt as string) as dt,
    cast(d.ayyuid as string) as luid,
    max(cast(d.nickname as string)) as snick,
    sum(coalesce(cast(d.live_mins as double), 0)) as day_live_hours,
    sum(coalesce(cast(d.live_mins as double), 0)) * 60.0 as day_live_minutes,
    coalesce(
        sum(coalesce(cast(d.acu as double), 0) * coalesce(cast(d.live_mins as double), 0))
        / nullif(sum(coalesce(cast(d.live_mins as double), 0)), 0),
        0.0
    ) as day_acu,
    sum(coalesce(cast(d.view_mins_only_live as double), 0)) * 60.0 as day_view_minutes
from gamelive.dm_huya_ayyuid_detail_day d
inner join zhgametemp.wwqy_cross_event60_maincat_20261022 c
    on cast(d.ayyuid as string) = c.luid
where d.dt between '2026-01-01' and '2026-10-20'
  and d.ayyuid is not null
group by
    cast(d.dt as string),
    cast(d.ayyuid as string);

-- 2. 主播x日总表：补充全品类DAU、无畏契约观看标识和大赛日标识
create table zhgametemp.wwqy_cross_event60_weighted_anchor_day_20261022 as
with big_days as (
    select distinct dt
    from zhgametemp.wwqy_fps_bigmatch_days_9449_862_gamefilter_v2_20261022
)
select
    d.dt,
    d.luid,
    coalesce(s.snick, d.snick) as snick,
    d.day_live_hours,
    d.day_live_minutes,
    d.day_acu,
    d.day_view_minutes,
    coalesce(s.total_dau, 0) as total_dau,
    coalesce(s.has_valorant, 0) as has_valorant,
    case when b.dt is not null then 1 else 0 end as is_big_match_day
from zhgametemp.wwqy_cross_event60_weighted_detail_day_20261022 d
left join zhgametemp.wwqy_cross_event60_session_day_20261022 s
    on d.dt = s.dt
   and d.luid = s.luid
left join big_days b
    on d.dt = b.dt;

-- 3. 跨播事件：从有效日序列剔除大赛日后，与上一个有效日比较
create table zhgametemp.wwqy_cross_event60_weighted_events_20261022 as
with valid_seq as (
    select *, row_number() over (partition by luid order by dt) as valid_seq
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
    100.0 * (p.cross_day_dau - p.prev_day_dau) / p.prev_day_dau as dau_growth_pct,
    p.cross_day_acu,
    p.prev_day_acu,
    case when p.prev_day_acu > 0
         then 100.0 * (p.cross_day_acu - p.prev_day_acu) / p.prev_day_acu end as acu_growth_pct,
    p.cross_day_view_minutes,
    p.prev_day_view_minutes,
    case when p.prev_day_view_minutes > 0
         then 100.0 * (p.cross_day_view_minutes - p.prev_day_view_minutes) / p.prev_day_view_minutes end as view_minutes_growth_pct
from cross_pair p
inner join zhgametemp.wwqy_cross_event60_maincat_20261022 c
    on p.luid = c.luid
where p.cur_has_valorant = 1
  and p.prev_has_valorant = 0
  and p.prev_day_dau > 0;

-- 4. 主播汇总：事件等权平均；年度ACU和分层沿用原简单 avg(acu) 结果
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
        avg(view_minutes_growth_pct) as avg_view_minutes_growth_pct
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
    round(e.avg_dau_growth_pct, 2) as avg_dau_growth_pct,
    round(e.avg_acu_growth_pct, 2) as avg_acu_growth_pct,
    round(e.avg_view_minutes_growth_pct, 2) as avg_view_minutes_growth_pct,
    y.acu_type,
    y.is_fps_game
from event_avg e
inner join zhgametemp.wwqy_cross_event60_nomatch_gamefilter_v2_anchor_20261022 y
    on e.luid = y.luid;
