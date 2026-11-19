-- 独立复算：季度内直接统计活跃日数和陪玩日数，不复用正式 SQL 的首末日窗口。
with anchor_period_day as (
    select
        case
            when dt between '2026-07-01' and '2026-09-30' then '2026Q3'
            when dt between '2026-10-01' and '2026-11-18' then '2026Q4_partial_20261118'
        end as period_name,
        cast(luid as string) as luid,
        count(distinct dt) as active_day_cnt,
        count(
            distinct case
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
                    then dt
            end
        ) as peiwan_day_cnt
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
        cast(luid as string)
),
gift_revenue_period as (
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
gift_revenue_total as (
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
anchor_period_with_revenue as (
    select
        a.period_name,
        a.luid,
        a.active_day_cnt,
        a.peiwan_day_cnt,
        coalesce(r.gift_revenue, 0) as gift_revenue,
        case
            when a.peiwan_day_cnt > 0 and a.peiwan_day_cnt < a.active_day_cnt then 1
            else 0
        end as is_jump
    from anchor_period_day a
    left join gift_revenue_period r
      on a.period_name = r.period_name
     and a.luid = r.luid
),
anchor_period_summary as (
    select
        period_name,
        count(*) as active_anchor_cnt,
        sum(is_jump) as jump_anchor_cnt,
        sum(case when is_jump = 1 then gift_revenue else 0 end) as jump_anchor_gift_revenue
    from anchor_period_with_revenue
    group by
        period_name
)
select
    s.period_name,
    s.active_anchor_cnt,
    s.jump_anchor_cnt,
    s.jump_anchor_cnt * 1.0 / nullif(s.active_anchor_cnt, 0) as jump_anchor_ratio,
    round(t.total_gift_revenue, 2) as total_gift_revenue,
    round(s.jump_anchor_gift_revenue, 2) as jump_anchor_gift_revenue,
    s.jump_anchor_gift_revenue * 1.0
        / nullif(t.total_gift_revenue, 0) as jump_anchor_revenue_ratio
from anchor_period_summary s
left join gift_revenue_total t
  on s.period_name = t.period_name
order by s.period_name
