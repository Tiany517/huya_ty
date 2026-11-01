-- =====================================================================
-- 目的：虎视 + 虎啸 无畏契约在抖音的月度有效ACU规模及大盘占比
-- 执行引擎：Presto
--
-- 样本时间：2026-01-01 ~ 2026-10-15
-- 注：截止日使用两套 MCN 来源此前共同可比的日期；若后续补齐新分区，
--     需同步调整三处日期条件，保证分子和分母时间范围完全一致。
--
-- 虎啸口径：
--   zhgametemp.zhubo_shengtai_platform_pinlei_dau_v4
--   platform in ('douyin', 'douyin-huxiao')，其中 douyin 统一归为虎啸
--   pinlei = '无畏契约'，使用 valid_acu
--
-- 虎视口径：
--   gamelive.ads_spider_douyin_mcn_hushi_info_d_i
--   game_name = '无畏契约'，沿用既有换算：有效ACU = acu / 4.6
--
-- 抖音无畏契约大盘口径：
--   gamelive.dm_mkt_rowner_day
--   pcode = 'douyin_web' and r_category = '无畏契约'
--   使用 cast(ext['vaild_acu'] as double)
--
-- 指标说明：
--   月累计有效ACU：月内每日有效ACU之和，单位为人·天
--   月日均有效ACU：月累计有效ACU / 当月有大盘记录的日期数，单位为人
--   月度大盘占比：月累计有效ACU / 月累计大盘有效ACU
-- =====================================================================

with huxiao_anchor_day as (
    -- 虎啸：先统一到 主播×日，避免原表同主播同日可能重复
    select
        cast(dt as date) as dt,
        cast(platform_id as varchar) as anchor_id,
        max(cast(valid_acu as double)) as valid_acu
    from zhgametemp.zhubo_shengtai_platform_pinlei_dau_v4
    where dt between '2026-01-01' and '2026-10-15'
        and platform in ('douyin', 'douyin-huxiao')
        and pinlei = '无畏契约'
    group by
        cast(dt as date),
        cast(platform_id as varchar)
),

hushi_anchor_day as (
    -- 虎视：先统一到 主播×日；沿用 acu / 4.6 的有效ACU换算
    select
        cast(date as date) as dt,
        cast(aweme_display_id as varchar) as anchor_id,
        max(cast(acu as double) / 4.6) as valid_acu
    from gamelive.ads_spider_douyin_mcn_hushi_info_d_i
    where dt between '2026-01-01' and '2026-10-15'
        and date between '2026-01-01' and '2026-10-15'
        and cast(acu as double) > 0
        and game_name = '无畏契约'
    group by
        cast(date as date),
        cast(aweme_display_id as varchar)
),

mcn_day as (
    -- 虎视、虎啸合并为日期粒度，同时保留两侧拆分
    select
        dt,
        sum(case when source = '虎啸' then valid_acu else 0 end) as huxiao_valid_acu,
        sum(case when source = '虎视' then valid_acu else 0 end) as hushi_valid_acu,
        sum(valid_acu) as mcn_valid_acu
    from (
        select
            dt,
            '虎啸' as source,
            valid_acu
        from huxiao_anchor_day

        union all

        select
            dt,
            '虎视' as source,
            valid_acu
        from hushi_anchor_day
    ) a
    group by dt
),

market_day as (
    -- 抖音无畏契约大盘：主播日有效ACU汇总到日期
    select
        cast(dt as date) as dt,
        sum(cast(ext['vaild_acu'] as double)) as market_valid_acu
    from gamelive.dm_mkt_rowner_day
    where dt between '2026-01-01' and '2026-10-15'
        and pcode = 'douyin_web'
        and r_category = '无畏契约'
    group by cast(dt as date)
),

month_summary as (
    -- 以大盘日期为主表，MCN 无记录日期按0计入月度累计与月日均
    select
        substr(cast(m.dt as varchar), 1, 7) as mth,
        count(*) as market_data_days,
        sum(coalesce(c.huxiao_valid_acu, 0)) as huxiao_valid_acu_sum,
        sum(coalesce(c.hushi_valid_acu, 0)) as hushi_valid_acu_sum,
        sum(coalesce(c.mcn_valid_acu, 0)) as mcn_valid_acu_sum,
        sum(m.market_valid_acu) as market_valid_acu_sum
    from market_day m
    left join mcn_day c
        on m.dt = c.dt
    group by substr(cast(m.dt as varchar), 1, 7)
)

select
    mth as "月份",
    market_data_days as "大盘记录天数",
    round(huxiao_valid_acu_sum, 2) as "虎啸月累计有效ACU_人天",
    round(huxiao_valid_acu_sum / nullif(market_data_days, 0), 2) as "虎啸月日均有效ACU",
    round(hushi_valid_acu_sum, 2) as "虎视月累计有效ACU_人天",
    round(hushi_valid_acu_sum / nullif(market_data_days, 0), 2) as "虎视月日均有效ACU",
    round(mcn_valid_acu_sum, 2) as "虎视虎啸月累计有效ACU_人天",
    round(mcn_valid_acu_sum / nullif(market_data_days, 0), 2) as "虎视虎啸月日均有效ACU",
    round(market_valid_acu_sum, 2) as "抖音无畏契约大盘月累计有效ACU_人天",
    round(market_valid_acu_sum / nullif(market_data_days, 0), 2) as "抖音无畏契约大盘月日均有效ACU",
    round(huxiao_valid_acu_sum / nullif(market_valid_acu_sum, 0), 6) as "虎啸大盘占比",
    round(hushi_valid_acu_sum / nullif(market_valid_acu_sum, 0), 6) as "虎视大盘占比",
    round(mcn_valid_acu_sum / nullif(market_valid_acu_sum, 0), 6) as "虎视虎啸整体大盘占比"
from month_summary
order by mth;

