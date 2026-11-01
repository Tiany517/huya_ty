-- 目的：列出2026-01-01至2026-10-20期间，主品类不是无畏契约的主播每一次跨播到无畏契约的事件
-- 主品类：统计期 app_view_mins 按 game_id 汇总，取观看时长最高的品类
-- 跨播事件：当天有无畏契约直播，且前一日有直播但无畏契约直播时长为0
-- 对比基准：严格使用日历前一日；前一日无数据时增幅为空
-- DAU：会话表按主播×日去重 user_ukey，移动端口径
-- ACU：dm_huya_ayyuid_detail_day.acu 按 live_hours_only_live 加权
-- 观时：dm_huya_ayyuid_detail_day.view_mins_only_live × 60，单位分钟
-- 建议引擎：Spark

with game_score as (
    select
        cast(ayyuid as varchar) as luid,
        cast(gameid as varchar) as game_id,
        max(cast(game_name as varchar)) as game_name,
        sum(coalesce(cast(app_view_mins as double), 0)) as app_view_mins
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2026-01-01' and '2026-10-20'
      and gameid is not null
      and live_hours_only_live > 0
    group by cast(ayyuid as varchar), cast(gameid as varchar)
),

main_game as (
    select luid, game_id, game_name, app_view_mins
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

first_valorant as (
    select cast(ayyuid as varchar) as luid, min(dt) as first_valorant_dt
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2026-01-01' and '2026-10-20'
      and cast(gameid as varchar) = '5937'
      and live_hours_only_live > 0
      and coalesce(cast(dau_app as bigint), 0) > 0
    group by cast(ayyuid as varchar)
),

candidate as (
    select
        f.luid,
        f.first_valorant_dt,
        m.game_id as belong_game_id,
        m.game_name as belong_game_name,
        m.app_view_mins as belong_app_view_mins
    from first_valorant f
    inner join main_game m
        on f.luid = m.luid
    where m.game_id <> '5937'
),

detail_day as (
    select
        cast(d.dt as varchar) as dt,
        cast(d.ayyuid as varchar) as luid,
        max(cast(d.nickname as varchar)) as snick,
        sum(coalesce(cast(d.live_hours_only_live as double), 0)) as live_hours,
        sum(
            coalesce(cast(d.acu as double), 0)
            * coalesce(cast(d.live_hours_only_live as double), 0)
        ) / nullif(
            sum(coalesce(cast(d.live_hours_only_live as double), 0)), 0
        ) as acu_weighted,
        sum(coalesce(cast(d.view_mins_only_live as double), 0)) * 60 as view_minutes,
        max(case when cast(d.gameid as varchar) = '5937' then 1 else 0 end) as has_valorant,
        max(
            case when cast(d.gameid as varchar) = '5937'
                 then cast(d.acu as double) end
        ) as valorant_acu,
        sum(
            case when cast(d.gameid as varchar) = '5937'
                 then coalesce(cast(d.view_mins_only_live as double), 0)
                 else 0 end
        ) * 60 as valorant_view_minutes
    from gamelive.dm_huya_ayyuid_detail_day d
    inner join candidate c
        on cast(d.ayyuid as varchar) = c.luid
    where d.dt between '2026-01-01' and '2026-10-20'
      and d.live_hours_only_live > 0
    group by cast(d.dt as varchar), cast(d.ayyuid as varchar)
),

detail_day_with_prev as (
    select
        *,
        lag(dt) over (partition by luid order by dt) as prev_detail_dt,
        lag(acu_weighted) over (partition by luid order by dt) as prev_acu,
        lag(view_minutes) over (partition by luid order by dt) as prev_view_minutes,
        lag(has_valorant) over (partition by luid order by dt) as prev_has_valorant
    from detail_day
),

anchor_day as (
    select
        cast(a.dt as varchar) as dt,
        cast(a.luid as varchar) as luid,
        count(distinct a.user_ukey) as total_dau
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
    inner join candidate c
        on cast(a.luid as varchar) = c.luid
    where a.dt between '2026-01-01' and '2026-10-20'
      and a.tag = 'gameid'
      and a.htime = 'session'
      and a.user_product in (
          'huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios'
      )
      and a.user_ukey is not null
      and coalesce(cast(a.user_duration as double), 0) > 0
    group by cast(a.dt as varchar), cast(a.luid as varchar)
),

cross_event as (
    select
        d.dt as cross_dt,
        d.luid,
        d.snick,
        c.belong_game_id,
        c.belong_game_name,
        d.valorant_acu,
        d.valorant_view_minutes,
        ad.total_dau as cross_day_total_dau,
        d.acu_weighted as cross_day_acu,
        d.view_minutes as cross_day_view_minutes,
        pd.total_dau as prev_day_total_dau,
        d.prev_acu,
        d.prev_view_minutes
    from detail_day_with_prev d
    inner join candidate c
        on d.luid = c.luid
    left join anchor_day ad
        on d.dt = ad.dt
       and d.luid = ad.luid
    left join anchor_day pd
        on d.prev_detail_dt = pd.dt
       and d.luid = pd.luid
    where d.has_valorant = 1
      and d.prev_has_valorant = 0
      and d.prev_detail_dt = cast(
          date_add('day', -1, cast(d.dt as date)) as varchar
      )
)

select
    cross_dt,
    row_number() over (partition by luid order by cross_dt) as cross_seq,
    luid,
    snick,
    belong_game_id,
    belong_game_name,
    valorant_acu,
    round(valorant_view_minutes, 2) as valorant_view_minutes,
    cross_day_total_dau,
    round(cross_day_acu, 2) as cross_day_acu,
    round(cross_day_view_minutes, 2) as cross_day_view_minutes,
    prev_day_total_dau,
    round(prev_acu, 2) as prev_day_acu,
    round(prev_view_minutes, 2) as prev_day_view_minutes,
    cross_day_total_dau - prev_day_total_dau as dau_change,
    round(
        100.0 * (cross_day_total_dau - prev_day_total_dau)
        / nullif(prev_day_total_dau, 0),
        2
    ) as dau_growth_pct,
    round(cross_day_acu - prev_acu, 2) as acu_change,
    round(
        100.0 * (cross_day_acu - prev_acu)
        / nullif(prev_acu, 0),
        2
    ) as acu_growth_pct,
    round(cross_day_view_minutes - prev_view_minutes, 2) as view_minutes_change,
    round(
        100.0 * (cross_day_view_minutes - prev_view_minutes)
        / nullif(prev_view_minutes, 0),
        2
    ) as view_minutes_growth_pct
from cross_event
order by cross_day_total_dau desc, cross_dt, luid;
