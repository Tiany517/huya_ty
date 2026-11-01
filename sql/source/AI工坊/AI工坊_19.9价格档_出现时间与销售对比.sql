-- =====================================================================
-- 目的：
--   1）定位 AI 礼物 19.9 元档首次出现的日期；
--   2）给出该日期 ~ 2026-09-19 期间 19.9 档 AI 礼物的销售情况；
--   3）给出同期间普通礼物（含 19.9 档与相邻价位档）的对照。
--
-- 时间窗：2026-07-13（AI工坊上线日）~ 2026-09-19（dim / revenue 最新可用分区）
--
-- 口径说明：
--   * 礼物识别：dim_huya_item_d_a.item_level = '礼物'
--   * AI 礼物：element_at(ext, 'is_ai') = '1'（Presto 中 ext 无该 key 时 element_at 返回 NULL，不报错）
--   * 抽奖 / 直送：play_type = '抽奖' 记为抽奖，其余记为直送
--   * 订单过滤：consume_order_type = '礼物'、user_consume_amount > 0、
--              user_uid 非空且不为 0/other、ext['ukey'] 非空
--   * 金额口径：user_consume_amount（实际成交金额）
--   * hyc_value：仅用于价格档分层（标准价值），与实际成交金额不完全一致；
--                从 revenue 侧按 user_consume_amount 反查 19.9 会捞到大量抽奖订单
--                （守护磁铁、星星碎片等按次扣费的道具），必须用 is_draw = 0 剔除
--   * 付费人数：count(distinct ext['ukey'])，即去重付费用户数
-- =====================================================================


-- 语句1：AI 礼物各价格档首次出现时间（用于定位 19.9 档上线日期）
with ai_item_tier as (
    select
        cast(d.hyc_value as double) as hyc_value,
        min(d.dt) as first_dt,
        max(d.dt) as last_dt,
        count(distinct d.item_id) as item_cnt
    from gamelive.dim_huya_item_d_a d
    where d.dt between '2026-07-13' and '2026-09-19'
      and d.item_level = '礼物'
      and element_at(d.ext, 'is_ai') = '1'
    group by cast(d.hyc_value as double)
)
select
    hyc_value,
    first_dt,
    last_dt,
    item_cnt
from ai_item_tier
order by
    first_dt,
    hyc_value
;


-- 语句2：19.9 档礼物逐日销售情况（AI 礼物 vs 直送普通礼物）
--        起点取语句1得到的 AI 19.9 首日 = 2026-09-14
with item_dim as (
    select
        dt,
        cast(item_id as varchar) as item_id,
        max(cast(hyc_value as double)) as hyc_value,
        max(case when element_at(ext, 'is_ai') = '1' then 1 else 0 end) as is_ai,
        max(case when play_type in ('抽奖') then 1 else 0 end) as is_draw
    from gamelive.dim_huya_item_d_a
    where dt between '2026-09-14' and '2026-09-19'
      and item_level = '礼物'
      and abs(cast(hyc_value as double) - 19.9) < 0.05
    group by dt, cast(item_id as varchar)
)
select
    r.dt as dt,
    case when d.is_ai = 1 then 'AI礼物' else '普通礼物' end as is_ai,
    count(distinct element_at(r.ext, 'ukey')) as pay_user_cnt,
    count(distinct r.order_id) as order_cnt,
    sum(cast(r.user_consume_amount as double)) as sales_amount
from gamelive.dws_huya_revenue_detail_d_i r
inner join item_dim d
    on r.dt = d.dt
   and cast(r.item_id as varchar) = d.item_id
where r.dt between '2026-09-14' and '2026-09-19'
  and r.consume_order_type = '礼物'
  and cast(r.user_consume_amount as double) > 0
  and r.user_uid is not null
  and lower(cast(r.user_uid as varchar)) not in ('0', 'other')
  and element_at(r.ext, 'ukey') is not null
  and d.is_draw = 0
group by
    r.dt,
    case when d.is_ai = 1 then 'AI礼物' else '普通礼物' end
order by
    dt,
    is_ai
;


-- 语句3：同期间（2026-09-14 ~ 2026-09-19）直送普通礼物价格档分布
--        用于说明 19.9 在直送普通礼物体系中几乎没有在售量，需看相邻价位档
with item_dim as (
    select
        dt,
        cast(item_id as varchar) as item_id,
        max(cast(hyc_value as double)) as hyc_value,
        max(case when element_at(ext, 'is_ai') = '1' then 1 else 0 end) as is_ai,
        max(case when play_type in ('抽奖') then 1 else 0 end) as is_draw
    from gamelive.dim_huya_item_d_a
    where dt between '2026-09-14' and '2026-09-19'
      and item_level = '礼物'
    group by dt, cast(item_id as varchar)
)
select
    d.hyc_value as hyc_value,
    count(distinct r.order_id) as order_cnt,
    count(distinct element_at(r.ext, 'ukey')) as pay_user_cnt,
    sum(cast(r.user_consume_amount as double)) as sales_amount
from gamelive.dws_huya_revenue_detail_d_i r
inner join item_dim d
    on r.dt = d.dt
   and cast(r.item_id as varchar) = d.item_id
where r.dt between '2026-09-14' and '2026-09-19'
  and r.consume_order_type = '礼物'
  and cast(r.user_consume_amount as double) > 0
  and r.user_uid is not null
  and lower(cast(r.user_uid as varchar)) not in ('0', 'other')
  and element_at(r.ext, 'ukey') is not null
  and d.is_ai = 0
  and d.is_draw = 0
group by d.hyc_value
order by order_cnt desc
limit 30
;


-- 语句4：同期间（2026-09-14 ~ 2026-09-19）AI 礼物各价格档销售情况（作为 AI 内部对照）
with item_dim as (
    select
        dt,
        cast(item_id as varchar) as item_id,
        max(cast(hyc_value as double)) as hyc_value,
        max(case when element_at(ext, 'is_ai') = '1' then 1 else 0 end) as is_ai,
        max(case when play_type in ('抽奖') then 1 else 0 end) as is_draw
    from gamelive.dim_huya_item_d_a
    where dt between '2026-09-14' and '2026-09-19'
      and item_level = '礼物'
    group by dt, cast(item_id as varchar)
)
select
    d.hyc_value as hyc_value,
    count(distinct element_at(r.ext, 'ukey')) as pay_user_cnt,
    count(distinct r.order_id) as order_cnt,
    sum(cast(r.user_consume_amount as double)) as sales_amount
from gamelive.dws_huya_revenue_detail_d_i r
inner join item_dim d
    on r.dt = d.dt
   and cast(r.item_id as varchar) = d.item_id
where r.dt between '2026-09-14' and '2026-09-19'
  and r.consume_order_type = '礼物'
  and cast(r.user_consume_amount as double) > 0
  and r.user_uid is not null
  and lower(cast(r.user_uid as varchar)) not in ('0', 'other')
  and element_at(r.ext, 'ukey') is not null
  and d.is_ai = 1
  and d.is_draw = 0
group by d.hyc_value
order by order_cnt desc
;


-- 语句5：19.9 档 AI 礼物道具明细（确认首个道具与上线节奏）
select
    d.dt as dt,
    cast(d.item_id as varchar) as item_id,
    max(cast(d.item_name as varchar)) as item_name,
    max(cast(d.hyc_value as double)) as hyc_value
from gamelive.dim_huya_item_d_a d
where d.dt between '2026-09-14' and '2026-09-19'
  and d.item_level = '礼物'
  and element_at(d.ext, 'is_ai') = '1'
  and abs(cast(d.hyc_value as double) - 19.9) < 0.05
group by d.dt, cast(d.item_id as varchar)
order by dt, item_id
;
