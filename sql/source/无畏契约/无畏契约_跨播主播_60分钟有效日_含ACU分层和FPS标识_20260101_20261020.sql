-- 目的：计算2026-01-01至2026-10-20期间，主品类不是无畏契约的主播，
--       以60分钟作为有效直播日门槛，计算跨播事件和主播级平均涨幅，并增加ACU分层与FPS标识。
-- 时间：2026-01-01 至 2026-10-20；源表最新分区为2026-10-21。
-- 端范围：huya_andriod、huya_ipad、huya_pad、huya_ios。
-- 主品类：会话表按主播x游戏累计user_duration，取最高者；并列取game_id较小者；剔除主品类5937。
-- 有效直播日：详情表按主播x日聚合后，sum(live_mins) * 60 >= 60。
-- ACU：严格采用详情表按dt、ayyuid分组后的coalesce(avg(acu), 0)，不按live_mins加权。
-- DAU：会话表主播x日全部品类按user_ukey去重。
-- 观时：详情表view_mins_only_live为小时，乘60转分钟。
-- 跨播事件：当天为有效直播日且有5937观看记录；上一有效直播日无5937记录且DAU>0。
-- 涨幅：逐事件计算百分比，主播内按指标可计算事件做算术平均，事件等权。
-- FPS：按main_game_id白名单识别，包含FPS/TPS/大逃杀/战术射击/撤离射击/英雄射击。
-- 引擎：Spark。

-- 1. 主播主品类
create table zhgametemp.wwqy_cross_event60_maincat_20261022 as
with game_score as (
    select
        cast(luid as string) as luid,
        cast(igameid as string) as game_id,
        max(cast(sgamename as string)) as game_name,
        sum(coalesce(cast(user_duration as double), 0)) as total_watch_ms
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where dt between '2026-01-01' and '2026-10-20'
      and tag = 'gameid'
      and htime = 'session'
      and user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios')
      and luid is not null
      and igameid is not null
      and user_ukey is not null
      and coalesce(cast(user_duration as double), 0) > 0
    group by
        cast(luid as string),
        cast(igameid as string)
),
main_game as (
    select luid, game_id, game_name, total_watch_ms
    from (
        select
            luid,
            game_id,
            game_name,
            total_watch_ms,
            row_number() over (
                partition by luid
                order by total_watch_ms desc, game_id
            ) as rn
        from game_score
    ) t
    where rn = 1
)
select
    luid,
    game_id as main_game_id,
    game_name as main_game_name,
    total_watch_ms
from main_game
where game_id <> '5937';

-- 2. 候选主播主播x日全品类DAU及无畏契约观看标识
create table zhgametemp.wwqy_cross_event60_session_day_20261022 as
select
    cast(a.dt as string) as dt,
    cast(a.luid as string) as luid,
    max(cast(a.snick as string)) as snick,
    count(distinct a.user_ukey) as total_dau,
    max(case when cast(a.igameid as string) = '5937' then 1 else 0 end) as has_valorant
from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
inner join zhgametemp.wwqy_cross_event60_maincat_20261022 c
    on cast(a.luid as string) = c.luid
where a.dt between '2026-01-01' and '2026-10-20'
  and a.tag = 'gameid'
  and a.htime = 'session'
  and a.user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios')
  and a.luid is not null
  and a.user_ukey is not null
  and coalesce(cast(a.user_duration as double), 0) > 0
group by
    cast(a.dt as string),
    cast(a.luid as string);

-- 3. 候选主播主播x日开播时长、标准ACU和观时
create table zhgametemp.wwqy_cross_event60_detail_day_20261022 as
select
    cast(d.dt as string) as dt,
    cast(d.ayyuid as string) as luid,
    max(cast(d.nickname as string)) as snick,
    sum(coalesce(cast(d.live_mins as double), 0)) as day_live_hours,
    sum(coalesce(cast(d.live_mins as double), 0)) * 60.0 as day_live_minutes,
    coalesce(avg(cast(d.acu as double)), 0.0) as day_acu,
    sum(coalesce(cast(d.view_mins_only_live as double), 0)) * 60.0 as day_view_minutes
from gamelive.dm_huya_ayyuid_detail_day d
inner join zhgametemp.wwqy_cross_event60_maincat_20261022 c
    on cast(d.ayyuid as string) = c.luid
where d.dt between '2026-01-01' and '2026-10-20'
  and d.ayyuid is not null
group by
    cast(d.dt as string),
    cast(d.ayyuid as string);

-- 4. 主播x日总明细：详情表作为有效日主表，左连接会话DAU
--    会话层缺失时DAU记为0、无畏契约标识记为0，避免从有效日序列中错误跳过该日。
create table zhgametemp.wwqy_cross_event60_anchor_day_20261022 as
select
    d.dt,
    d.luid,
    coalesce(s.snick, d.snick) as snick,
    d.day_live_hours,
    d.day_live_minutes,
    d.day_acu,
    d.day_view_minutes,
    coalesce(s.total_dau, 0) as total_dau,
    coalesce(s.has_valorant, 0) as has_valorant
from zhgametemp.wwqy_cross_event60_detail_day_20261022 d
left join zhgametemp.wwqy_cross_event60_session_day_20261022 s
    on d.dt = s.dt
   and d.luid = s.luid;

-- 5. 跨播事件明细：当天有效且有5937，上一有效日无5937且DAU>0
create table zhgametemp.wwqy_cross_event60_events_20261022 as
with valid_seq as (
    select
        *,
        row_number() over (partition by luid order by dt) as valid_seq
    from zhgametemp.wwqy_cross_event60_anchor_day_20261022
    where day_live_minutes >= 60.0
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
    case
        when p.prev_day_acu > 0 then 100.0 * (p.cross_day_acu - p.prev_day_acu) / p.prev_day_acu
    end as acu_growth_pct,
    p.cross_day_view_minutes,
    p.prev_day_view_minutes,
    case
        when p.prev_day_view_minutes > 0
            then 100.0 * (p.cross_day_view_minutes - p.prev_day_view_minutes) / p.prev_day_view_minutes
    end as view_minutes_growth_pct
from cross_pair p
inner join zhgametemp.wwqy_cross_event60_maincat_20261022 c
    on p.luid = c.luid
where p.cur_has_valorant = 1
  and p.prev_has_valorant = 0
  and p.prev_day_dau > 0;

-- 6. 主播汇总表：每个主播一行，事件等权平均
create table zhgametemp.wwqy_cross_event60_anchor_20261022 as
with yearly_acu as (
    select
        luid,
        avg(day_acu) as yearly_avg_acu
    from zhgametemp.wwqy_cross_event60_anchor_day_20261022
    where day_live_minutes >= 60.0
    group by luid
),
event_avg as (
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
    from zhgametemp.wwqy_cross_event60_events_20261022
    group by luid
)
select
    e.luid,
    e.anchor_nickname,
    round(y.yearly_avg_acu, 2) as yearly_avg_acu,
    e.main_game_id,
    e.main_game_name,
    e.cross_event_cnt,
    e.valid_dau_growth_event_cnt,
    e.valid_acu_growth_event_cnt,
    e.valid_view_growth_event_cnt,
    round(e.avg_dau_growth_pct, 2) as avg_dau_growth_pct,
    round(e.avg_acu_growth_pct, 2) as avg_acu_growth_pct,
    round(e.avg_view_minutes_growth_pct, 2) as avg_view_minutes_growth_pct,
    case
        when y.yearly_avg_acu >= 2000 then '头部主播'
        when y.yearly_avg_acu >= 100 then '腰部主播'
        when y.yearly_avg_acu < 100 then '尾部主播'
    end as acu_type,
    case
        when e.main_game_id in (
            '5937','62639',
            '862','863','1918','1126','4','2413','6079','3183',
            '2793','4341','7465','75359','3203','71827','72203','3185','3084','3639','4013','3090','4751','5435',
            '9449','10963','7209','3493','2327','7549','3677','2360','6507',
            '4769','4429','5713','5911','969','81001','74801','4371','7311','617','7369','618',
            '7575','135','5011','2174','496','861','1182','2471','6091','939','2953','3027',
            '9073','6933','68167','8359','9457','7955',
            '2942','1446','5969','5023','2342','2794','5649','6077','268','74059','4713',
            '3671','3777','7329','1656','806'
        ) then 1 else 0
    end as is_fps_game
from event_avg e
left join yearly_acu y
    on e.luid = y.luid
order by
    e.avg_dau_growth_pct desc nulls last,
    e.luid;
