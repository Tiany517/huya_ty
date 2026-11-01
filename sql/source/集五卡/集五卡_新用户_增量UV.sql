with activity_user_visit_info as (
    select
        a.uid,
        b.creator_uid,
        case
            when b.game_id = 4079 then '交友'
            when b.game_id = 2165 then '户外'
            when b.game_id = 1663 then '星秀'
            when c.game_label = '游戏' then '游戏'
            else null
        end as game_label
    from zhgametemp.hss_collectcard_user_20260626_t0_20260628 a
    inner join gamelive.dws_huya_user_behavior_d_i b
        on b.creator_uid = a.pid
       and substr(a.time, 1, 10) = b.dt
       and a.uid = b.user_uid
    left join (
        select
            game_id,
            max(game_label) as game_label
        from gamelive.dim_huya_game_d_a
        where dt >= '2026-01-01'
        group by game_id
    ) c
        on b.game_id = c.game_id
    where b.dt between '2026-06-26' and '2026-06-28'
    group by
        a.uid,
        b.creator_uid,
        case
            when b.game_id = 4079 then '交友'
            when b.game_id = 2165 then '户外'
            when b.game_id = 1663 then '星秀'
            when c.game_label = '游戏' then '游戏'
            else null
        end
),

user_duration_stat as (
    select
        a.user_yyuid as uid,
        case
            when a.igameid = 4079 then '交友'
            when a.igameid = 2165 then '户外'
            when a.igameid = 1663 then '星秀'
            when b.game_label = '游戏' then '游戏'
            else null
        end as guiyin_type,
        sum(a.user_duration) as user_duration
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
    left join (
        select
            game_id,
            max(game_label) as game_label
        from gamelive.dim_huya_game_d_a
        where dt >= '2026-01-01'
        group by game_id
    ) b
        on a.igameid = b.game_id
    where a.dt between '2026-06-15' and '2026-06-21'
    group by
        a.user_yyuid,
        case
            when a.igameid = 4079 then '交友'
            when a.igameid = 2165 then '户外'
            when a.igameid = 1663 then '星秀'
            when b.game_label = '游戏' then '游戏'
            else null
        end
),

user_game_belongs as (
    select uid, guiyin_type
    from (
        select
            uid,
            guiyin_type,
            row_number() over (partition by uid order by user_duration desc) as rnk
        from user_duration_stat
    ) t
    where rnk = 1
),

dashang_revenue as (
    select
        user_uid as uid,
        creator_uid,
        sum(case when dt between '2026-06-26' and '2026-06-28' then user_consume_amount else 0 end) as activity_user_consume_amount,
        sum(case when dt between '2026-06-15' and '2026-06-16' then user_consume_amount else 0 end) as shouhu1_ser_consume_amount
    from gamelive.dws_huya_revenue_detail_d_i
    where dt between '2026-06-01' and '2026-06-28'
    group by user_uid, creator_uid
),

final_data as (
    select
        a.uid,
        a.creator_uid,
        a.game_label,
        b.guiyin_type,
        case
            when a.game_label is not null and b.guiyin_type is null then 1
            when a.game_label <> b.guiyin_type then 1
            else 0
        end as is_incremental,
        c.activity_user_consume_amount,
        c.shouhu1_ser_consume_amount
    from activity_user_visit_info a
    left join user_game_belongs b
        on a.uid = b.uid
    left join dashang_revenue c
        on a.uid = c.uid
       and a.creator_uid = c.creator_uid
)

select
    game_label,
    count(distinct case when is_incremental = 1 then uid end) as new_user_incremental_uv,
    sum(case when is_incremental = 1 then activity_user_consume_amount else 0 end) as new_user_incremental_revenue,
    count(distinct case when is_incremental = 0 then uid end) as old_user_uv,
    sum(case when is_incremental = 0 then activity_user_consume_amount else 0 end) as old_user_activity_revenue,
    sum(case when is_incremental = 0 then shouhu1_ser_consume_amount else 0 end) as old_user_shouhu1_revenue
from final_data
group by game_label;