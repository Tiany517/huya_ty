-- ============================================================
-- 三群购买能力画像：抽奖单日满52 / 直送单日满52 / 直送消费下限≥52
-- 时间窗口：2026-07-13 ~ 2026-09-14（64 天）
-- 输出粒度：每个口径 2 行（订单级指标 / 用户级指标）
-- ============================================================
-- 三个口径定义（均为窗口内「曾经达到」，不是常态）：
--   A_抽奖单日满52    窗口内任意一天，抽奖类订单当日合计金额 >= 52 元
--   B_直送单日满52    窗口内任意一天，直送类订单当日合计金额 >= 52 元
--   C_直送下限>=52    窗口内所有直送订单的礼物标准价值(hyc_value) 均 >= 52 元
-- 指标口径：
--   avg_direct_amt_per_user   人均直送流水（窗口内累计）
--   avg_direct_order_per_user 人均直送订单数
--   direct_amt_p50 / p90      直送单笔金额中位数 / P90
--   avg_draw_* / draw_amt_*   同上，抽奖侧
--   avg_direct_day_cnt        人均有直送支付的天数
--   touch_52_pct / touch_1000_pct  该群中买过 52 元档 / 1000 元档直送礼物的占比
--   both_52_1000_pct          同时买过 52 元档和 1000 元档直送礼物的占比
-- 说明：
--   1) 全部指标基于 consume_order_type = '礼物'，不含守护/月票等非礼物消费
--   2) 流水为窗口内累计值，不是日均；要日均除以 64
--   3) 抽奖/直送以道具维表 play_type = '抽奖' 区分
--   4) hyc_value 为礼物标准价值，仅用于价格档分层
--   5) ext 用 element_at 取值，key 缺失时返回 NULL
-- ============================================================

with item_dim as (
    select
        d.dt as dt,
        cast(d.item_id as varchar) as item_id,
        max(cast(d.hyc_value as double)) as hyc_value,
        max(case when d.play_type in ('抽奖') then 1 else 0 end) as is_draw
    from gamelive.dim_huya_item_d_a d
    where d.dt between '2026-07-13' and '2026-09-14'
      and d.item_level = '礼物'
    group by d.dt, cast(d.item_id as varchar)
),

o as (
    select
        r.dt as dt,
        cast(element_at(r.ext, 'ukey') as varchar) as ukey,
        cast(r.order_id as varchar) as order_id,
        cast(r.user_consume_amount as double) as amt,
        i.is_draw as is_draw,
        i.hyc_value as hyc_value
    from gamelive.dws_huya_revenue_detail_d_i r
    inner join item_dim i
        on r.dt = i.dt
       and cast(r.item_id as varchar) = i.item_id
    where r.dt between '2026-07-13' and '2026-09-14'
      and r.consume_order_type = '礼物'
      and cast(r.user_consume_amount as double) > 0
      and r.user_uid is not null
      and lower(cast(r.user_uid as varchar)) not in ('0', 'other')
      and element_at(r.ext, 'ukey') is not null
      and lower(cast(element_at(r.ext, 'ukey') as varchar)) not in ('', '0', 'other')
),

day_ukey as (
    -- 用户 × 日期 × 玩法 的当日金额，用于判断「单日累计满 52 元」
    select ukey, dt, is_draw, sum(amt) as day_amt
    from o
    group by ukey, dt, is_draw
),

flags as (
    select
        ukey,
        max(case when is_draw = 1 and day_amt >= 52 then 1 else 0 end) as f_draw_day52,
        max(case when is_draw = 0 and day_amt >= 52 then 1 else 0 end) as f_direct_day52
    from day_ukey
    group by ukey
),

minflag as (
    select
        ukey,
        min(case when is_draw = 0 then hyc_value end) as min_direct_price
    from o
    group by ukey
),

grp as (
    select 'A_抽奖单日满52' as grp, ukey from flags where f_draw_day52 = 1
    union all
    select 'B_直送单日满52' as grp, ukey from flags where f_direct_day52 = 1
    union all
    select 'C_直送下限>=52' as grp, ukey from minflag where min_direct_price >= 52
),

main_metrics as (
    select
        g.grp as grp,
        count(distinct g.ukey) as pay_user_cnt,
        round(sum(case when o.is_draw = 0 then o.amt else 0 end) / count(distinct g.ukey), 0) as avg_direct_amt_per_user,
        round(cast(sum(case when o.is_draw = 0 then 1 else 0 end) as double) / count(distinct g.ukey), 1) as avg_direct_order_per_user,
        round(approx_percentile(case when o.is_draw = 0 then o.amt end, 0.5), 1) as direct_amt_p50,
        round(approx_percentile(case when o.is_draw = 0 then o.amt end, 0.9), 1) as direct_amt_p90,
        round(sum(case when o.is_draw = 1 then o.amt else 0 end) / count(distinct g.ukey), 0) as avg_draw_amt_per_user,
        round(cast(sum(case when o.is_draw = 1 then 1 else 0 end) as double) / count(distinct g.ukey), 1) as avg_draw_order_per_user,
        round(approx_percentile(case when o.is_draw = 1 then o.amt end, 0.5), 1) as draw_amt_p50,
        round(approx_percentile(case when o.is_draw = 1 then o.amt end, 0.9), 1) as draw_amt_p90
    from grp g
    inner join o
        on g.ukey = o.ukey
    group by g.grp
),

user_base as (
    select
        ukey,
        count(distinct case when is_draw = 0 then dt end) as direct_day_cnt,
        count(distinct case when is_draw = 1 then dt end) as draw_day_cnt
    from o
    group by ukey
),

cats as (
    select
        ukey,
        max(case when is_draw = 0 and abs(hyc_value - 52) < 0.05 then 1 else 0 end) as b52,
        max(case when is_draw = 0 and abs(hyc_value - 1000) < 0.5 then 1 else 0 end) as b1000
    from o
    group by ukey
),

user_metrics as (
    select
        g.grp as grp,
        count(1) as pay_user_cnt,
        round(avg(cast(u.direct_day_cnt as double)), 2) as avg_direct_day_cnt,
        round(avg(cast(u.draw_day_cnt as double)), 2) as avg_draw_day_cnt,
        round(100.0 * sum(case when c.b52 = 1 then 1 else 0 end) / count(1), 1) as touch_52_pct,
        round(100.0 * sum(case when c.b1000 = 1 then 1 else 0 end) / count(1), 1) as touch_1000_pct,
        round(100.0 * sum(case when c.b52 = 1 and c.b1000 = 1 then 1 else 0 end) / count(1), 1) as both_52_1000_pct
    from grp g
    inner join user_base u
        on g.ukey = u.ukey
    inner join cats c
        on g.ukey = c.ukey
    group by g.grp
)

select
    'main' as metric_type,
    grp,
    pay_user_cnt,
    avg_direct_amt_per_user,
    avg_direct_order_per_user,
    direct_amt_p50,
    direct_amt_p90,
    avg_draw_amt_per_user,
    avg_draw_order_per_user,
    draw_amt_p50,
    draw_amt_p90,
    cast(null as double) as avg_direct_day_cnt,
    cast(null as double) as avg_draw_day_cnt,
    cast(null as double) as touch_52_pct,
    cast(null as double) as touch_1000_pct,
    cast(null as double) as both_52_1000_pct
from main_metrics
union all
select
    'user' as metric_type,
    grp,
    pay_user_cnt,
    cast(null as double),
    cast(null as double),
    cast(null as double),
    cast(null as double),
    cast(null as double),
    cast(null as double),
    cast(null as double),
    cast(null as double),
    avg_direct_day_cnt,
    avg_draw_day_cnt,
    touch_52_pct,
    touch_1000_pct,
    both_52_1000_pct
from user_metrics
order by metric_type, grp
;
