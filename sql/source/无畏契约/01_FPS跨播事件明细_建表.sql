-- 引擎：Spark。
-- 产出：zhgametemp.wwqy_val_fps_cross_event_compact_20261023
-- 粒度：FPS 主品类主播 × 真实跨播事件。
-- 说明：主品类、赛事日、有效开播日、加权 ACU 和上一有效日配对均在本 SQL 内完成。

create table zhgametemp.wwqy_val_fps_cross_event_compact_20261023 as
with maincat_score as (
    -- 主播全期累计观看时长最高的游戏，作为主品类判断依据。
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

candidate_maincat as (
    -- 每个主播取累计观看时长最高的主品类。
    select
        luid,
        game_id as main_game_id,
        game_name as main_game_name,
        total_watch_ms
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
        from maincat_score
    ) t
    where rn = 1
),

fps_maincat as (
    -- 主品类不是无畏契约，且属于原 FPS 品类白名单。
    select
        luid,
        main_game_id,
        main_game_name,
        total_watch_ms
    from candidate_maincat
    where main_game_id <> '5937'
      and main_game_id in (
          '62639','862','863','1918','1126','4','2413','6079','3183',
          '2793','4341','7465','75359','3203','71827','72203','3185','3084','3639','4013','3090','4751','5435',
          '9449','10963','7209','3493','2327','7549','3677','2360','6507',
          '4769','4429','5713','5911','969','81001','74801','4371','7311','617','7369','618',
          '7575','135','5011','2174','496','861','1182','2471','6091','939','2953','3027',
          '9073','6933','68167','8359','9457','7955',
          '2942','1446','5969','5023','2342','2794','5649','6077','268','74059','4713',
          '3671','3777','7329','1656','806'
      )
),

session_day as (
    -- 主播 × 日全部品类 DAU，以及当天是否出现无畏契约观看记录。
    select
        cast(a.dt as string) as dt,
        cast(a.luid as string) as luid,
        max(cast(a.snick as string)) as snick,
        count(distinct a.user_ukey) as total_dau,
        max(case when cast(a.igameid as string) = '5937' then 1 else 0 end) as has_valorant
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
    inner join fps_maincat c
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
        cast(a.luid as string)
),

detail_day as (
    -- 主播 × 日开播、ACU 和观时；同时保留简单 ACU 与直播时长加权 ACU。
    select
        cast(d.dt as string) as dt,
        cast(d.ayyuid as string) as luid,
        max(cast(d.nickname as string)) as snick,
        sum(coalesce(cast(d.live_mins as double), 0)) as day_live_hours,
        sum(coalesce(cast(d.live_mins as double), 0)) * 60.0 as day_live_minutes,
        coalesce(avg(cast(d.acu as double)), 0.0) as day_simple_acu,
        coalesce(
            sum(coalesce(cast(d.acu as double), 0) * coalesce(cast(d.live_mins as double), 0))
            / nullif(sum(coalesce(cast(d.live_mins as double), 0)), 0),
            0.0
        ) as day_weighted_acu,
        sum(coalesce(cast(d.view_mins_only_live as double), 0)) * 60.0 as day_view_minutes
    from gamelive.dm_huya_ayyuid_detail_day d
    inner join fps_maincat c
        on cast(d.ayyuid as string) = c.luid
    where d.dt between '2026-01-01' and '2026-10-20'
      and d.ayyuid is not null
    group by
        cast(d.dt as string),
        cast(d.ayyuid as string)
),

match_anchor_info as (
    -- 三角洲、CS2 赛事主播 × 日期 × 赛事名称。
    select distinct
        substr(cast(date as string), 1, 10) as dt,
        cast(game_id as string) as game_id,
        cast(match_name as string) as match_name,
        cast(uid as string) as luid
    from gamelive.dwd_huya_dim_game_copyright_info_d_a
    where dt = '2026-10-20'
      and substr(cast(date as string), 1, 10) between '2026-01-01' and '2026-10-20'
      and live_type like '%直播%'
      and cast(game_id as string) in ('9449', '862')
),

match_daily as (
    -- 赛事 DAU 粒度：赛事日期 × 游戏 × 赛事名称。
    select
        cast(a.dt as string) as dt,
        m.game_id,
        m.match_name,
        count(distinct a.user_ukey) as match_dau
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
    inner join match_anchor_info m
        on cast(a.dt as string) = m.dt
       and cast(a.luid as string) = m.luid
       and cast(a.igameid as string) = m.game_id
    where a.dt between '2026-01-01' and '2026-10-20'
      and a.tag = 'gameid'
      and a.htime = 'session'
      and a.user_product in ('huya', 'huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios')
    group by
        cast(a.dt as string),
        m.game_id,
        m.match_name
),

big_match_days as (
    -- 赛事 DAU 达到 50000 的日期均视为大赛日。
    select distinct dt
    from match_daily
    where match_dau >= 50000
),

anchor_day as (
    -- 主表为主播 × 日详情，补充全品类 DAU、5937 标识和大赛日标识。
    select
        d.dt,
        d.luid,
        coalesce(s.snick, d.snick) as snick,
        d.day_live_hours,
        d.day_live_minutes,
        d.day_simple_acu,
        d.day_weighted_acu,
        d.day_view_minutes,
        coalesce(s.total_dau, 0) as total_dau,
        coalesce(s.has_valorant, 0) as has_valorant,
        case when b.dt is not null then 1 else 0 end as is_big_match_day
    from detail_day d
    left join session_day s
        on d.dt = s.dt
       and d.luid = s.luid
    left join big_match_days b
        on d.dt = b.dt
),

valid_seq as (
    -- 有效开播日至少 60 分钟；大赛日从序列中剔除。
    select
        *,
        row_number() over (partition by luid order by dt) as valid_seq
    from anchor_day
    where day_live_minutes >= 60.0
      and is_big_match_day = 0
),

cross_pair as (
    -- 只与上一个实际有效开播日比较，不要求自然日连续。
    select
        cur.dt as cross_dt,
        prev.dt as prev_valid_dt,
        cur.luid,
        cur.snick,
        cur.day_live_minutes as cross_live_minutes,
        prev.day_live_minutes as prev_live_minutes,
        cur.total_dau as cross_day_dau,
        prev.total_dau as prev_day_dau,
        cur.day_weighted_acu as cross_day_acu,
        prev.day_weighted_acu as prev_day_acu,
        cur.day_view_minutes as cross_day_view_minutes,
        prev.day_view_minutes as prev_day_view_minutes,
        cur.has_valorant as cur_has_valorant,
        prev.has_valorant as prev_has_valorant
    from valid_seq cur
    inner join valid_seq prev
        on cur.luid = prev.luid
       and cur.valid_seq = prev.valid_seq + 1
),

yearly_acu as (
    -- 主播年度简单平均 ACU：只使用至少 60 分钟且非大赛日的有效开播日。
    select
        luid,
        avg(day_simple_acu) as yearly_avg_acu
    from anchor_day
    where day_live_minutes >= 60.0
      and is_big_match_day = 0
    group by luid
)

select
    p.cross_dt,
    p.prev_valid_dt,
    p.luid,
    p.snick as anchor_nickname,
    c.main_game_id,
    c.main_game_name,
    1 as is_fps_game,
    round(y.yearly_avg_acu, 2) as yearly_avg_acu,
    case when y.yearly_avg_acu >= 2000 then '头部主播'
         when y.yearly_avg_acu >= 100 then '腰部主播'
         else '尾部主播'
    end as acu_type,
    p.cross_live_minutes,
    p.prev_live_minutes,
    p.cross_day_dau,
    p.prev_day_dau,
    100.0 * (p.cross_day_dau - p.prev_day_dau) / p.prev_day_dau as dau_growth_pct,
    p.cross_day_acu,
    p.prev_day_acu,
    case when p.prev_day_acu > 0
         then 100.0 * (p.cross_day_acu - p.prev_day_acu) / p.prev_day_acu
    end as acu_growth_pct,
    p.cross_day_view_minutes,
    p.prev_day_view_minutes,
    case when p.prev_day_view_minutes > 0
         then 100.0 * (p.cross_day_view_minutes - p.prev_day_view_minutes) / p.prev_day_view_minutes
    end as view_minutes_growth_pct
from cross_pair p
inner join fps_maincat c
    on p.luid = c.luid
inner join yearly_acu y
    on p.luid = y.luid
where p.cur_has_valorant = 1
  and p.prev_has_valorant = 0
  and p.prev_day_dau > 0;
