-- =====================================================================
-- 目的：莫拉塔联播合作效果 - 开播日日均有效ACU汇总
-- 数据源：gamelive.dm_mkt_rowner_day
-- 执行引擎：Presto
--
-- 输出粒度：窗口 × 主播/群组/大盘；不输出逐日数据。
-- 主播开播日均有效ACU = 窗口内有效ACU合计 / 该主播实际有记录的开播天数。
-- 群组开播日均有效ACU = 群组有效ACU合计 / 该群组至少一人有记录的日期数。
-- 大盘日均有效ACU = 窗口内大盘ACU合计 / 实际大盘记录天数。
--
-- 时间口径：
--   合作前30天：2026-05-25 ~ 2026-06-23
--   联播期：    2026-06-24 ~ 2026-06-30
--   合作后30天：2026-07-01 ~ 2026-07-30
--
-- 重要口径：
--   1. 莫拉塔与合作主播不限制 r_category，避免品类标签变化导致漏掉已确认联播日。
--   2. 无畏契约大盘限制 r_category = '无畏契约'。
--   3. 大盘不剔除任何账号；非合作大盘仅剔除莫拉塔与5位合作主播。
-- =====================================================================

with selected_anchor_day_raw as (
    -- 6位圈选主播：不按品类过滤
    select
        cast(dt as date) as dt,
        cast(r_lid as varchar) as r_lid,
        cast(ext['vaild_acu'] as double) as valid_acu
    from gamelive.dm_mkt_rowner_day
    where dt between '2026-05-25' and '2026-07-30'
        and pcode = 'douyin_web'
        and cast(r_lid as varchar) in (
            '688292233649',
            '928481163143',
            '4577510133',
            '67556051524',
            '971406464239',
            '559868704090'
        )
),

selected_anchor_day as (
    -- 统一到 主播×日；若同日出现多条记录，取有效ACU最高值，避免重复相加
    select
        dt,
        case
            when dt between date '2026-05-25' and date '2026-06-23' then '合作前30天'
            when dt between date '2026-06-24' and date '2026-06-30' then '联播期'
            when dt between date '2026-07-01' and date '2026-07-30' then '合作后30天'
        end as window_name,
        r_lid,
        max(valid_acu) as valid_acu
    from selected_anchor_day_raw
    group by dt, r_lid
),

anchor_window as (
    -- 每位主播的分母是本人实际有记录的开播天数
    select
        window_name,
        r_lid,
        count(*) as actual_live_days,
        sum(valid_acu) as valid_acu_sum,
        avg(valid_acu) as avg_valid_acu_per_live_day
    from selected_anchor_day
    group by window_name, r_lid
),

group_day as (
    -- 先汇总到群组×日，以便群组按实际活跃日期计算日均
    select
        dt,
        window_name,
        sum(
            case
                when r_lid in (
                    '928481163143',
                    '4577510133',
                    '67556051524',
                    '971406464239',
                    '559868704090'
                )
                then valid_acu
                else 0
            end
        ) as collab_anchor_acu,
        sum(valid_acu) as selected_six_acu,
        sum(
            case
                when r_lid in (
                    '928481163143',
                    '4577510133',
                    '67556051524',
                    '971406464239',
                    '559868704090'
                )
                then 1
                else 0
            end
        ) as collab_anchor_member_live_days,
        count(*) as selected_six_member_live_days
    from selected_anchor_day
    group by dt, window_name
),

group_window as (
    -- 群组活跃日：当日至少一名该群组成员有记录
    select
        window_name,
        sum(
            case
                when collab_anchor_member_live_days > 0 then 1
                else 0
            end
        ) as collab_anchor_active_days,
        sum(collab_anchor_member_live_days) as collab_anchor_member_live_days,
        sum(collab_anchor_acu) as collab_anchor_acu_sum,
        count(*) as selected_six_active_days,
        sum(selected_six_member_live_days) as selected_six_member_live_days,
        sum(selected_six_acu) as selected_six_acu_sum
    from group_day
    group by window_name
),

market_day as (
    -- douyin_web 无畏契约大盘，不剔除任何异常主播
    select
        cast(dt as date) as dt,
        case
            when cast(dt as date) between date '2026-05-25' and date '2026-06-23' then '合作前30天'
            when cast(dt as date) between date '2026-06-24' and date '2026-06-30' then '联播期'
            when cast(dt as date) between date '2026-07-01' and date '2026-07-30' then '合作后30天'
        end as window_name,
        sum(cast(ext['vaild_acu'] as double)) as market_valid_acu,
        sum(
            case
                when cast(r_lid as varchar) not in (
                    '688292233649',
                    '928481163143',
                    '4577510133',
                    '67556051524',
                    '971406464239',
                    '559868704090'
                )
                then cast(ext['vaild_acu'] as double)
                else 0
            end
        ) as non_collab_market_valid_acu
    from gamelive.dm_mkt_rowner_day
    where dt between '2026-05-25' and '2026-07-30'
        and pcode = 'douyin_web'
        and r_category = '无畏契约'
    group by cast(dt as date)
),

market_window as (
    select
        window_name,
        count(*) as market_data_days,
        sum(market_valid_acu) as market_valid_acu_sum,
        avg(market_valid_acu) as market_avg_valid_acu_per_day,
        sum(non_collab_market_valid_acu) as non_collab_market_valid_acu_sum,
        avg(non_collab_market_valid_acu) as non_collab_market_avg_valid_acu_per_day
    from market_day
    group by window_name
),

summary_base as (
    -- 每位主播明细
    select
        a.window_name,
        '主播明细' as metric_type,
        case a.r_lid
            when '688292233649' then '莫拉塔'
            when '928481163143' then 'EQ118'
            when '4577510133' then '哀酱'
            when '67556051524' then '森森'
            when '971406464239' then '月芒zzZ'
            when '559868704090' then '小泽老师'
        end as metric_name,
        a.actual_live_days as active_days,
        a.actual_live_days as member_live_days,
        a.valid_acu_sum,
        a.avg_valid_acu_per_live_day as avg_valid_acu,
        a.valid_acu_sum / nullif(m.market_valid_acu_sum, 0) as market_share
    from anchor_window a
    inner join market_window m
        on a.window_name = m.window_name

    union all

    -- 5位合作主播整体：分母为群组实际活跃日；成员开播人天另列保留
    select
        g.window_name,
        '主播群组' as metric_type,
        '合作主播整体' as metric_name,
        g.collab_anchor_active_days as active_days,
        g.collab_anchor_member_live_days as member_live_days,
        g.collab_anchor_acu_sum as valid_acu_sum,
        g.collab_anchor_acu_sum / nullif(g.collab_anchor_active_days, 0) as avg_valid_acu,
        g.collab_anchor_acu_sum / nullif(m.market_valid_acu_sum, 0) as market_share
    from group_window g
    inner join market_window m
        on g.window_name = m.window_name

    union all

    -- 5位合作主播 + 莫拉塔
    select
        g.window_name,
        '主播群组' as metric_type,
        '合作主播整体加莫拉塔' as metric_name,
        g.selected_six_active_days as active_days,
        g.selected_six_member_live_days as member_live_days,
        g.selected_six_acu_sum as valid_acu_sum,
        g.selected_six_acu_sum / nullif(g.selected_six_active_days, 0) as avg_valid_acu,
        g.selected_six_acu_sum / nullif(m.market_valid_acu_sum, 0) as market_share
    from group_window g
    inner join market_window m
        on g.window_name = m.window_name

    union all

    -- 原始无畏契约大盘
    select
        window_name,
        '大盘' as metric_type,
        '无畏契约大盘' as metric_name,
        market_data_days as active_days,
        market_data_days as member_live_days,
        market_valid_acu_sum as valid_acu_sum,
        market_avg_valid_acu_per_day as avg_valid_acu,
        cast(1.0 as double) as market_share
    from market_window

    union all

    -- 大盘剔除莫拉塔和5位合作主播
    select
        window_name,
        '大盘' as metric_type,
        '非合作大盘_剔莫拉塔及合作主播' as metric_name,
        market_data_days as active_days,
        market_data_days as member_live_days,
        non_collab_market_valid_acu_sum as valid_acu_sum,
        non_collab_market_avg_valid_acu_per_day as avg_valid_acu,
        non_collab_market_valid_acu_sum / nullif(market_valid_acu_sum, 0) as market_share
    from market_window
),

summary_with_pre as (
    select
        window_name,
        metric_type,
        metric_name,
        active_days,
        member_live_days,
        valid_acu_sum,
        avg_valid_acu,
        market_share,
        max(
            case
                when window_name = '合作前30天' then avg_valid_acu
            end
        ) over (partition by metric_name) as pre_avg_valid_acu
    from summary_base
)

select
    window_name as "窗口",
    metric_type as "指标类型",
    metric_name as "指标",
    active_days as "实际开播天数或大盘记录天数",
    member_live_days as "成员开播人天",
    round(valid_acu_sum, 2) as "有效ACU合计",
    round(avg_valid_acu, 2) as "开播日日均有效ACU",
    round(market_share, 6) as "窗口无畏契约大盘占比",
    round(
        avg_valid_acu / nullif(pre_avg_valid_acu, 0) - 1,
        6
    ) as "开播日日均ACU较合作前增幅"
from summary_with_pre
order by
    case window_name
        when '合作前30天' then 1
        when '联播期' then 2
        when '合作后30天' then 3
    end,
    case metric_type
        when '主播明细' then 1
        when '主播群组' then 2
        when '大盘' then 3
    end,
    case metric_name
        when '莫拉塔' then 1
        when 'EQ118' then 2
        when '哀酱' then 3
        when '森森' then 4
        when '月芒zzZ' then 5
        when '小泽老师' then 6
        when '合作主播整体' then 7
        when '合作主播整体加莫拉塔' then 8
        when '无畏契约大盘' then 9
        when '非合作大盘_剔莫拉塔及合作主播' then 10
    end;

