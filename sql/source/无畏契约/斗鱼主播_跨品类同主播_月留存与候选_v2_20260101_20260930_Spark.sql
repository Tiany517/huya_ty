-- 目的：重新计算斗鱼主播“下一有效月”弹幕用户留存，并筛选 2026 年留存表现持续高于同层中位数的主播。
-- 数据源：gamelive.dm_mkt_rowner_day、gamelive.dwt_jingpin_danmulog_day。
-- 时间范围：2026-01-01 至 2026-09-30；不包含尚未结束的 2026-10。
-- 核心变化：留存只要求同一主播，不限制当前月与下一有效月的弹幕品类一致。
-- 品类口径：直接使用 dm_mkt_rowner_day.r_category；同主播同月多品类时保留多个品类月行，并复用同一主播月留存。
-- 下一有效月：同一主播之后第一个有效 ACU 天数 >= 3 的完整月份，可跨品类、可跳过无效月份。
-- 留存：当前月普通弹幕用户中，下一有效月仍向同一主播发送普通弹幕的用户占比。
-- 候选：2026 年内，留存高样本且高于“同品类 x 同 ACU 层级”中位数的月份数 >= 3。
-- 引擎：Spark SQL。

-- 1. 主播-品类-日底表：统一有效 ACU、弹幕人数和弹幕次数口径。
create table zhgametemp.douyu_crosscat_daily_v2 using parquet as
select
    cast(dt as string) as dt,
    cast(r_lid as string) as anchor_id,
    trim(cast(r_category as string)) as r_category,
    max(cast(r_owner as string)) as anchor_name,
    max(coalesce(cast(element_at(ext, 'vaild_acu') as double), 0.0)) as valid_acu,
    max(coalesce(cast(danmu_ucnt as double), 0.0)) as danmu_ucnt,
    max(coalesce(cast(danmu_cnt as double), 0.0)) as danmu_cnt
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

-- 2. 主播-品类-月底表：互动指标和 ACU 分层使用品类月口径。
create table zhgametemp.douyu_crosscat_cat_month_v2 using parquet as
with anchor_month_base as (
    select
        substr(dt, 1, 7) as month_key,
        r_category,
        anchor_id,
        max_by(anchor_name, dt) as anchor_name,
        count(distinct dt) as observed_days,
        count(distinct if(valid_acu > 0, dt, null)) as valid_acu_days,
        avg(if(valid_acu > 0, valid_acu, null)) as avg_daily_acu,
        avg(if(valid_acu > 0, danmu_ucnt, null)) as avg_daily_danmu_users,
        sum(if(valid_acu > 0, danmu_cnt, 0.0)) as total_danmu_cnt
    from zhgametemp.douyu_crosscat_daily_v2
    group by
        substr(dt, 1, 7),
        r_category,
        anchor_id
    having count(distinct if(valid_acu > 0, dt, null)) > 0
)
select
    month_key,
    r_category,
    anchor_id,
    anchor_name,
    observed_days,
    valid_acu_days,
    avg_daily_acu,
    avg_daily_danmu_users,
    avg_daily_danmu_users / nullif(avg_daily_acu, 0) as interaction_rate,
    total_danmu_cnt,
    case
        when valid_acu_days >= 3 and avg_daily_danmu_users >= 30 then '高样本'
        when valid_acu_days >= 2 and avg_daily_danmu_users >= 20 then '中样本'
        else '低样本'
    end as interaction_sample_grade,
    case
        when avg_daily_acu < 100 then '尾部'
        when avg_daily_acu < 1000 then '腰部'
        else '头部'
    end as acu_tier,
    cast(
        months_between(
            cast(concat(month_key, '-01') as date),
            date '2020-01-01'
        ) as int
    ) as month_index
from anchor_month_base;

-- 3. 主播-月底表：跨品类计算主播是否有效，并寻找下一有效月。
create table zhgametemp.douyu_crosscat_anchor_month_v2 using parquet as
with anchor_day_all as (
    select
        dt,
        anchor_id,
        max(anchor_name) as anchor_name,
        max(valid_acu) as valid_acu
    from zhgametemp.douyu_crosscat_daily_v2
    group by dt, anchor_id
),
anchor_month_base as (
    select
        substr(dt, 1, 7) as month_key,
        anchor_id,
        max_by(anchor_name, dt) as anchor_name,
        count(distinct if(valid_acu > 0, dt, null)) as valid_acu_days
    from anchor_day_all
    group by substr(dt, 1, 7), anchor_id
    having count(distinct if(valid_acu > 0, dt, null)) > 0
),
anchor_month_indexed as (
    select
        *,
        cast(
            months_between(
                cast(concat(month_key, '-01') as date),
                date '2020-01-01'
            ) as int
        ) as month_index
    from anchor_month_base
)
select
    month_key,
    anchor_id,
    anchor_name,
    valid_acu_days,
    month_index,
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
        if(valid_acu_days >= 3, valid_acu_days, null),
        true
    ) over (
        partition by anchor_id
        order by month_index
        rows between 1 following and unbounded following
    ) as next_valid_acu_days
from anchor_month_indexed;

-- 4. 主播-月-弹幕用户：不区分弹幕类别，只按主播和 sender 去重。
--    仅保留可能作为“当前月”或“下一有效月”的主播月，减少扫描输出。
create table zhgametemp.douyu_crosscat_danmu_month_v2 using parquet as
with target_month as (
    select anchor_id, month_key
    from zhgametemp.douyu_crosscat_anchor_month_v2
    where next_valid_month_key is not null
    union
    select anchor_id, next_valid_month_key as month_key
    from zhgametemp.douyu_crosscat_anchor_month_v2
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

-- 5. 主播-月留存：当前月用户是否仍出现在下一有效月，品类不参与匹配。
create table zhgametemp.douyu_crosscat_retention_month_v2 using parquet as
with target_month as (
    select
        anchor_id,
        month_key as current_month_key,
        next_valid_month_key,
        next_valid_month_index - month_index as retention_gap_months,
        next_valid_acu_days
    from zhgametemp.douyu_crosscat_anchor_month_v2
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
left join zhgametemp.douyu_crosscat_danmu_month_v2 c
    on t.anchor_id = c.anchor_id
   and t.current_month_key = c.month_key
left join zhgametemp.douyu_crosscat_danmu_month_v2 n
    on t.anchor_id = n.anchor_id
   and t.next_valid_month_key = n.month_key
   and c.danmu_user_id = n.danmu_user_id
group by
    t.anchor_id,
    t.current_month_key,
    t.next_valid_month_key,
    t.retention_gap_months,
    t.next_valid_acu_days;

-- 6. 留存分层阈值：使用主播品类月高样本，按品类 x ACU 层级计算中位数。
--    阈值可用条件：高样本月 >= 10 且高样本主播 >= 3。
create table zhgametemp.douyu_crosscat_retention_threshold_v2 using parquet as
with detail as (
    select
        c.month_key,
        c.r_category,
        c.anchor_id,
        c.anchor_name,
        c.valid_acu_days,
        c.avg_daily_acu,
        c.avg_daily_danmu_users,
        c.acu_tier,
        a.next_valid_month_key,
        r.retention_gap_months,
        r.next_valid_acu_days,
        coalesce(r.retention_base_users, 0) as retention_base_users,
        coalesce(r.retained_users, 0) as retained_users,
        r.retention_rate,
        case
            when c.valid_acu_days >= 3
             and c.avg_daily_danmu_users >= 30
             and r.retention_base_users >= 30
             and r.retention_rate is not null then '高样本'
            when c.valid_acu_days >= 2
             and c.avg_daily_danmu_users >= 20
             and r.retention_base_users >= 20
             and r.retention_rate is not null then '中样本'
            else '低样本'
        end as retention_sample_grade
    from zhgametemp.douyu_crosscat_cat_month_v2 c
    left join zhgametemp.douyu_crosscat_anchor_month_v2 a
        on c.anchor_id = a.anchor_id
       and c.month_key = a.month_key
    left join zhgametemp.douyu_crosscat_retention_month_v2 r
        on c.anchor_id = r.anchor_id
       and c.month_key = r.current_month_key
)
select
    r_category,
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
group by r_category, acu_tier;

-- 7. 候选主播-品类：只要求 2026 年内，高于同品类同 ACU 层留存中位数的月份数 >= 3。
create table zhgametemp.douyu_crosscat_retention_candidates_v2 using parquet as
with detail as (
    select
        c.month_key,
        c.r_category,
        c.anchor_id,
        c.anchor_name,
        c.valid_acu_days,
        c.avg_daily_acu,
        c.avg_daily_danmu_users,
        c.acu_tier,
        a.next_valid_month_key,
        r.retention_gap_months,
        r.next_valid_acu_days,
        coalesce(r.retention_base_users, 0) as retention_base_users,
        coalesce(r.retained_users, 0) as retained_users,
        r.retention_rate,
        t.median_retention_rate,
        t.threshold_is_valid,
        case
            when c.valid_acu_days >= 3
             and c.avg_daily_danmu_users >= 30
             and r.retention_base_users >= 30
             and r.retention_rate is not null then '高样本'
            when c.valid_acu_days >= 2
             and c.avg_daily_danmu_users >= 20
             and r.retention_base_users >= 20
             and r.retention_rate is not null then '中样本'
            else '低样本'
        end as retention_sample_grade
    from zhgametemp.douyu_crosscat_cat_month_v2 c
    left join zhgametemp.douyu_crosscat_anchor_month_v2 a
        on c.anchor_id = a.anchor_id
       and c.month_key = a.month_key
    left join zhgametemp.douyu_crosscat_retention_month_v2 r
        on c.anchor_id = r.anchor_id
       and c.month_key = r.current_month_key
    left join zhgametemp.douyu_crosscat_retention_threshold_v2 t
        on c.r_category = t.r_category
       and c.acu_tier = t.acu_tier
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
),
anchor_pair as (
    select
        r_category,
        anchor_id,
        max_by(anchor_name, month_key) as anchor_name,
        count(distinct month_key) as observed_months,
        count(distinct if(retention_sample_grade = '高样本', month_key, null)) as high_sample_months,
        count(distinct if(above_median_flag = 1, month_key, null)) as above_median_months,
        max(month_key) as latest_month,
        avg(if(retention_sample_grade = '高样本', retention_rate, null)) as avg_high_sample_retention_rate,
        avg(if(retention_sample_grade = '高样本', avg_daily_acu, null)) as avg_high_sample_acu
    from anchor_month_flag
    group by r_category, anchor_id
)
select
    r_category,
    anchor_id,
    anchor_name,
    observed_months,
    high_sample_months,
    above_median_months,
    latest_month,
    avg_high_sample_retention_rate,
    avg_high_sample_acu
from anchor_pair
where above_median_months >= 3;

