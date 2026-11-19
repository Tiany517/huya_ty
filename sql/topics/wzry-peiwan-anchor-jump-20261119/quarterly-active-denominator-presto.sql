-- 王者荣耀陪玩主播季度跳动：整体活跃主播口径。
-- 引擎：Presto。
-- 范围：2026Q3 全季度；2026Q4 截至最新分区 2026-11-18。
-- 收入：王者荣耀 game_id=2336 的全部用户消费金额，不限制 consume_order_type。
with anchor_day as (
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
        cast(luid as varchar) as luid,
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
      and cast(igameid as varchar) = '2336'
      and luid is not null
      and trim(cast(luid as varchar)) not in ('', '0', '-1')
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
        cast(luid as varchar)
),
anchor_period_state as (
    select
        period_name,
        period_order,
        luid,
        max(is_peiwan_day) as has_peiwan_day,
        max(case when is_peiwan_day = 0 then 1 else 0 end) as has_non_peiwan_day
    from anchor_day
    group by
        period_name,
        period_order,
        luid
),
revenue_by_anchor as (
    select
        case
            when dt between '2026-07-01' and '2026-09-30' then '2026Q3'
            when dt between '2026-10-01' and '2026-11-18' then '2026Q4_partial_20261118'
        end as period_name,
        cast(creator_uid as varchar) as luid,
        sum(cast(user_consume_amount as double)) as consume_amt
    from zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i
    where dt between '2026-07-01' and '2026-11-18'
      and cast(game_id as varchar) = '2336'
      and cast(user_consume_amount as double) > 0
      and creator_uid is not null
      and trim(cast(creator_uid as varchar)) not in ('', '0', '-1')
    group by
        case
            when dt between '2026-07-01' and '2026-09-30' then '2026Q3'
            when dt between '2026-10-01' and '2026-11-18' then '2026Q4_partial_20261118'
        end,
        cast(creator_uid as varchar)
),
anchor_period_metric as (
    select
        s.period_name,
        s.period_order,
        s.luid,
        s.has_peiwan_day,
        s.has_non_peiwan_day,
        coalesce(r.consume_amt, 0) as consume_amt
    from anchor_period_state s
    left join revenue_by_anchor r
      on s.period_name = r.period_name
     and s.luid = r.luid
),
period_summary as (
    select
        period_name,
        period_order,
        count(*) as active_anchor_cnt,
        sum(case when has_peiwan_day = 1 then 1 else 0 end) as peiwan_anchor_cnt,
        sum(
            case
                when has_peiwan_day = 1 and has_non_peiwan_day = 1 then 1
                else 0
            end
        ) as jump_anchor_cnt,
        sum(case when has_peiwan_day = 1 then consume_amt else 0 end) as peiwan_anchor_consume_amt,
        sum(
            case
                when has_peiwan_day = 1 and has_non_peiwan_day = 1 then consume_amt
                else 0
            end
        ) as jump_anchor_consume_amt
    from anchor_period_metric
    group by
        period_name,
        period_order
),
period_revenue as (
    select
        period_name,
        sum(consume_amt) as total_consume_amt
    from revenue_by_anchor
    group by
        period_name
)
select
    s.period_name,
    s.active_anchor_cnt,
    s.peiwan_anchor_cnt,
    s.jump_anchor_cnt,
    s.peiwan_anchor_cnt * 1.0 / nullif(s.active_anchor_cnt, 0) as peiwan_anchor_ratio,
    s.jump_anchor_cnt * 1.0 / nullif(s.active_anchor_cnt, 0) as jump_anchor_active_ratio,
    s.jump_anchor_cnt * 1.0 / nullif(s.peiwan_anchor_cnt, 0) as jump_anchor_peiwan_ratio,
    round(t.total_consume_amt, 2) as total_consume_amt,
    round(s.peiwan_anchor_consume_amt, 2) as peiwan_anchor_consume_amt,
    round(s.jump_anchor_consume_amt, 2) as jump_anchor_consume_amt,
    s.peiwan_anchor_consume_amt * 1.0
        / nullif(t.total_consume_amt, 0) as peiwan_anchor_revenue_ratio,
    s.jump_anchor_consume_amt * 1.0
        / nullif(t.total_consume_amt, 0) as jump_anchor_revenue_ratio,
    s.jump_anchor_consume_amt * 1.0
        / nullif(s.peiwan_anchor_consume_amt, 0) as jump_anchor_peiwan_revenue_ratio
from period_summary s
left join period_revenue t
  on s.period_name = t.period_name
order by
    s.period_order
