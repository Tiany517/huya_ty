-- ============================================================
-- AI工坊 × App版本：剥离时间趋势 · 方案一「同日基准折算」
-- 时间窗口：2026-07-13 ~ 2026-09-14
-- 输出粒度：每个版本一行
-- ============================================================
-- 【要解决的问题】
--   8 个版本的活跃窗口高度重叠（13.3.82 从 7/13 到 9/14 共 64 天，13.4.63 只有 7 天），
--   版本号和时间几乎共线。直接横比「13.4.63 转化率 0.0754% vs 13.3.82 的 0.0208%」，
--   比出来的其实是「9 月 vs 7 月」。实测这段时间大盘自己的转化率就从 0.0124% 涨到 0.0751%，
--   所以必须先把这个共同的时间因素扣掉。
--
-- 【方案一在干什么】同日基准折算
--   第1步：按 (天, 版本) 算该版本当天的曝光人数 / 支付人数 / AI 流水
--   第2步：按「天」算基准 = 白名单 8 个版本当天的合计效率
--            基准转化率       = 当天 8 版本支付人数合计 / 当天 8 版本曝光人数合计
--            基准曝光人均流水 = 当天 8 版本 AI 流水合计 / 当天 8 版本曝光人数合计
--   第3步：把该版本每天的曝光，按当天基准折成「应得值」
--            应得支付人数 = 曝光人数 × 当天基准转化率
--            应得AI流水   = 曝光人数 × 当天基准曝光人均流水
--   第4步：指数 = 实际合计 / 应得合计（比率求和，不是逐日比值的简单平均）
--
--   为什么除当天基准就能扣掉时间：应得值用的是「同一天、同人群口径」的效率。
--   任何只作用在当天的共同冲击（大盘曝光衰减、活动位撤下、9/1 曝光口径切换、季节性）
--   在版本实际值和应得值里同时出现，相除时被约掉。剩下的差异才是这个版本相对同期其他版本的位置。
--
--   举例：某版本某天曝光 10 万、实际支付 60 人；当天 8 版本合计转化率 0.05%，
--         则应得支付 50 人，当天指数 = 60/50 = 1.2。把该版本所有天这样加总，就是它的最终指数。
--
-- 【为什么不逐日比值再平均】
--   简单平均会给曝光只有几千的那一天和曝光几十万的那一天同样的权重，被噪声主导。
--   实测 13.3.82 简单平均 = 1.141，比率求和 = 0.977，方向都相反。
--   比率求和天然按曝光加权，且对「一个版本多一天少一天」不敏感，所以用它。
--
-- 【怎么读结果】
--   avg_conv_idx    支付人数指数：> 1 表示这个版本的人比其他版本更愿意掏钱
--   avg_amount_idx  流水指数：> 1 表示这个版本带来的流水高于同期基准
--   两者关系：流水指数 ≈ 支付人数指数 × ARPPU 指数
--   每个指数的加权平均恒为 1，只能横向比版本，不能解释成绝对好坏
--
-- 【实测结果（供核对，本次已跑）】
--   支付人数指数：0.977(13.3.82) 0.987(13.4.0) 0.991(13.4.2) 1.024(13.4.22)
--                 1.046(13.4.40) 0.992(13.4.41) 1.000(13.4.52) 0.989(13.4.63)
--                 → 剥离时间后 8 个版本差异不到 5%，版本对「愿不愿意付费」几乎没有影响
--   流水指数：    0.926 1.142 0.762 1.186 1.127 0.885 1.021 1.191（同上顺序）
--                 → 差异约 ±20%，且方向与版本新旧不一致，受少数大额订单影响大
--
-- 【口径与限制】
--   1. 基准是白名单 8 个版本当天的合计，不是全体 App 大盘。
--      用全体 App 大盘会掺入白名单外版本，把基准拉低，导致所有版本指数都大于 1、失去区分度。
--      文件末尾附了 App 大盘口径供对照。
--   2. 支付人数用常规口径：revenue 表当天实际送出过 AI 礼物的人（人天去重）。
--   3. 版本归属按 (日期, ukey) 取一个版本号；PC / Web 无版本号，天然排除。
--   4. 曝光 < 100 的版本-天不参与，避免灰度首日单日抖动。
--   5. 方案一的隐含假设是「版本效应与时间效应相乘」。它只能回答
--      「相对同期其他版本好多少」，不能回答「绝对涨了多少」。
--   6. 已知数据问题：曝光口径在 2026-09-01 有约 4 倍断崖（大盘 134.7 万 → 31.8 万），
--      9/1 前后的曝光和转化率不可直接比，需先与调度表口径负责人确认。
--      同日基准折算对该断点免疫（版本和基准同步变化），但它无法区分
--      「版本效应」和「随 9/1 一起发生的其他策略变更」。
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
        max(case when t.is_exposure then 1 else 0 end) as is_exposure
    from zhgametemp.zty_ads_huya_ai_gift_user_detail_0901_v1 t
    where t.dt between '2026-07-13' and '2026-09-14'
      and t.user_ukey is not null
    group by
        t.dt,
        cast(t.user_ukey as varchar)
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
    -- funnel_user_day 与 ai_gift_pay_user_day 都已收敛到 (dt, ukey) 一行，两路 join 不会互相放大
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

wl_day as (
    -- 基准：白名单 8 个版本当天合计（不是全体 App 大盘）
    select
        dt as dt,
        sum(exposure_user_cnt) as wl_exposure_user_cnt,
        sum(pay_user_cnt) as wl_pay_user_cnt,
        sum(ai_amount) as wl_ai_amount,
        sum(pay_user_cnt) / sum(exposure_user_cnt) as wl_conv_rate,
        sum(ai_amount) / sum(exposure_user_cnt) as wl_amt_per_exposure
    from version_day
    where exposure_user_cnt > 0
    group by
        dt
),

daily_base as (
    -- 版本 × 天：实际值 + 按当天基准折算的应得值
    select
        d.dt as dt,
        d.iver as iver,
        d.exposure_user_cnt as exposure_user_cnt,
        d.pay_user_cnt as pay_user_cnt,
        d.ai_amount as ai_amount,
        d.exposure_user_cnt * w.wl_conv_rate as expect_pay_user_cnt,
        d.exposure_user_cnt * w.wl_amt_per_exposure as expect_ai_amount
    from version_day d
    inner join wl_day w
        on d.dt = w.dt
    where d.exposure_user_cnt >= 100
)

select
    case
        when iver like '13.4.%' then '13.4'
        when iver like '13.3.%' then '13.3'
        when iver like '13.2.%' then '13.2'
        else '其他'
    end as iver_line,
    iver as iver,
    count(1) as day_cnt,
    round(avg(cast(exposure_user_cnt as double)), 0) as avg_exposure_user_cnt_by_day,
    round(avg(cast(pay_user_cnt as double)), 1) as avg_pay_user_cnt_by_day,
    round(avg(expect_pay_user_cnt), 1) as avg_expect_pay_user_cnt_by_day,
    round(sum(cast(pay_user_cnt as double)) / sum(expect_pay_user_cnt), 3) as conv_idx,
    round(avg(ai_amount), 0) as avg_ai_amount_by_day,
    round(avg(expect_ai_amount), 0) as avg_expect_ai_amount_by_day,
    round(sum(ai_amount) / sum(expect_ai_amount), 3) as amount_idx,
    round(sum(ai_amount) / sum(cast(pay_user_cnt as double)), 1) as arppu,
    round(sum(cast(pay_user_cnt as double)) / sum(cast(exposure_user_cnt as double)) * 100, 4) as conv_rate_pct,
    round(sum(ai_amount) / sum(cast(exposure_user_cnt as double)), 4) as amt_per_exposure
from daily_base
group by
    case
        when iver like '13.4.%' then '13.4'
        when iver like '13.3.%' then '13.3'
        when iver like '13.2.%' then '13.2'
        else '其他'
    end,
    iver
order by
    iver
;

-- ============================================================
-- 【附1】逐日明细：核对每个版本的指数是怎么加出来的（也可以直接拿去画折线）
--   把上面最后的 select 整段换成下面这段，CTE 不用动：
--
--   select
--       dt,
--       iver,
--       exposure_user_cnt,
--       pay_user_cnt,
--       round(expect_pay_user_cnt, 2) as expect_pay_user_cnt,
--       round(expect_ai_amount, 1) as expect_ai_amount,
--       round(ai_amount, 1) as ai_amount
--   from daily_base
--   order by
--       iver,
--       dt
--   ;
--
-- 【附2】口径断点体检：白名单合计占全体 App 大盘的比重
--   2026-09-01 前后该比重从约 55% 跳到约 94%，说明曝光口径发生变化。
--   做法：另建 market_user_day（4 个 App 端、不限版本白名单、iver 非空）算出大盘曝光，再与 wl_day 相除。
--
-- 【附3】换成「漏斗口径」支付人数
--   在 funnel_user_day 里补 max(case when t.is_pay then 1 else 0 end) as is_pay，
--   把 version_day 的 pay_user_cnt 换成
--       count(distinct case when u.is_exposure = 1 and u.is_pay = 1 then v.ukey end)
--   注意换完之后 ai_amount（流水）与 pay_user_cnt（漏斗人数）口径不一致，
--   只看 conv_idx，不要看 amount_idx。
-- ============================================================
