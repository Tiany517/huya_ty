with wx_anchor_day as (
    select
        a.dt,
        substr(a.dt, 1, 7) as month,
        b.creator_uid as luid,
        a.userid,
        sum(cast(a.audiencecnt as bigint)) as dau
    from gamelive.dwd_spider_wxmcn_anchor_livedata_list_d_i a
    left join (
        select
            pid as creator_uid,
            vx_vedio_id
        from gamelive.ods_live_huya_vedio_stream_push_conf_1760614652931321858
        where dt = date_format(
            date_add('day', -1, current_date),
            '%Y-%m-%d'
        )
        group by
            pid,
            vx_vedio_id
    ) b
        on a.userid = b.vx_vedio_id
    where a.dt >= '2026-06-01'
      and a.dt <= '2026-08-18'
      and cast(a.onlinetimeduration as double) > 0
      and b.creator_uid is not null
    group by
        a.dt,
        substr(a.dt, 1, 7),
        b.creator_uid,
        a.userid
),

huya_anchor_day as (
    select
        dt,
        luid,
        sum(cast(online_duration as double) / 1000 / 3600) as online_duration_huya
    from gamelive.dwt_huya_ayyuid_session_from_server_no_user
    where dt >= '2015-06-01'
      and dt <= '2026-08-18'
      and length(dt) = 10
      and tag = 'gameid'
      and htime = 'session'
    group by
        dt,
        luid
),

game_dim as (
    select
        game_id,
        max(game_name) as game_name
    from gamelive.dim_huya_game_d_a
    where dt <= '2026-08-18'
    group by
        game_id
),

anchor_2025_game_duration as (
    -- 2025年主播按游戏品类聚合虎牙直播时长，单位：小时
    select
        luid,
        igameid,
        max(sgamename) as sgamename,
        sum(cast(online_duration as double) / 1000 / 3600) as online_duration_2025
    from gamelive.dwt_huya_ayyuid_session_from_server_no_user
    where dt >= '2025-01-01'
      and dt <= '2026-12-31'
      and length(dt) = 10
      and tag = 'gameid'
      and htime = 'session'
      and luid is not null
      and igameid is not null
    group by
        luid,
        igameid
),

anchor_belong_game as (
    -- 每个主播取2025年直播时长最长的游戏，作为归属品类
    select
        t.luid,
        t.igameid as belong_game_id,
        coalesce(g.game_name, t.sgamename, '未知') as belong_game_name
    from (
        select
            luid,
            igameid,
            sgamename,
            online_duration_2025,
            row_number() over (
                partition by luid
                order by online_duration_2025 desc, igameid
            ) as rn
        from anchor_2025_game_duration
    ) t
    left join game_dim g
        on t.igameid = g.game_id
    where t.rn = 1
),

anchor_nickname as (
    select
        uid as luid,
        max(nick) as nickname
    from gamelive.dim_huya_ayyuid_info
    where dt <= '2026-08-18'
    group by
        uid
)

select
    a.month,
    case
        when coalesce(c.online_duration_huya, 0) > 0
            then '双播'
        else '单播'
    end as luid_type,
    a.luid,
    n.nickname,
    g.belong_game_name as belong_game_name,
    sum(a.dau) as dau,
    sum(a.dau) * 0.26 as dau_youxiao,
    count(distinct a.dt) as live_days
from wx_anchor_day a
left join huya_anchor_day c
    on a.dt = c.dt
   and a.luid = c.luid
left join anchor_nickname n
    on a.luid = n.luid
left join anchor_belong_game g
    on a.luid = g.luid
group by
    a.month,
    case
        when coalesce(c.online_duration_huya, 0) > 0
            then '双播'
        else '单播'
    end,
    a.luid,
    n.nickname,
    g.belong_game_name
order by
    a.month,
    luid_type,
    a.luid