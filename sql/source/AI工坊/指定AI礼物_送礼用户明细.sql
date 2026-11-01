-- ============================================================
-- 指定 AI 礼物（阿初招主持 / 仙女招主持 / 仙女传媒）是谁送的、送了多少
-- 时间窗：2026-07-13 ~ 2026-09-14
-- 目标礼物（先在标签表里按名字解析 item_id，避免同名多 ID 漏抓）：
--   30021215 阿初招主持（主播肖像，主主播 仙女-小漫春曲）
--   30014587 仙女招主持（主播肖像，主主播 仙女-好运FM）
--   30011703 仙女传媒（公会肖像，主主播 仙女-初恋Fm）
-- 用户口径：ukey 去重（与打标表 pay_user_cnt 一致），user_uid 一并带出做核对
-- 注意：数仓里没有用户昵称维表，只能给到 ukey / user_uid，识别不到“谁”
-- ============================================================
with target_item as (
    select distinct
        cast(item_id as varchar) as item_id
        ,item_name
        ,primary_anchor_name
        ,category_l2
        ,order_cnt      as label_order_cnt
        ,pay_user_cnt   as label_pay_user_cnt
        ,sales_amount   as label_sales_amount
    from zhgametemp.zty_sold_gift_item_with_label_v5
    where item_name in ('阿初招主持', '仙女招主持', '仙女传媒')
),

-- 主查询：礼物 x 用户
order_detail as (
    select
        t.item_name
        ,t.primary_anchor_name
        ,r.creator_uid
        ,cast(r.ext['ukey'] as varchar)            as ukey
        ,cast(r.user_uid as varchar)               as user_uid
        ,r.dt
        ,r.order_id
        ,cast(r.user_consume_amount as double)     as consume_amount
    from gamelive.dws_huya_revenue_detail_d_i r
    inner join target_item t
        on cast(r.item_id as varchar) = t.item_id
    where r.dt between '2026-07-13' and '2026-09-14'
      and r.consume_order_type = '礼物'
      and cast(r.user_consume_amount as double) > 0
      and r.user_uid is not null
      and lower(cast(r.user_uid as varchar)) not in ('0', 'other')
      and r.ext['ukey'] is not null
      and lower(cast(r.ext['ukey'] as varchar)) not in ('', '0', 'other')
)

select
    item_name
    ,primary_anchor_name                          as anchor_name
    ,creator_uid
    ,ukey
    ,max(user_uid)                                as user_uid
    ,count(distinct order_id)                     as order_cnt
    ,sum(consume_amount)                          as consume_amount
    ,min(dt)                                      as first_dt
    ,max(dt)                                      as last_dt
from order_detail
group by
    item_name
    ,primary_anchor_name
    ,creator_uid
    ,ukey
order by
    consume_amount desc
;

-- ============================================================
-- 变体A：用户维度汇总（一个用户在这三件礼物上总共花了多少）
-- ============================================================
-- 同上，把最后的 select 换成：
-- select
--     ukey
--     ,max(user_uid)                                        as user_uid
--     ,count(distinct item_name)                            as item_cnt
--     ,count(distinct order_id)                             as order_cnt
--     ,sum(consume_amount)                                  as consume_amount
--     ,min(dt)                                              as first_dt
--     ,max(dt)                                              as last_dt
-- from order_detail
-- group by ukey
-- order by consume_amount desc
-- ;

-- ============================================================
-- 变体B：对账（跑完主查询后用这段跟标签表自身口径核一遍）
--   期望：
--     阿初招主持  order_cnt 116  pay_user_cnt 2  sales_amount 314000
--     仙女招主持  order_cnt  79  pay_user_cnt 2  sales_amount 291000
--     仙女传媒    order_cnt  86  pay_user_cnt 1  sales_amount 250000
-- ============================================================
-- with target_item as (
--     select distinct
--         cast(item_id as varchar) as item_id
--         ,item_name
--         ,order_cnt      as label_order_cnt
--         ,pay_user_cnt   as label_pay_user_cnt
--         ,sales_amount   as label_sales_amount
--     from zhgametemp.zty_sold_gift_item_with_label_v5
--     where item_name in ('阿初招主持', '仙女招主持', '仙女传媒')
-- )
-- select
--     t.item_name
--     ,t.label_order_cnt
--     ,count(distinct r.order_id)                              as calc_order_cnt
--     ,t.label_pay_user_cnt
--     ,count(distinct cast(r.ext['ukey'] as varchar))          as calc_pay_user_cnt
--     ,t.label_sales_amount
--     ,sum(cast(r.user_consume_amount as double))              as calc_sales_amount
-- from gamelive.dws_huya_revenue_detail_d_i r
-- inner join target_item t
--     on cast(r.item_id as varchar) = t.item_id
-- where r.dt between '2026-07-13' and '2026-09-14'
--   and r.consume_order_type = '礼物'
--   and cast(r.user_consume_amount as double) > 0
--   and r.ext['ukey'] is not null
--   and lower(cast(r.ext['ukey'] as varchar)) not in ('', '0', 'other')
-- group by
--     t.item_name
--     ,t.label_order_cnt
--     ,t.label_pay_user_cnt
--     ,t.label_sales_amount
-- order by t.label_sales_amount desc
-- ;
