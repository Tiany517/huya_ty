-- ============================================================
-- 无畏契约（gameid = 5937）2026-09 整月：主播层级 ACU 分布【剔除 09-03 ~ 09-13 赛事日】
--
-- 基准版 = 无畏契约_202609_主播层级月ACU分布_20261009.sql，本次唯一改动：
--   anchor_day 的 where 里加一行，把这 11 天整个剔掉：
--       and dt not between '2026-09-03' and '2026-09-13'
--
-- 剔除后的影响（重要，别和未剔除版直接比）：
--   1. 有效窗口从 30 天变成 19 天（09-01、09-02、09-14 ~ 09-30）
--   2. 开播天数 / 月累计ACU / 月日均ACU 全部按「剔完之后剩下的天」重算
--      - 月日均ACU 的分母 = 该主播在剩下的 19 天里有开播的天数（不是 19，也不是 30）
--      - 月累计ACU是"人日"，剔了 11 天自然变小 → 不要和未剔除版比大小
--      - 月日均ACU 可以和未剔除版比（同一套剔除逻辑下的日均）
--   3. 分层用月日均ACU，所以某主播被剔掉的那 11 天本来是头部/尾部的极端值，
--      剔完后层级可能变化 —— 这是预期行为
--
-- 口径（未改动部分沿基准版）：
--   - 源表 gamelive.dm_huya_ayyuid_detail_day，gameid = 5937，
--     live_hours_only_live > 0（当天真的开播）
--   - 分层阈值：头部 >=2000 / 颈部 1000~2000 / 腰部 100~1000 / 尾部 <100
--   - ACU 按主播累加（各层主播月日均ACU 之和）；同一观众看多个主播会重复计数
--
-- 输出：主播层级 / 主播数 / 主播数占比 / 开播天数合计 / 月日均ACU合计 / ACU占比 /
--       人均月日均ACU / 月累计ACU合计（含合计行）
-- ============================================================
with

-- 1) 主播日明细：分区时间 + 业务条件过滤（这里剔掉 09-03 ~ 09-13 赛事日）
anchor_day as (
    select
        substr(cast(dt as varchar), 1, 10) as dt,
        cast(ayyuid as varchar) as luid,   -- 统一 varchar，避免 ID 类型混比
        max(nickname) as nickname,
        sum(acu) as acu                    -- 正常一个主播一天该品类一行，sum 就等于原值
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2026-09-01' and '2026-09-30'
      and dt not between '2026-09-03' and '2026-09-13'   -- 【本次改动】剔除 11 天赛事日
      and gameid = 5937
      and live_hours_only_live > 0
    group by
        substr(cast(dt as varchar), 1, 10),
        cast(ayyuid as varchar)
),

-- 2) 主播月口径：开播天数 / 月累计ACU / 月日均ACU（都基于剔除后的 19 天窗口）
anchor_month as (
    select
        luid,
        max(nickname) as nickname,
        count(distinct dt) as live_days,
        sum(acu) as acu_sum_month,          -- 月累计ACU（人日，已剔 11 天）
        avg(acu) as acu_avg_day             -- 月日均ACU（分母 = 剔除后该主播的开播天数）
    from anchor_day
    group by
        luid
),

-- 3) 按「月日均ACU」分层
anchor_tier as (
    select
        luid,
        nickname,
        live_days,
        acu_sum_month,
        acu_avg_day,
        case
            when acu_avg_day >= 2000 then '头部'
            when acu_avg_day >= 1000 then '颈部'
            when acu_avg_day >= 100 then '腰部'
            else '尾部'
        end as acu_type
    from anchor_month
),

-- 4) 分层聚合
tier_agg as (
    select
        acu_type,
        count(distinct luid) as anchor_cnt,
        sum(live_days) as live_days_sum,
        sum(acu_avg_day) as acu_avg_sum,
        sum(acu_sum_month) as acu_sum_month
    from anchor_tier
    group by
        acu_type
),

-- 5) 整体合计（1 行，用于算占比；cross join 是刻意为之，只为拼合计行）
total as (
    select
        count(distinct luid) as anchor_cnt,
        sum(live_days) as live_days_sum,
        sum(acu_avg_day) as acu_avg_sum,
        sum(acu_sum_month) as acu_sum_month
    from anchor_tier
)

-- 主查询：各层 + 合计
select
    t.acu_type as "主播层级",
    t.anchor_cnt as "主播数",
    round(t.anchor_cnt * 100.0 / nullif(tot.anchor_cnt, 0), 2) as "主播数占比(%)",
    t.live_days_sum as "开播天数合计",
    round(t.acu_avg_sum, 1) as "月日均ACU合计",
    round(t.acu_avg_sum * 100.0 / nullif(tot.acu_avg_sum, 0), 2) as "ACU占比(%)",
    round(t.acu_avg_sum / nullif(t.anchor_cnt, 0), 1) as "人均月日均ACU",
    round(t.acu_sum_month, 0) as "月累计ACU合计(人日)"
from tier_agg t
cross join total tot

union all

select
    '合计' as "主播层级",
    tot.anchor_cnt as "主播数",
    100.00 as "主播数占比(%)",
    tot.live_days_sum as "开播天数合计",
    round(tot.acu_avg_sum, 1) as "月日均ACU合计",
    100.00 as "ACU占比(%)",
    round(tot.acu_avg_sum / nullif(tot.anchor_cnt, 0), 1) as "人均月日均ACU",
    round(tot.acu_sum_month, 0) as "月累计ACU合计(人日)"
from total tot

order by
    case "主播层级"
        when '头部' then 1
        when '颈部' then 2
        when '腰部' then 3
        when '尾部' then 4
        else 5
    end;


-- ============================================================
-- 【校验 / 可选】把主查询换成下面任意一段即可，with 里的 CTE 都不用动
-- ============================================================
--
-- 校验 1：确认剔除生效、且剩下的天数 = 19
--   有数据的天数应该是 19；如果还是 30，说明 not between 没生效（或被写在了聚合之后）
--
-- select
--     count(distinct substr(cast(dt as varchar), 1, 10)) as "剔除后剩余有数据天数",
--     min(substr(cast(dt as varchar), 1, 10)) as "最早日",
--     max(substr(cast(dt as varchar), 1, 10)) as "最晚日",
--     count(distinct cast(ayyuid as varchar)) as "开播主播数"
-- from gamelive.dm_huya_ayyuid_detail_day
-- where dt between '2026-09-01' and '2026-09-30'
--   and dt not between '2026-09-03' and '2026-09-13'
--   and gameid = 5937
--   and live_hours_only_live > 0;
--
-- 校验 2：剔除前 vs 剔除后 对比（看赛事日对整体盘子影响多大）
--   两段的 月累计ACU 差异就是那 11 天的量；月日均ACU 差异反映赛事日是不是更热
--
-- select
--     '剔除后(19天)' as "口径",
--     count(distinct ayyuid) as "开播主播数",
--     count(distinct substr(cast(dt as varchar),1,10)) as "窗口有数据天数",
--     sum(acu) as "月累计ACU",
--     round(avg(acu), 1) as "行级平均acu"
-- from gamelive.dm_huya_ayyuid_detail_day
-- where dt between '2026-09-01' and '2026-09-30'
--   and dt not between '2026-09-03' and '2026-09-13'
--   and gameid = 5937
--   and live_hours_only_live > 0
-- union all
-- select
--     '剔除前(30天)',
--     count(distinct ayyuid),
--     count(distinct substr(cast(dt as varchar),1,10)),
--     sum(acu),
--     round(avg(acu), 1)
-- from gamelive.dm_huya_ayyuid_detail_day
-- where dt between '2026-09-01' and '2026-09-30'
--   and gameid = 5937
--   and live_hours_only_live > 0;
--
-- 校验 3：主播级明细（看剔完 11 天后层级边界怎么变）
--
-- select
--     luid as "主播uid",
--     nickname as "主播昵称",
--     live_days as "开播天数(剔除后)",
--     round(acu_avg_day, 1) as "月日均ACU",
--     round(acu_sum_month, 0) as "月累计ACU",
--     acu_type as "主播层级"
-- from anchor_tier
-- order by acu_avg_day desc;
--
-- ============================================================
-- 【可选】不想硬编码赛事日：直接从赛事版权表自动取赛事日（更省事、可复盘）
--   如果这批赛事日以后还会变（比如换成 10 月、或赛事排期调整），
--   建议把 anchor_day 的 "dt not between ..." 换成下面这个写法：
--
--   先加一个 CTE：
--   excluded_dt as (
--       select distinct
--           substr(cast(a.date as varchar), 1, 10) as dt
--       from gamelive.dwd_huya_dim_game_copyright_info_d_a a
--       where a.dt = '2026-09-30'                        -- 快照分区日
--         and substr(cast(a.date as varchar), 1, 10) between '2026-09-01' and '2026-09-30'
--         and a.live_type like '%直播%'
--         and cast(a.game_id as varchar) = '5937'
--         -- 赛事名按需收窄，避免把普通排位直播也剔掉
--         -- and a.match_name in ('2026VCTCN第二赛段', ...)
--   ),
--
--   然后 anchor_day 里改成：
--     and not exists (select 1 from excluded_dt e where e.dt = substr(cast(dt as varchar), 1, 10))
--   （用 not exists 而不是 not in：子查询里万一有 NULL，not in 会让整个条件变 NULL、结果直接空表）
-- ============================================================

