-- 目的：在60分钟有效直播日、avg(acu)、事件等权平均涨幅的基础上，
--       剔除三角洲行动(9449)、CS2(862)赛事当天DAU>=50000的大赛日。
-- 时间：2026-01-01 至 2026-10-20。
-- 大赛日：同一 game_id、match_name、dt 的赛事观看DAU>=50000；
--         不使用赛事周期平均DAU，也不使用赛事周期平均后的整段赛事日期。
-- 赛事DAU必须限定在赛事对应的游戏会话，避免赛事主播当天播放其他游戏时误算。
-- 有效日：详情表主播x日sum(live_mins)*60>=60，且不是大赛日。
-- 跨播事件：当天有5937观看记录，上一有效日无5937且总DAU>0。
-- ACU：coalesce(avg(acu),0)，不按live_mins加权。
-- 涨幅：主播内每次跨播事件分别计算，再对事件做等权算术平均。
-- 引擎：Spark。

-- 1. 三角洲行动、CS2赛事x日DAU
create table zhgametemp.wwqy_fps_match_daily_9449_862_gamefilter_v2b_20261022 as
with match_anchor_info as (
    select distinct
        substr(cast(date as string),1,10) as dt,
        cast(game_id as string) as game_id,
        cast(match_name as string) as match_name,
        cast(uid as string) as luid
    from gamelive.dwd_huya_dim_game_copyright_info_d_a
    where dt='2026-10-20'
      and substr(cast(date as string),1,10) between '2026-01-01' and '2026-10-20'
      and live_type like '%直播%'
      and cast(game_id as string) in ('9449','862')
)
select
    cast(a.dt as string) as dt,
    m.game_id,
    m.match_name,
    count(distinct a.user_ukey) as match_dau
from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
inner join match_anchor_info m
    on cast(a.dt as string)=m.dt
   and cast(a.luid as string)=m.luid
   and cast(a.igameid as string)=m.game_id
where a.dt between '2026-01-01' and '2026-10-20'
  and a.tag='gameid'
  and a.htime='session'
  and a.user_product in ('huya','huya_andriod','huya_ipad','huya_pad','huya_ios')
group by
    cast(a.dt as string),
    m.game_id,
    m.match_name;

-- 2. 赛事当天DAU>=50000的大赛日明细
create table zhgametemp.wwqy_fps_bigmatch_days_9449_862_gamefilter_v2_20261022 as
select dt, game_id, match_name, match_dau
from zhgametemp.wwqy_fps_match_daily_9449_862_gamefilter_v2b_20261022
where match_dau >= 50000;

-- 3. 主播x日明细增加大赛日标识；大赛日不等同于有效对比日
create table zhgametemp.wwqy_cross_event60_nomatch_gamefilter_v2_anchor_day_20261022 as
with big_days as (
    select distinct dt
    from zhgametemp.wwqy_fps_bigmatch_days_9449_862_gamefilter_v2_20261022
)
select
    d.dt,
    d.luid,
    d.snick,
    d.day_live_hours,
    d.day_live_minutes,
    d.day_acu,
    d.day_view_minutes,
    d.total_dau,
    d.has_valorant,
    case when b.dt is not null then 1 else 0 end as is_big_match_day
from zhgametemp.wwqy_cross_event60_anchor_day_20261022 d
left join big_days b on d.dt = b.dt;

-- 4. 从有效日序列中彻底剔除大赛日，再识别跨播事件
create table zhgametemp.wwqy_cross_event60_nomatch_gamefilter_v2_events_20261022 as
with valid_seq as (
    select *, row_number() over (partition by luid order by dt) as valid_seq
    from zhgametemp.wwqy_cross_event60_nomatch_gamefilter_v2_anchor_day_20261022
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

-- 5. 主播级汇总：剔除大赛日后再计算年度ACU和事件等权平均涨幅
create table zhgametemp.wwqy_cross_event60_nomatch_gamefilter_v2_anchor_20261022 as
with yearly_acu as (
    select luid, avg(day_acu) as yearly_avg_acu
    from zhgametemp.wwqy_cross_event60_nomatch_gamefilter_v2_anchor_day_20261022
    where day_live_minutes >= 60.0
      and is_big_match_day = 0
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
    from zhgametemp.wwqy_cross_event60_nomatch_gamefilter_v2_events_20261022
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
    case when y.yearly_avg_acu >= 2000 then '头部主播'
         when y.yearly_avg_acu >= 100 then '腰部主播'
         when y.yearly_avg_acu < 100 then '尾部主播' end as acu_type,
    case when e.main_game_id in (
        '5937','62639','862','863','1918','1126','4','2413','6079','3183',
        '2793','4341','7465','75359','3203','71827','72203','3185','3084','3639','4013','3090','4751','5435',
        '9449','10963','7209','3493','2327','7549','3677','2360','6507',
        '4769','4429','5713','5911','969','81001','74801','4371','7311','617','7369','618',
        '7575','135','5011','2174','496','861','1182','2471','6091','939','2953','3027',
        '9073','6933','68167','8359','9457','7955',
        '2942','1446','5969','5023','2342','2794','5649','6077','268','74059','4713',
        '3671','3777','7329','1656','806'
    ) then 1 else 0 end as is_fps_game
from event_avg e
left join yearly_acu y on e.luid = y.luid;
