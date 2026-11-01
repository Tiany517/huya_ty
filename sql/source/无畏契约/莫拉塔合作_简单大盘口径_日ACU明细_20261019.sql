-- =====================================================================
-- 目的：莫拉塔联播合作效果的简单大盘对比
-- 数据源：gamelive.dm_mkt_rowner_day
-- 平台：pcode = 'douyin_web'
-- 有效ACU：cast(ext['vaild_acu'] as double)
--
-- 合作主播：
--   EQ118       928481163143
--   哀酱        4577510133
--   森森        67556051524
--   月芒zzZ     971406464239
--   小泽老师    559868704090
-- 莫拉塔：688292233649
--
-- 时间口径：
--   合作前30天：2026-05-25 ~ 2026-06-23
--   联播期：    2026-06-24 ~ 2026-06-30
--   合作后30天：2026-07-01 ~ 2026-07-30
--
-- 重要口径：
--   1. 合作主播及莫拉塔：不限制 r_category。
--      联播事实由业务人工确认；r_category 是当天直播时间最长的品类，
--      不能把它作为联播是否发生的判断条件。
--   2. 无畏契约大盘：限制 r_category = '无畏契约'。
--   3. 主播日数据若存在多条品类记录，取 max(valid_acu)，避免重复相加；
--      输出 source_row_cnt 和 source_categories 便于复核。
-- =====================================================================


-- =====================================================================
-- 输出1：莫拉塔及合作主播的逐日明细（主播×日）
-- 用于核查每位合作主播在合作前、联播期、合作后的有效ACU变化。
-- =====================================================================
with anchor_day_raw as (
    select
        cast(dt as date) as dt,
        cast(r_lid as varchar) as r_lid,
        r_owner,
        r_category,
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

anchor_day as (
    -- 统一至 主播×日；若同日出现多品类行，保留有效ACU最高的一行
    select
        dt,
        r_lid,
        max_by(r_owner, valid_acu) as r_owner,
        array_join(array_agg(distinct r_category), ' | ') as source_categories,
        max(valid_acu) as valid_acu,
        count(*) as source_row_cnt
    from anchor_day_raw
    group by dt, r_lid
)

select
    cast(dt as varchar) as "日期",
    case
        when dt between date '2026-05-25' and date '2026-06-23' then '合作前30天'
        when dt between date '2026-06-24' and date '2026-06-30' then '联播期'
        when dt between date '2026-07-01' and date '2026-07-30' then '合作后30天'
    end as "窗口",
    case r_lid
        when '688292233649' then '莫拉塔'
        when '928481163143' then 'EQ118'
        when '4577510133' then '哀酱'
        when '67556051524' then '森森'
        when '971406464239' then '月芒zzZ'
        when '559868704090' then '小泽老师'
    end as "主播",
    r_lid as "主播ID",
    r_owner as "表内昵称",
    source_categories as "当天品类标签",
    round(valid_acu, 2) as "有效ACU",
    source_row_cnt as "源表记录数"
from anchor_day
order by dt, "主播";


-- =====================================================================
-- 输出2：逐日汇总
-- 包含：莫拉塔、5位合作主播明细、合作主播整体、6人整体、原始无畏契约大盘、
--       剔除莫拉塔和5位合作主播后的非合作大盘、两种大盘份额。
-- =====================================================================
with anchor_day_raw as (
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

anchor_day as (
    -- 合作主播结果不按品类筛选，防止已确认联播日因品类标签变化而漏数
    select
        dt,
        r_lid,
        max(valid_acu) as valid_acu
    from anchor_day_raw
    group by dt, r_lid
),

market_day as (
    -- 无畏契约大盘：保留全部主播，不剔除任何异常账号
    select
        cast(dt as date) as dt,
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

daily_summary as (
    select
        m.dt,
        coalesce(max(case when a.r_lid = '688292233649' then a.valid_acu end), 0) as molata_acu,
        coalesce(max(case when a.r_lid = '928481163143' then a.valid_acu end), 0) as eq118_acu,
        coalesce(max(case when a.r_lid = '4577510133' then a.valid_acu end), 0) as aijiang_acu,
        coalesce(max(case when a.r_lid = '67556051524' then a.valid_acu end), 0) as sensen_acu,
        coalesce(max(case when a.r_lid = '971406464239' then a.valid_acu end), 0) as yuemang_acu,
        coalesce(max(case when a.r_lid = '559868704090' then a.valid_acu end), 0) as xiaoze_acu,
        m.market_valid_acu,
        m.non_collab_market_valid_acu
    from market_day m
    left join anchor_day a
        on m.dt = a.dt
    group by m.dt, m.market_valid_acu, m.non_collab_market_valid_acu
),

daily_with_group as (
    select
        dt,
        molata_acu,
        eq118_acu,
        aijiang_acu,
        sensen_acu,
        yuemang_acu,
        xiaoze_acu,
        eq118_acu + aijiang_acu + sensen_acu + yuemang_acu + xiaoze_acu as collab_anchor_acu,
        molata_acu + eq118_acu + aijiang_acu + sensen_acu + yuemang_acu + xiaoze_acu as selected_six_acu,
        market_valid_acu,
        non_collab_market_valid_acu
    from daily_summary
)

select
    cast(dt as varchar) as "日期",
    case
        when dt between date '2026-05-25' and date '2026-06-23' then '合作前30天'
        when dt between date '2026-06-24' and date '2026-06-30' then '联播期'
        when dt between date '2026-07-01' and date '2026-07-30' then '合作后30天'
    end as "窗口",
    round(molata_acu, 2) as "莫拉塔有效ACU",
    round(eq118_acu, 2) as "EQ118有效ACU",
    round(aijiang_acu, 2) as "哀酱有效ACU",
    round(sensen_acu, 2) as "森森有效ACU",
    round(yuemang_acu, 2) as "月芒zzZ有效ACU",
    round(xiaoze_acu, 2) as "小泽老师有效ACU",
    round(collab_anchor_acu, 2) as "合作主播整体有效ACU",
    round(selected_six_acu, 2) as "合作主播整体加莫拉塔有效ACU",
    round(market_valid_acu, 2) as "无畏契约大盘有效ACU",
    round(non_collab_market_valid_acu, 2) as "非合作大盘有效ACU",
    round(collab_anchor_acu / nullif(market_valid_acu, 0), 6) as "合作主播整体大盘占比",
    round(selected_six_acu / nullif(market_valid_acu, 0), 6) as "合作主播整体加莫拉塔大盘占比"
from daily_with_group
order by dt;


-- =====================================================================
-- 输出3：合作前 / 联播期 / 合作后 窗口汇总（可独立执行）
-- 日均以完整自然日为分母：合作前30天、联播期7天、合作后30天。
-- =====================================================================
with anchor_day_raw as (
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

anchor_day as (
    select
        dt,
        r_lid,
        max(valid_acu) as valid_acu
    from anchor_day_raw
    group by dt, r_lid
),

market_day as (
    select
        cast(dt as date) as dt,
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

daily as (
    select
        m.dt,
        coalesce(max(case when a.r_lid = '688292233649' then a.valid_acu end), 0) as molata_acu,
        coalesce(max(case when a.r_lid = '928481163143' then a.valid_acu end), 0) as eq118_acu,
        coalesce(max(case when a.r_lid = '4577510133' then a.valid_acu end), 0) as aijiang_acu,
        coalesce(max(case when a.r_lid = '67556051524' then a.valid_acu end), 0) as sensen_acu,
        coalesce(max(case when a.r_lid = '971406464239' then a.valid_acu end), 0) as yuemang_acu,
        coalesce(max(case when a.r_lid = '559868704090' then a.valid_acu end), 0) as xiaoze_acu,
        m.market_valid_acu,
        m.non_collab_market_valid_acu
    from market_day m
    left join anchor_day a
        on m.dt = a.dt
    group by m.dt, m.market_valid_acu, m.non_collab_market_valid_acu
),

metric_daily as (
    select
        dt,
        '莫拉塔' as metric,
        molata_acu as valid_acu
    from daily

    union all

    select
        dt,
        '合作主播整体' as metric,
        eq118_acu + aijiang_acu + sensen_acu + yuemang_acu + xiaoze_acu as valid_acu
    from daily

    union all

    select
        dt,
        '合作主播整体加莫拉塔' as metric,
        molata_acu + eq118_acu + aijiang_acu + sensen_acu + yuemang_acu + xiaoze_acu as valid_acu
    from daily

    union all

    select
        dt,
        '无畏契约大盘' as metric,
        market_valid_acu as valid_acu
    from daily

    union all

    select
        dt,
        '非合作大盘_剔莫拉塔及合作主播' as metric,
        non_collab_market_valid_acu as valid_acu
    from daily
),

window_summary as (
    select
        case
            when dt between date '2026-05-25' and date '2026-06-23' then '合作前30天'
            when dt between date '2026-06-24' and date '2026-06-30' then '联播期'
            when dt between date '2026-07-01' and date '2026-07-30' then '合作后30天'
        end as window_name,
        metric,
        count(*) as calendar_day_cnt,
        avg(valid_acu) as avg_valid_acu
    from metric_daily
    group by 1, 2
)

select
    window_name as "窗口",
    metric as "指标",
    calendar_day_cnt as "自然日天数",
    round(avg_valid_acu, 2) as "日均有效ACU",
    round(
        avg_valid_acu
        / nullif(
            max(case when window_name = '合作前30天' then avg_valid_acu end)
                over (partition by metric),
            0
        ) - 1,
        6
    ) as "较合作前增幅"
from window_summary
order by
    case window_name
        when '合作前30天' then 1
        when '联播期' then 2
        when '合作后30天' then 3
    end,
    case metric
        when '莫拉塔' then 1
        when '合作主播整体' then 2
        when '合作主播整体加莫拉塔' then 3
        when '无畏契约大盘' then 4
        when '非合作大盘_剔莫拉塔及合作主播' then 5
    end;

