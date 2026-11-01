-- ============================================================
-- 无畏契约（gameid = 5937）2026-09-30 单日：主播层级 ACU 分布
--
-- 需求：看 9月30日 无畏契约 头部/颈部/腰部/尾部 各层的 ACU 分布
--
-- 源表：gamelive.dm_huya_ayyuid_detail_day（主播 x 日 x 品类 的开播/人气日表）
--   过滤：dt = '2026-09-30'、gameid = 5937（无畏契约）、live_hours_only_live > 0（当天真的开播）
--
-- 口径：
--   1. 分层依据 = 该主播「当天」的 ACU，不是月均；单日一天一层，不存在跨月切换
--   2. 分层阈值沿用 腰部AI直播间 那份 SQL 的四层写法：
--        头部 acu >= 2000 / 颈部 1000 <= acu < 2000 / 腰部 100 <= acu < 1000 / 尾部 acu < 100
--      （另一份 各等级主播的月ACU均值.sql 用的是三层：头部>=2000 / 腰部100~2000 / 尾部<100，
--        要三层口径跟我说，把 case 删掉颈部那段即可）
--   3. ACU 按主播累加（sum(acu)），即「各层主播 ACU 之和」；
--      注意这是主播维度累加，同一个观众看多个主播会被重复计数，不等于该品类在线总人数
--   4. 当天没开播的主播不参与（没有行）；ACU 本身也只有开播日才有值
--   5. 人均ACU = 该层 ACU合计 / 该层主播数（不是加权的日均值）
--
-- 输出：主播层级 / 主播数 / 主播数占比 / ACU合计 / ACU占比 / 人均ACU（含合计行）
-- ============================================================
with

-- 1) 主播日明细：先做分区时间 + 业务条件过滤，再按主播汇总当天 ACU
anchor_day as (
    select
        cast(ayyuid as varchar) as luid,   -- 统一 varchar，避免和别处的 ID 类型混比
        max(nickname) as nickname,
        sum(acu) as acu                    -- 正常一个主播一天该品类一行，sum 就等于原值
    from gamelive.dm_huya_ayyuid_detail_day
    where dt = '2026-09-30'
      and gameid = 5937
      and live_hours_only_live > 0
    group by
        cast(ayyuid as varchar)
),

-- 2) 按当天 ACU 分层
anchor_tier as (
    select
        luid,
        nickname,
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
        sum(acu) as acu_sum
    from anchor_tier
    group by
        acu_type
),

-- 4) 整体合计（只有 1 行，用于算占比；这里 cross join 是刻意的，就为拼合计行）
total as (
    select
        count(distinct luid) as anchor_cnt,
        sum(acu) as acu_sum
    from anchor_tier
)

-- 主查询：各层 + 合计
select
    t.acu_type as "主播层级",
    t.anchor_cnt as "主播数",
    round(t.anchor_cnt * 100.0 / nullif(tot.anchor_cnt, 0), 2) as "主播数占比(%)",
    t.acu_sum as "ACU合计",
    round(t.acu_sum * 100.0 / nullif(tot.acu_sum, 0), 2) as "ACU占比(%)",
    round(t.acu_sum / nullif(t.anchor_cnt, 0), 1) as "人均ACU"
from tier_agg t
cross join total tot

union all

select
    '合计' as "主播层级",
    tot.anchor_cnt as "主播数",
    100.00 as "主播数占比(%)",
    tot.acu_sum as "ACU合计",
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
-- 【校验 / 可选】把上面的主查询换成下面任意一段即可，with 里的 CTE 都不用动
-- ============================================================
--
-- 校验 1：先确认这天的数据存在、且分层样本量合理
--   如果 anchors=0，说明 2026-09-30 分区还没产出或 gameid 不对
--
-- select
--     count(distinct luid) as "当天开播主播数",
--     sum(acu) as "ACU合计",
--     min(acu) as "最小acu",
--     max(acu) as "最大acu",
--     round(avg(acu), 1) as "平均acu"
-- from anchor_day;
--
-- 校验 2：确认有没有「同一主播同一天多行」的情况
--   阈值 1 表示一主播一行（正常）；大于 1 说明当天该品类有多行，
--   这时 sum(acu) 需要和你们口径确认是 sum 还是 max
--
-- select
--     max(cnt) as "单主播最大行数",
--     count_if(cnt > 1) as "多行主播数"
-- from (
--     select
--         cast(ayyuid as varchar) as luid,
--         count(*) as cnt
--     from gamelive.dm_huya_ayyuid_detail_day
--     where dt = '2026-09-30'
--       and gameid = 5937
--       and live_hours_only_live > 0
--     group by cast(ayyuid as varchar)
-- ) t;
--
-- 校验 3：主播级明细（哪个人落在哪一层，按 ACU 降序看头部/颈部边界）
--
-- select
--     luid as "主播uid",
--     nickname as "主播昵称",
--     acu as "当日acu",
--     acu_type as "主播层级"
-- from anchor_tier
-- order by acu desc;

