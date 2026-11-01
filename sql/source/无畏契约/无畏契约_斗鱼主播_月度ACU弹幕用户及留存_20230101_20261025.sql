-- 目的：计算无畏契约品类内斗鱼主播的月度经营与弹幕用户留存指标。
-- 数据源：
--   1. gamelive.dm_mkt_rowner_day：主播无畏契约开播日、有效 ACU。
--   2. gamelive.dwt_jingpin_danmulog_day：斗鱼普通弹幕明细和发送用户 ID。
-- 时间范围：2023-01-01 至最新可用分区 2026-10-25。
-- 粒度：主播 x 月，一行。
-- 主播范围：pcode = 'douyu' 且 r_category = '无畏契约'。
-- 弹幕范围：pcode = 'douyu'、r_category = '无畏契约'、msgtype = '0'。
-- 发送用户 ID：斗鱼使用 sender；sender 为空或空字符串的记录剔除。
-- 月日均 ACU：有效 ACU > 0 的开播日 ACU 算术平均，分母为 valid_acu_days。
-- 月日均弹幕用户数：先计算每个开播日的去重弹幕用户数，再除以该主播当月有效开播日数。
-- 月总弹幕用户数：当月该主播下至少发送一次普通弹幕的用户去重数。
-- 次月弹幕留存：当月用户中，下月仍在同一主播、同一无畏契约品类发送普通弹幕的用户占比。
--               只有次月日历完整时才输出留存率；次月不完整时保留观察人数但留存率置空。
-- D3/D7/D14：对每个自然日计算当天弹幕用户的 D3/D7/D14 精确日留存，再在月内按日等权平均。
--              同一用户必须在同一主播、同一无畏契约品类、目标日期再次发送普通弹幕。
-- 引擎：Presto。

with douyu_live_day as (
    select
        cast(dt as varchar) as dt,
        cast(r_lid as varchar) as anchor_id,
        max(cast(r_owner as varchar)) as r_owner,
        max(coalesce(try_cast(element_at(ext, 'vaild_acu') as double), 0.0)) as valid_acu,
        max(coalesce(try_cast(live_mins as double), 0.0)) as live_mins
    from gamelive.dm_mkt_rowner_day
    where dt between '2023-01-01' and '2026-10-25'
      and pcode = 'douyu'
      and r_category = '无畏契约'
    group by
        cast(dt as varchar),
        cast(r_lid as varchar)
    having max(coalesce(try_cast(live_mins as double), 0.0)) > 0
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

-- 只保留弹幕发送用户、主播和日期的去重组合，供所有用户指标复用。
danmu_user_day as (
    select
        cast(a.dt as varchar) as dt,
        cast(a.uid as varchar) as anchor_id,
        cast(a.sender as varchar) as danmu_user_id
    from gamelive.dwt_jingpin_danmulog_day a
    inner join douyu_live_day d
        on cast(a.dt as varchar) = d.dt
       and cast(a.uid as varchar) = d.anchor_id
    where a.dt between '2023-01-01' and '2026-10-25'
      and a.pcode = 'douyu'
      and a.r_category = '无畏契约'
      and cast(a.msgtype as varchar) = '0'
      and a.sender is not null
      and trim(cast(a.sender as varchar)) <> ''
    group by
        cast(a.dt as varchar),
        cast(a.uid as varchar),
        cast(a.sender as varchar)
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

-- 当月用户左连同一主播、同一用户的下月记录；未匹配到下月记录即视为未留存。
next_month_user_flag as (
    select
        c.month_key,
        c.anchor_id,
        c.danmu_user_id,
        case when n.danmu_user_id is not null then 1 else 0 end as is_retained
    from monthly_user c
    left join monthly_user n
        on c.anchor_id = n.anchor_id
       and c.danmu_user_id = n.danmu_user_id
       and n.month_key = substr(
           cast(
               date_add(
                   'month',
                   1,
                   cast(concat(c.month_key, '-01') as date)
               ) as varchar
           ),
           1,
           7
       )
),

next_month_retention as (
    select
        month_key,
        anchor_id,
        count(distinct danmu_user_id) as next_month_base_users,
        sum(is_retained) as next_month_observed_retained_users
    from next_month_user_flag
    group by
        month_key,
        anchor_id
),

-- 将同一主播、同一用户的历史发送日期压成一个数组，用于精确 D+3/D+7/D+14 判断。
user_date_history as (
    select
        anchor_id,
        danmu_user_id,
        array_agg(distinct dt) as send_dates
    from danmu_user_day
    group by
        anchor_id,
        danmu_user_id
),

retention_user_flag as (
    select
        a.anchor_id,
        a.dt,
        a.danmu_user_id,
        contains(
            h.send_dates,
            cast(date_add('day', 3, cast(a.dt as date)) as varchar)
        ) as is_d3_retained,
        contains(
            h.send_dates,
            cast(date_add('day', 7, cast(a.dt as date)) as varchar)
        ) as is_d7_retained,
        contains(
            h.send_dates,
            cast(date_add('day', 14, cast(a.dt as date)) as varchar)
        ) as is_d14_retained
    from danmu_user_day a
    inner join user_date_history h
        on a.anchor_id = h.anchor_id
       and a.danmu_user_id = h.danmu_user_id
),

daily_retention_cohort as (
    select
        anchor_id,
        dt,
        count(distinct danmu_user_id) as cohort_users,
        count(distinct if(is_d3_retained, danmu_user_id, null)) as d3_retained_users,
        count(distinct if(is_d7_retained, danmu_user_id, null)) as d7_retained_users,
        count(distinct if(is_d14_retained, danmu_user_id, null)) as d14_retained_users
    from retention_user_flag
    group by
        anchor_id,
        dt
),

monthly_daily_retention as (
    select
        substr(dt, 1, 7) as month_key,
        anchor_id,
        count(distinct if(
            cast(date_add('day', 3, cast(dt as date)) as varchar) <= '2026-10-25',
            dt,
            null
        )) as d3_cohort_days,
        count(distinct if(
            cast(date_add('day', 7, cast(dt as date)) as varchar) <= '2026-10-25',
            dt,
            null
        )) as d7_cohort_days,
        count(distinct if(
            cast(date_add('day', 14, cast(dt as date)) as varchar) <= '2026-10-25',
            dt,
            null
        )) as d14_cohort_days,
        avg(
            if(
                cast(date_add('day', 3, cast(dt as date)) as varchar) <= '2026-10-25'
                and cohort_users > 0,
                1.0 * d3_retained_users / cohort_users,
                null
            )
        ) as avg_d3_retention_rate,
        avg(
            if(
                cast(date_add('day', 7, cast(dt as date)) as varchar) <= '2026-10-25'
                and cohort_users > 0,
                1.0 * d7_retained_users / cohort_users,
                null
            )
        ) as avg_d7_retention_rate,
        avg(
            if(
                cast(date_add('day', 14, cast(dt as date)) as varchar) <= '2026-10-25'
                and cohort_users > 0,
                1.0 * d14_retained_users / cohort_users,
                null
            )
        ) as avg_d14_retention_rate
    from daily_retention_cohort
    group by
        substr(dt, 1, 7),
        anchor_id
)

select
    a.month_key as "月份",
    a.anchor_id as "斗鱼主播ID",
    a.anchor_name as "主播名称",
    a.live_days as "当月有效开播日数",
    a.valid_acu_days as "有效ACU天数",
    round(a.avg_daily_valid_acu, 2) as "月日均ACU",
    coalesce(
        round(
            1.0 * coalesce(u.monthly_daily_user_sum, 0) / nullif(a.live_days, 0),
            2
        ),
        0.0
    ) as "月日均弹幕用户数",
    coalesce(t.monthly_total_danmu_users, 0) as "月总弹幕用户数",
    case
        when cast(
            date_add(
                'day',
                -1,
                date_add(
                    'month',
                    2,
                    cast(concat(a.month_key, '-01') as date)
                )
            ) as varchar
        ) <= '2026-10-25'
            then 1
        else 0
    end as "次月是否完整",
    coalesce(n.next_month_base_users, 0) as "次月留存分母用户数",
    coalesce(n.next_month_observed_retained_users, 0) as "次月观察留存用户数",
    case
        when cast(
            date_add(
                'day',
                -1,
                date_add(
                    'month',
                    2,
                    cast(concat(a.month_key, '-01') as date)
                )
            ) as varchar
        ) <= '2026-10-25'
        and coalesce(n.next_month_base_users, 0) > 0
            then round(
                100.0 * n.next_month_observed_retained_users
                / n.next_month_base_users,
                2
            )
        else null
    end as "次月弹幕用户留存率_%",
    coalesce(r.d3_cohort_days, 0) as "D3有完整观察窗口天数",
    coalesce(r.d7_cohort_days, 0) as "D7有完整观察窗口天数",
    coalesce(r.d14_cohort_days, 0) as "D14有完整观察窗口天数",
    case
        when r.avg_d3_retention_rate is not null
            then round(100.0 * r.avg_d3_retention_rate, 2)
        else null
    end as "平均D3弹幕留存率_%",
    case
        when r.avg_d7_retention_rate is not null
            then round(100.0 * r.avg_d7_retention_rate, 2)
        else null
    end as "平均D7弹幕留存率_%",
    case
        when r.avg_d14_retention_rate is not null
            then round(100.0 * r.avg_d14_retention_rate, 2)
        else null
    end as "平均D14弹幕留存率_%"
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
left join monthly_daily_retention r
    on a.month_key = r.month_key
   and a.anchor_id = r.anchor_id
order by
    a.month_key,
    a.avg_daily_valid_acu desc nulls last,
    a.anchor_id;
