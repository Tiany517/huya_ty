with daily_view as (
    select
        dt,
        luid,
        snick,
        count(distinct user_ukey) as user_cnt
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user --用户观看表
    where
        dt between '2025-01-01' and '2026-06-21'
        and tag = 'gameid'
        and htime = 'session'
    group by dt, luid, snick
),

luid_dim as (
    select
        creator_uid,
        creator_nick,
        game_name
    from (
        select
            creator_uid,
            creator_nick,
            game_name,
            row_number() over(partition by creator_uid order by total_live_duration desc) as rnk
        from (
            select
                creator_uid,
                creator_nick,
                game_name,
                sum(anchor_live_duration) as total_live_duration -- 开播时长
            from gamelive.dws_huya_user_behavior_d_i --用户/主播行为表
            where 
                dt >= '2025-01-01'
                and data_type in ('live_watch_session') 
                and is_black_ukey = 0 --去黑产
                and product in('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi') --APP 
            group by creator_uid,creator_nick,game_name
        ) t
    )
    where rnk = 1
)

select
    date_trunc('month', cast(a.dt as date)) as mth,
    a.luid,
    a.snick,
    b.game_name as belongs_game_name,
    sum(a.user_cnt) / count(distinct a.dt) as avg_view_uv
from daily_view a
left join luid_dim b
    on a.luid = b.creator_uid
group by 
    date_trunc('month', cast(a.dt as date)),
    a.luid,
    a.snick,
    b.game_name