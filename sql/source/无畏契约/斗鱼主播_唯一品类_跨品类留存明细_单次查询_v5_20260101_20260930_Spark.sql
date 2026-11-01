-- 目的：一条 Spark SQL 下载主播月明细，后续在本地计算 ACU 分层中位数和候选。
-- 时间：2026-01-01 至 2026-09-30。
-- 主播品类：2026 年累计 live_mins 最长的 r_category；一主播只保留一个代表品类。
-- 留存：当前月普通弹幕用户中，下一有效月仍向同一主播发送普通弹幕的用户占比。
-- 留存匹配只要求同一主播，不要求弹幕品类一致。
-- 下一有效月：同一主播跨品类之后第一个有效 ACU 天数 >= 3 的完整月份。
-- 月度 ACU、弹幕人数：使用主播唯一代表品类的品类月口径。
-- 本查询不创建任何中间表，也不提前做候选过滤。

with daily as (
    select
        cast(dt as string) as dt,
        cast(r_lid as string) as anchor_id,
        trim(cast(r_category as string)) as r_category,
        max(cast(r_owner as string)) as anchor_name,
        max(coalesce(cast(element_at(ext, 'vaild_acu') as double), 0.0)) as valid_acu,
        max(coalesce(cast(danmu_ucnt as double), 0.0)) as danmu_ucnt,
        max(coalesce(cast(danmu_cnt as double), 0.0)) as danmu_cnt,
        max(coalesce(cast(live_mins as double), 0.0)) as live_mins
    from gamelive.dm_mkt_rowner_day
    where dt between '2026-01-01' and '2026-09-30'
      and pcode = 'douyu'
      and r_category is not null
      and trim(cast(r_category as string)) <> ''
      and r_category not in ('直播列表', '企鹅直播', '心悦专区')
    group by
        cast(dt as string),
        cast(r_lid as string),
        trim(cast(r_category as string))
),

-- 主播唯一代表品类：2026 年累计直播时长最长；并列时按有效 ACU 日数和品类名排序。
primary_category as (
    select anchor_id, r_category, anchor_name, total_live_mins
    from (
        select
            anchor_id,
            r_category,
            max_by(anchor_name, dt) as anchor_name,
            sum(live_mins) as total_live_mins,
            row_number() over (
                partition by anchor_id
                order by sum(live_mins) desc,
                         count(distinct if(valid_acu > 0, dt, null)) desc,
                         r_category
            ) as rn
        from daily
        group by anchor_id, r_category
    ) x
    where rn = 1 and total_live_mins > 0
),

-- 下一有效月使用主播全品类有效日，避免主播月内切品类造成误判。
anchor_day_all as (
    select
        dt,
        anchor_id,
        max(anchor_name) as anchor_name,
        max(valid_acu) as valid_acu
    from daily
    group by dt, anchor_id
),
anchor_month_all as (
    select
        substr(dt, 1, 7) as month_key,
        anchor_id,
        max_by(anchor_name, dt) as anchor_name,
        count(distinct if(valid_acu > 0, dt, null)) as valid_acu_days_any
    from anchor_day_all
    group by substr(dt, 1, 7), anchor_id
    having count(distinct if(valid_acu > 0, dt, null)) > 0
),

-- 月 ACU、弹幕人数使用唯一代表品类。
primary_month as (
    select
        substr(d.dt, 1, 7) as month_key,
        d.anchor_id,
        max_by(d.anchor_name, d.dt) as anchor_name,
        count(distinct d.dt) as observed_days_primary,
        count(distinct if(d.valid_acu > 0, d.dt, null)) as valid_acu_days_primary,
        avg(if(d.valid_acu > 0, d.valid_acu, null)) as avg_daily_acu,
        avg(if(d.valid_acu > 0, d.danmu_ucnt, null)) as avg_daily_danmu_users,
        sum(if(d.valid_acu > 0, d.danmu_cnt, 0.0)) as total_danmu_cnt,
        sum(d.live_mins) as primary_live_mins
    from daily d
    inner join primary_category p
        on d.anchor_id = p.anchor_id
       and d.r_category = p.r_category
    group by substr(d.dt, 1, 7), d.anchor_id
),

anchor_month_base as (
    select
        a.month_key,
        a.anchor_id,
        coalesce(m.anchor_name, a.anchor_name) as anchor_name,
        p.r_category as primary_category,
        p.total_live_mins as primary_category_live_mins,
        coalesce(m.observed_days_primary, 0) as observed_days_primary,
        coalesce(m.valid_acu_days_primary, 0) as valid_acu_days_primary,
        a.valid_acu_days_any,
        m.avg_daily_acu,
        m.avg_daily_danmu_users,
        coalesce(m.total_danmu_cnt, 0.0) as total_danmu_cnt,
        coalesce(m.primary_live_mins, 0.0) as primary_live_mins,
        cast(
            months_between(
                cast(concat(a.month_key, '-01') as date),
                date '2020-01-01'
            ) as int
        ) as month_index
    from anchor_month_all a
    inner join primary_category p
        on a.anchor_id = p.anchor_id
    left join primary_month m
        on a.month_key = m.month_key
       and a.anchor_id = m.anchor_id
),

anchor_month as (
    select
        *,
        first_value(if(valid_acu_days_any >= 3, month_key, null), true) over (
            partition by anchor_id
            order by month_index
            rows between 1 following and unbounded following
        ) as next_valid_month_key,
        first_value(if(valid_acu_days_any >= 3, month_index, null), true) over (
            partition by anchor_id
            order by month_index
            rows between 1 following and unbounded following
        ) as next_valid_month_index,
        first_value(if(valid_acu_days_any >= 3, valid_acu_days_any, null), true) over (
            partition by anchor_id
            order by month_index
            rows between 1 following and unbounded following
        ) as next_valid_acu_days
    from anchor_month_base
),

target_month as (
    select anchor_id, month_key
    from anchor_month
    where next_valid_month_key is not null
      and valid_acu_days_primary >= 3
      and avg_daily_danmu_users >= 30
    union
    select anchor_id, next_valid_month_key as month_key
    from anchor_month
    where next_valid_month_key is not null
      and valid_acu_days_primary >= 3
      and avg_daily_danmu_users >= 30
),

-- 普通弹幕用户：只按主播、月、sender 去重，不限制弹幕品类。
danmu_user_month as (
    select
        substr(cast(d.dt as string), 1, 7) as month_key,
        cast(d.uid as string) as anchor_id,
        cast(d.sender as string) as danmu_user_id
    from gamelive.dwt_jingpin_danmulog_day d
    inner join target_month t
        on cast(d.uid as string) = t.anchor_id
       and substr(cast(d.dt as string), 1, 7) = t.month_key
    where d.dt between '2026-01-01' and '2026-09-30'
      and d.pcode = 'douyu'
      and cast(d.msgtype as string) = '0'
      and d.sender is not null
      and trim(cast(d.sender as string)) <> ''
    group by
        substr(cast(d.dt as string), 1, 7),
        cast(d.uid as string),
        cast(d.sender as string)
),

retention_month as (
    select
        a.anchor_id,
        a.month_key,
        a.next_valid_month_key,
        a.next_valid_month_index - a.month_index as retention_gap_months,
        a.next_valid_acu_days,
        count(distinct c.danmu_user_id) as retention_base_users,
        count(distinct n.danmu_user_id) as retained_users,
        case
            when count(distinct c.danmu_user_id) > 0
            then 1.0 * count(distinct n.danmu_user_id)
                 / count(distinct c.danmu_user_id)
            else null
        end as retention_rate
    from anchor_month a
    left join danmu_user_month c
        on a.anchor_id = c.anchor_id
       and a.month_key = c.month_key
    left join danmu_user_month n
        on a.anchor_id = n.anchor_id
       and a.next_valid_month_key = n.month_key
       and c.danmu_user_id = n.danmu_user_id
    where a.next_valid_month_key is not null
    group by
        a.anchor_id,
        a.month_key,
        a.next_valid_month_key,
        a.next_valid_month_index - a.month_index,
        a.next_valid_acu_days
)

select
    a.month_key as `月份`,
    a.primary_category as `主播代表品类`,
    a.anchor_id as `斗鱼主播ID`,
    a.anchor_name as `主播名称`,
    a.primary_category_live_mins as `2026主品类累计直播时长`,
    a.observed_days_primary as `当月主品类观测开播日数`,
    a.valid_acu_days_primary as `当月主品类有效ACU天数`,
    a.valid_acu_days_any as `当月主播全品类有效ACU天数`,
    a.avg_daily_acu as `月日均ACU`,
    a.avg_daily_danmu_users as `月日均弹幕人数`,
    a.avg_daily_danmu_users / nullif(a.avg_daily_acu, 0) as `互动强度`,
    a.total_danmu_cnt as `月弹幕次数`,
    a.primary_live_mins as `当月主品类直播时长`,
    case
        when a.avg_daily_acu < 100 then '尾部'
        when a.avg_daily_acu < 1000 then '腰部'
        else '头部'
    end as `ACU层级`,
    r.next_valid_month_key as `下一有效月`,
    r.retention_gap_months as `留存间隔月数`,
    r.next_valid_acu_days as `下一有效月有效ACU天数`,
    coalesce(r.retention_base_users, 0) as `当前月留存分母用户数`,
    coalesce(r.retained_users, 0) as `下一有效月观察留存用户数`,
    r.retention_rate as `下一有效月留存率`,
    case
        when a.valid_acu_days_primary >= 3
         and a.avg_daily_danmu_users >= 30
         and r.retention_base_users >= 30
         and r.retention_rate is not null then '高样本'
        when a.valid_acu_days_primary >= 2
         and a.avg_daily_danmu_users >= 20
         and r.retention_base_users >= 20
         and r.retention_rate is not null then '中样本'
        else '低样本'
    end as `留存样本等级`,
    case
        when a.valid_acu_days_primary >= 3
         and a.avg_daily_danmu_users >= 30
         and r.retention_base_users >= 30
         and r.retention_rate is not null then 1 else 0
    end as `留存是否可评估`,
    case
        when r.next_valid_month_key is null then null
        when r.retention_gap_months = 1 then 1
        else 0
    end as `是否自然次月`
from anchor_month a
left join retention_month r
    on a.anchor_id = r.anchor_id
   and a.month_key = r.month_key
order by
    a.primary_category,
    a.anchor_id,
    a.month_key;
