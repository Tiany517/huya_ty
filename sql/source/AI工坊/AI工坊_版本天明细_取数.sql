-- ============================================================
-- AI工坊 × App版本：版本 × 天 明细取数（用于同时算「本版本窗口原始值」和「同日大盘指数」）
-- 时间窗口：2026-07-13 ~ 2026-09-14
-- 输出粒度：版本号 × 天，一行；不做样本量过滤，保留版本长尾天数
-- ============================================================
-- 说明：
--   1) 曝光 / 支付 / 流水三个指标，版本侧和大盘侧同口径、同一天并列输出，
--      方便本地同时算「本版本自身窗口的日均值」和「相对同日大盘的指数」
--   2) 支付人数用常规口径：revenue 表里当天实际送出过 AI 礼物的人（人天去重）
--   3) 大盘 = 当天 4 个 App 端（huya_andriod / huya_ipad / huya_pad / huya_ios）
--      在 dw_huya_session_level 里有版本号的全体用户；PC / Web 无版本号，天然排除
--   4) 不过滤曝光人数下限，版本刚出现或快退场的天也会保留，便于判断真实共存期
-- ============================================================

with item_dim as (
    -- 每日道具维表：识别 AI 礼物与抽奖礼物
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

ai_gift_pay_user_day as (
    -- AI 礼物支付人天：常规口径的分子来源，人天粒度，带当天 AI 流水
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
    -- 调度表漏斗：人天粒度的 AI工坊曝光 / 支付标记
    select
        t.dt as dt,
        cast(t.user_ukey as varchar) as ukey,
        max(case when t.is_exposure then 1 else 0 end) as is_exposure,
        max(case when t.is_pay then 1 else 0 end) as is_pay
    from zhgametemp.zty_ads_huya_ai_gift_user_detail_0901_v1 t
    where t.dt between '2026-07-13' and '2026-09-14'
      and t.user_ukey is not null
    group by
        t.dt,
        cast(t.user_ukey as varchar)
),

market_user_day as (
    -- 大盘人群：4 个 App 端当天有版本号的全体用户（不限版本白名单）
    select
        s.dt as dt,
        cast(s.ukey as varchar) as ukey
    from gamelive.dw_huya_session_level s
    where s.dt between '2026-07-13' and '2026-09-14'
      and s.product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios')
      and s.tag = 'product'
      and s.ukey is not null
      and s.iver is not null
      and cast(s.iver as varchar) not in ('', '0')
    group by
        s.dt,
        cast(s.ukey as varchar)
),

version_user_day as (
    -- 待评估人群：只看白名单版本；同一 ukey 同一天只保留一个版本
    select
        s.dt as dt,
        cast(s.ukey as varchar) as ukey,
        max(cast(s.iver as varchar)) as iver
    from gamelive.dw_huya_session_level s
    where s.dt between '2026-07-13' and '2026-09-14'
      and s.product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios')
      and s.tag = 'product'
      and cast(s.iver as varchar) in (
            '13.3.82',
            '13.4.0', '13.4.2', '13.4.22', '13.4.40', '13.4.41', '13.4.52', '13.4.63'
      )
      and s.ukey is not null
    group by
        s.dt,
        cast(s.ukey as varchar)
),

version_day as (
    -- 版本 × 天：曝光人数 / 常规支付人数 / AI 流水
    select
        v.dt as dt,
        v.iver as iver,
        count(distinct case when u.is_exposure = 1 then v.ukey end) as exposure_user_cnt,
        count(distinct p.ukey) as pay_user_cnt,
        coalesce(sum(p.ai_amount), 0) as ai_amount
    from version_user_day v
    left join funnel_user_day u
        on v.dt = u.dt
       and v.ukey = u.ukey
    left join ai_gift_pay_user_day p
        on v.dt = p.dt
       and v.ukey = p.ukey
    group by
        v.dt,
        v.iver
),

market_day as (
    -- 大盘 × 天：同口径（曝光 / 常规支付人数 / AI 流水）
    select
        v.dt as dt,
        count(distinct case when u.is_exposure = 1 then v.ukey end) as exposure_user_cnt,
        count(distinct p.ukey) as pay_user_cnt,
        coalesce(sum(p.ai_amount), 0) as ai_amount
    from market_user_day v
    left join funnel_user_day u
        on v.dt = u.dt
       and v.ukey = u.ukey
    left join ai_gift_pay_user_day p
        on v.dt = p.dt
       and v.ukey = p.ukey
    group by
        v.dt
)

select
    d.dt as dt,
    d.iver as iver,
    d.exposure_user_cnt as exposure_user_cnt,
    d.pay_user_cnt as pay_user_cnt,
    round(d.ai_amount, 2) as ai_amount,
    m.exposure_user_cnt as market_exposure_user_cnt,
    m.pay_user_cnt as market_pay_user_cnt,
    round(m.ai_amount, 2) as market_ai_amount
from version_day d
inner join market_day m
    on d.dt = m.dt
order by
    d.iver,
    d.dt
;
