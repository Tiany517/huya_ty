-- 无畏契约行业区间日均观时（人·分钟）
-- 时间范围：2026-01-01 至 2026-10-21
-- 行业范围：虎牙、抖音、斗鱼、B站、快手
-- 有效主播日：vaild_acu > 0 且 live_mins >= 15
-- 区间日均观时：先汇总每日行业观时，再对有数据的自然日求平均，不补零

with anchor_day as (
    -- 先聚合到 平台 × 主播 × 日，避免同主播同日多行造成重复
    select
        cast(dt as varchar) as dt,
        case
            when cast(pcode as varchar) = 'douyin_web' then 'douyin'
            else cast(pcode as varchar)
        end as pcode,
        cast(r_lid as varchar) as r_lid,
        max(
            coalesce(
                cast(element_at(ext, 'vaild_acu') as double),
                0.0
            )
        ) as valid_acu,
        sum(
            case
                when cast(pcode as varchar) in (
                    'douyin_web', 'douyin', 'kuaishou'
                )
                    then coalesce(cast(hour_cnt as bigint), 0) * 60
                else coalesce(cast(live_mins as bigint), 0)
            end
        ) as live_mins,
        sum(
            case
                when cast(pcode as varchar) in (
                    'douyin_web', 'douyin', 'kuaishou'
                )
                    then coalesce(cast(hour_cnt as bigint), 0) * 60
                else coalesce(cast(live_mins as bigint), 0)
            end
            *
            coalesce(
                cast(element_at(ext, 'vaild_acu') as double),
                0.0
            )
        ) as watch_min
    from gamelive.dm_mkt_rowner_day
    where dt between '2026-01-01' and '2026-10-21'
      and cast(pcode as varchar) in (
          'huya',
          'douyin',
          'douyin_web',
          'douyu',
          'bilibili',
          'kuaishou'
      )
      and coalesce(
          nullif(cast(cate1 as varchar), ''),
          cast(r_category as varchar)
      ) = '无畏契约'
    group by
        cast(dt as varchar),
        case
            when cast(pcode as varchar) = 'douyin_web' then 'douyin'
            else cast(pcode as varchar)
        end,
        cast(r_lid as varchar)
),

valid_anchor_day as (
    -- 与主播分析保持一致：有效 ACU 且有效开播时长至少 15 分钟
    select
        dt,
        pcode,
        r_lid,
        valid_acu,
        live_mins,
        watch_min
    from anchor_day
    where valid_acu > 0
      and live_mins >= 15
),

industry_day as (
    -- 每天把全平台、全主播的观时汇总，单位：人·分钟
    select
        dt,
        count(distinct concat(pcode, '|', r_lid)) as active_anchor_cnt,
        sum(watch_min) as daily_watch_min
    from valid_anchor_day
    group by dt
)

select
    min(dt) as min_dt,
    max(dt) as max_dt,
    count(distinct dt) as valid_day_cnt,
    avg(active_anchor_cnt) as avg_daily_active_anchor_cnt,
    avg(daily_watch_min) as avg_daily_watch_min,
    sum(daily_watch_min) as total_watch_min
from industry_day;
