with game_dim as (
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
    count(distinct a.user_ukey) as mau
from gamelive.dwt_huya_ayyuid_session_from_server_with_user a --用户观看表
left join game_dim b
    on a.igameid = b.game_id
where
    a.dt between '2025-01-01' and '2026-06-21'
    and a.tag = 'gameid'
    and a.htime = 'session'
group by
    date_trunc('month', cast(a.dt as date)),
    a.igameid,
    a.sgamename,
    b.game_label
order by
    mth,
    mau desc