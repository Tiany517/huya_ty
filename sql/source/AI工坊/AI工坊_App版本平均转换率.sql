-- ============================================================
-- AI工坊 × App版本 日均转换率 + AI礼物量
-- 需求：比较不同 App 版本下，"看到 AI工坊入口 → 送出 AI 礼物"的转化，并看每个版本的 AI 礼物量
-- 口径：
--   日均人均转换率 = By天 AVG( 当日该版本支付人数 / 当日该版本曝光人数 )
--   曝光人数：调度表 zty_ads_huya_ai_gift_user_detail_0901_v1 里 is_exposure = true 的去重用户
--   支付人数：同一张表里 is_exposure = true 且 is_pay = true 的去重用户，
--             即"当天曝光过 AI工坊、当天也送出过 AI 礼物"的人
--   AI 礼物量：dws_huya_revenue_detail_d_i 里 play_type 非抽奖、ext['is_ai'] = '1' 的礼物，
--             按付费人当天的 App 版本归属（与转换率同一套版本口径）
--   版本口径：gamelive.dw_huya_session_level，tag='product'，
--             product 取 ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios')
--             同一 dt + ukey 只保留一个 iver（取 max），即一个用户一天只归一个版本
-- 时间窗口：2026-07-13 ~ 2026-09-14
-- 输出：每个版本一行
-- ============================================================
-- 对比版本（按窗口内实际在线量级筛，采样日 07-14 / 08-15 / 09-14 的 ukey 去重人数）：
--   13.4 线：13.4.63(9/14 118万) / 13.4.40(116万) / 13.4.52(31万) / 13.4.41(15万)
--            13.4.22(8/15 143万、9/14 14万) / 13.4.2(76万) / 13.4.0(141万)
--   13.3 线：13.3.82(27万/21万/5万) / 13.3.64(7/14 125万) / 13.3.60(102万) / 13.3.52(17万)
--   13.2 线：13.2.91 / 13.2.74 / 13.2.64 / 13.2.42，其中 13.2.64 只有 7k~13k，
--            是 13.4.63 的 1/170，分母会很小，日均比值波动大，读结论时先看 day_cnt
-- ============================================================
-- 注意：
--   1) 不用 full outer join：以"该版本当天有活跃用户"的 (dt, iver) 作主表，三个指标 left join 上来
--   2) 调度表的 is_pay 是 left join 打上去的交叉标记，隐含"曝光与支付同一天、同 game_id"，
--      所以比自拉 revenue 表算出来的支付人数少
--      （2026-09-14 实测：revenue 口径 300 人，调度表 is_pay 口径 269 人）
--   3) is_exposure / is_pay 按附件 DDL 是 boolean；若落表实际是 0/1，把
--      "case when t.is_exposure then 1 else 0 end" 换成
--      "case when t.is_exposure = 1 then 1 else 0 end"，is_pay 同理
--   4) 曝光人数为 0 的天不参与平均，day_cnt 会小于窗口天数
-- ============================================================

with item_dim as (
    -- 每日道具维表：识别 AI 礼物、抽奖礼物（沿用参考 SQL 的口径）
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
    -- 用户 × 日期 漏斗：直接读每天在跑的调度表，收敛到人天粒度
    -- 一个用户同一天在多个 game_id 下有多行，只要任意一行命中曝光/支付即记为 1
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
    -- 用户 × 日期 的 App 版本；同一天同一 ukey 只保留一个版本，避免跨版本重复计数
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
    -- 分子：当日该版本"曝光过 AI工坊、且当天送出过 AI 礼物"的人数
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

ai_gift_by_version_total as (
    -- 全窗口该版本的 AI 礼物量，按版本去重（同一道具跨天只算一个）
    select
        v.iver as iver,
        count(distinct o.order_id) as ai_gift_order_cnt_total,
        count(distinct o.item_id) as ai_gift_item_cnt_total
    from ai_gift_order_day o
    inner join user_version_day v
        on o.dt = v.dt
       and o.ukey = v.ukey
    group by
        v.iver
),

version_day_base as (
    -- 汇总主表：该版本当天有活跃用户的全部 (dt, iver)，
    -- 用它作主表 + left join，替代 full outer join，也避免丢"有送礼但当天无曝光"的版本-天
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
        coalesce(p.pay_user_cnt, 0) as pay_user_cnt
    from version_day_base b
    left join exposure_by_version e
        on b.dt = e.dt
       and b.iver = e.iver
    left join funnel_pay_by_version p
        on b.dt = p.dt
       and b.iver = p.iver
)

-- 按版本汇总
-- avg_conv_rate_by_day = 日均人均转换率，逐日转化率的算术平均（曝光人数为 0 的天不参与平均）
select
    agg.iver_line as iver_line,
    agg.iver as iver,
    agg.day_cnt as day_cnt,
    cast(agg.avg_conv_rate_by_day as double) as avg_conv_rate_by_day,
    coalesce(t.ai_gift_order_cnt_total, 0) as ai_gift_order_cnt_total,
    coalesce(t.ai_gift_item_cnt_total, 0) as ai_gift_item_cnt_total
from (
    select
        case
            when iver like '13.4.%' then '13.4'
            when iver like '13.3.%' then '13.3'
            when iver like '13.2.%' then '13.2'
        end as iver_line,
        iver,
        count(case when exposure_user_cnt > 0 then 1 end) as day_cnt,
        avg(
            case
                when exposure_user_cnt > 0
                then cast(pay_user_cnt as double) / exposure_user_cnt
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
) agg
left join ai_gift_by_version_total t
    on agg.iver = t.iver
order by
    agg.iver
;
