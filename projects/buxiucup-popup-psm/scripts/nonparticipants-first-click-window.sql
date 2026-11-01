with attend_user_info as (
    select
        uid,
        attend_dt,
        1 as is_attend
    from (
        select
            date_trunc('day', auto_updatetime) as attend_dt,
            uid,
            row_number() over (partition by uid order by auto_updatetime asc) as rnk
        from paimon.gamelive.t_ActUserSignIn_0_1753430895206
        where activityId = 1185
    ) t
    where rnk = 1
) --找到了参与了不朽杯弹窗的用户，并找出第一次点击时间

, not_attend_user_info as (
    select
        a.dt
        ,a.user_uid
        , 0 as is_attend
    from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i a
    left join attend_user_info b
        on a.user_uid = b.uid
        -- and a.dt = b.attend_dt
    where
        a.dt between '2026-05-11' and '2026-06-04'
        and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and is_black_ukey = 0
        and b.uid is null --用户从来没参与
    group by a.dt, a.user_uid
)

-- 找到对DOTA2感兴趣的人群（4月份观看DOTA2时长最长）
, is_interest_dota2 as (
    select
        user_yyuid,
        igameid
    from (
        select
            user_yyuid,
            igameid,
            total_duration,
            row_number() over (partition by user_yyuid order by total_duration desc) as rnk
        from (
            select
                user_yyuid,
                igameid,
                sum(user_duration) as total_duration
            from gamelive.dwt_huya_ayyuid_session_from_server_with_user
            where dt >= '2026-04-01' and dt <= '2026-04-30'
            and tag = 'gameid'
            and htime = 'session'
            and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios')
            group by user_yyuid, igameid
        ) t
    ) t2
    where rnk = 1 and igameid = 7 --DOTA2
)

-- =================== 对照组（未参与不朽杯弹窗） ===================
, not_attend_user_full_info as (
    select distinct
        a.user_uid,
        a.first_active_dt as pseudo_attend_dt,   -- 用户在活动期内第一次活跃的日期
        a.is_attend,
        case
            when b.user_yyuid is not null then 1
            when b.user_yyuid is null then 0
        end as is_interest_dota2
    from (
        select
            user_uid,
            min(dt) as first_active_dt,
            0 as is_attend
        from not_attend_user_info
        group by user_uid
    ) a
    left join is_interest_dota2 b
        on a.user_uid = b.user_yyuid
)

-- 观看前7天后7天聚合（对照组）
, not_attend_view_agg as (
    select
        a.user_uid,
        a.pseudo_attend_dt,
        case
            when datediff(cast(b.dt as date), cast(a.pseudo_attend_dt as date)) < 0 then 'pre'
            when datediff(cast(b.dt as date), cast(a.pseudo_attend_dt as date)) > 0 then 'post'
        end as period_flag,
        sum(b.user_duration) / 60000 as watch_duration_min,
        count(distinct b.dt) as view_day_cnt,
        count(distinct b.luid) as view_zhubo_num,
        count(distinct b.igameid) as view_game_num
    from not_attend_user_full_info a
    inner join gamelive.dwt_huya_ayyuid_session_from_server_with_user b
        on a.user_uid = b.user_yyuid
    where
        cast(b.dt as date) between date_sub(cast(a.pseudo_attend_dt as date), 7) and date_add(cast(a.pseudo_attend_dt as date), 7)
        and cast(b.dt as date) <> cast(a.pseudo_attend_dt as date)
        and b.tag = 'gameid'
        and b.htime = 'session'
        and b.user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios')
    group by
        a.user_uid,
        a.pseudo_attend_dt,
        case
            when datediff(cast(b.dt as date), cast(a.pseudo_attend_dt as date)) < 0 then 'pre'
            when datediff(cast(b.dt as date), cast(a.pseudo_attend_dt as date)) > 0 then 'post'
        end
)

-- 活跃前7天后7天聚合（对照组）
, not_attend_activity_agg as (
    select
        a.user_uid,
        a.pseudo_attend_dt,
        case
            when datediff(cast(b.dt as date), cast(a.pseudo_attend_dt as date)) < 0 then 'pre'
            when datediff(cast(b.dt as date), cast(a.pseudo_attend_dt as date)) > 0 then 'post'
        end as period_flag,
        count(distinct b.dt) as active_day_cnt
    from not_attend_user_full_info a
    inner join gamelive.dws_huya_active_product_ukey_info_withsdk_d_i b
        on a.user_uid = b.user_uid
    where
        cast(b.dt as date) between date_sub(cast(a.pseudo_attend_dt as date), 7) and date_add(cast(a.pseudo_attend_dt as date), 7)
        and cast(b.dt as date) <> cast(a.pseudo_attend_dt as date)
        and b.product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and b.is_black_ukey = 0
    group by
        a.user_uid,
        a.pseudo_attend_dt,
        case
            when datediff(cast(b.dt as date), cast(a.pseudo_attend_dt as date)) < 0 then 'pre'
            when datediff(cast(b.dt as date), cast(a.pseudo_attend_dt as date)) > 0 then 'post'
        end
)

-- 打赏前7天后7天聚合（对照组）
, not_attend_payment_agg as (
    select
        a.user_uid,
        a.pseudo_attend_dt,
        case
            when datedi ff(cast(b.dt as date), cast(a.pseudo_attend_dt as date)) < 0 then 'pre'
            when datediff(cast(b.dt as date), cast(a.pseudo_attend_dt as date)) > 0 then 'post'
        end as period_flag,
        sum(b.user_consume_amount) as user_consume_amount
    from not_attend_user_full_info a
    inner join gamelive.dws_huya_revenue_detail_d_i b
        on a.user_uid = b.user_uid
    where
        cast(b.dt as date) between date_sub(cast(a.pseudo_attend_dt as date), 7) and date_add(cast(a.pseudo_attend_dt as date), 7)
        and cast(b.dt as date) <> cast(a.pseudo_attend_dt as date)
        and b.user_consume_amount > 0
    group by
        a.user_uid,
        a.pseudo_attend_dt,
        case
            when datediff(cast(b.dt as date), cast(a.pseudo_attend_dt as date)) < 0 then 'pre'
            when datediff(cast(b.dt as date), cast(a.pseudo_attend_dt as date)) > 0 then 'post'
        end
)


select
    v.user_uid as uid,
    v.pseudo_attend_dt as attend_dt,
    a.is_attend,
    a.is_interest_dota2,
    v.period_flag,
    v.watch_duration_min,
    v.view_day_cnt,
    v.view_zhubo_num,
    v.view_game_num,
    coalesce(act.active_day_cnt, 0) as active_day_cnt,
    coalesce(pay.user_consume_amount, 0) as user_consume_amount
from not_attend_view_agg v
left join not_attend_activity_agg act
    on v.user_uid = act.user_uid
    and v.pseudo_attend_dt = act.pseudo_attend_dt
    and v.period_flag = act.period_flag
left join not_attend_payment_agg pay
    on v.user_uid = pay.user_uid
    and v.pseudo_attend_dt = pay.pseudo_attend_dt
    and v.period_flag = pay.period_flag
join not_attend_user_full_info a
    on v.user_uid = a.user_uid
    and v.pseudo_attend_dt = a.pseudo_attend_dt
