-- ============================================================
-- AI工坊 × App版本：版本 × 天 明细取数（含 AI 礼物流水）
-- 用途：本地透视出「周日均流水」趋势，口径与现有「曝光占比表 / 周日均转换率表」保持一致
-- 时间窗口：2026-07-13 ~ 2026-09-14
-- 输出粒度：版本号 × 天，一行
-- ============================================================
-- 口径对齐说明（与现有两张表一致）：
--   1) 版本归属：dw_huya_session_level，4 个 App 端 + tag = 'product'，
--      白名单 8 个版本，同一 ukey 同一天只保留一个版本（取 max(iver)）
--   2) 曝光 / 支付：来自调度表 zty_ads_huya_ai_gift_user_detail_0901_v1 的人天标记，
--      支付走漏斗口径（曝光过工坊、且当天送出过 AI 礼物）
--   3) 流水：来自 dws_huya_revenue_detail_d_i，AI 礼物（ext.is_ai = 1 且非抽奖），
--      按 dt + ukey 汇总后挂到该人天所属版本上
--   4) 三条指标都是「人天」口径，不含 PC / Web（无版本号，天然排除）
-- ============================================================

with item_dim as (
    -- 每日道具维表：识别 AI 礼物、抽奖礼物
    select
        d.dt as dt,
        cast(d.item_id as varchar) as item_id,
        max(case when d.item_level = '礼物' and element_at(d.ext, 'is_ai') = '1' then 1 else 0 end) as is_ai,
        max(case when d.play_type in ('抽奖') then 1 else 0 end) as is_draw
    from gamelive.dim_huya_item_d_a d
    where d.dt between '2026-07-13' and '2026-09-14'
      and d.item_level = '礼物'
    group by
        d.dt,
        cast(d.item_id as varchar)
),

ai_gift_amount_user_day as (
    -- AI 礼物流水：人天粒度，用于把流水挂到版本上
    select
        r.dt as dt,
        cast(element_at(r.ext, 'ukey') as varchar) as ukey,
        sum(cast(r.user_consume_amount as double)) as ai_amount
    from gamelive.dws_huya_revenue_detail_d_i r
    inner join item_dim i
        on r.dt = i.dt
       and cast(r.item_id as varchar) = i.item_id
       and i.is_ai = 1
       and i.is_draw = 0
    where r.dt between '2026-07-13' and '2026-09-14'
      and r.consume_order_type = '礼物'
      and cast(r.user_consume_amount as double) > 0
      and r.user_uid is not null
      and lower(cast(r.user_uid as varchar)) not in ('0', 'other')
      and r.creator_uid is not null
      and r.order_time is not null
      and element_at(r.ext, 'ukey') is not null
      and lower(cast(element_at(r.ext, 'ukey') as varchar)) not in ('', '0', 'other')
    group by
        r.dt,
        cast(element_at(r.ext, 'ukey') as varchar)
),

funnel_user_day as (
    -- AI工坊漏斗：人天粒度的曝光 / 支付标记（来自调度表）
    select
        t.dt as dt,
        cast(t.user_ukey as varchar) as ukey,
        max(case when t.is_exposure then 1 else 0 end) as is_exposure,
        max(case when t.is_pay then 1 else 0 end) as is_pay
    from zhgametemp.zty_ads_huya_ai_gift_user_detail_0901_v1 t
    where t.dt between '2026-07-13' and '2026-09-14'
      and t.user_ukey is not null
      and lower(cast(t.user_ukey as varchar)) not in ('', '0', 'other')
    group by
        t.dt,
        cast(t.user_ukey as varchar)
),

version_user_day as (
    -- 版本归属：白名单版本，同一 ukey 同一天只保留一个版本
    select
        s.dt as dt,
        cast(s.ukey as varchar) as ukey,
        max(cast(s.iver as varchar)) as iver
    from gamelive.dw_huya_session_level s
    where s.dt between '2026-07-13' and '2026-09-14'
      and s.product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios')
      and s.tag = 'product'
      and s.ukey is not null
      and cast(s.iver as varchar) in (
            '13.3.82',
            '13.4.0', '13.4.2', '13.4.22',
            '13.4.40', '13.4.41', '13.4.52', '13.4.63'
      )
    group by
        s.dt,
        cast(s.ukey as varchar)
)

select
    v.dt as dt,
    v.iver as iver,
    count(distinct case when coalesce(f.is_exposure, 0) = 1 then v.ukey end) as exposure_user_cnt,
    count(distinct case when coalesce(f.is_exposure, 0) = 1 and coalesce(f.is_pay, 0) = 1 then v.ukey end) as pay_user_cnt,
    round(coalesce(sum(p.ai_amount), 0), 2) as ai_amount,
    count(distinct case when p.ai_amount > 0 then v.ukey end) as pay_user_cnt_amount
from version_user_day v
left join funnel_user_day f
    on v.dt = f.dt
   and v.ukey = f.ukey
left join ai_gift_amount_user_day p
    on v.dt = p.dt
   and v.ukey = p.ukey
group by
    v.dt,
    v.iver
order by
    v.dt,
    v.iver
;

