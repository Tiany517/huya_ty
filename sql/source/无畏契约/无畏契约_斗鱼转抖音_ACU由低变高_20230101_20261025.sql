-- 目的：找出斗鱼无畏契约 ACU 较低，转到抖音无畏契约后 ACU 变高的主播候选。
-- 数据源：gamelive.dm_mkt_rowner_day。
-- 时间范围：2023-01-01 至最新可用分区 2026-10-25。
-- 类目口径：douyin_web 和 douyu 两侧均严格限定 r_category = '无畏契约'。
-- 开播时序：斗鱼最后开播日 < 抖音首次开播日，两段开播期完全不重叠；重叠主播全部剔除。
-- ACU 口径：只统计有效 ACU > 0 的开播日，两边均至少 3 个有效 ACU 日。
-- 变高口径：抖音有效开播日平均 ACU > 斗鱼有效开播日平均 ACU。
-- 主播匹配：清理昵称中的空格、括号和“无畏契约”等结尾后缀后做同名粗匹配。
-- 注意：这是同名粗筛结果，仍需人工确认两个平台账号是否属于同一主播。
-- 引擎：Presto。

with douyin_day as (
    select
        cast(dt as varchar) as dt,
        cast(r_lid as varchar) as r_lid,
        max(cast(r_owner as varchar)) as r_owner,
        max(cast(r_url as varchar)) as r_url,
        max(coalesce(try_cast(element_at(ext, 'vaild_acu') as double), 0.0)) as valid_acu,
        max(coalesce(try_cast(hour_cnt as double), 0.0) * 60.0) as live_mins,
        max(
            regexp_replace(
                regexp_replace(
                    lower(trim(cast(r_owner as varchar))),
                    '[\\s　（）()【】\\[\\]·._-]+',
                    ''
                ),
                '(无畏契约|瓦罗兰特|valorant)$',
                ''
            )
        ) as owner_key
    from gamelive.dm_mkt_rowner_day
    where dt between '2023-01-01' and '2026-10-25'
      and pcode = 'douyin_web'
      and r_category = '无畏契约'
    group by
        cast(dt as varchar),
        cast(r_lid as varchar)
),

douyin_anchor as (
    select
        r_lid,
        max_by(r_owner, dt) as douyin_owner,
        max_by(owner_key, dt) as owner_key,
        min(dt) as douyin_first_dt,
        max(dt) as douyin_last_dt,
        count(distinct dt) as douyin_live_days,
        count(distinct if(valid_acu > 0, dt, null)) as douyin_acu_days,
        avg(if(valid_acu > 0, valid_acu, null)) as douyin_avg_acu,
        approx_percentile(if(valid_acu > 0, valid_acu, null), 0.5) as douyin_median_acu,
        sum(if(valid_acu > 0, valid_acu * live_mins, 0.0))
            / nullif(sum(if(valid_acu > 0, live_mins, 0.0)), 0.0) as douyin_weighted_acu,
        max(r_url) as douyin_r_url
    from douyin_day
    where length(owner_key) >= 3
    group by r_lid
    having count(distinct dt) >= 14
       and count(distinct if(valid_acu > 0, dt, null)) >= 3
),

douyu_day as (
    select
        cast(dt as varchar) as dt,
        cast(r_lid as varchar) as r_lid,
        max(cast(r_owner as varchar)) as r_owner,
        max(cast(r_url as varchar)) as r_url,
        max(coalesce(try_cast(element_at(ext, 'vaild_acu') as double), 0.0)) as valid_acu,
        max(coalesce(try_cast(live_mins as double), 0.0)) as live_mins,
        max(
            regexp_replace(
                regexp_replace(
                    lower(trim(cast(r_owner as varchar))),
                    '[\\s　（）()【】\\[\\]·._-]+',
                    ''
                ),
                '(无畏契约|瓦罗兰特|valorant)$',
                ''
            )
        ) as owner_key
    from gamelive.dm_mkt_rowner_day
    where dt between '2023-01-01' and '2026-10-25'
      and pcode = 'douyu'
      and r_category = '无畏契约'
    group by
        cast(dt as varchar),
        cast(r_lid as varchar)
),

douyu_anchor as (
    select
        d.owner_key,
        d.r_lid as douyu_r_lid,
        max_by(d.r_owner, d.dt) as douyu_owner,
        min(d.dt) as douyu_first_dt,
        max(d.dt) as douyu_last_dt,
        count(distinct d.dt) as douyu_live_days,
        count(distinct if(d.valid_acu > 0, d.dt, null)) as douyu_acu_days,
        avg(if(d.valid_acu > 0, d.valid_acu, null)) as douyu_avg_acu,
        approx_percentile(if(d.valid_acu > 0, d.valid_acu, null), 0.5) as douyu_median_acu,
        sum(if(d.valid_acu > 0, d.valid_acu * d.live_mins, 0.0))
            / nullif(sum(if(d.valid_acu > 0, d.live_mins, 0.0)), 0.0) as douyu_weighted_acu,
        max(d.r_url) as douyu_r_url
    from douyu_day d
    inner join (
        select distinct owner_key
        from douyin_anchor
    ) n
        on d.owner_key = n.owner_key
    group by
        d.owner_key,
        d.r_lid
    having count(distinct d.dt) >= 14
       and count(distinct if(d.valid_acu > 0, d.dt, null)) >= 3
),

-- A 级映射：斗鱼记录结束后，抖音才开始有记录
a_mapping as (
    select
        d.douyin_owner,
        d.r_lid as douyin_r_lid,
        d.douyin_first_dt,
        d.douyin_last_dt,
        d.douyin_live_days,
        d.douyin_acu_days,
        d.douyin_avg_acu,
        d.douyin_median_acu,
        d.douyin_weighted_acu,
        d.douyin_r_url,
        u.douyu_owner,
        u.douyu_r_lid,
        u.douyu_first_dt,
        u.douyu_last_dt,
        u.douyu_live_days,
        u.douyu_acu_days,
        u.douyu_avg_acu,
        u.douyu_median_acu,
        u.douyu_weighted_acu,
        u.douyu_r_url
    from douyin_anchor d
    inner join douyu_anchor u
        on d.owner_key = u.owner_key
    where u.douyu_last_dt < d.douyin_first_dt
)

select
    douyin_owner,
    douyin_r_lid,
    douyin_first_dt,
    douyin_last_dt,
    douyin_live_days,
    douyin_acu_days,
    round(douyin_avg_acu, 2) as douyin_avg_acu,
    round(douyin_median_acu, 2) as douyin_median_acu,
    round(douyin_weighted_acu, 2) as douyin_weighted_acu,
    douyin_r_url,
    douyu_owner,
    douyu_r_lid,
    douyu_first_dt,
    douyu_last_dt,
    douyu_live_days,
    douyu_acu_days,
    round(douyu_avg_acu, 2) as douyu_avg_acu,
    round(douyu_median_acu, 2) as douyu_median_acu,
    round(douyu_weighted_acu, 2) as douyu_weighted_acu,
    douyu_r_url,
    round(douyin_avg_acu - douyu_avg_acu, 2) as avg_acu_delta,
    round(1.0 * douyin_avg_acu / nullif(douyu_avg_acu, 0), 2) as avg_acu_multiple,
    round(
        100.0 * (douyin_avg_acu - douyu_avg_acu) / nullif(douyu_avg_acu, 0),
        2
    ) as avg_acu_growth_pct
from a_mapping
where douyu_avg_acu > 0
  and douyin_avg_acu > douyu_avg_acu
order by
    avg_acu_multiple desc,
    avg_acu_delta desc,
    douyin_avg_acu desc;
