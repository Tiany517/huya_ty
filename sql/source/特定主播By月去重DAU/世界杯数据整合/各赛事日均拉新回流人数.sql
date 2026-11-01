with copyright_info as (
    select distinct
        substr(a.date, 1, 10) as dt,
        a.game_id,
        b.game_name,
        a.match_name,
        a.uid as luid
    from gamelive.dwd_huya_dim_game_copyright_info_d_a a
    left join (
        select
            game_id,
            game_name,
            max(game_label) as game_label
        from gamelive.dim_huya_game_d_a
        where dt >= '2024-01-01'
        group by
            game_id,
            game_name
    ) b
        on a.game_id = b.game_id
    where a.dt = '2026-07-12'
      and substr(a.date, 1, 10) between '2026-06-12' and '2026-07-15'
      and a.live_type like '%直播%'
),

laxin_huiliu_user as (
    select distinct
        dt as new_dt,
        luid,
        user_ukey,
        '拉新' as label
    from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
    where dt between '2026-06-12' and '2026-07-15'
      and user_ukey is not null

    union all

    select distinct
        dt as new_dt,
        luid,
        user_ukey,
        '回流' as label
    from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1
    where dt between '2026-06-12' and '2026-07-15'
      and user_ukey is not null
),

event_user_detail as (
    select distinct
        a.dt,
        a.game_id,
        a.game_name,
        a.match_name,
        b.user_ukey,
        b.label
    from copyright_info a
    inner join laxin_huiliu_user b
        on a.dt = b.new_dt
       and a.luid = b.luid
),

daily_user_cnt as (
    select
        dt,
        game_id,
        game_name,
        match_name,

        count(distinct case
            when label = '拉新' then user_ukey
        end) as daily_laxin_user_cnt,

        count(distinct case
            when label = '回流' then user_ukey
        end) as daily_huiliu_user_cnt,

        count(distinct user_ukey) as daily_total_user_cnt

    from event_user_detail
    group by
        dt,
        game_id,
        game_name,
        match_name
),

period_user_cnt as (
    select
        game_id,
        game_name,
        match_name,

        count(distinct case
            when label = '拉新' then user_ukey
        end) as laxin_user_cnt,

        count(distinct case
            when label = '回流' then user_ukey
        end) as huiliu_user_cnt,

        count(distinct user_ukey) as total_user_cnt

    from event_user_detail
    group by
        game_id,
        game_name,
        match_name
),

event_days as (
    select
        game_id,
        game_name,
        match_name,
        count(distinct dt) as event_day_cnt
    from copyright_info
    group by
        game_id,
        game_name,
        match_name
)

select
    e.game_id,
    e.game_name,
    e.match_name,

    e.event_day_cnt,

    p.laxin_user_cnt,
    p.huiliu_user_cnt,
    p.total_user_cnt,

    sum(coalesce(d.daily_laxin_user_cnt, 0)) * 1.0
        / e.event_day_cnt as avg_daily_laxin_user_cnt,

    sum(coalesce(d.daily_huiliu_user_cnt, 0)) * 1.0
        / e.event_day_cnt as avg_daily_huiliu_user_cnt,

    sum(coalesce(d.daily_total_user_cnt, 0)) * 1.0
        / e.event_day_cnt as avg_daily_total_user_cnt

from event_days e
left join daily_user_cnt d
    on e.game_id = d.game_id
   and e.game_name = d.game_name
   and e.match_name = d.match_name

left join period_user_cnt p
    on e.game_id = p.game_id
   and e.game_name = p.game_name
   and e.match_name = p.match_name

group by
    e.game_id,
    e.game_name,
    e.match_name,
    e.event_day_cnt,
    p.laxin_user_cnt,
    p.huiliu_user_cnt,
    p.total_user_cnt

order by
    e.game_id,
    e.match_name