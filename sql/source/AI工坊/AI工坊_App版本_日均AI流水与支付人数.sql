-- ============================================================
-- AI工坊 × App版本：各版本 日均AI流水 / 日均AI支付人数
-- 时间窗口：2026-07-13 ~ 2026-09-14
-- 输出粒度：每个版本一行
-- ============================================================
-- 字段口径：
--   iver_line                    版本大类（13.4 / 13.3 / 13.2）
--   iver                         版本号
--   day_cnt                      该版本当天有活跃用户的天数（日均的天数分母）
--   ai_amount_total              该版本口径内 AI 礼物（非抽奖）总流水
--   avg_ai_pay_user_cnt_by_day   日均AI支付人数（revenue 表实际送出 AI 礼物的人，按用户当天版本归属）
--   avg_ai_amount_by_day         日均AI流水
-- 说明：
--   1) AI 支付人来自 revenue 表（无版本字段），按「付费人当天的 App 版本」归属；
--      因此只统计当天在 4 个 App 端有会话、且版本命中白名单的用户；
--      PC/Web/HD/WAP 等端天然没有 App 版本号，会被排除
--   2) 版本归属是「用户×日期」级别：同一 ukey 在不同日期可能属于不同版本，
--      所以每个 CTE 都必须带 dt 关联
--   3) 日均 = 该版本有效天数上的算术平均，各版本 day_cnt 不同，不能直接比总量
--   4) 抽奖礼物按 play_type = '抽奖' 剔除；AI 礼物按 ext['is_ai'] = '1' 识别
--   5) ext 用 element_at 取值：key 不存在时返回 NULL，避免 Presto 直接报错
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

ai_gift_pay_user_day as (
    -- 人天粒度：AI 礼物（非抽奖）的支付人 + 当天 AI 流水
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
      and element_at(r.ext, 'ukey') is not null
      and lower(cast(element_at(r.ext, 'ukey') as varchar)) not in ('', '0', 'other')
    group by
        r.dt,
        cast(element_at(r.ext, 'ukey') as varchar)
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
            '13.4.63', '13.4.52', '13.4.41', '13.4.40', '13.4.22', '13.4.2', '13.4.0', '13.3.82'
      )
      and s.ukey is not null
    group by
        s.dt,
        cast(s.ukey as varchar)
),

version_day_base as (
    -- 骨架：该版本当天有活跃用户的全部 (dt, iver)，用作「日均」的天数分母
    select distinct
        v.dt as dt,
        v.iver as iver
    from user_version_day v
),

pay_by_version_day as (
    -- 分子：当日该版本的 AI 支付人数、AI 流水
    select
        v.dt as dt,
        v.iver as iver,
        count(distinct p.ukey) as ai_pay_user_cnt,
        sum(p.ai_amount) as ai_amount
    from ai_gift_pay_user_day p
    inner join user_version_day v
        on p.dt = v.dt
       and p.ukey = v.ukey
    group by
        v.dt,
        v.iver
),

daily as (
    -- 按 (dt, iver) 对齐，支付人/流水为空的天补 0，保证 day_cnt 与均值同一套天
    select
        b.dt as dt,
        b.iver as iver,
        coalesce(p.ai_pay_user_cnt, 0) as ai_pay_user_cnt,
        coalesce(p.ai_amount, 0) as ai_amount
    from version_day_base b
    left join pay_by_version_day p
        on b.dt = p.dt
       and b.iver = p.iver
)

select
    case
        when iver like '13.4.%' then '13.4'
        when iver like '13.3.%' then '13.3'
        when iver like '13.2.%' then '13.2'
    end as iver_line,
    iver,
    count(1) as day_cnt,
    round(sum(ai_amount), 0) as ai_amount_total,
    round(avg(cast(ai_pay_user_cnt as double)), 1) as avg_ai_pay_user_cnt_by_day,
    round(avg(ai_amount), 0) as avg_ai_amount_by_day
from daily
group by
    case
        when iver like '13.4.%' then '13.4'
        when iver like '13.3.%' then '13.3'
        when iver like '13.2.%' then '13.2'
    end,
    iver
order by
    iver
;
