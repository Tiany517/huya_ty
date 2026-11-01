-- 目的：计算2026-01-01至2026-10-20期间，主品类不是无畏契约的主播，
--       每次真实跨播到无畏契约相对上一个有效开播日的涨幅，并按事件等权求主播平均涨幅。
-- 时间：2026-01-01 至 2026-10-20。
-- 端范围：huya_andriod、huya_ipad、huya_pad、huya_ios。
-- 主品类：全期按主播×igameid汇总会话 user_duration，取累计观众观看时长最高品类；
--         并列取 game_id 较小者；主品类为5937的主播剔除。
-- 有效开播日：dm_huya_ayyuid_detail_day 当天 live_mins（小时）合计×60 > 15分钟。
-- 上一个实际开播日：同一主播有效开播日按 dt 排序后的前一个有效开播日。
-- 跨播事件：当天有5937观看记录，上一有效开播日没有5937观看记录，且上一日DAU>0。
-- DAU：会话表当天全部品类按 user_ukey 去重；当天和上一日均为主播总DAU。
-- ACU：详情表主播当天全品类，按 live_mins 加权。
-- 观时：详情表 view_mins_only_live 为小时，×60转为分钟，当天全部品类合计。
-- 平均涨幅：逐事件计算百分比涨幅后，在主播内按有效事件等权算术平均。
-- 建议引擎：Spark

with game_score as (
    -- 全期累计观众观看时长，用于判断主播主品类
    select
        cast(luid as string) as luid,
        cast(igameid as string) as game_id,
        max(cast(sgamename as string)) as game_name,
        sum(coalesce(cast(user_duration as double), 0)) as total_watch_ms
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where dt between '2026-01-01' and '2026-10-20'
      and tag = 'gameid'
      and htime = 'session'
      and user_product in (
          'huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios'
      )
      and luid is not null
      and igameid is not null
      and user_ukey is not null
      and coalesce(cast(user_duration as double), 0) > 0
    group by
        cast(luid as string),
        cast(igameid as string)
),

main_game as (
    -- 每个主播全期累计观众观看时长最高的品类；并列取 game_id 较小者
    select
        luid,
        game_id,
        game_name,
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
        from game_score
    ) t
    where rn = 1
),

candidate as (
    -- 只保留主品类不是无畏契约的主播
    select
        luid,
        game_id as main_game_id,
        game_name as main_game_name
    from main_game
    where game_id <> '5937'
),

session_day as (
    -- 候选主播的主播×日全品类DAU，以及当天是否存在无畏契约观看记录
    select
        cast(a.dt as string) as dt,
        cast(a.luid as string) as luid,
        max(cast(a.snick as string)) as snick,
        count(distinct a.user_ukey) as total_dau,
        max(case when cast(a.igameid as string) = '5937' then 1 else 0 end)
            as has_valorant
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
    inner join candidate c
        on cast(a.luid as string) = c.luid
    where a.dt between '2026-01-01' and '2026-10-20'
      and a.tag = 'gameid'
      and a.htime = 'session'
      and a.user_product in (
          'huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios'
      )
      and a.luid is not null
      and a.user_ukey is not null
      and coalesce(cast(a.user_duration as double), 0) > 0
    group by
        cast(a.dt as string),
        cast(a.luid as string)
),

detail_day as (
    -- 候选主播的详情表主播×日全品类指标
    select
        cast(d.dt as string) as dt,
        cast(d.ayyuid as string) as luid,
        max(cast(d.nickname as string)) as snick,
        sum(coalesce(cast(d.live_mins as double), 0)) as day_live_mins,
        sum(coalesce(cast(d.acu as double), 0)
            * coalesce(cast(d.live_mins as double), 0))
            / nullif(sum(coalesce(cast(d.live_mins as double), 0)), 0)
            as day_acu_weighted,
        sum(coalesce(cast(d.view_mins_only_live as double), 0)) * 60
            as day_view_minutes
    from gamelive.dm_huya_ayyuid_detail_day d
    inner join candidate c
        on cast(d.ayyuid as string) = c.luid
    where d.dt between '2026-01-01' and '2026-10-20'
      and coalesce(cast(d.live_mins as double), 0) > 0
    group by
        cast(d.dt as string),
        cast(d.ayyuid as string)
),

valid_detail_day as (
    -- 有效开播日：当天 live_mins（小时）×60 > 15分钟
    select
        dt,
        luid,
        snick,
        day_live_mins,
        day_acu_weighted,
        day_view_minutes
    from detail_day
    where day_live_mins * 60 > 15
),

yearly_avg_acu as (
    -- 主播全年平均ACU：只平均有效开播日的日ACU
    select
        luid,
        avg(day_acu_weighted) as yearly_avg_acu
    from valid_detail_day
    where day_acu_weighted is not null
    group by luid
),

valid_detail_day_seq as (
    -- 给每个主播的有效开播日排序，用于找上一个实际开播日
    select
        *,
        row_number() over (
            partition by luid
            order by dt
        ) as valid_seq
    from valid_detail_day
),

cross_pair as (
    -- 当前有效开播日与上一个有效开播日配对
    select
        cur.dt as cross_dt,
        cur.luid,
        cur.snick,
        cur.day_acu_weighted as cross_day_acu,
        cur.day_view_minutes as cross_day_view_minutes,
        prev.dt as prev_valid_dt,
        prev.day_acu_weighted as prev_day_acu,
        prev.day_view_minutes as prev_day_view_minutes
    from valid_detail_day_seq cur
    inner join valid_detail_day_seq prev
        on cur.luid = prev.luid
       and cur.valid_seq = prev.valid_seq + 1
),

cross_event as (
    -- 当天有5937观看记录；上一个有效开播日无5937观看记录且DAU>0
    select
        p.cross_dt,
        p.luid,
        p.snick,
        c.main_game_id,
        c.main_game_name,
        cur_session.total_dau as cross_day_dau,
        prev_session.total_dau as prev_day_dau,
        p.cross_day_acu,
        p.prev_day_acu,
        p.cross_day_view_minutes,
        p.prev_day_view_minutes,
        100.0 * (
            cur_session.total_dau - prev_session.total_dau
        ) / prev_session.total_dau as dau_growth_pct,
        case
            when p.prev_day_acu > 0 then 100.0 * (
                p.cross_day_acu - p.prev_day_acu
            ) / p.prev_day_acu
        end as acu_growth_pct,
        case
            when p.prev_day_view_minutes > 0 then 100.0 * (
                p.cross_day_view_minutes - p.prev_day_view_minutes
            ) / p.prev_day_view_minutes
        end as view_minutes_growth_pct
    from cross_pair p
    inner join candidate c
        on p.luid = c.luid
    inner join session_day cur_session
        on p.cross_dt = cur_session.dt
       and p.luid = cur_session.luid
    inner join session_day prev_session
        on p.prev_valid_dt = prev_session.dt
       and p.luid = prev_session.luid
    where cur_session.has_valorant = 1
      and prev_session.has_valorant = 0
      and prev_session.total_dau > 0
),

anchor_avg as (
    -- 每个主播一行；每个指标均对可计算事件做算术平均
    select
        e.luid,
        max(e.snick) as snick,
        y.yearly_avg_acu,
        e.main_game_id,
        e.main_game_name,
        count(*) as cross_event_cnt,
        count(e.dau_growth_pct) as valid_growth_event_cnt,
        avg(e.dau_growth_pct) as avg_dau_growth_pct,
        avg(e.acu_growth_pct) as avg_acu_growth_pct,
        avg(e.view_minutes_growth_pct) as avg_view_minutes_growth_pct
    from cross_event e
    left join yearly_avg_acu y
        on e.luid = y.luid
    group by
        e.luid,
        y.yearly_avg_acu,
        e.main_game_id,
        e.main_game_name
)

select
    luid,
    snick as anchor_nickname,
    round(yearly_avg_acu, 2) as yearly_avg_acu,
    main_game_id,
    main_game_name,
    cross_event_cnt,
    valid_growth_event_cnt,
    round(avg_dau_growth_pct, 2) as avg_dau_growth_pct,
    round(avg_acu_growth_pct, 2) as avg_acu_growth_pct,
    round(avg_view_minutes_growth_pct, 2) as avg_view_minutes_growth_pct
from anchor_avg
order by
    avg_dau_growth_pct desc,
    luid;
