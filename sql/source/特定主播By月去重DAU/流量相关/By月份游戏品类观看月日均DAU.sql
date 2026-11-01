with daily_view as (
    select
        dt,
        igameid,
        sgamename,
        count(distinct user_ukey) as user_cnt
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user --用户观看表
    where
        dt between '2025-01-01' and '2026-06-21'
        and tag = 'gameid'
        and htime = 'session'
    group by dt, igameid, sgamename
),
game_dim as (
    select
        game_id,
        max(game_label) as game_label
    from gamelive.dim_huya_game_d_a
    where dt between '2026-05-23' and '2026-06-21'
    group by game_id
)

select
    date_trunc('month', cast(a.dt as date)) as mth,
    a.igameid as game_id,
    a.sgamename,
    b.game_label,
    sum(a.user_cnt) / count(distinct a.dt) as avg_view_uv
from daily_view a
left join game_dim b
    on a.igameid = b.game_id
group by
    date_trunc('month', cast(a.dt as date)),
    a.igameid,
    a.sgamename,
    b.game_label
order by
    mth,
    avg_view_uv desc