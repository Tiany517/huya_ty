-- 目的：先产出斗鱼无畏契约主播的“主播月”互动与下一有效月留存明细，暂不分层、不计算中位数。
-- 数据源：
--   1. gamelive.dm_mkt_rowner_day：ACU、弹幕人数、弹幕次数、直播天数。
--   2. gamelive.dwt_jingpin_danmulog_day：弹幕发送用户，用于同主播留存。
-- 时间范围：2026-01-01 至 2026-09-30，排除尚未结束的 2026-10。
-- 粒度：斗鱼主播 x 月。
-- 平台与品类：pcode = 'douyu'、r_category = '无畏契约'。
-- 互动强度：avg(danmu_ucnt) / avg(vaild_acu)，两个字段均来自 dm_mkt_rowner_day。
-- 互动可评估月：有效 ACU 天数 >= 3，且日均弹幕人数 >= 30。
-- 下一有效月：同一主播之后第一个“有效 ACU 天数 >= 3”的完整月份；跳过无效月份。
-- 下一有效月留存：当前月弹幕用户中，在该主播下一有效月继续发送普通弹幕的用户占比。
-- 留存可评估月：当前月弹幕用户 >= 30，且下一有效月存在并满足有效 ACU 天数 >= 3。
-- 本 SQL 不直接筛选最终主播，而是输出主播月明细及主播级可评估月数；
-- 后续应先基于完整可评估月明细计算 ACU 分层中位数，再应用“互动可评估月 >= 3、留存可评估月 >= 4”。
-- 本 SQL 不计算 ACU 分层和分层中位数，留给后续分析。
-- 引擎：Spark SQL。

with douyu_live_day as (
    select
        cast(dt as string) as dt,
        cast(r_lid as string) as anchor_id,
        max(cast(r_owner as string)) as r_owner,
        max(coalesce(cast(element_at(ext, 'vaild_acu') as double), 0.0)) as valid_acu,
        max(coalesce(cast(danmu_ucnt as double), 0.0)) as danmu_ucnt,
        max(coalesce(cast(danmu_cnt as double), 0.0)) as danmu_cnt,
        max(coalesce(cast(live_mins as double), 0.0)) as live_mins
    from gamelive.dm_mkt_rowner_day
    where dt between '2026-01-01' and '2026-09-30'
      and pcode = 'douyu'
      and r_category = '无畏契约'
    group by
        cast(dt as string),
        cast(r_lid as string)
    having max(coalesce(cast(live_mins as double), 0.0)) > 0
),

-- 主播月基础指标。互动人数与 ACU 都来自同一张主播日表。
anchor_month_base as (
    select
        substr(dt, 1, 7) as month_key,
        anchor_id,
        max_by(r_owner, dt) as anchor_name,
        count(distinct dt) as live_days,
        count(distinct if(valid_acu > 0, dt, null)) as valid_acu_days,
        avg(if(valid_acu > 0, valid_acu, null)) as avg_daily_acu,
        avg(if(valid_acu > 0, danmu_ucnt, null)) as avg_daily_danmu_users,
        sum(if(valid_acu > 0, danmu_cnt, 0.0)) as total_danmu_cnt
    from douyu_live_day
    group by
        substr(dt, 1, 7),
        anchor_id
),

anchor_month as (
    select
        *,
        avg_daily_danmu_users / nullif(avg_daily_acu, 0) as interaction_rate,
        if(
            valid_acu_days >= 3
            and avg_daily_danmu_users >= 30,
            1,
            0
        ) as interaction_evaluable,
        cast(
            months_between(
                cast(concat(month_key, '-01') as date),
                date '2020-01-01'
            ) as int
        ) as month_index
    from anchor_month_base
),

-- 只有有效 ACU 天数 >= 3 的月份才参与“下一有效月”序列。
-- lead 会跳过中间未达到有效标准的月份，直接取下一个有效开播月。
anchor_month_next as (
    select
        *,
        lead(month_key) over (
            partition by anchor_id
            order by month_index
        ) as next_valid_month_key,
        lead(month_index) over (
            partition by anchor_id
            order by month_index
        ) as next_valid_month_index,
        lead(live_days) over (
            partition by anchor_id
            order by month_index
        ) as next_valid_live_days,
        lead(valid_acu_days) over (
            partition by anchor_id
            order by month_index
        ) as next_valid_acu_days,
        lead(avg_daily_acu) over (
            partition by anchor_id
            order by month_index
        ) as next_valid_avg_daily_acu
    from anchor_month
    where valid_acu_days >= 3
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
    inner join douyu_live_day d
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

-- 主播月明细：保留互动指标、下一有效月、留存分子分母及可评估标记。
monthly_detail as (
    select
        a.month_key,
        a.anchor_id,
        a.anchor_name,
        a.live_days as `当月有效开播日数`,
        a.valid_acu_days as `有效ACU天数`,
        round(a.avg_daily_acu, 2) as `月日均ACU`,
        round(a.avg_daily_danmu_users, 2) as `月日均弹幕人数`,
        round(a.interaction_rate, 4) as `互动强度指数`,
        a.total_danmu_cnt as `月弹幕次数`,
        a.interaction_evaluable,

        a.next_valid_month_key as `下一有效月`,
        a.next_valid_month_index - a.month_index as `留存间隔月数`,
        a.next_valid_live_days as `下一有效月开播日数`,
        a.next_valid_acu_days as `下一有效月有效ACU天数`,
        round(a.next_valid_avg_daily_acu, 2) as `下一有效月日均ACU`,

        coalesce(r.retention_base_users, 0) as `当前月留存分母用户数`,
        coalesce(r.next_valid_month_retained_users, 0) as `下一有效月观察留存用户数`,

        case
            when a.next_valid_month_key is not null
             and a.next_valid_acu_days >= 3
             and coalesce(r.retention_base_users, 0) >= 30
                then round(
                    1.0 * r.next_valid_month_retained_users
                    / r.retention_base_users,
                    4
                )
            else null
        end as `下一有效月留存率`,

        if(
            a.next_valid_month_key is not null
            and a.next_valid_acu_days >= 3
            and coalesce(r.retention_base_users, 0) >= 30,
            1,
            0
        ) as retention_evaluable,

        if(a.next_valid_month_index - a.month_index = 1, 1, 0)
            as is_natural_next_month
    from anchor_month_next a
    left join retention_metric r
        on a.month_key = r.month_key
       and a.anchor_id = r.anchor_id
),

-- 主播级仅保留样本月数，不计算任何中位数或高于中位数月份数。
anchor_evaluable_count as (
    select
        anchor_id,
        count(distinct if(interaction_evaluable = 1, month_key, null))
            as interaction_evaluable_months,
        count(distinct if(retention_evaluable = 1, month_key, null))
            as retention_evaluable_months,
        sum(if(retention_evaluable = 1 and is_natural_next_month = 1, 1, 0))
            as natural_next_month_retention_months
    from monthly_detail
    group by
        anchor_id
)

select
    d.month_key as `月份`,
    d.anchor_id as `斗鱼主播ID`,
    d.anchor_name as `主播名称`,
    d.`当月有效开播日数`,
    d.`有效ACU天数`,
    d.`月日均ACU`,
    d.`月日均弹幕人数`,
    d.`互动强度指数`,
    d.`月弹幕次数`,
    d.interaction_evaluable as `互动是否可评估`,
    d.`下一有效月`,
    d.`留存间隔月数`,
    d.`下一有效月开播日数`,
    d.`下一有效月有效ACU天数`,
    d.`下一有效月日均ACU`,
    d.`当前月留存分母用户数`,
    d.`下一有效月观察留存用户数`,
    d.`下一有效月留存率`,
    d.retention_evaluable as `留存是否可评估`,
    d.is_natural_next_month as `是否自然次月`,
    c.interaction_evaluable_months as `互动可评估月数`,
    c.retention_evaluable_months as `留存可评估月数`,
    c.natural_next_month_retention_months as `自然次月留存月数`,
    if(
        c.interaction_evaluable_months >= 3
        and c.retention_evaluable_months >= 4,
        1,
        0
    ) as `样本月数是否达标`
from monthly_detail d
left join anchor_evaluable_count c
    on d.anchor_id = c.anchor_id
where d.interaction_evaluable = 1
   or d.retention_evaluable = 1
order by
    d.anchor_id,
    d.month_key;
