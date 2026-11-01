-- ============================================================
-- 英雄联盟（gameid = 1）主播层级 ACU 分布【有效窗口 2026-09-20 ~ 2026-09-30】
--                        —— 分层用「日均ACU」，份额给「水平 / 承载」双口径
--
-- 相对上一版（英雄联盟_20260920至20260930_主播层级ACU分布_改正版_20261009.sql）的改动：
--
--   1【核心】把「分层依据」和「份额度量」拆成两个口径，不再混成一个数：
--        · 分层（谁进头部/颈部/腰部/尾部）  = 日均ACU（窗口内开播日的算术平均）
--          —— 层级标签描述的是「常态人气水平」，不能被开播天数带偏
--        · 份额（这层占多大）给两套，各自命名清楚：
--            日均ACU合计 / 日均ACU占比(%)    = 层级日常水平（Σ 各主播日均ACU）
--            累计ACU合计(人日) / 累计ACU占比(%) = 层级承载量（Σ 各主播窗口内累计ACU，时间加权）
--      两套占比各自都会等于 100%，不要互相混用，也不要问"为什么不等于那个"
--
--   2【保留】日均ACU 的分母 = 该主播在窗口内有开播的天数（不是 11，也不是 30）；
--      未开播日不参与，避免把"开播少"当成 ACU=0 混进人气口径
--
--   3【修正】外层只按 luid 分组，昵称用 max_by(nickname, dt) 取最后一次开播日的昵称
--      —— 原来 group by (luid, nickname) 遇到中途改昵称会拆行，和 count(distinct luid) 口径打架
--
--   4【可复盘】输出「开播天数合计」，并把三个占比放在一起（主播数占比 / 水平占比 / 承载占比），
--      一眼能看出"头部主播少、但吃掉多少 ACU"
--
--   5【可选】偶发开播的主播（只开播 1~2 天）日均ACU 抖动大，容易误分到头部/尾部。
--      要剔掉的话，把 anchor_tier 里那行注释放开（阈值自己定）：
--          where live_days >= 3
--
-- 口径：
--   - 源表 gamelive.dm_huya_ayyuid_detail_day，gameid = 1（英雄联盟），live_hours_only_live > 0
--   - 窗口 2026-09-20 ~ 2026-09-30（11 天）= 9 月剔掉 9/1~9/19
--   - 分层阈值（四层，作用在日均ACU 上）：头部 >=2000 / 颈部 1000~2000 / 腰部 100~1000 / 尾部 <100
--     注意阈值只在日均口径下成立；累计ACU 是"人日"，不能拿 2000 这种阈值去卡
--   - ACU 都是主播维度累加，同一观众看多个主播/跨天会重复计数
--     → 「累计ACU合计」只能当"人日承载量"，不能当"观看人数总量"（要人数总量得用 DAU 去重）
--
-- 输出：主播层级 / 主播数 / 主播数占比 / 开播天数合计 / 日均ACU合计 / 日均ACU占比 /
--       人均日均ACU / 累计ACU合计(人日) / 累计ACU占比（含合计行）
-- ============================================================
with

-- 1) 主播日明细：先汇总到「主播 x 日」，再汇总到「主播」
anchor_day as (
    select
        luid,
        max_by(nickname, dt) as nickname,       -- 窗口内最后一次开播日的昵称
        count(distinct dt) as live_days,        -- 窗口内开播天数（日均ACU 的分母）
        avg(acu) as acu_avg_day,                -- 日均ACU：分层依据
        sum(acu) as acu_person_day              -- 累计ACU（人日）：承载量依据
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
        luid
),

-- 2) 分层：只看日均ACU
anchor_tier as (
    select
        luid,
        nickname,
        live_days,
        acu_avg_day,
        acu_person_day,
        case
            when acu_avg_day >= 2000 then '头部'
            when acu_avg_day >= 1000 then '颈部'
            when acu_avg_day >= 100 then '腰部'
            else '尾部'
        end as acu_type
    from anchor_day
    -- 【可选】剔掉偶发开播，日均ACU 更稳：
    -- where live_days >= 3
),

-- 3) 分层聚合：水平合计 + 承载合计，两个都留着
tier_agg as (
    select
        acu_type,
        count(distinct luid) as anchor_cnt,
        sum(live_days) as live_days_sum,
        sum(acu_avg_day) as acu_avg_sum,          -- 层级日常水平（Σ日均ACU）
        sum(acu_person_day) as acu_pd_sum         -- 层级承载量（Σ累计ACU，人日）
    from anchor_tier
    group by
        acu_type
),

-- 4) 整体合计（只有 1 行，用于算占比；这里 cross join 是刻意的，就为拼合计行）
total as (
    select
        count(distinct luid) as anchor_cnt,
        sum(live_days) as live_days_sum,
        sum(acu_avg_day) as acu_avg_sum,
        sum(acu_person_day) as acu_pd_sum
    from anchor_tier
)

-- 主查询：各层 + 合计
select
    t.acu_type as "主播层级",
    t.anchor_cnt as "主播数",
    round(t.anchor_cnt * 100.0 / nullif(tot.anchor_cnt, 0), 2) as "主播数占比(%)",
    t.live_days_sum as "开播天数合计",
    round(t.acu_avg_sum, 1) as "日均ACU合计",
    round(t.acu_avg_sum * 100.0 / nullif(tot.acu_avg_sum, 0), 2) as "日均ACU占比(%)",
    round(t.acu_avg_sum / nullif(t.anchor_cnt, 0), 1) as "人均日均ACU",
    round(t.acu_pd_sum, 0) as "累计ACU合计(人日)",
    round(t.acu_pd_sum * 100.0 / nullif(tot.acu_pd_sum, 0), 2) as "累计ACU占比(%)"
from tier_agg t
cross join total tot

union all

select
    '合计' as "主播层级",
    tot.anchor_cnt as "主播数",
    100.00 as "主播数占比(%)",
    tot.live_days_sum as "开播天数合计",
    round(tot.acu_avg_sum, 1) as "日均ACU合计",
    100.00 as "日均ACU占比(%)",
    round(tot.acu_avg_sum / nullif(tot.anchor_cnt, 0), 1) as "人均日均ACU",
    round(tot.acu_pd_sum, 0) as "累计ACU合计(人日)",
    100.00 as "累计ACU占比(%)"
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
-- 校验 1：窗口是不是真的 11 天、有数据的天数是多少
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
-- 校验 2：有没有「同一主播窗口内改过昵称」（验证只按 luid 分组的必要性）
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
-- 校验 3：三个占比放在一起看（这张表就是结论本身）
--   头部主播数占比很小、但 日均ACU占比 / 累计ACU占比 很高 = 头部化明显；
--   两种 ACU 占比差得多 = 某个层级"人不多但开播时长长"（时间加权后被放大）
--
-- select
--     acu_type as "主播层级",
--     count(distinct luid) as "主播数",
--     sum(live_days) as "开播天数合计",
--     round(sum(live_days) / nullif(count(distinct luid), 0), 1) as "人均开播天数",
--     round(sum(acu_avg_day), 1) as "日均ACU合计",
--     round(sum(acu_person_day), 0) as "累计ACU合计(人日)"
-- from anchor_tier
-- group by acu_type
-- order by 5 desc;
--
-- 校验 4：偶发开播主播的影响（只开播 1~2 天的人，占了多少 ACU）
--   如果这两档的 ACU 占比很小，那剔不剔都无所谓；占比大就建议剔出分层
--
-- select
--     case when live_days >= 5 then '5天以上'
--          when live_days >= 3 then '3~4天'
--          else '1~2天' end as "开播天数档",
--     count(*) as "主播数",
--     round(avg(acu_avg_day), 1) as "平均日均ACU",
--     round(sum(acu_avg_day), 1) as "日均ACU合计",
--     round(sum(acu_avg_day) * 100.0 / sum(sum(acu_avg_day)) over (), 2) as "日均ACU占比(%)"
-- from anchor_tier
-- group by 1
-- order by 1;
--
-- 校验 5：主播级明细（看层级边界、以及同一层内开播天数的差异）
--
-- select
--     luid as "主播uid",
--     nickname as "主播昵称",
--     live_days as "开播天数",
--     round(acu_avg_day, 1) as "日均ACU",
--     round(acu_person_day, 0) as "累计ACU(人日)",
--     acu_type as "主播层级"
-- from anchor_tier
-- order by acu_avg_day desc;

