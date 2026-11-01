-- ============================================================
-- AI工坊 × App版本 × 价格档：曝光 / 支付 / 转换率
-- 时间窗口：2026-07-13 ~ 2026-09-14
-- 输出粒度：版本号 × 价格档（52 / 131.4 / 520 / 1000），每个版本 4 行
-- 版本范围：13.3.82 / 13.4.0 / 13.4.2 / 13.4.22 / 13.4.40 / 13.4.41 / 13.4.52 / 13.4.63
-- ============================================================
-- 字段口径：
--   hyc_value                        价格档（道具标准价值）
--   iver                             版本号
--   day_cnt                          参与平均的天数（曝光人数 > 0 的天）
--   avg_exposure_user_cnt_by_day     日均人均曝光人数（同一版本各价格档相同，重复列出便于直接算比率）
--   avg_pay_user_cnt_revenue_by_day  日均人均支付人数（常规口径，该价格档）
--   avg_pay_user_cnt_funnel_by_day   日均人均支付人数（漏斗口径，该价格档）
--   ai_gift_order_cnt_total          该价格档总AI礼物订单数（全窗口，按订单去重）
--   ai_gift_item_cnt_total           该价格档总AI礼物供给数量（全窗口去重道具数）
--   avg_conv_rate_revenue_by_day     日均转换率（常规口径 = 该档支付人数 / 曝光人数）
--   avg_conv_rate_funnel_by_day      日均转换率（漏斗口径 = 该档"曝光且当天送出"人数 / 曝光人数）
-- 说明：
--   1) 曝光没有价格属性——用户看到的是整个 AI工坊，不是某个价位。
--      所以分母对同一版本的所有价格档完全相同，各档共用同一个曝光人数。
--   2) 同一天送了两个价位的用户，会在两个价位各算一次，
--      因此各价格档支付人数之和 >= 该版本总支付人数，不能相加当总数用。
--   3) 调度表的 is_pay 没有价位信息，所以两个口径的分档都从 revenue 表取：
--      常规口径 = 当天送过该档 AI 礼物；漏斗口径 = 在此基础上再要求当天曝光且 is_pay = 1。
--   4) 日均转换率是「逐日比值的算术平均」，不是 日均支付 / 日均曝光，两者会有小幅差异。
--   5) is_exposure / is_pay 按附件 DDL 是 boolean；若落表实际是 0/1，
--      把 "case when t.is_exposure then 1 else 0 end" 换成 "case when t.is_exposure = 1 then 1 else 0 end"
-- ============================================================

with price_dim as (
    -- 价格档维度（AI 礼物当前只有这四档）；纯常量表，用于给每个版本补齐 4 行
    select cast(52 as double) as hyc_value
    union all
    select cast(131.4 as double) as hyc_value
    union all
    select cast(520 as double) as hyc_value
    union all
    select cast(1000 as double) as hyc_value
),

item_dim as (
    -- 每日道具维表：识别 AI 礼物、抽奖礼物，并带出标准价值
    select
        d.dt as dt,
        cast(d.item_id as varchar) as item_id,
        max(cast(d.hyc_value as double)) as hyc_value,
        max(case when d.item_level = '礼物' and d.ext['is_ai'] = '1' then 1 else 0 end) as is_ai,
        max(case when d.play_type in ('抽奖') then 1 else 0 end) as is_draw
    from gamelive.dim_huya_item_d_a d
    where d.dt between '2026-07-13' and '2026-09-14'
      and d.item_level = '礼物'
    group by
        d.dt,
        cast(d.item_id as varchar)
),

ai_gift_order_day as (
    -- AI 礼物订单明细（非抽奖、限定四个价格档）：dt × 付费人 ukey × 订单 × 道具 × 价格档
    -- 想看除这四档之外还有没有别的价位，把下面 hyc_value in (...) 那行去掉即可
    select
        r.dt as dt,
        cast(r.ext['ukey'] as varchar) as ukey,
        cast(r.order_id as varchar) as order_id,
        cast(r.item_id as varchar) as item_id,
        i.hyc_value as hyc_value
    from gamelive.dws_huya_revenue_detail_d_i r
    inner join item_dim i
        on r.dt = i.dt
       and cast(r.item_id as varchar) = i.item_id
       and i.is_ai = 1
       and i.is_draw = 0
    where r.dt between '2026-07-13' and '2026-09-14'
      and r.consume_order_type = '礼物'
      and r.user_consume_amount > 0
      and r.user_uid is not null
      and lower(cast(r.user_uid as varchar)) not in ('0', 'other')
      and r.creator_uid is not null
      and r.order_time is not null
      and r.ext['ukey'] is not null
      and lower(cast(r.ext['ukey'] as varchar)) not in ('', '0', 'other')
      and i.hyc_value in (52, 131.4, 520, 1000)
),

funnel_user_day as (
    -- 用户 × 日期 漏斗：读每天在跑的调度表，收敛到人天粒度
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

user_version_day as (
    -- 用户 × 日期 的 App 版本；同一天同一 ukey 只保留一个版本
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

exposure_by_version as (
    -- 分母：当日该版本的曝光人数（不分价格档）
    select
        v.dt as dt,
        v.iver as iver,
        count(distinct v.ukey) as exposure_user_cnt
    from funnel_user_day u
    inner join user_version_day v
        on u.dt = v.dt
       and u.ukey = v.ukey
    where u.is_exposure = 1
    group by
        v.dt,
        v.iver
),

revenue_pay_by_version_price as (
    -- 常规口径：当日该版本、该价格档的 AI 礼物支付人数（不要求当天有曝光）
    select
        v.dt as dt,
        v.iver as iver,
        o.hyc_value as hyc_value,
        count(distinct v.ukey) as pay_user_cnt
    from ai_gift_order_day o
    inner join user_version_day v
        on o.dt = v.dt
       and o.ukey = v.ukey
    group by
        v.dt,
        v.iver,
        o.hyc_value
),

funnel_pay_by_version_price as (
    -- 漏斗口径：当日该版本"曝光过 AI工坊、is_pay = 1、且送过该价格档 AI 礼物"的人数
    select
        v.dt as dt,
        v.iver as iver,
        o.hyc_value as hyc_value,
        count(distinct v.ukey) as pay_user_cnt
    from ai_gift_order_day o
    inner join funnel_user_day u
        on o.dt = u.dt
       and o.ukey = u.ukey
       and u.is_exposure = 1
       and u.is_pay = 1
    inner join user_version_day v
        on o.dt = v.dt
       and o.ukey = v.ukey
    group by
        v.dt,
        v.iver,
        o.hyc_value
),

gift_total_by_version_price as (
    -- 全窗口该版本、该价格档的订单数与去重道具数
    select
        v.iver as iver,
        o.hyc_value as hyc_value,
        count(distinct o.order_id) as ai_gift_order_cnt_total,
        count(distinct o.item_id) as ai_gift_item_cnt_total
    from ai_gift_order_day o
    inner join user_version_day v
        on o.dt = v.dt
       and o.ukey = v.ukey
    group by
        v.iver,
        o.hyc_value
),

version_day_base as (
    -- 骨架：该版本当天有活跃用户的 (dt, iver)
    select distinct
        v.dt as dt,
        v.iver as iver
    from user_version_day v
),

version_price_day as (
    -- 骨架补齐价格档：63 天 × 8 版本 × 4 档，量很小，
    -- 目的是让"某天某档没人支付"也能落到 0，而不是整天被跳过
    select
        b.dt as dt,
        b.iver as iver,
        p.hyc_value as hyc_value
    from version_day_base b
    cross join price_dim p
),

daily as (
    select
        d.dt as dt,
        d.iver as iver,
        d.hyc_value as hyc_value,
        coalesce(e.exposure_user_cnt, 0) as exposure_user_cnt,
        coalesce(r.pay_user_cnt, 0) as revenue_pay_user_cnt,
        coalesce(f.pay_user_cnt, 0) as funnel_pay_user_cnt
    from version_price_day d
    left join exposure_by_version e
        on d.dt = e.dt
       and d.iver = e.iver
    left join revenue_pay_by_version_price r
        on d.dt = r.dt
       and d.iver = r.iver
       and d.hyc_value = r.hyc_value
    left join funnel_pay_by_version_price f
        on d.dt = f.dt
       and d.iver = f.iver
       and d.hyc_value = f.hyc_value
),

version_price_agg as (
    -- 所有均值只在"曝光人数 > 0"的天上算，和 day_cnt 同一套天
    select
        iver,
        hyc_value,
        count(case when exposure_user_cnt > 0 then 1 end) as day_cnt,
        avg(case when exposure_user_cnt > 0 then cast(exposure_user_cnt as double) end) as avg_exposure_user_cnt_by_day,
        avg(case when exposure_user_cnt > 0 then cast(revenue_pay_user_cnt as double) end) as avg_pay_user_cnt_revenue_by_day,
        avg(case when exposure_user_cnt > 0 then cast(funnel_pay_user_cnt as double) end) as avg_pay_user_cnt_funnel_by_day,
        avg(
            case
                when exposure_user_cnt > 0
                then cast(revenue_pay_user_cnt as double) / exposure_user_cnt
            end
        ) as avg_conv_rate_revenue_by_day,
        avg(
            case
                when exposure_user_cnt > 0
                then cast(funnel_pay_user_cnt as double) / exposure_user_cnt
            end
        ) as avg_conv_rate_funnel_by_day
    from daily
    group by
        iver,
        hyc_value
)

select
    a.hyc_value as hyc_value,
    a.iver as iver,
    a.day_cnt as day_cnt,
    cast(a.avg_exposure_user_cnt_by_day as double) as avg_exposure_user_cnt_by_day,
    cast(a.avg_pay_user_cnt_revenue_by_day as double) as avg_pay_user_cnt_revenue_by_day,
    cast(a.avg_pay_user_cnt_funnel_by_day as double) as avg_pay_user_cnt_funnel_by_day,
    coalesce(g.ai_gift_order_cnt_total, 0) as ai_gift_order_cnt_total,
    coalesce(g.ai_gift_item_cnt_total, 0) as ai_gift_item_cnt_total,
    cast(a.avg_conv_rate_revenue_by_day as double) as avg_conv_rate_revenue_by_day,
    cast(a.avg_conv_rate_funnel_by_day as double) as avg_conv_rate_funnel_by_day
from version_price_agg a
left join gift_total_by_version_price g
    on a.iver = g.iver
   and a.hyc_value = g.hyc_value
order by
    a.hyc_value,
    a.iver
;

