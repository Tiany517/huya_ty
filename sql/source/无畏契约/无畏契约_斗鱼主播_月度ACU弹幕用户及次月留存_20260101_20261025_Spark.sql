-- 目的：计算无畏契约品类内斗鱼主播的月度 ACU、弹幕用户和次月弹幕留存。
-- 数据源：gamelive.dm_mkt_rowner_day、gamelive.dwt_jingpin_danmulog_day。
-- 时间范围：2026-01-01 至最新可用分区 2026-10-25。
-- 粒度：斗鱼主播 x 月。
-- 主播与弹幕均限定：pcode = 'douyu'、r_category = '无畏契约'。
-- 弹幕口径：msgtype = '0'，即普通文字弹幕；斗鱼发送用户 ID 使用 sender。
-- 月日均 ACU：有效 ACU > 0 的开播日 ACU 算术平均。
-- 月日均弹幕用户数：当月每日去重弹幕用户数之和 / 当月有效开播日数。
-- 月总弹幕用户数：当月同一主播下去重弹幕用户数。
-- 互动率：月日均弹幕用户数 / 月日均 ACU，使用普通小数；两者统计单位不同，仅作为粗略互动强度指标。
-- 次月留存率：当月弹幕用户中，下月在“同一主播、同一无畏契约品类”再次发送弹幕的用户占比，使用普通小数。
-- 次月不完整时不输出留存率，避免把 2026-10 这类未结束月份误判为低留存。
-- 引擎：Spark SQL。

with douyu_live_day as (
    select
        cast(dt as string) as dt,
        cast(r_lid as string) as anchor_id,
        max(cast(r_owner as string)) as r_owner,
        max(coalesce(cast(element_at(ext, 'vaild_acu') as double), 0.0)) as valid_acu,
        max(coalesce(cast(live_mins as double), 0.0)) as live_mins
    from gamelive.dm_mkt_rowner_day
    where dt between '2026-01-01' and '2026-10-25'
      and pcode = 'douyu'
      and r_category = '无畏契约'
    group by
        cast(dt as string),
        cast(r_lid as string)
    having max(coalesce(cast(live_mins as double), 0.0)) > 0
),

anchor_month as (
    select
        substr(dt, 1, 7) as month_key,
        anchor_id,
        max_by(r_owner, dt) as anchor_name,
        count(distinct dt) as live_days,
        count(distinct if(valid_acu > 0, dt, null)) as valid_acu_days,
        avg(if(valid_acu > 0, valid_acu, null)) as avg_daily_valid_acu
    from douyu_live_day
    group by
        substr(dt, 1, 7),
        anchor_id
),

-- 先把弹幕明细压缩到主播-日-用户粒度，降低后续与主播开播日关联的数据量。
danmu_user_day_raw as (
    select
        cast(a.dt as string) as dt,
        cast(a.uid as string) as anchor_id,
        cast(a.sender as string) as danmu_user_id
    from gamelive.dwt_jingpin_danmulog_day a
    where a.dt between '2026-01-01' and '2026-10-25'
      and a.pcode = 'douyu'
      and a.r_category = '无畏契约'
      and cast(a.msgtype as string) = '0'
      and a.sender is not null
      and trim(cast(a.sender as string)) <> ''
    group by
        cast(a.dt as string),
        cast(a.uid as string),
        cast(a.sender as string)
),

-- 只保留 dm_mkt_rowner_day 中同日、同主播可观测到有效开播的记录，
-- 保证 ACU、日均弹幕用户数、月总弹幕用户和留存使用一致的开播日样本。
danmu_user_day as (
    select
        a.dt,
        a.anchor_id,
        a.danmu_user_id
    from danmu_user_day_raw a
    inner join douyu_live_day d
        on a.dt = d.dt
       and a.anchor_id = d.anchor_id
),

daily_danmu_users as (
    select
        dt,
        anchor_id,
        count(distinct danmu_user_id) as daily_danmu_users
    from danmu_user_day
    group by
        dt,
        anchor_id
),

monthly_daily_user_sum as (
    select
        substr(dt, 1, 7) as month_key,
        anchor_id,
        sum(daily_danmu_users) as monthly_daily_user_sum
    from daily_danmu_users
    group by
        substr(dt, 1, 7),
        anchor_id
),

monthly_user as (
    select
        substr(dt, 1, 7) as month_key,
        anchor_id,
        danmu_user_id
    from danmu_user_day
    group by
        substr(dt, 1, 7),
        anchor_id,
        danmu_user_id
),

monthly_user_total as (
    select
        month_key,
        anchor_id,
        count(distinct danmu_user_id) as monthly_total_danmu_users
    from monthly_user
    group by
        month_key,
        anchor_id
),

-- 用用户在“同一主播”下的下一条月度弹幕记录判断次月是否连续留存，避免大表自关联。
monthly_user_history as (
    select
        month_key,
        anchor_id,
        danmu_user_id,
        cast(
            months_between(
                cast(concat(month_key, '-01') as date),
                date '2020-01-01'
            ) as int
        ) as month_index,
        lead(
            cast(
                months_between(
                    cast(concat(month_key, '-01') as date),
                    date '2020-01-01'
                ) as int
            )
        ) over (
            partition by anchor_id, danmu_user_id
            order by month_key
        ) as next_active_month_index
    from monthly_user
),

next_month_retention as (
    select
        month_key,
        anchor_id,
        count(distinct danmu_user_id) as next_month_base_users,
        sum(
            if(next_active_month_index = month_index + 1, 1, 0)
        ) as next_month_observed_retained_users
    from monthly_user_history
    group by
        month_key,
        anchor_id
)

select
    a.month_key as `月份`,
    a.anchor_id as `斗鱼主播ID`,
    a.anchor_name as `主播名称`,
    a.live_days as `当月有效开播日数`,
    a.valid_acu_days as `有效ACU天数`,
    round(a.avg_daily_valid_acu, 2) as `月日均ACU`,
    coalesce(
        round(
            1.0 * coalesce(u.monthly_daily_user_sum, 0) / nullif(a.live_days, 0),
            2
        ),
        0.0
    ) as `月日均弹幕用户数`,
    case
        when a.avg_daily_valid_acu > 0
            then round(
                (
                    1.0 * coalesce(u.monthly_daily_user_sum, 0)
                    / nullif(a.live_days, 0)
                )
                / a.avg_daily_valid_acu,
                4
            )
        else null
    end as `互动率`,
    coalesce(t.monthly_total_danmu_users, 0) as `月总弹幕用户数`,
    case
        when cast(
            date_sub(
                add_months(
                    cast(concat(a.month_key, '-01') as date),
                    2
                ),
                1
            ) as string
        ) <= '2026-10-25'
            then 1
        else 0
    end as `次月是否完整`,
    coalesce(n.next_month_base_users, 0) as `次月留存分母用户数`,
    coalesce(n.next_month_observed_retained_users, 0) as `次月观察留存用户数`,
    case
        when cast(
            date_sub(
                add_months(
                    cast(concat(a.month_key, '-01') as date),
                    2
                ),
                1
            ) as string
        ) <= '2026-10-25'
        and coalesce(n.next_month_base_users, 0) > 0
            then round(
                1.0 * n.next_month_observed_retained_users
                / n.next_month_base_users,
                4
            )
        else null
    end as `次月弹幕用户留存率`
from anchor_month a
left join monthly_daily_user_sum u
    on a.month_key = u.month_key
   and a.anchor_id = u.anchor_id
left join monthly_user_total t
    on a.month_key = t.month_key
   and a.anchor_id = t.anchor_id
left join next_month_retention n
    on a.month_key = n.month_key
   and a.anchor_id = n.anchor_id
order by
    a.month_key,
    a.avg_daily_valid_acu desc nulls last,
    a.anchor_id;
