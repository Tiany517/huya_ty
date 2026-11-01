with zhubo_info as (
    select
        dt,
        ayyuid as luid,
        nickname,
        sum(live_hours_only_live) as live_hours_only_live
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2025-01-01' and '2026-05-31'
      and gameid in (393) --炉石传说
    group by dt, ayyuid,nickname
),

dashang_agg as (
    select
        dt,
        ukey,
        creator_uid as luid,
        sum(consume_amt) as total_consume_amt
    from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2
    where dt between '2025-01-01' and '2026-05-31'
    group by dt,ukey, creator_uid
),


-- 按月+主播：开播指标
monthly_host as (
    select
        month,
        luid,
        nickname,
        sum(live_hours_only_live) as total_live_hours,
        sum(if(live_hours_only_live > 2, 1, 0)) as valid_days,
        dayofmonth(last_day(to_date(concat(month, '-01')))) as days_in_month
    from (
        select
            substr(dt, 1, 7) as month,
            luid,
            nickname,
            live_hours_only_live
        from zhubo_info
    ) t
    group by month, luid,nickname
),

-- 按月：有效开播主播数（两个口径）
effective_hosts as (
    select
        month,
        -- 口径1：月日均开播>2h的主播数
        count(distinct case when total_live_hours / days_in_month > 2 then luid end) as valid_host_daily_avg_gt2h,
        -- 口径2：月有效开播天数>=10的主播数
        count(distinct case when valid_days >= 10 then luid end) as valid_host_10days
    from monthly_host
    group by month
),


-- 按月+主播：营收、付费用户数
monthly_revenue as (
    select
        substr(a.dt, 1, 7) as month,
        a.luid,
        a.nickname,
        sum(b.total_consume_amt) as revenue,
        count(distinct b.ukey) as pay_users
    from zhubo_info a
    left join dashang_agg b
      on a.dt = b.dt and a.luid = b.luid
    group by substr(a.dt, 1, 7), a.luid, a.nickname
),

-- 按月+主播：总观看UV（月度去重）
monthly_uv as (
    select
        substr(dt, 1, 7) as month,
        luid,
        count(distinct ukey) as monthly_uv
    from zhgametemp.cwq_huya_ayyuid_session_from_server_with_user_heichan_pachong_v1 --用户观看表（更快速）
    where dt between '2025-01-01' and '2026-05-31'
      and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios')
      and heichan_lable = 'not_heichan'
      and pachong_lable = 'not_pachong'
    group by substr(dt, 1, 7), luid
)


-- 主查询：每个主播的月度指标 + 当月有效主播数（全局）
select
    mr.month,
    mr.luid,
    mr.nickname,
    mr.revenue,
    mr.pay_users,
    muv.monthly_uv,
    eh.valid_host_daily_avg_gt2h,
    eh.valid_host_10days
from monthly_revenue mr
left join monthly_uv muv
  on mr.month = muv.month and mr.luid = muv.luid
left join effective_hosts eh
  on mr.month = eh.month
order by mr.month, mr.luid