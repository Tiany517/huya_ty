-- =====================================================================
-- 目的：莫拉塔联播合作效果 - 单次查询版（含主播明细、群组及无畏契约大盘占比）
-- 数据源：gamelive.dm_mkt_rowner_day
-- 执行引擎：Presto
--
-- 时间口径：
--   合作前30天：2026-05-25 ~ 2026-06-23
--   联播期：    2026-06-24 ~ 2026-06-30
--   合作后30天：2026-07-01 ~ 2026-07-30
--
-- 有效ACU：cast(ext['vaild_acu'] as double)
-- 主播明细不限制 r_category：联播事实由业务确认，品类标签不作为联播判定。
-- 大盘限制 r_category = '无畏契约'：代表 douyin_web 无畏契约全市场。
--
-- 合作主播：
--   EQ118       928481163143
--   哀酱        4577510133
--   森森        67556051524
--   月芒zzZ     971406464239
--   小泽老师    559868704090
-- 莫拉塔：688292233649
--
-- 输出粒度：日期 × 指标
-- 指标包括：6位主播明细、合作主播整体、合作主播整体加莫拉塔、
--           无畏契约大盘、非合作大盘（剔除莫拉塔和5位合作主播）。
-- =====================================================================

with selected_anchor_day_raw as (
    -- 6位圈选主播的原始日记录；不按品类过滤
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
    -- 统一到 主播×日；同日多条记录时取有效ACU最高值，避免重复相加
    select
        dt,
        r_lid,
        max(valid_acu) as valid_acu
    from selected_anchor_day_raw
    group by dt, r_lid
),

market_day as (
    -- douyin_web 无畏契约大盘，以及剔除本次6位圈选主播后的非合作大盘
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

daily_wide as (
    -- 先形成 日期×6位主播 的宽表，再计算合作群组
    select
        m.dt,
        case
            when m.dt between date '2026-05-25' and date '2026-06-23' then '合作前30天'
            when m.dt between date '2026-06-24' and date '2026-06-30' then '联播期'
            when m.dt between date '2026-07-01' and date '2026-07-30' then '合作后30天'
        end as window_name,
        coalesce(max(case when a.r_lid = '688292233649' then a.valid_acu end), 0) as molata_acu,
        coalesce(max(case when a.r_lid = '928481163143' then a.valid_acu end), 0) as eq118_acu,
        coalesce(max(case when a.r_lid = '4577510133' then a.valid_acu end), 0) as aijiang_acu,
        coalesce(max(case when a.r_lid = '67556051524' then a.valid_acu end), 0) as sensen_acu,
        coalesce(max(case when a.r_lid = '971406464239' then a.valid_acu end), 0) as yuemang_acu,
        coalesce(max(case when a.r_lid = '559868704090' then a.valid_acu end), 0) as xiaoze_acu,
        m.market_valid_acu,
        m.non_collab_market_valid_acu
    from market_day m
    left join selected_anchor_day a
        on m.dt = a.dt
    group by
        m.dt,
        m.market_valid_acu,
        m.non_collab_market_valid_acu
),

metric_day as (
    -- 主播明细
    select dt, window_name, '主播明细' as metric_type, '莫拉塔' as metric_name,
           molata_acu as valid_acu, market_valid_acu
    from daily_wide

    union all

    select dt, window_name, '主播明细', 'EQ118', eq118_acu, market_valid_acu
    from daily_wide

    union all

    select dt, window_name, '主播明细', '哀酱', aijiang_acu, market_valid_acu
    from daily_wide

    union all

    select dt, window_name, '主播明细', '森森', sensen_acu, market_valid_acu
    from daily_wide

    union all

    select dt, window_name, '主播明细', '月芒zzZ', yuemang_acu, market_valid_acu
    from daily_wide

    union all

    select dt, window_name, '主播明细', '小泽老师', xiaoze_acu, market_valid_acu
    from daily_wide

    union all

    -- 5位合作主播整体，不含莫拉塔
    select
        dt,
        window_name,
        '主播群组' as metric_type,
        '合作主播整体' as metric_name,
        eq118_acu + aijiang_acu + sensen_acu + yuemang_acu + xiaoze_acu as valid_acu,
        market_valid_acu
    from daily_wide

    union all

    -- 5位合作主播 + 莫拉塔
    select
        dt,
        window_name,
        '主播群组' as metric_type,
        '合作主播整体加莫拉塔' as metric_name,
        molata_acu + eq118_acu + aijiang_acu + sensen_acu + yuemang_acu + xiaoze_acu as valid_acu,
        market_valid_acu
    from daily_wide

    union all

    -- 原始无畏契约大盘，不剔除任何账号
    select
        dt,
        window_name,
        '大盘' as metric_type,
        '无畏契约大盘' as metric_name,
        market_valid_acu as valid_acu,
        market_valid_acu
    from daily_wide

    union all

    -- 无畏契约大盘剔除莫拉塔与5位合作主播
    select
        dt,
        window_name,
        '大盘' as metric_type,
        '非合作大盘_剔莫拉塔及合作主播' as metric_name,
        non_collab_market_valid_acu as valid_acu,
        market_valid_acu
    from daily_wide
),

metric_window as (
    -- 计算每个主播/群组在各窗口的日均ACU与窗口大盘占比
    select
        window_name,
        metric_name,
        count(*) as calendar_day_cnt,
        avg(valid_acu) as window_avg_valid_acu,
        sum(valid_acu) / nullif(sum(market_valid_acu), 0) as window_market_share
    from metric_day
    group by window_name, metric_name
),

metric_window_with_pre as (
    select
        window_name,
        metric_name,
        calendar_day_cnt,
        window_avg_valid_acu,
        window_market_share,
        max(
            case
                when window_name = '合作前30天' then window_avg_valid_acu
            end
        ) over (partition by metric_name) as pre_window_avg_valid_acu
    from metric_window
)

select
    cast(d.dt as varchar) as "日期",
    d.window_name as "窗口",
    d.metric_type as "指标类型",
    d.metric_name as "指标",
    round(d.valid_acu, 2) as "当日有效ACU",
    round(d.market_valid_acu, 2) as "当日无畏契约大盘有效ACU",
    round(d.valid_acu / nullif(d.market_valid_acu, 0), 6) as "当日大盘占比",
    w.calendar_day_cnt as "窗口自然日天数",
    round(w.window_avg_valid_acu, 2) as "窗口日均有效ACU",
    round(w.window_market_share, 6) as "窗口大盘占比",
    round(
        w.window_avg_valid_acu / nullif(w.pre_window_avg_valid_acu, 0) - 1,
        6
    ) as "窗口较合作前ACU增幅"
from metric_day d
left join metric_window_with_pre w
    on d.window_name = w.window_name
    and d.metric_name = w.metric_name
order by
    d.dt,
    case d.metric_type
        when '主播明细' then 1
        when '主播群组' then 2
        when '大盘' then 3
    end,
    case d.metric_name
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

