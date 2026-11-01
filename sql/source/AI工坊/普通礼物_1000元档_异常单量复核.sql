-- =====================================================================
-- 目的：复核「普通礼物 1000 元档单量远高于 520 元档」这一异常曲线是否为真实消费结构。
--       验证路径：
--         1）1000 元档在道具维表里的道具构成（是否混入守护/月票/粉丝牌等非礼物类道具）
--         2）1000 元档按道具拆分的单量/人数/人均单数（找出异常道具）
--         3）异常道具的用户集中度与逐日分布
--         4）与「剔除刷单」表 zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i 对照
--
-- 时间窗：2026-07-13 ~ 2026-09-19（AI工坊上线日 ~ 最新可用分区）
--
-- 口径说明：
--   * 金额口径：user_consume_amount（实际成交金额）；hyc_value 仅用于价格档分层
--   * 礼物识别：dim_huya_item_d_a.item_level = '礼物'
--   * AI 礼物：element_at(ext,'is_ai') = '1'；普通礼物：coalesce(element_at(ext,'is_ai'),'0') <> '1'
--   * 抽奖 / 直送：play_type = '抽奖' 记为抽奖
--   * 订单过滤：consume_order_type = '礼物'、user_consume_amount > 0、
--              user_uid 非空且不为 0/other、ext['ukey'] 非空
--   * 单量：count(distinct order_id)；人数：count(distinct ext['ukey'])
-- =====================================================================


-- 语句1：1000 元档在道具维表里的构成（item_level × play_type）
--        结论预期：只有 '礼物/普通' 与 '礼物/抽奖'，不存在守护/月票/粉丝牌类道具
select
    cast(d.item_level as varchar) as item_level,
    cast(d.play_type as varchar) as play_type,
    count(distinct d.item_id) as item_cnt
from gamelive.dim_huya_item_d_a d
where d.dt = '2026-09-19'
  and abs(cast(d.hyc_value as double) - 1000) < 0.5
group by
    cast(d.item_level as varchar),
    cast(d.play_type as varchar)
order by item_cnt desc
;


-- 语句2：1000 元档 直送普通礼物 按道具拆分（全窗口）
--        order_per_user（人均单数）用于识别复购/连击/异常道具
select
    cast(r.item_id as varchar) as item_id,
    count(distinct r.order_id) as order_cnt,
    count(distinct element_at(r.ext,'ukey')) as pay_user_cnt,
    round(cast(count(distinct r.order_id) as double)
          / count(distinct element_at(r.ext,'ukey')), 2) as order_per_user,
    round(sum(cast(r.user_consume_amount as double)), 0) as sales_amount
from gamelive.dws_huya_revenue_detail_d_i r
where r.dt between '2026-07-13' and '2026-09-19'
  and r.consume_order_type = '礼物'
  and cast(r.user_consume_amount as double) > 0
  and r.user_uid is not null
  and lower(cast(r.user_uid as varchar)) not in ('0','other')
  and element_at(r.ext,'ukey') is not null
  and cast(r.item_id as varchar) in (
      select cast(d.item_id as varchar)
      from gamelive.dim_huya_item_d_a d
      where d.dt = '2026-09-19'
        and d.item_level = '礼物'
        and abs(cast(d.hyc_value as double) - 1000) < 0.5
        and coalesce(element_at(d.ext,'is_ai'),'0') <> '1'
        and coalesce(cast(d.play_type as varchar),'') <> '抽奖'
  )
group by cast(r.item_id as varchar)
order by order_cnt desc
limit 50
;


-- 语句3：异常道具的用户集中度（以 20859 圣灵之梦 为例，可替换 item_id）
with u as (
    select
        element_at(r.ext,'ukey') as ukey,
        count(distinct r.order_id) as order_cnt,
        sum(cast(r.user_consume_amount as double)) as amt
    from gamelive.dws_huya_revenue_detail_d_i r
    where r.dt between '2026-07-13' and '2026-09-19'
      and r.consume_order_type = '礼物'
      and cast(r.item_id as varchar) = '20859'
      and cast(r.user_consume_amount as double) > 0
      and element_at(r.ext,'ukey') is not null
    group by element_at(r.ext,'ukey')
)
select
    count(1) as user_cnt,
    max(order_cnt) as max_orders_per_user,
    sum(case when order_cnt >= 100 then 1 else 0 end) as users_ge_100_orders,
    sum(case when order_cnt >= 100 then order_cnt else 0 end) as orders_from_users_ge_100,
    sum(order_cnt) as orders_total,
    round(sum(amt), 0) as amt_total
from u
;


-- 语句4：异常道具逐日分布（看是否存在极少数人单日高频送出的尖峰）
select
    r.dt as dt,
    count(distinct r.order_id) as order_cnt,
    count(distinct element_at(r.ext,'ukey')) as pay_user_cnt,
    round(sum(cast(r.user_consume_amount as double)), 0) as sales_amount
from gamelive.dws_huya_revenue_detail_d_i r
where r.dt between '2026-07-13' and '2026-09-19'
  and r.consume_order_type = '礼物'
  and cast(r.item_id as varchar) = '20859'
  and cast(r.user_consume_amount as double) > 0
group by r.dt
order by r.dt
;


-- 语句5：原始表 vs 剔除刷单表 对照（同一道具，同一时间窗）
--        剔除刷单表：zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i
select
    cast(r.item_id as varchar) as item_id,
    count(distinct r.order_id) as order_cnt,
    count(distinct element_at(r.ext,'ukey')) as pay_user_cnt,
    round(sum(cast(r.user_consume_amount as double)), 0) as sales_amount
from zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i r
where r.dt between '2026-07-13' and '2026-09-19'
  and r.consume_order_type = '礼物'
  and cast(r.item_id as varchar) in ('20859', '20269')
  and cast(r.user_consume_amount as double) > 0
group by cast(r.item_id as varchar)
;


-- 语句6：剔除刷单 + 剔除抽奖后，普通礼物 52 / 131.4 / 520 / 1000 元档横向对比
--        必须同时剔除抽奖：52 元标准价值档在原始表里被 42 个抽奖道具贡献了 2.7 万单，
--        不剔除抽奖会把 52 元档严重高估（剔除后 52 元直送普通仅 461 单）
select
    cast(d.hyc_value as double) as hyc_value,
    count(distinct r.order_id) as order_cnt,
    count(distinct element_at(r.ext,'ukey')) as pay_user_cnt,
    round(cast(count(distinct r.order_id) as double)
          / count(distinct element_at(r.ext,'ukey')), 2) as order_per_user,
    round(sum(cast(r.user_consume_amount as double)), 0) as sales_amount
from zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i r
inner join (
    select
        cast(item_id as varchar) as item_id,
        max(cast(hyc_value as double)) as hyc_value
    from gamelive.dim_huya_item_d_a
    where dt = '2026-09-19'
      and item_level = '礼物'
      and coalesce(cast(play_type as varchar),'') <> '抽奖'
      and (
           abs(cast(hyc_value as double) - 1000) < 0.5
        or abs(cast(hyc_value as double) - 520) < 0.5
        or abs(cast(hyc_value as double) - 131.4) < 0.05
        or abs(cast(hyc_value as double) - 52) < 0.05
      )
    group by cast(item_id as varchar)
) d
    on cast(r.item_id as varchar) = d.item_id
where r.dt between '2026-07-13' and '2026-09-19'
  and r.consume_order_type = '礼物'
  and cast(r.user_consume_amount as double) > 0
  and r.user_uid is not null
  and lower(cast(r.user_uid as varchar)) not in ('0','other')
  and element_at(r.ext,'ukey') is not null
group by cast(d.hyc_value as double)
order by hyc_value
;
