-- ============================================================
-- AI工坊 × App版本：曝光 / 支付（双口径）/ AI礼物供给 / 日均转换率
-- 时间窗口：2026-07-13 ~ 2026-09-14
-- 输出粒度：每个版本一行
-- ============================================================
-- 字段口径：
--   iver_line                        版本大类（13.4 / 13.3 / 13.2）
--   iver                             版本号
--   day_cnt                          参与平均的天数（曝光人数 > 0 的天）
--   avg_exposure_user_cnt_by_day     日均人均曝光人数
--   avg_pay_user_cnt_revenue_by_day  日均人均支付人数（常规口径：revenue 表实际送出 AI 礼物的人）
--   avg_pay_user_cnt_funnel_by_day   日均人均支付人数（漏斗口径：调度表 is_pay，曝光且当天送出）
--   ai_gift_item_cnt_total           总AI礼物供给数量（全窗口去重道具数，同一道具跨天只算一个）
--   avg_conv_rate_by_day             日均人均转换率（本版用漏斗口径做分子，换口径见下方注释）
-- 说明：
--   1) 四个均值都只在"曝光人数 > 0"的天上平均，和 day_cnt 同一套天，三者可直接对照
--   2) 日均人均转换率是「逐日比值的算术平均」，不等于 日均支付 / 日均曝光
--   3) 常规口径的支付人来自 revenue 表（无版本字段），版本按付费人当天的 App 版本归属；
--      再 join 版本表，等于只统计当天在 4 个 App 端有过会话且版本命中列表的用户，
--      PC/Web 用户天然被排除，和漏斗口径的人群范围对齐
--   4) 漏斗口径的 is_pay 隐含"曝光与支付同一天、同 game_id"，所以恒 <= 常规口径
--   5) is_exposure / is_pay 按附件 DDL 是 boolean；若落表实际是 0/1，
--      把 "case when t.is_exposure then 1 else 0 end" 换成 "case when t.is_exposure = 1 then 1 else 0 end"
-- ============================================================

with item_dim as (
    -- 每日道具维表：识别 AI 礼物、抽奖礼物
    select
        d.dt as dt,
        cast(d.item_id as varchar) as item_id,
        max(case when d.item_level = '礼物' and d.ext['is_ai'] = '1' then 1 else 0 end) as is_ai,
        max(case when d.play_type in ('抽奖') then 1 else 0 end) as is_draw
    from gamelive.dim_huya_item_d_a d
    where d.dt between '2026-07-13' and '2026-09-14'
      and d.item_level = '礼物'
    group by
        d.dt,
        cast(d.item_id as varchar)
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
            '13.4.63', '13.4.52', '13.4.41', '13.4.40', '13.4.22', '13.4.2', '13.4.0',
            '13.3.82', '13.3.64', '13.3.60', '13.3.52',
            '13.2.91', '13.2.74', '13.2.64', '13.2.42'
      )
      and s.ukey is not null
    group by
        s.dt,
        cast(s.ukey as varchar)
),

ai_gift_order_day as (
    -- AI 礼物订单明细（非抽奖）：dt × 付费人 ukey × 订单 × 道具
    select
        r.dt as dt,
        cast(r.ext['ukey'] as varchar) as ukey,
        cast(r.order_id as varchar) as order_id,
        cast(r.item_id as varchar) as item_id
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
),

revenue_pay_user_day as (
    -- 常规口径支付人：revenue 表里实际送出过 AI 礼物的去重付费人（人天粒度）
    select distinct
        o.dt as dt,
        o.ukey as ukey
    from ai_gift_order_day o
),

exposure_by_version as (
    -- 分母：当日该版本的曝光人数
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

funnel_pay_by_version as (
    -- 漏斗口径：当日该版本"曝光过 AI工坊、且当天送出过 AI 礼物"的人数
    select
        v.dt as dt,
        v.iver as iver,
        count(distinct v.ukey) as pay_user_cnt
    from funnel_user_day u
    inner join user_version_day v
        on u.dt = v.dt
       and u.ukey = v.ukey
    where u.is_exposure = 1
      and u.is_pay = 1
    group by
        v.dt,
        v.iver
),

revenue_pay_by_version as (
    -- 常规口径：当日该版本的 AI 礼物支付人数（不要求当天有曝光）
    select
        v.dt as dt,
        v.iver as iver,
        count(distinct v.ukey) as pay_user_cnt
    from revenue_pay_user_day p
    inner join user_version_day v
        on p.dt = v.dt
       and p.ukey = v.ukey
    group by
        v.dt,
        v.iver
),

ai_gift_supply_total as (
    -- 总AI礼物供给数量：全窗口去重道具数（按付费人当天的版本归属，同一道具跨天只算一个）
    select
        v.iver as iver,
        count(distinct o.item_id) as ai_gift_item_cnt_total
    from ai_gift_order_day o
    inner join user_version_day v
        on o.dt = v.dt
       and o.ukey = v.ukey
    group by
        v.iver
),

version_day_base as (
    -- 骨架：该版本当天有活跃用户的全部 (dt, iver)，用它做主表 + left join
    select distinct
        v.dt as dt,
        v.iver as iver
    from user_version_day v
),

daily as (
    select
        b.dt as dt,
        b.iver as iver,
        coalesce(e.exposure_user_cnt, 0) as exposure_user_cnt,
        coalesce(f.pay_user_cnt, 0) as funnel_pay_user_cnt,
        coalesce(r.pay_user_cnt, 0) as revenue_pay_user_cnt
    from version_day_base b
    left join exposure_by_version e
        on b.dt = e.dt
       and b.iver = e.iver
    left join funnel_pay_by_version f
        on b.dt = f.dt
       and b.iver = f.iver
    left join revenue_pay_by_version r
        on b.dt = r.dt
       and b.iver = r.iver
),

version_agg as (
    -- 四个均值都只在"曝光人数 > 0"的天上平均，和 day_cnt 同一套天
    select
        case
            when iver like '13.4.%' then '13.4'
            when iver like '13.3.%' then '13.3'
            when iver like '13.2.%' then '13.2'
        end as iver_line,
        iver,
        count(case when exposure_user_cnt > 0 then 1 end) as day_cnt,
        avg(case when exposure_user_cnt > 0 then cast(exposure_user_cnt as double) end) as avg_exposure_user_cnt_by_day,
        avg(case when exposure_user_cnt > 0 then cast(revenue_pay_user_cnt as double) end) as avg_pay_user_cnt_revenue_by_day,
        avg(case when exposure_user_cnt > 0 then cast(funnel_pay_user_cnt as double) end) as avg_pay_user_cnt_funnel_by_day,
        -- 本版转换率用漏斗口径做分子；要用常规口径，把下行换成 revenue_pay_user_cnt
        avg(
            case
                when exposure_user_cnt > 0
                then cast(funnel_pay_user_cnt as double) / exposure_user_cnt
            end
        ) as avg_conv_rate_by_day
    from daily
    group by
        case
            when iver like '13.4.%' then '13.4'
            when iver like '13.3.%' then '13.3'
            when iver like '13.2.%' then '13.2'
        end,
        iver
)

select
    a.iver_line as iver_line,
    a.iver as iver,
    a.day_cnt as day_cnt,
    cast(a.avg_exposure_user_cnt_by_day as double) as avg_exposure_user_cnt_by_day,
    cast(a.avg_pay_user_cnt_revenue_by_day as double) as avg_pay_user_cnt_revenue_by_day,
    cast(a.avg_pay_user_cnt_funnel_by_day as double) as avg_pay_user_cnt_funnel_by_day,
    coalesce(s.ai_gift_item_cnt_total, 0) as ai_gift_item_cnt_total,
    cast(a.avg_conv_rate_by_day as double) as avg_conv_rate_by_day
from version_agg a
left join ai_gift_supply_total s
    on a.iver = s.iver
order by
    a.iver
;

