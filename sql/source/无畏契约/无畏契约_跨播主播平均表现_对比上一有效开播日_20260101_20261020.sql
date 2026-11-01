-- 目的：识别2026-01-01至2026-10-20期间，原本主品类不是无畏契约的主播，
--       汇总其每一次“跨播到无畏契约”相对上一个有效开播日的 DAU/ACU/观时表现。
-- 主品类：统计期内按主播×game_id汇总 app_view_mins，取观看时长最高的品类；
--         主品类为无畏契约（game_id=5937）的主播不计入跨播样本。
-- 有效开播日：主播当日 live_mins（小时）合计×60 >= 15分钟。
-- 跨播事件：当前有效开播日有无畏契约直播，且上一个有效开播日没有无畏契约直播。
-- 对比基准：按主播 valid_seq 配对，当前第n个有效开播日对比第n-1个有效开播日；
--           不使用日历自然日前一日。
-- DAU：会话表移动端，主播×日按 user_ukey 去重，范围为当天全部品类。
-- ACU：dm_huya_ayyuid_detail_day 当天全部品类，按 live_hours_only_live 加权。
-- 观时：view_mins_only_live 为小时，×60转为分钟；范围为当天全部品类。
-- 主播级汇总：对同一主播的所有有效跨播事件求算术平均，再输出主播级一行。
-- 平均增幅：先逐次计算涨幅，再对事件涨幅求平均；上一有效日为0或缺失的涨幅不参与平均。
-- 建议引擎：Spark（已在虎牙 Bigdata Spark 实跑；Presto 全量直跑存在单节点内存上限风险）

with game_score as (
    -- 统计期内主播在各品类的 app 观看时长，用于判定原主品类
    select
        cast(ayyuid as string) as luid,
        cast(gameid as string) as game_id,
        max(cast(game_name as string)) as game_name,
        sum(coalesce(cast(app_view_mins as double), 0)) as app_view_mins
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2026-01-01' and '2026-10-20'
      and gameid is not null
      and live_hours_only_live > 0
    group by
        cast(ayyuid as string),
        cast(gameid as string)
),

main_game as (
    -- 每个主播全统计期 app 观看时长最高的品类；并列时取 game_id 较小者
    select
        luid,
        game_id,
        game_name,
        app_view_mins
    from (
        select
            luid,
            game_id,
            game_name,
            app_view_mins,
            row_number() over (
                partition by luid
                order by app_view_mins desc, game_id
            ) as rnk
        from game_score
    ) t
    where rnk = 1
),

candidate as (
    -- 原主品类不是无畏契约，且统计期内实际出现过无畏契约有效开播记录的主播
    select
        m.luid,
        m.game_id as belong_game_id,
        m.game_name as belong_game_name
    from main_game m
    inner join (
        select distinct cast(ayyuid as string) as luid
        from gamelive.dm_huya_ayyuid_detail_day
        where dt between '2026-01-01' and '2026-10-20'
          and cast(gameid as string) = '5937'
          and live_hours_only_live > 0
          and coalesce(cast(dau_app as bigint), 0) > 0
    ) v
        on m.luid = v.luid
    where m.game_id <> '5937'
),

detail_day as (
    -- 候选主播的主播×日全品类指标；ACU和观时均汇总当天全部品类
    select
        cast(d.dt as string) as dt,
        cast(d.ayyuid as string) as luid,
        max(cast(d.nickname as string)) as snick,
        sum(coalesce(cast(d.live_mins as double), 0)) as day_live_mins,
        sum(coalesce(cast(d.live_hours_only_live as double), 0)) as live_hours,
        sum(
            coalesce(cast(d.acu as double), 0)
            * coalesce(cast(d.live_hours_only_live as double), 0)
        ) / nullif(
            sum(coalesce(cast(d.live_hours_only_live as double), 0)), 0
        ) as day_acu_weighted,
        sum(coalesce(cast(d.view_mins_only_live as double), 0)) * 60
            as day_view_minutes,
        max(
            case when cast(d.gameid as string) = '5937' then 1 else 0 end
        ) as has_valorant
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
    -- 有效开播日：当天 live_mins（小时）×60 至少15分钟
    select
        dt,
        luid,
        snick,
        day_live_mins,
        live_hours,
        day_acu_weighted,
        day_view_minutes,
        has_valorant
    from detail_day
    where day_live_mins * 60 >= 15
),

valid_detail_day_seq as (
    -- 给主播的每个有效开播日顺序编号，用于找上一个有效开播日
    select
        *,
        row_number() over (
            partition by luid
            order by dt
        ) as valid_seq
    from valid_detail_day
),

cross_pair as (
    -- 当前有效开播日跨播到无畏契约，上一个有效开播日没有无畏契约
    select
        cur.dt as cross_dt,
        cur.luid,
        cur.snick,
        cur.day_acu_weighted as cross_day_acu,
        cur.day_view_minutes as cross_day_view_minutes,
        prev.dt as prev_valid_dt,
        prev.day_acu_weighted as prev_valid_day_acu,
        prev.day_view_minutes as prev_valid_day_view_minutes
    from valid_detail_day_seq cur
    inner join valid_detail_day_seq prev
        on cur.luid = prev.luid
       and cur.valid_seq = prev.valid_seq + 1
    where cur.has_valorant = 1
      and prev.has_valorant = 0
),

session_day as (
    -- 会话事实先独立完成时间和业务过滤，再到主播级关联，避免把过滤条件写进 join
    select
        cast(a.dt as string) as dt,
        cast(a.luid as string) as luid,
        count(distinct a.user_ukey) as total_dau
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
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

candidate_session_day as (
    -- 只保留候选主播的主播×日全品类 DAU
    select
        s.dt,
        s.luid,
        s.total_dau
    from session_day s
    inner join candidate c
        on s.luid = c.luid
),

cross_event as (
    -- 一次跨播事件一行：跨播日与上一个有效开播日的 DAU/ACU/观时配对
    select
        p.cross_dt,
        p.luid,
        p.snick,
        c.belong_game_id,
        c.belong_game_name,
        cur_dau.total_dau as cross_day_dau,
        prev_dau.total_dau as prev_valid_day_dau,
        p.cross_day_acu,
        p.prev_valid_day_acu,
        p.cross_day_view_minutes,
        p.prev_valid_day_view_minutes
    from cross_pair p
    inner join candidate c
        on p.luid = c.luid
    left join candidate_session_day cur_dau
        on p.cross_dt = cur_dau.dt
       and p.luid = cur_dau.luid
    left join candidate_session_day prev_dau
        on p.prev_valid_dt = prev_dau.dt
       and p.luid = prev_dau.luid
),

anchor_avg as (
    -- 主播级汇总：每个主播的所有有效跨播事件求平均；增幅是逐事件涨幅的算术平均
    select
        luid,
        max(snick) as snick,
        belong_game_id,
        belong_game_name,
        count(*) as cross_event_cnt,
        count(cross_day_dau) as dau_valid_event_cnt,
        count(
            case
                when cross_day_dau is not null
                 and prev_valid_day_dau > 0 then 1
            end
        ) as dau_growth_valid_event_cnt,
        avg(cross_day_dau) as avg_cross_day_dau,
        avg(prev_valid_day_dau) as avg_prev_valid_day_dau,
        avg(cross_day_dau - prev_valid_day_dau) as avg_dau_change,
        avg(
            100.0 * (cross_day_dau - prev_valid_day_dau)
            / nullif(prev_valid_day_dau, 0)
        ) as avg_dau_growth_pct,
        count(cross_day_acu) as acu_valid_event_cnt,
        count(
            case
                when cross_day_acu is not null
                 and prev_valid_day_acu > 0 then 1
            end
        ) as acu_growth_valid_event_cnt,
        avg(cross_day_acu) as avg_cross_day_acu,
        avg(prev_valid_day_acu) as avg_prev_valid_day_acu,
        avg(cross_day_acu - prev_valid_day_acu) as avg_acu_change,
        avg(
            100.0 * (cross_day_acu - prev_valid_day_acu)
            / nullif(prev_valid_day_acu, 0)
        ) as avg_acu_growth_pct,
        count(cross_day_view_minutes) as view_valid_event_cnt,
        count(
            case
                when cross_day_view_minutes is not null
                 and prev_valid_day_view_minutes > 0 then 1
            end
        ) as view_growth_valid_event_cnt,
        avg(cross_day_view_minutes) as avg_cross_day_view_minutes,
        avg(prev_valid_day_view_minutes) as avg_prev_valid_day_view_minutes,
        avg(cross_day_view_minutes - prev_valid_day_view_minutes)
            as avg_view_minutes_change,
        avg(
            100.0 * (cross_day_view_minutes - prev_valid_day_view_minutes)
            / nullif(prev_valid_day_view_minutes, 0)
        ) as avg_view_minutes_growth_pct
    from cross_event
    group by
        luid,
        belong_game_id,
        belong_game_name
)

select
    luid,
    snick,
    belong_game_id,
    belong_game_name,
    cross_event_cnt,
    dau_valid_event_cnt,
    dau_growth_valid_event_cnt,
    round(avg_cross_day_dau, 2) as avg_cross_day_dau,
    round(avg_prev_valid_day_dau, 2) as avg_prev_valid_day_dau,
    round(avg_dau_change, 2) as avg_dau_change,
    round(avg_dau_growth_pct, 2) as avg_dau_growth_pct,
    acu_valid_event_cnt,
    acu_growth_valid_event_cnt,
    round(avg_cross_day_acu, 2) as avg_cross_day_acu,
    round(avg_prev_valid_day_acu, 2) as avg_prev_valid_day_acu,
    round(avg_acu_change, 2) as avg_acu_change,
    round(avg_acu_growth_pct, 2) as avg_acu_growth_pct,
    view_valid_event_cnt,
    view_growth_valid_event_cnt,
    round(avg_cross_day_view_minutes, 2) as avg_cross_day_view_minutes,
    round(avg_prev_valid_day_view_minutes, 2) as avg_prev_valid_day_view_minutes,
    round(avg_view_minutes_change, 2) as avg_view_minutes_change,
    round(avg_view_minutes_growth_pct, 2) as avg_view_minutes_growth_pct
from anchor_avg
order by
    avg_cross_day_dau desc,
    luid;
