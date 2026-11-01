-- 目的：查找 2026-04-01 至 2026-09-30 期间，品类 393（炉石传说）或 1964（主机游戏）中，
--       日均 ACU > 6000 的主播；同时按单月拆分，单月日均 ACU > 6000 也会输出。
-- 粒度：
--   1. 主播 × 品类（4-9 月整体）
--   2. 主播 × 品类 × 月份（单月）
-- ACU 口径：
--   1. 先聚合到主播 × 品类 × 日，day_acu = avg(acu)。
--   2. 有效开播日：当天所选品类累计 live_mins × 60 >= 15 分钟，沿用四品类 ACU SQL 口径。
--   3. 4-9 月日均 ACU：全部有效开播日的 day_acu 等权平均。
--   4. 单月日均 ACU：当月全部有效开播日的 day_acu 等权平均。
-- 输出：只保留对应层级日均 ACU > 6000 的主播。

with

-- 主播 × 品类 × 日；393=炉石传说，1964=主机游戏
anchor_day as (
    select
        cast(gameid as varchar) as game_id,
        cast(ayyuid as varchar) as uid,
        cast(dt as varchar) as dt,
        max(cast(nickname as varchar)) as nickname,
        avg(cast(acu as double)) as day_acu
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2026-04-01' and '2026-09-30'
      and cast(gameid as varchar) in ('393', '1964')
    group by
        cast(gameid as varchar),
        cast(ayyuid as varchar),
        cast(dt as varchar)
    having sum(coalesce(cast(live_mins as double), 0.0)) * 60 >= 15
),

-- 4-9 月整体：主播 × 品类一行
period_anchor as (
    select
        game_id,
        uid,
        max(nickname) as nickname,
        count(distinct dt) as valid_days,
        count(distinct substr(dt, 1, 7)) as active_months,
        avg(day_acu) as avg_daily_acu,
        max(day_acu) as max_day_acu
    from anchor_day
    group by game_id, uid
),

-- 单月：主播 × 品类 × 月份一行
month_anchor as (
    select
        game_id,
        substr(dt, 1, 7) as month,
        uid,
        max(nickname) as nickname,
        count(distinct dt) as valid_days,
        avg(day_acu) as avg_daily_acu,
        max(day_acu) as max_day_acu
    from anchor_day
    group by game_id, substr(dt, 1, 7), uid
)

select
    '4-9月整体' as "统计层级",
    null as "月份",
    game_id as "品类ID",
    case game_id
        when '393' then '炉石传说'
        when '1964' then '主机游戏'
    end as "品类",
    uid as "主播UID",
    nickname as "主播昵称",
    valid_days as "有效开播天数",
    active_months as "有效开播月数",
    round(avg_daily_acu, 2) as "日均ACU",
    round(max_day_acu, 2) as "单日最高ACU"
from period_anchor
where avg_daily_acu > 6000

union all

select
    '单月' as "统计层级",
    month as "月份",
    game_id as "品类ID",
    case game_id
        when '393' then '炉石传说'
        when '1964' then '主机游戏'
    end as "品类",
    uid as "主播UID",
    nickname as "主播昵称",
    valid_days as "有效开播天数",
    1 as "有效开播月数",
    round(avg_daily_acu, 2) as "日均ACU",
    round(max_day_acu, 2) as "单日最高ACU"
from month_anchor
where avg_daily_acu > 6000

order by
    case when "统计层级" = '4-9月整体' then 0 else 1 end,
    "品类ID",
    "月份",
    "日均ACU" desc;
