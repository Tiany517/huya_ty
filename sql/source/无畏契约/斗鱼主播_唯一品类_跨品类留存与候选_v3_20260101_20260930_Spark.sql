-- 目的：以“一主播一品类”重新计算斗鱼主播下一有效月弹幕用户留存，并筛选 2026 年留存表现持续高于同层中位数的主播。
-- 数据源：gamelive.dm_mkt_rowner_day、gamelive.dwt_jingpin_danmulog_day。
-- 时间范围：2026-01-01 至 2026-09-30；不包含尚未结束的 2026-10。
-- 主播品类：统计 2026 年同一主播各品类累计 live_mins，取累计直播时长最长的品类；并列时依次按有效 ACU 日数、品类名排序。
-- 月度 ACU/弹幕人数：使用主播唯一品类对应的品类月数据。
-- 下一有效月：同一主播跨品类之后第一个有效 ACU 天数 >= 3 的完整月份。
-- 留存：只需同一主播；当前月普通弹幕用户中，下一有效月仍向同一主播发送普通弹幕的用户占比。
-- 候选：2026 年内，留存高样本且高于“主播品类 x ACU 层级”中位数的月份数 >= 3。
-- 引擎：Spark SQL。

-- 1. 主播-品类-日底表。
create table zhgametemp.douyu_crosscat_daily_v3 as
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
    trim(cast(r_category as string));

-- 2. 主播唯一品类：2026 年累计直播时长最长的品类。
create table zhgametemp.douyu_crosscat_primary_category_v3 as
with category_total as (
    select
        anchor_id,
        r_category,
        max_by(anchor_name, dt) as anchor_name,
        sum(live_mins) as total_live_mins,
        count(distinct if(valid_acu > 0, dt, null)) as valid_acu_days
    from zhgametemp.douyu_crosscat_daily_v3
    group by anchor_id, r_category
),
ranked as (
    select
        *,
        row_number() over (
            partition by anchor_id
            order by total_live_mins desc, valid_acu_days desc, r_category
        ) as category_rank
    from category_total
    where total_live_mins > 0
)
select
    anchor_id,
    r_category as primary_category,
    anchor_name,
    total_live_mins as primary_category_live_mins,
    valid_acu_days as primary_category_valid_acu_days
from ranked
where category_rank = 1;

-- 3. 主播-月底表：ACU/弹幕人数使用唯一品类；下一有效月使用主播全品类有效日。
create table zhgametemp.douyu_crosscat_anchor_month_v3 as
with anchor_day_all as (
    select
        dt,
        anchor_id,
        max(anchor_name) as anchor_name,
        max(valid_acu) as valid_acu
    from zhgametemp.douyu_crosscat_daily_v3
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
    from zhgametemp.douyu_crosscat_daily_v3 d
    inner join zhgametemp.douyu_crosscat_primary_category_v3 p
        on d.anchor_id = p.anchor_id
       and d.r_category = p.primary_category
    group by substr(d.dt, 1, 7), d.anchor_id
),
combined as (
    select
        a.month_key,
        a.anchor_id,
        coalesce(m.anchor_name, a.anchor_name) as anchor_name,
        p.primary_category,
        coalesce(m.observed_days_primary, 0) as observed_days_primary,
        coalesce(m.valid_acu_days_primary, 0) as valid_acu_days_primary,
        a.valid_acu_days_any,
        m.avg_daily_acu,
        m.avg_daily_danmu_users,
        coalesce(m.total_danmu_cnt, 0.0) as total_danmu_cnt,
        coalesce(m.primary_live_mins, 0.0) as primary_live_mins
    from anchor_month_all a
    inner join zhgametemp.douyu_crosscat_primary_category_v3 p
        on a.anchor_id = p.anchor_id
    left join primary_month m
        on a.month_key = m.month_key
       and a.anchor_id = m.anchor_id
),
indexed as (
    select
        *,
        cast(
            months_between(
                cast(concat(month_key, '-01') as date),
                date '2020-01-01'
            ) as int
        ) as month_index
    from combined
)
select
    month_key,
    anchor_id,
    anchor_name,
    primary_category,
    observed_days_primary,
    valid_acu_days_primary,
    valid_acu_days_any,
    avg_daily_acu,
    avg_daily_danmu_users,
    avg_daily_danmu_users / nullif(avg_daily_acu, 0) as interaction_rate,
    total_danmu_cnt,
    primary_live_mins,
    case
        when avg_daily_acu < 100 then '尾部'
        when avg_daily_acu < 1000 then '腰部'
        else '头部'
    end as acu_tier,
    month_index,
    first_value(
        if(valid_acu_days_any >= 3, month_key, null),
        true
    ) over (
        partition by anchor_id
        order by month_index
        rows between 1 following and unbounded following
    ) as next_valid_month_key,
    first_value(
        if(valid_acu_days_any >= 3, month_index, null),
        true
    ) over (
        partition by anchor_id
        order by month_index
        rows between 1 following and unbounded following
    ) as next_valid_month_index,
    first_value(
        if(valid_acu_days_any >= 3, valid_acu_days_any, null),
        true
    ) over (
        partition by anchor_id
        order by month_index
        rows between 1 following and unbounded following
    ) as next_valid_acu_days
from indexed;

-- 4. 主播-月-弹幕用户：不区分弹幕类别，只按主播和 sender 去重。
create table zhgametemp.douyu_crosscat_danmu_month_v3 as
with target_month as (
    select anchor_id, month_key
    from zhgametemp.douyu_crosscat_anchor_month_v3
    where next_valid_month_key is not null
    union
    select anchor_id, next_valid_month_key as month_key
    from zhgametemp.douyu_crosscat_anchor_month_v3
    where next_valid_month_key is not null
)
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
    cast(d.sender as string);

-- 5. 主播-月留存：跨品类、同主播匹配。
create table zhgametemp.douyu_crosscat_retention_month_v3 as
with target_month as (
    select
        anchor_id,
        month_key as current_month_key,
        next_valid_month_key,
        next_valid_month_index - month_index as retention_gap_months,
        next_valid_acu_days
    from zhgametemp.douyu_crosscat_anchor_month_v3
    where next_valid_month_key is not null
)
select
    t.anchor_id,
    t.current_month_key,
    t.next_valid_month_key,
    t.retention_gap_months,
    t.next_valid_acu_days,
    count(distinct c.danmu_user_id) as retention_base_users,
    count(distinct n.danmu_user_id) as retained_users,
    case
        when count(distinct c.danmu_user_id) > 0
        then 1.0 * count(distinct n.danmu_user_id)
             / count(distinct c.danmu_user_id)
        else null
    end as retention_rate
from target_month t
left join zhgametemp.douyu_crosscat_danmu_month_v3 c
    on t.anchor_id = c.anchor_id
   and t.current_month_key = c.month_key
left join zhgametemp.douyu_crosscat_danmu_month_v3 n
    on t.anchor_id = n.anchor_id
   and t.next_valid_month_key = n.month_key
   and c.danmu_user_id = n.danmu_user_id
group by
    t.anchor_id,
    t.current_month_key,
    t.next_valid_month_key,
    t.retention_gap_months,
    t.next_valid_acu_days;

-- 6. 留存分层阈值：按主播唯一品类 x 月 ACU 层级，计算高样本月留存中位数。
create table zhgametemp.douyu_crosscat_retention_threshold_v3 as
with detail as (
    select
        a.month_key,
        a.primary_category,
        a.anchor_id,
        a.anchor_name,
        a.valid_acu_days_primary,
        a.avg_daily_acu,
        a.avg_daily_danmu_users,
        a.acu_tier,
        a.next_valid_month_key,
        r.retention_gap_months,
        r.next_valid_acu_days,
        coalesce(r.retention_base_users, 0) as retention_base_users,
        coalesce(r.retained_users, 0) as retained_users,
        r.retention_rate,
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
        end as retention_sample_grade
    from zhgametemp.douyu_crosscat_anchor_month_v3 a
    left join zhgametemp.douyu_crosscat_retention_month_v3 r
        on a.anchor_id = r.anchor_id
       and a.month_key = r.current_month_key
)
select
    primary_category,
    acu_tier,
    count(distinct if(retention_sample_grade = '高样本', month_key, null)) as high_sample_months,
    count(distinct if(retention_sample_grade = '高样本', anchor_id, null)) as high_sample_anchors,
    percentile_approx(
        if(retention_sample_grade = '高样本', retention_rate, null),
        0.5
    ) as median_retention_rate,
    case
        when count(distinct if(retention_sample_grade = '高样本', month_key, null)) >= 10
         and count(distinct if(retention_sample_grade = '高样本', anchor_id, null)) >= 3
        then 1 else 0
    end as threshold_is_valid
from detail
group by primary_category, acu_tier;

-- 7. 候选主播：一主播一品类；只要求高于同层留存中位数的月份数 >= 3。
create table zhgametemp.douyu_crosscat_retention_candidates_v3 as
with detail as (
    select
        a.month_key,
        a.primary_category,
        a.anchor_id,
        a.anchor_name,
        a.valid_acu_days_primary,
        a.avg_daily_acu,
        a.avg_daily_danmu_users,
        a.acu_tier,
        a.next_valid_month_key,
        r.retention_gap_months,
        r.next_valid_acu_days,
        coalesce(r.retention_base_users, 0) as retention_base_users,
        coalesce(r.retained_users, 0) as retained_users,
        r.retention_rate,
        t.median_retention_rate,
        t.threshold_is_valid,
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
        end as retention_sample_grade
    from zhgametemp.douyu_crosscat_anchor_month_v3 a
    left join zhgametemp.douyu_crosscat_retention_month_v3 r
        on a.anchor_id = r.anchor_id
       and a.month_key = r.current_month_key
    left join zhgametemp.douyu_crosscat_retention_threshold_v3 t
        on a.primary_category = t.primary_category
       and a.acu_tier = t.acu_tier
),
anchor_month_flag as (
    select
        *,
        case
            when threshold_is_valid = 1
             and retention_sample_grade = '高样本'
             and retention_rate > median_retention_rate then 1
            else 0
        end as above_median_flag
    from detail
)
select
    primary_category,
    anchor_id,
    max_by(anchor_name, month_key) as anchor_name,
    count(distinct month_key) as observed_months,
    count(distinct if(retention_sample_grade = '高样本', month_key, null)) as high_sample_months,
    count(distinct if(above_median_flag = 1, month_key, null)) as above_median_months,
    max(month_key) as latest_month,
    avg(if(retention_sample_grade = '高样本', retention_rate, null)) as avg_high_sample_retention_rate,
    avg(if(retention_sample_grade = '高样本', avg_daily_acu, null)) as avg_high_sample_acu
from anchor_month_flag
group by primary_category, anchor_id
having count(distinct if(above_median_flag = 1, month_key, null)) >= 3;

