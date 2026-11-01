-- ============================================================
-- 英雄联盟（gameid = 1）主播层级 ACU 分布【有效窗口 2026-09-20 ~ 2026-09-30】
--
-- 基准版 = 你 2026-10-09 发来的那份，本次修正：
--
--   1【窗口写法】你写的是
--         dt between '2026-09-01' and '2026-09-30'
--         and dt not between '2026-09-01' and '2026-09-19'
--      结果等价于「只保留 9/20 ~ 9/30（11 天）」，但两行放一起很容易看错。
--      这里直接写成 dt between '2026-09-20' and '2026-09-30'。
--      ★ 如果本意其实是「剔除赛事日」（赛事日不是连续的 9/1~9/19），告诉我赛事名单，我换成排除列表。
--
--   2【分组 bug】把外层 group by 从 (luid, nickname) 改成 (luid)。
--      原来同一主播在一个窗口内改过昵称，会被拆成两行 —— 而 count(distinct luid) 又只算 1 个主播，
--      于是"主播数"和"ACU合计"口径不一致：ACU合计重复计了这个人，甚至可能把同一个人算进两个层级。
--      昵称改成 max_by(nickname, dt)：取窗口内最后一次开播日的昵称。
--
--   3【注释过期】内层原来写的是 sum(acu) 且注释"sum 就等于原值"，
--      现在这里已经是「按主播 x 日 汇总」，外层再做跨天平均，所以注释改成了正确描述。
--      第 2 步注释里的"按当天 ACU 分层"也改掉了 —— 现在分层用的是「窗口日均ACU」，不是单日 ACU。
--
--   4【口径可复盘】多输出一列「开播天数合计」，方便确认 11 天窗口里主播到底开了几天。
--      不要这列的话，删掉 t.live_days_sum 和 tot.live_days_sum 两处即可。
--
-- 口径：
--   - 源表 gamelive.dm_huya_ayyuid_detail_day，gameid = 1（英雄联盟），
--     live_hours_only_live > 0（当天真的开播）
--   - 窗口 2026-09-20 ~ 2026-09-30 共 11 天（= 9 月剔掉 9/1~9/19）
--   - ACU 口径：先按「主播 x 日」取当天 acu，再对该主播在窗口内有开播的天取算术平均
--     → 所以下面所有 "ACU合计 / 人均ACU" 都是「窗口日均ACU」量级，不是单日 ACU、也不是人日累计
--   - 分层阈值：头部 >=2000 / 颈部 1000~2000 / 腰部 100~1000 / 尾部 <100
--   - ACU 按主播累加（各层主播窗口日均ACU 之和）；同一观众看多个主播会重复计数
--
-- 输出：主播层级 / 主播数 / 主播数占比 / 开播天数合计 / ACU合计 / ACU占比 / 人均ACU（含合计行）
-- ============================================================
with

-- 1) 主播日明细：先汇总到「主播 x 日」，再汇总到「主播」
anchor_day as (
    select
        luid,
        max_by(nickname, dt) as nickname,   -- 窗口内最后一次开播日的昵称
        count(distinct dt) as live_days,    -- 窗口内开播天数
        avg(acu) as acu                     -- 窗口日均ACU（分母 = 该主播窗口内开播天数）
    from (
        select
            substr(cast(dt as varchar), 1, 10) as dt,
            cast(ayyuid as varchar) as luid,        -- 统一 varchar，避免和别处的 ID 类型混比
            max(nickname) as nickname,
            coalesce(avg(acu), 0) as acu            -- 主播 x 日：当天该品类 acu（正常只有一行）
        from gamelive.dm_huya_ayyuid_detail_day
        where dt between '2026-09-20' and '2026-09-30'   -- 【窗口】9 月剔掉 9/1~9/19 后的 11 天
          and gameid = 1                                  -- 英雄联盟
          and live_hours_only_live > 0
        group by
            substr(cast(dt as varchar), 1, 10),
            cast(ayyuid as varchar)
    ) t
    group by
        luid                                            -- 【修正】只按 luid 分组
),

-- 2) 按「窗口日均ACU」分层
anchor_tier as (
    select
        luid,
        nickname,
        live_days,
        acu,
        case
            when acu >= 2000 then '头部'
            when acu >= 1000 then '颈部'
            when acu >= 100 then '腰部'
            else '尾部'
        end as acu_type
    from anchor_day
),

-- 3) 分层聚合
tier_agg as (
    select
        acu_type,
        count(distinct luid) as anchor_cnt,
        sum(live_days) as live_days_sum,
        sum(acu) as acu_sum
    from anchor_tier
    group by
        acu_type
),

-- 4) 整体合计（只有 1 行，用于算占比；这里 cross join 是刻意的，就为拼合计行）
total as (
    select
        count(distinct luid) as anchor_cnt,
        sum(live_days) as live_days_sum,
        sum(acu) as acu_sum
    from anchor_tier
)

-- 主查询：各层 + 合计
select
    t.acu_type as "主播层级",
    t.anchor_cnt as "主播数",
    round(t.anchor_cnt * 100.0 / nullif(tot.anchor_cnt, 0), 2) as "主播数占比(%)",
    t.live_days_sum as "开播天数合计",
    round(t.acu_sum, 1) as "ACU合计",
    round(t.acu_sum * 100.0 / nullif(tot.acu_sum, 0), 2) as "ACU占比(%)",
    round(t.acu_sum / nullif(t.anchor_cnt, 0), 1) as "人均ACU"
from tier_agg t
cross join total tot

union all

select
    '合计' as "主播层级",
    tot.anchor_cnt as "主播数",
    100.00 as "主播数占比(%)",
    tot.live_days_sum as "开播天数合计",
    round(tot.acu_sum, 1) as "ACU合计",
    100.00 as "ACU占比(%)",
    round(tot.acu_sum / nullif(tot.anchor_cnt, 0), 1) as "人均ACU"
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
-- 【校验 SQL】把主查询换成下面任意一段即可，with 里的 CTE 都不用动
-- ============================================================
--
-- 校验 1：窗口是不是真的只剩 11 天，且这 11 天里有数据
--
-- select
--     count(distinct substr(cast(dt as varchar), 1, 10)) as "有数据天数",
--     min(substr(cast(dt as varchar), 1, 10)) as "最早日",
--     max(substr(cast(dt as varchar), 1, 10)) as "最晚日",
--     count(distinct cast(ayyuid as varchar)) as "开播主播数"
-- from gamelive.dm_huya_ayyuid_detail_day
-- where dt between '2026-09-20' and '2026-09-30'
--   and gameid = 1
--   and live_hours_only_live > 0;
--
-- 校验 2：有没有「同一主播窗口内改过昵称」（上面第 2 条修正就是这个原因）
--   dup_nick_anchor_cnt > 0 说明原来 group by (luid, nickname) 会拆行
--
-- select
--     count_if(nick_cnt > 1) as "同主播多昵称数"
-- from (
--     select
--         cast(ayyuid as varchar) as luid,
--         count(distinct nickname) as nick_cnt
--     from gamelive.dm_huya_ayyuid_detail_day
--     where dt between '2026-09-20' and '2026-09-30'
--       and gameid = 1
--       and live_hours_only_live > 0
--     group by cast(ayyuid as varchar)
-- ) t;
--
-- 校验 3：剔除前（9月整月）vs 剔除后（9/20~9/30）对比 —— 看被剔掉的 19 天影响多大
--
-- select
--     '9/20~9/30(11天)' as "口径",
--     count(distinct cast(ayyuid as varchar)) as "开播主播数",
--     sum(acu) as "ACU累加",
--     round(avg(acu), 1) as "行级平均acu"
-- from gamelive.dm_huya_ayyuid_detail_day
-- where dt between '2026-09-20' and '2026-09-30'
--   and gameid = 1
--   and live_hours_only_live > 0
-- union all
-- select
--     '9月整月(30天)',
--     count(distinct cast(ayyuid as varchar)),
--     sum(acu),
--     round(avg(acu), 1)
-- from gamelive.dm_huya_ayyuid_detail_day
-- where dt between '2026-09-01' and '2026-09-30'
--   and gameid = 1
--   and live_hours_only_live > 0;
--
-- 校验 4：主播级明细（看层级边界和开播天数分布）
--
-- select
--     luid as "主播uid",
--     nickname as "主播昵称",
--     live_days as "开播天数",
--     round(acu, 1) as "窗口日均ACU",
--     acu_type as "主播层级"
-- from anchor_tier
-- order by acu desc;
--
-- ============================================================
-- 【小提醒】gameid 的类型
--   这里沿用你原来的 gameid = 1 写法；你们别的 SQL 里同一张表也出现过 gameid = '5937'（带引号）。
--   如果某次报「类型不匹配」，用 describe gamelive.dm_huya_ayyuid_detail_day 确认，
--   必要时统一写成 cast(gameid as varchar) = '1'。
-- ============================================================

