-- 王者荣耀陪玩主播季度内跳动及王者荣耀礼物收入
-- 引擎：Spark SQL
-- 范围：2026Q3（2026-07-01 至 2026-09-30）及 2026Q4（2026-10-01 至最新分区 2026-11-18）。
-- 跳动：季度内同一主播同时出现陪玩日和非陪玩日。
-- 收入：剔刷单收入明细表，仅 consume_order_type='礼物'、game_id=2336、user_consume_amount>0。
with anchor_day as (
    -- 粒度：period_key + dt + luid；主播当日任意一场标题命中陪玩关键词即为陪玩日。
    select
        case
            when dt between '2026-07-01' and '2026-09-30' then '2026Q3'
            when dt between '2026-10-01' and '2026-11-18' then '2026Q4_partial_20261118'
        end as period_name,
        case
            when dt between '2026-07-01' and '2026-09-30' then 1
            when dt between '2026-10-01' and '2026-11-18' then 2
        end as period_order,
        dt,
        cast(luid as string) as luid,
        max(
            case
                when slivedesc like '%车位%'
                  or slivedesc like '%带粉%'
                  or slivedesc like '%车%'
                  or slivedesc like '%位置%'
                  or slivedesc like '%等单%'
                  or slivedesc like '%发车%'
                  or slivedesc like '%有位%'
                  or slivedesc like '%甜妹%'
                  or slivedesc like '%接号%'
                  or slivedesc like '%秒上%'
                  or slivedesc like '%有缘人%'
                  or slivedesc like '%包天%'
                  or slivedesc like '%打号%'
                  or slivedesc like '%黑色%'
                  or slivedesc like '%带飞%'
                  or slivedesc like '%电一%'
                  or slivedesc like '%网一%'
                  or slivedesc like '%黑玫%'
                  or slivedesc like '%老板%'
                  or slivedesc like '%上分%'
                  or slivedesc like '%无单%'
                  or slivedesc like '%滴滴%'
                  or slivedesc like '%软萌%'
                  or slivedesc like '%甜御%'
                  or slivedesc like '%下三%'
                  or slivedesc like '%养号%'
                  or slivedesc like '%全包%'
                  or slivedesc like '%接所有%'
                    then 1
                else 0
            end
        ) as is_peiwan_day
    from gamelive.dwt_huya_ayyuid_session_from_server_no_user
    where dt between '2026-07-01' and '2026-11-18'
      and length(dt) = 10
      and tag = 'gameid'
      and htime = 'session'
      and cast(igameid as string) = '2336'
      and luid is not null
      and trim(cast(luid as string)) not in ('', '0', '-1')
    group by
        case
            when dt between '2026-07-01' and '2026-09-30' then '2026Q3'
            when dt between '2026-10-01' and '2026-11-18' then '2026Q4_partial_20261118'
        end,
        case
            when dt between '2026-07-01' and '2026-09-30' then 1
            when dt between '2026-10-01' and '2026-11-18' then 2
        end,
        dt,
        cast(luid as string)
),
anchor_day_window as (
    -- 为季度内首次和最后开播日标记状态，用于判断首末净方向。
    select
        period_name,
        period_order,
        dt,
        luid,
        is_peiwan_day,
        row_number() over (
            partition by period_name, luid
            order by dt asc
        ) as first_day_rn,
        row_number() over (
            partition by period_name, luid
            order by dt desc
        ) as last_day_rn
    from anchor_day
),
anchor_period_state as (
    -- 粒度：period_name + luid；唯一键保证每个主播每个季度只有一条状态。
    select
        period_name,
        period_order,
        luid,
        count(*) as active_day_cnt,
        max(is_peiwan_day) as has_peiwan_day,
        max(case when is_peiwan_day = 0 then 1 else 0 end) as has_non_peiwan_day,
        max(case when first_day_rn = 1 then is_peiwan_day else 0 end) as first_day_status,
        max(case when last_day_rn = 1 then is_peiwan_day else 0 end) as last_day_status
    from anchor_day_window
    group by
        period_name,
        period_order,
        luid
),
gift_revenue_period as (
    -- 粒度：period_name + luid；仅王者荣耀直播间礼物收入，已使用剔刷单明细表。
    select
        case
            when dt between '2026-07-01' and '2026-09-30' then '2026Q3'
            when dt between '2026-10-01' and '2026-11-18' then '2026Q4_partial_20261118'
        end as period_name,
        cast(creator_uid as string) as luid,
        sum(cast(user_consume_amount as double)) as gift_revenue
    from zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i
    where dt between '2026-07-01' and '2026-11-18'
      and consume_order_type = '礼物'
      and cast(user_consume_amount as double) > 0
      and cast(game_id as string) = '2336'
      and creator_uid is not null
      and trim(cast(creator_uid as string)) not in ('', '0', '-1')
    group by
        case
            when dt between '2026-07-01' and '2026-09-30' then '2026Q3'
            when dt between '2026-10-01' and '2026-11-18' then '2026Q4_partial_20261118'
        end,
        cast(creator_uid as string)
),
gift_revenue_period_total as (
    -- 粒度：period_name；分母使用整个王者荣耀礼物收入，不限制在活跃主播集合内。
    select
        case
            when dt between '2026-07-01' and '2026-09-30' then '2026Q3'
            when dt between '2026-10-01' and '2026-11-18' then '2026Q4_partial_20261118'
        end as period_name,
        sum(cast(user_consume_amount as double)) as total_gift_revenue
    from zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i
    where dt between '2026-07-01' and '2026-11-18'
      and consume_order_type = '礼物'
      and cast(user_consume_amount as double) > 0
      and cast(game_id as string) = '2336'
      and creator_uid is not null
      and trim(cast(creator_uid as string)) not in ('', '0', '-1')
    group by
        case
            when dt between '2026-07-01' and '2026-09-30' then '2026Q3'
            when dt between '2026-10-01' and '2026-11-18' then '2026Q4_partial_20261118'
        end
),
anchor_period_metric as (
    -- 把季度活跃主播及其收入规整为 period_name + luid 一行；无礼物收入补 0。
    select
        s.period_name,
        s.period_order,
        s.luid,
        s.active_day_cnt,
        s.has_peiwan_day,
        s.has_non_peiwan_day,
        s.first_day_status,
        s.last_day_status,
        coalesce(r.gift_revenue, 0) as gift_revenue
    from anchor_period_state s
    left join gift_revenue_period r
      on s.period_name = r.period_name
     and s.luid = r.luid
),
anchor_period_summary as (
    -- 粒度：period_name；活跃主播、跳动人数和跳动主播收入。
    select
        period_name,
        period_order,
        count(*) as active_anchor_cnt,
        sum(
            case
                when has_peiwan_day = 1 and has_non_peiwan_day = 1 then 1
                else 0
            end
        ) as jump_anchor_cnt,
        sum(
            case
                when has_peiwan_day = 1 and has_non_peiwan_day = 1
                 and first_day_status = 1 and last_day_status = 0 then 1
                else 0
            end
        ) as peiwan_to_non_anchor_cnt,
        sum(
            case
                when has_peiwan_day = 1 and has_non_peiwan_day = 1
                 and first_day_status = 0 and last_day_status = 1 then 1
                else 0
            end
        ) as non_to_peiwan_anchor_cnt,
        sum(
            case
                when has_peiwan_day = 1 and has_non_peiwan_day = 1
                 and first_day_status = last_day_status then 1
                else 0
            end
        ) as round_trip_same_anchor_cnt,
        sum(
            case
                when has_peiwan_day = 1 and has_non_peiwan_day = 1 then gift_revenue
                else 0
            end
        ) as jump_anchor_gift_revenue
    from anchor_period_metric
    group by
        period_name,
        period_order
)
select
    s.period_name,
    s.active_anchor_cnt,
    s.jump_anchor_cnt,
    s.jump_anchor_cnt * 1.0 / nullif(s.active_anchor_cnt, 0) as jump_anchor_ratio,
    s.peiwan_to_non_anchor_cnt,
    s.non_to_peiwan_anchor_cnt,
    s.round_trip_same_anchor_cnt,
    round(t.total_gift_revenue, 2) as total_gift_revenue,
    round(s.jump_anchor_gift_revenue, 2) as jump_anchor_gift_revenue,
    s.jump_anchor_gift_revenue * 1.0
        / nullif(t.total_gift_revenue, 0) as jump_anchor_revenue_ratio
from anchor_period_summary s
left join gift_revenue_period_total t
  on s.period_name = t.period_name
order by
    s.period_order
