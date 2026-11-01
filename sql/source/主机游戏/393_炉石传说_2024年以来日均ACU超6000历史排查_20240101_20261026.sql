-- 目的：排查 393（炉石传说）自 2024 年以来是否出现日均 ACU > 6000 的主播。
-- 窗口：2024-01-01 至 2026-10-26（实际最新可用分区）。
-- 粒度：主播一行，同时给出 2024 / 2025 / 2026 年至今日均、单月达标次数、单日达标次数。
-- ACU 口径：
--   1. 主播 × 日 day_acu = avg(acu)。
--   2. 有效开播日：当天 393 品类累计 live_mins × 60 >= 15 分钟。
--   3. 各层级日均 ACU 均为有效开播日等权平均。
-- 输出：只要满足以下任一口径的主体：
--   2024以来整体日均 > 6000，或任一年度日均 > 6000，或任一月份日均 > 6000。

with

anchor_day as (
    select
        cast(ayyuid as varchar) as uid,
        cast(dt as varchar) as dt,
        max(cast(nickname as varchar)) as nickname,
        avg(cast(acu as double)) as day_acu
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2024-01-01' and '2026-10-26'
      and cast(gameid as varchar) = '393'
    group by
        cast(ayyuid as varchar),
        cast(dt as varchar)
    having sum(coalesce(cast(live_mins as double), 0.0)) * 60 >= 15
),

-- 2024 以来整体表现
overall_anchor as (
    select
        uid,
        max(nickname) as nickname,
        count(distinct dt) as days,
        avg(day_acu) as avg_acu,
        max(day_acu) as max_day_acu,
        count(distinct case when day_acu > 6000 then dt end) as days_gt_6000
    from anchor_day
    group by uid
),

-- 主播 × 月
month_anchor as (
    select
        uid,
        substr(dt, 1, 7) as month,
        max(nickname) as nickname,
        count(distinct dt) as days,
        avg(day_acu) as avg_acu
    from anchor_day
    group by uid, substr(dt, 1, 7)
),

month_summary as (
    select
        uid,
        count(case when avg_acu > 6000 then 1 end) as months_gt_6000,
        max(avg_acu) as max_month_acu,
        max(case when avg_acu > 6000 then avg_acu end) as max_qualified_month_acu
    from month_anchor
    group by uid
),

-- 主播 × 年
year_anchor as (
    select
        uid,
        substr(dt, 1, 4) as year,
        avg(day_acu) as avg_acu
    from anchor_day
    group by uid, substr(dt, 1, 4)
),

year_pivot as (
    select
        uid,
        max(case when year = '2024' then avg_acu end) as avg_2024,
        max(case when year = '2025' then avg_acu end) as avg_2025,
        max(case when year = '2026' then avg_acu end) as avg_2026
    from year_anchor
    group by uid
)

select
    a.uid as "主播UID",
    a.nickname as "主播昵称",
    a.days as "有效开播天数",
    round(a.avg_acu, 2) as "2024以来日均ACU",
    a.days_gt_6000 as "单日ACU超6000天数",
    round(a.max_day_acu, 2) as "单日最高ACU",
    round(y.avg_2024, 2) as "2024年度日均ACU",
    round(y.avg_2025, 2) as "2025年度日均ACU",
    round(y.avg_2026, 2) as "2026年至今日均ACU",
    m.months_gt_6000 as "单月日均超6000月份数",
    round(m.max_qualified_month_acu, 2) as "达标月份最高日均ACU"
from overall_anchor a
join month_summary m
  on a.uid = m.uid
join year_pivot y
  on a.uid = y.uid
where a.avg_acu > 6000
   or y.avg_2024 > 6000
   or y.avg_2025 > 6000
   or y.avg_2026 > 6000
   or m.months_gt_6000 > 0
order by a.avg_acu desc;
