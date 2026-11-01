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
    inner join (
        select distinct
            dt, stime, yyuid
        from gamelive.dwd_huya_event 
        where dt between '2026-06-26' and '2026-06-28'
          and cast(stime as timestamp) >= cast('2026-06-26 23:00:00' as timestamp)
          and cast(stime as timestamp) <= cast('2026-06-28 23:00:00' as timestamp)
          and eventid = 'click/jwk_activity_button'
          and product = 'huya_hd'
    ) t1
        on a.uid = t1.yyuid
       and a.time = t1.stime
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
    where a.time >= '2026-06-26 23:00:00'
      and a.time <= '2026-06-28 23:00:00'
      and b.dt between '2026-06-26' and '2026-06-28'
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
        end as game_label,
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
    select uid, watch_game_label
    from (
        select
            uid,
            game_label as watch_game_label,
            row_number() over (partition by uid order by user_duration desc) as rnk
        from user_duration_stat
        where game_label is not null
    ) t
    where rnk = 1
),

category_revenue_stat as (
    select
        t.user_uid as uid,
        case
            when t.game_id = 4079 then '交友'
            when t.game_id = 2165 then '户外'
            when t.game_id = 1663 then '星秀'
            when d.game_label = '游戏' then '游戏'
            else null
        end as game_label,
        sum(t.user_consume_amount) as pay_amount
    from gamelive.dws_huya_revenue_detail_d_i t
    left join (
        select
            game_id,
            max(game_label) as game_label
        from gamelive.dim_huya_game_d_a
        where dt >= '2026-01-01'
        group by game_id
    ) d
        on t.game_id = d.game_id
    where t.dt between '2026-06-15' and '2026-06-21'
      and t.user_consume_amount > 0
    group by
        t.user_uid,
        case
            when t.game_id = 4079 then '交友'
            when t.game_id = 2165 then '户外'
            when t.game_id = 1663 then '星秀'
            when d.game_label = '游戏' then '游戏'
            else null
        end
),

user_dashang_belongs as (
    select uid, pay_game_label
    from (
        select
            uid,
            game_label as pay_game_label,
            row_number() over (partition by uid order by pay_amount desc) as rnk
        from category_revenue_stat
        where game_label is not null
    ) t
    where rnk = 1
),

dashang_revenue as (
    select
        user_uid as uid,
        creator_uid,
        sum(case when dt between '2026-06-26' and '2026-06-28' then user_consume_amount else 0 end) as activity_user_consume_amount,
        sum(case when dt between '2026-06-15' and '2026-06-16' then user_consume_amount else 0 end) as shouhu1_user_consume_amount,
        sum(case when dt between '2026-06-06' and '2026-06-07' then user_consume_amount else 0 end) as shouhu2_user_consume_amount,
        sum(case when dt between '2026-05-08' and '2026-05-09' then user_consume_amount else 0 end) as shouhu3_user_consume_amount,
        sum(case when dt between '2026-04-15' and '2026-04-17' then user_consume_amount else 0 end) as shouhu4_user_consume_amount
    from gamelive.dws_huya_revenue_detail_d_i
    where dt between '2026-04-15' and '2026-06-28'
    group by user_uid, creator_uid
),

final_data as (
    select
        a.uid,
        a.creator_uid,
        a.game_label,
        b.watch_game_label,
        d.pay_game_label,
        case
            when a.game_label is not null and b.watch_game_label is null then 1
            when a.game_label is not null and b.watch_game_label is not null and a.game_label <> b.watch_game_label then 1
            else 0
        end as is_new_watch,
        case
            when d.pay_game_label is not null and c.pay_game_label is null then 1
            when d.pay_game_label is not null and c.pay_game_label is not null and d.pay_game_label <> c.pay_game_label then 1
            else 0
        end as is_new_pay,
        c.activity_user_consume_amount,
        c.shouhu1_user_consume_amount,
        c.shouhu2_user_consume_amount,
        c.shouhu3_user_consume_amount,
        c.shouhu4_user_consume_amount
    from activity_user_visit_info a
    left join user_game_belongs b
        on a.uid = b.uid
    left join user_dashang_belongs d
        on a.uid = d.uid
    left join dashang_revenue c
        on a.uid = c.uid
       and a.creator_uid = c.creator_uid
)

select
    game_label,
    count(distinct case when is_new_watch = 1 then uid end) as new_watch_uv,
    count(distinct case when is_new_watch = 0 then uid end) as old_watch_uv,
    count(distinct case when is_new_pay = 1 then uid end) as new_pay_uv,
    count(distinct case when is_new_pay = 0 then uid end) as old_pay_uv,
    sum(case when is_new_pay = 1 then activity_user_consume_amount else 0 end) as new_pay_activity_revenue,
    sum(case when is_new_pay = 0 then activity_user_consume_amount else 0 end) as old_pay_activity_revenue,
    sum(case when is_new_pay = 1 then shouhu1_user_consume_amount else 0 end) as new_watch_shouhu1_revenue,
    sum(case when is_new_pay = 1 then shouhu2_user_consume_amount else 0 end) as new_watch_shouhu2_revenue,
    sum(case when is_new_pay = 1 then shouhu3_user_consume_amount else 0 end) as new_watch_shouhu3_revenue,
    sum(case when is_new_pay = 1 then shouhu4_user_consume_amount else 0 end) as new_watch_shouhu4_revenue,
    sum(case when is_new_pay = 0 then shouhu1_user_consume_amount else 0 end) as old_watch_shouhu1_revenue,
    sum(case when is_new_pay = 0 then shouhu2_user_consume_amount else 0 end) as old_watch_shouhu2_revenue,
    sum(case when is_new_pay = 0 then shouhu3_user_consume_amount else 0 end) as old_watch_shouhu3_revenue,
    sum(case when is_new_pay = 0 then shouhu4_user_consume_amount else 0 end) as old_watch_shouhu4_revenue
from final_data
group by game_label
order by game_label