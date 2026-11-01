-- ============================================================
-- 无畏契约（gameid = 5937）2026-09-01 ~ 2026-09-30 整月：主播层级 ACU 分布
--
-- 跟单日版（无畏契约_20260930_主播层级ACU分布_20261009.sql）的区别：
--   单日版：分层用「当天 ACU」
--   整月版：分层用「该主播当月日均 ACU」= 当月各开播日 ACU 的算术平均
--           （沿用 各等级主播的月ACU均值.sql 和 无畏契约 Top20 综合指标 SQL 的月日均口径）
--
-- 源表：gamelive.dm_huya_ayyuid_detail_day（主播 x 日 x 品类）
--   过滤：dt between '2026-09-01' and '2026-09-30'、gameid = 5937、live_hours_only_live > 0
--
-- 口径：
--   1. 月日均ACU = 该主播 9 月「开播日」的 acu 算术平均（分母 = 当月开播天数，不是 30）
--      —— 分层用的是它，这样和单日版都是一个"人数"量级，可比
--   2. 月累计ACU = 当月各天 acu 直接相加（sum），是"人日"口径，量级会被开播天数放大，
--      只作参考列，不用来分层（要看它分层用文末「可选口径 2」）
--   3. 分层阈值沿用四层写法：头部 >=2000 / 颈部 1000~2000 / 腰部 100~1000 / 尾部 <100
--      （要三层就把 case 里颈部那段删掉）
--   4. ACU 按主播累加（各层主播的月日均ACU 之和），同一观众看多个主播会重复计数，
--      不等于该品类在线总人数
--   5. 只统计当月有开播记录的主播；波动提醒：只开播 1~2 天的主播月日均ACU 抖动大，
--      想更稳可在 anchor_month 后加 live_days >= 3（文末给了写法）
--
-- 输出：主播层级 / 主播数 / 主播数占比 / 开播天数合计 / 月日均ACU合计 / ACU占比 /
--       人均月日均ACU / 月累计ACU合计（含合计行）
-- ============================================================
with

-- 1) 主播日明细：先做分区时间 + 业务条件过滤，再按 主播 x 日 汇总
anchor_day as (
    select
        substr(cast(dt as varchar), 1, 10) as dt,
        cast(ayyuid as varchar) as luid,   -- 统一 varchar，避免 ID 类型混比
        max(nickname) as nickname,
        sum(acu) as acu                    -- 正常一个主播一天该品类一行，sum 就等于原值
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2026-09-01' and '2026-09-30'
      and gameid = 5937
      and live_hours_only_live > 0
    group by
        substr(cast(dt as varchar), 1, 10),
        cast(ayyuid as varchar)
),

-- 2) 主播月口径：开播天数 / 月累计ACU / 月日均ACU
anchor_month as (
    select
        luid,
        max(nickname) as nickname,
        count(distinct dt) as live_days,
        sum(acu) as acu_sum_month,          -- 月累计ACU（人日）
        avg(acu) as acu_avg_day             -- 月日均ACU（按开播日平均，用于分层）
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
-- 【校验 / 可选】把上面的主查询换成下面任意一段即可，with 里的 CTE 都不用动
-- ============================================================
--
-- 校验 1：9 月分区覆盖（days 应该是 30；少于 30 说明有缺分区，占比会被扭曲）
--
-- select
--     count(distinct substr(cast(dt as varchar), 1, 10)) as "9月有数据的天数",
--     count(distinct cast(ayyuid as varchar)) as "当月开播主播数",
--     sum(acu) as "月累计ACU合计",
--     round(avg(acu), 1) as "行级平均acu"
-- from gamelive.dm_huya_ayyuid_detail_day
-- where dt between '2026-09-01' and '2026-09-30'
--   and gameid = 5937
--   and live_hours_only_live > 0;
--
-- 校验 2：单主播开播天数分布（看有多少主播只开播 1~2 天，他们的月日均ACU 最不稳）
--
-- select
--     case when live_days >= 20 then '20天以上'
--          when live_days >= 10 then '10~19天'
--          when live_days >= 3  then '3~9天'
--          else '1~2天' end as "开播天数档",
--     count(*) as "主播数",
--     round(avg(acu_avg_day), 1) as "平均月日均ACU",
--     round(avg(acu_sum_month), 0) as "平均月累计ACU"
-- from anchor_month
-- group by 1
-- order by 1;
--
-- 校验 3：主播级明细（哪个人落在哪一层，按月日均ACU 降序看层级边界）
--
-- select
--     luid as "主播uid",
--     nickname as "主播昵称",
--     live_days as "开播天数",
--     round(acu_avg_day, 1) as "月日均ACU",
--     round(acu_sum_month, 0) as "月累计ACU",
--     acu_type as "主播层级"
-- from anchor_tier
-- order by acu_avg_day desc;
--
-- ============================================================
-- 可选口径 2：改用「月累计ACU」分层（量级会偏向开播天数多的主播，一般不推荐）
--   把 anchor_tier 里的 case 条件换成 acu_sum_month 的阈值（下面按 x30 折算成月累计）：
--     when acu_sum_month >= 2000 * live_days then '头部'
--     when acu_sum_month >= 1000 * live_days then '颈部'
--     when acu_sum_month >= 100  * live_days then '腰部'
--   —— 注意这样等价于还是按日均分层；如果真要按"总量"分层，用固定阈值：
--     when acu_sum_month >= 60000 then '头部'
--     when acu_sum_month >= 30000 then '颈部'
--     when acu_sum_month >= 3000  then '腰部'
-- ============================================================
--
-- ============================================================
-- 可选视角 3：逐日 x 层级 的 ACU 矩阵（想画 9 月每天各层的变化曲线用这个）
--   把主查询换成：
--
-- select
--     d.dt as "日期",
--     t.acu_type as "主播层级",
--     count(distinct t.luid) as "主播数",
--     sum(d.acu) as "当日ACU合计"
-- from anchor_day d
-- inner join anchor_tier t
--     on d.luid = t.luid
-- group by
--     d.dt,
--     t.acu_type
-- order by
--     d.dt,
--     case t.acu_type
--         when '头部' then 1 when '颈部' then 2 when '腰部' then 3 else 4
--     end;
--   —— 注意：这里的层级是「整月」的层，逐日只是看同一批主播每天的表现，
--      不是每天重新分层（要每天重新分层，用单日版那份 SQL 把 dt 改成 between）
-- ============================================================
--
-- 可选：只要开播 >= 3 天的主播（月日均ACU 更稳）
--   在 anchor_month 之后、anchor_tier 之前加一个 CTE 过滤：
--   anchor_month_valid as (
--       select * from anchor_month where live_days >= 3
--   )  然后把 anchor_tier 的 from anchor_month 改成 anchor_month_valid
-- ============================================================

