-- 目的：先产出斗鱼无畏契约主播的“主播月”互动与下一有效月留存明细，暂不分层、不计算中位数。
-- 数据源：
--   1. gamelive.dm_mkt_rowner_day：ACU、弹幕人数、弹幕次数、直播天数。
--   2. gamelive.dwt_jingpin_danmulog_day：弹幕发送用户，用于同主播留存。
-- 时间范围：2026-01-01 至 2026-09-30，排除尚未结束的 2026-10。
-- 粒度：斗鱼主播 x 月。
-- 平台与品类：pcode = 'douyu'、r_category = '无畏契约'。
-- 有效 ACU 日：ext['vaild_acu'] > 0。
-- 互动强度：avg(danmu_ucnt) / avg(vaild_acu)，两个字段均来自 dm_mkt_rowner_day，
--           并统一限定在有效 ACU 日，保证分子和分母使用同一批日期。
-- 注意：dm_mkt_rowner_day.live_mins 的底层来源是弹幕活跃分钟跨度 duration，
--      不是主播真实开播分钟数，因此不使用它判断有效开播或计算 ACU。
--      dm_mkt_rowner_day.danmu_ucnt 对斗鱼按去重发送者人数乘 0.68 后取整。
-- 互动样本等级（暂定标签，本 SQL 不据此删除任何主播月）：
--   高样本：有效 ACU 天数 >= 3 且日均弹幕人数 >= 30。
--   中样本：有效 ACU 天数 >= 2 且日均弹幕人数 >= 20。
--   其余为低样本。
-- 下一有效月：同一主播之后第一个“有效 ACU 天数 >= 3”的完整月份；跳过无效月份。
-- 下一有效月留存：当前月弹幕用户中，在该主播下一有效月继续发送普通弹幕的用户占比。
-- 留存样本等级（暂定标签，本 SQL 不据此删除任何主播月）：
--   高样本：下一有效月存在且有效 ACU 天数 >= 3，当前月留存分母 >= 30。
--   中样本：下一有效月存在且有效 ACU 天数 >= 2，当前月留存分母 >= 20。
--   其余为低样本。
-- 本 SQL 输出全部主播月及互动、留存两个独立样本等级，不据此删除数据。
-- 后续根据样本等级分布和候选数量调整门槛，再计算 ACU 分层和分层中位数。
-- 引擎：Spark SQL。

with douyu_anchor_day as (
    select
        cast(dt as string) as dt,
        cast(r_lid as string) as anchor_id,
        max(cast(r_owner as string)) as r_owner,
        max(coalesce(cast(element_at(ext, 'vaild_acu') as double), 0.0)) as valid_acu,
        max(coalesce(cast(danmu_ucnt as double), 0.0)) as danmu_ucnt,
        max(coalesce(cast(danmu_cnt as double), 0.0)) as danmu_cnt,
        max(coalesce(cast(live_mins as double), 0.0)) as chat_active_mins,
        max(coalesce(cast(hour_cnt as bigint), 0)) as observed_hours
    from gamelive.dm_mkt_rowner_day
    where dt between '2026-01-01' and '2026-09-30'
      and pcode = 'douyu'
      and r_category = '无畏契约'
    group by
        cast(dt as string),
        cast(r_lid as string)
),

-- 有效 ACU 日只保留 vaild_acu > 0，ACU 与弹幕人数统一使用这批日期。
douyu_valid_day as (
    select *
    from douyu_anchor_day
    where valid_acu > 0
),

-- 主播月基础指标。开播观测日数来自整张主播日表，互动指标来自有效 ACU 日。
anchor_month_base as (
    select
        substr(dt, 1, 7) as month_key,
        anchor_id,
        max_by(r_owner, dt) as anchor_name,
        count(distinct dt) as observed_days,
        count(distinct if(valid_acu > 0, dt, null)) as valid_acu_days,
        avg(if(valid_acu > 0, valid_acu, null)) as avg_daily_acu,
        avg(if(valid_acu > 0, danmu_ucnt, null)) as avg_daily_danmu_users,
        sum(danmu_cnt) as total_danmu_cnt
    from douyu_anchor_day
    group by
        substr(dt, 1, 7),
        anchor_id
    having count(distinct if(valid_acu > 0, dt, null)) > 0
),

anchor_month as (
    select
        *,
        avg_daily_danmu_users / nullif(avg_daily_acu, 0) as interaction_rate,
        cast(
            months_between(
                cast(concat(month_key, '-01') as date),
                date '2020-01-01'
            ) as int
        ) as month_index
    from anchor_month_base
),

-- 在当前月之后的所有月份中，寻找第一个有效 ACU 天数 >= 3 的月份。
-- first_value(ignoreNulls=true) 会跳过中间未达到有效标准的月份。
anchor_month_next as (
    select
        *,
        first_value(
            if(valid_acu_days >= 3, month_key, null),
            true
        ) over (
            partition by anchor_id
            order by month_index
            rows between 1 following and unbounded following
        ) as next_valid_month_key,
        first_value(
            if(valid_acu_days >= 3, month_index, null),
            true
        ) over (
            partition by anchor_id
            order by month_index
            rows between 1 following and unbounded following
        ) as next_valid_month_index,
        first_value(
            if(valid_acu_days >= 3, observed_days, null),
            true
        ) over (
            partition by anchor_id
            order by month_index
            rows between 1 following and unbounded following
        ) as next_valid_live_days,
        first_value(
            if(valid_acu_days >= 3, valid_acu_days, null),
            true
        ) over (
            partition by anchor_id
            order by month_index
            rows between 1 following and unbounded following
        ) as next_valid_acu_days,
        first_value(
            if(valid_acu_days >= 3, avg_daily_acu, null),
            true
        ) over (
            partition by anchor_id
            order by month_index
            rows between 1 following and unbounded following
        ) as next_valid_avg_daily_acu
    from anchor_month
),

-- 弹幕明细先压缩到主播-日-用户，避免大表重复。
danmu_user_day_raw as (
    select
        cast(a.dt as string) as dt,
        cast(a.uid as string) as anchor_id,
        cast(a.sender as string) as danmu_user_id
    from gamelive.dwt_jingpin_danmulog_day a
    where a.dt between '2026-01-01' and '2026-09-30'
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

-- 只保留主播日表中可观测到有效开播的日期，保证留存和互动样本一致。
danmu_user_day as (
    select
        a.dt,
        a.anchor_id,
        a.danmu_user_id
    from danmu_user_day_raw a
    inner join douyu_valid_day d
        on a.dt = d.dt
       and a.anchor_id = d.anchor_id
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

-- 当前月用户与“下一有效月”组合，左关联下一有效月的同主播用户。
retention_user_flag as (
    select
        a.month_key as current_month_key,
        a.anchor_id,
        a.next_valid_month_key,
        a.next_valid_month_index - a.month_index as retention_gap_months,
        c.danmu_user_id,
        if(n.danmu_user_id is not null, 1, 0) as is_retained
    from anchor_month_next a
    left join monthly_user c
        on a.month_key = c.month_key
       and a.anchor_id = c.anchor_id
    left join monthly_user n
        on a.anchor_id = n.anchor_id
       and a.next_valid_month_key = n.month_key
       and c.danmu_user_id = n.danmu_user_id
),

retention_metric as (
    select
        current_month_key as month_key,
        anchor_id,
        count(distinct danmu_user_id) as retention_base_users,
        sum(is_retained) as next_valid_month_retained_users
    from retention_user_flag
    group by
        current_month_key,
        anchor_id
),

-- 主播月明细基础层：保留互动指标、下一有效月、留存分子分母及样本等级。
monthly_detail_base as (
    select
        a.month_key,
        a.anchor_id,
        a.anchor_name,
        a.observed_days as `当月观测开播日数`,
        a.valid_acu_days as `有效ACU天数`,
        round(a.avg_daily_acu, 2) as `月日均ACU`,
        round(a.avg_daily_danmu_users, 2) as `月日均弹幕人数`,
        round(a.interaction_rate, 4) as `互动强度`,
        a.total_danmu_cnt as `月弹幕次数`,

        case
            when a.valid_acu_days >= 3
             and a.avg_daily_danmu_users >= 30
                then '高样本'
            when a.valid_acu_days >= 2
             and a.avg_daily_danmu_users >= 20
                then '中样本'
            else '低样本'
        end as interaction_sample_grade,

        a.next_valid_month_key as `下一有效月`,
        a.next_valid_month_index - a.month_index as `留存间隔月数`,
        a.next_valid_live_days as `下一有效月观测开播日数`,
        a.next_valid_acu_days as `下一有效月有效ACU天数`,
        round(a.next_valid_avg_daily_acu, 2) as `下一有效月日均ACU`,

        coalesce(r.retention_base_users, 0) as `当前月留存分母用户数`,
        coalesce(r.next_valid_month_retained_users, 0) as `下一有效月观察留存用户数`,

        case
            when a.next_valid_month_key is null then null
            when coalesce(r.retention_base_users, 0) <= 0 then null
            else
                round(
                    1.0 * r.next_valid_month_retained_users
                    / r.retention_base_users,
                    4
                )
        end as `下一有效月留存率`,

        case
            when a.next_valid_month_key is not null
             and a.next_valid_acu_days >= 3
             and coalesce(r.retention_base_users, 0) >= 30
                then '高样本'
            when a.next_valid_month_key is not null
             and a.next_valid_acu_days >= 2
             and coalesce(r.retention_base_users, 0) >= 20
                then '中样本'
            else '低样本'
        end as retention_sample_grade,

        case
            when a.next_valid_month_key is null then null
            when a.next_valid_month_index - a.month_index = 1 then 1
            else 0
        end
            as is_natural_next_month
    from anchor_month_next a
    left join retention_metric r
        on a.month_key = r.month_key
       and a.anchor_id = r.anchor_id
)

select
    d.month_key as `月份`,
    d.anchor_id as `斗鱼主播ID`,
    d.anchor_name as `主播名称`,
    d.`当月观测开播日数`,
    d.`有效ACU天数`,
    d.`月日均ACU`,
    d.`月日均弹幕人数`,
    d.`互动强度`,
    d.`月弹幕次数`,
    d.interaction_sample_grade as `互动样本等级`,
    d.`下一有效月`,
    d.`留存间隔月数`,
    d.`下一有效月观测开播日数`,
    d.`下一有效月有效ACU天数`,
    d.`下一有效月日均ACU`,
    d.`当前月留存分母用户数`,
    d.`下一有效月观察留存用户数`,
    d.`下一有效月留存率`,
    d.retention_sample_grade as `留存样本等级`,
    d.is_natural_next_month as `是否自然次月`
from monthly_detail_base d
order by
    d.anchor_id,
    d.month_key;
