-- =====================================================================
-- 目的：莫拉塔 + 5位合作主播 合作前后1个月 有效ACU 日明细 / 大盘对比
-- 数据源：gamelive.dm_mkt_rowner_day
-- 平台：pcode = 'douyin_web'；品类：r_category = '无畏契约'
-- ACU：cast(ext['vaild_acu'] as double)
-- 样本：2026-05-01 ~ 2026-08-31（Presto）
-- 合作日：2026-06-24 起（小组赛），合作期 2026-06-24 ~ 2026-06-30
-- 窗口：
--   合作前1月        2026-05-24 ~ 2026-06-23（31天）
--   后1月(含合作期)  2026-06-24 ~ 2026-07-23（30天）
--   后1月(剔合作期)  2026-07-01 ~ 2026-07-30（30天）
-- 异常号：HangHang，r_lid=557481980778，5-8月日均ACU 4.3万、单日最高35.7万，
--         占全平台约25%，同时输出「原始大盘」与「剔除HangHang大盘」
-- 主播ID：688292233649 莫拉塔 / 928481163143 EQ118 / 4577510133 哀酱
--          67556051524 森森 / 971406464239 月芒zzZ / 559868704090 小泽老师
-- =====================================================================

-- 【输出1】主播×日 日明细 + 大盘日汇总
with anchor_daily as (
    -- 6位主播的主播×日粒度，日ACU取均值（同一天只应有一条记录）
    select
        substr(cast(dt as varchar), 1, 10) as dt_text,
        cast(r_lid as varchar) as r_lid,
        avg(cast(ext['vaild_acu'] as double)) as valid_acu
    from gamelive.dm_mkt_rowner_day
    where dt between '2026-05-01' and '2026-08-31'
        and pcode = 'douyin_web'
        and r_category = '无畏契约'
        and cast(r_lid as varchar) in (
            '688292233649','928481163143','4577510133',
            '67556051524','971406464239','559868704090'
        )
    group by substr(cast(dt as varchar), 1, 10), cast(r_lid as varchar)
),

market_daily as (
    -- 全平台日汇总：原始、剔HangHang、剔6人、剔6人且剔HangHang
    select
        substr(cast(dt as varchar), 1, 10) as dt_text,
        round(sum(cast(ext['vaild_acu'] as double)), 1) as acu_all,
        round(sum(case when cast(r_lid as varchar) <> '557481980778'
                       then cast(ext['vaild_acu'] as double) else 0 end), 1) as acu_all_ex_hh,
        round(sum(case when cast(r_lid as varchar) not in (
                '688292233649','928481163143','4577510133',
                '67556051524','971406464239','559868704090')
                       then cast(ext['vaild_acu'] as double) else 0 end), 1) as acu_non6,
        round(sum(case when cast(r_lid as varchar) not in (
                '688292233649','928481163143','4577510133',
                '67556051524','971406464239','559868704090')
                 and cast(r_lid as varchar) <> '557481980778'
                       then cast(ext['vaild_acu'] as double) else 0 end), 1) as acu_non6_ex_hh
    from gamelive.dm_mkt_rowner_day
    where dt between '2026-05-01' and '2026-08-31'
        and pcode = 'douyin_web'
        and r_category = '无畏契约'
    group by substr(cast(dt as varchar), 1, 10)
),

daily as (
    select
        m.dt_text,
        max(case when a.r_lid = '688292233649' then a.valid_acu end) as "莫拉塔",
        max(case when a.r_lid = '928481163143' then a.valid_acu end) as "EQ118",
        max(case when a.r_lid = '4577510133' then a.valid_acu end) as "哀酱",
        max(case when a.r_lid = '67556051524' then a.valid_acu end) as "森森",
        max(case when a.r_lid = '971406464239' then a.valid_acu end) as "月芒zzZ",
        max(case when a.r_lid = '559868704090' then a.valid_acu end) as "小泽老师",
        m.acu_all as "全平台",
        m.acu_all_ex_hh as "全平台_剔HangHang",
        m.acu_non6 as "非圈选_剔6人",
        m.acu_non6_ex_hh as "非圈选_剔6人_剔HangHang"
    from market_daily m
    left join anchor_daily a on m.dt_text = a.dt_text
    group by m.dt_text, m.acu_all, m.acu_all_ex_hh, m.acu_non6, m.acu_non6_ex_hh
)

select
    dt_text as "日期",
    "莫拉塔", "EQ118", "哀酱", "森森", "月芒zzZ", "小泽老师",
    round(coalesce("EQ118", 0) + coalesce("哀酱", 0) + coalesce("森森", 0)
          + coalesce("月芒zzZ", 0) + coalesce("小泽老师", 0), 2) as "合作5人组",
    round(coalesce("莫拉塔", 0) + coalesce("EQ118", 0) + coalesce("哀酱", 0)
          + coalesce("森森", 0) + coalesce("月芒zzZ", 0) + coalesce("小泽老师", 0), 2) as "6人合计",
    "非圈选_剔6人", "全平台", "全平台_剔HangHang", "非圈选_剔6人_剔HangHang"
from daily
order by dt_text;

-- =====================================================================
-- 【输出2】窗口汇总（把上面输出1的 daily 复制进来后执行）
-- 日均 = 窗口内ACU合计 / 窗口自然日天数（无开播记录按0计入）
-- =====================================================================
-- with daily as ( ... 与输出1的 daily CTE 完全一致 ... )
-- select
--     unit as "统计单位",
--     round(sum(case when dt_text between '2026-05-24' and '2026-06-23' then acu else 0 end) / 31.0, 1) as "合作前1月日均ACU",
--     round(sum(case when dt_text between '2026-06-24' and '2026-07-23' then acu else 0 end) / 30.0, 1) as "后1月含合作期日均ACU",
--     round(sum(case when dt_text between '2026-07-01' and '2026-07-30' then acu else 0 end) / 30.0, 1) as "后1月剔合作期日均ACU"
-- from (
--     select '6人合计' as unit, dt_text, "6人合计" as acu from daily
--     union all select '合作5人组', dt_text, "合作5人组" from daily
--     union all select '莫拉塔', dt_text, "莫拉塔" from daily
--     union all select 'EQ118', dt_text, "EQ118" from daily
--     union all select '哀酱', dt_text, "哀酱" from daily
--     union all select '森森', dt_text, "森森" from daily
--     union all select '月芒zzZ', dt_text, "月芒zzZ" from daily
--     union all select '小泽老师', dt_text, "小泽老师" from daily
--     union all select '非圈选_剔6人', dt_text, "非圈选_剔6人" from daily
--     union all select '全平台', dt_text, "全平台" from daily
--     union all select '全平台_剔HangHang', dt_text, "全平台_剔HangHang" from daily
--     union all select '非圈选_剔6人_剔HangHang', dt_text, "非圈选_剔6人_剔HangHang" from daily
-- ) t
-- group by unit
-- order by unit;

