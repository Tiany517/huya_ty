-- ============================================================
-- AI工坊 × App版本：不剥离时间趋势，只算「本版本自己窗口内」的日均流水与转换率
-- 时间窗口：2026-07-13 ~ 2026-09-14
-- 输出粒度：每个版本一行
-- ============================================================
-- 【这份 SQL 回答什么】
--   13.3.82 就只算它主推那段（7/13~7/19）的日均流水和转换率，
--   13.4.63 就只算它主推那段（9/8~9/14），不考虑大盘如何变化。
--
-- 【为什么窗口不能靠人肉拍一个日期】
--   之前那张表给出的 day_cnt 是 64/57/50/39/35/25/15/7，加起来 292 天，
--   远超 64 天的窗口长度。说明版本不是「上一个退干净、下一个才上」，
--   而是长期共存的：13.3.82 在全部 64 天都有曝光，13.4.63 只有最后 7 天。
--   所以「13.3.82 只算 7/13~7/19」是一个需要验证的假设，不能直接写死。
--
--   这里用数据来定义窗口：某天哪个版本的曝光量最大，那天就归它，
--   连续归属它的日期段就是它的「主推窗口」，取 min(dt) ~ max(dt)。
--   窗口边界跑出来以后，再和之前那张表里的 range 列对一下是否一致。
--
-- 【输出字段】
--   iver_line                          版本大类
--   iver                               版本号
--   win_start_dt / win_end_dt          主推窗口（该版本当天曝光量最大）
--   day_cnt                            窗口内该版本有量（曝光 >= 100）的天数
--   avg_exposure_user_cnt_by_day       窗口内日均曝光人数
--   avg_exposure_share_by_day          窗口内日均曝光占大盘比重（判断窗口含金量）
--   avg_pay_user_cnt_by_day            窗口内日均AI礼物支付人数（常规口径）
--   avg_ai_amount_by_day               窗口内日均AI流水
--   avg_conv_rate_by_day_pct           窗口内日均转化率（逐日比值算术平均）
--   full_*                             该版本出现过的全部天（含被取代后的长尾）的同口径值，仅作对照
--
-- 【口径与限制】
--   1. 支付人数用常规口径：revenue 表当天实际送出过 AI 礼物的人（人天去重）
--   2. 大盘 = 当天 4 个 App 端里有版本号的全体用户；PC / Web 无版本号，天然排除
--   3. 版本-天曝光人数 < 100 的天不参与，避免灰度首日和退场长尾把均值带偏
--   4. 这份结果按定义包含时间趋势，只能回答「这个版本在那段时间表现如何」，
--      不能回答「新版本是不是比老版本好」——后者要看同日大盘指数
--   5. 主推窗口用 min/max 取连续段，如果某个版本中途被抢回、区间不连续，
--      它会盖住中间的空档；用附1 的明细可以核对
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
            '13.3.82','13.4.0', '13.4.2', '13.4.22', '13.4.40', '13.4.41', '13.4.52', '13.4.63'
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
    -- 大盘 × 天：同口径
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
),

daily as (
    -- 版本 × 天：版本原始值 + 大盘值 + 曝光占比（曝光 < 100 的天剔除）
    select
        d.dt as dt,
        d.iver as iver,
        d.exposure_user_cnt as exposure_user_cnt,
        d.pay_user_cnt as pay_user_cnt,
        d.ai_amount as ai_amount,
        case when m.exposure_user_cnt > 0
             then cast(d.exposure_user_cnt as double) / m.exposure_user_cnt end as exposure_share
    from version_day d
    inner join market_day m
        on d.dt = m.dt
    where d.exposure_user_cnt >= 100
      and m.exposure_user_cnt > 0
),

leader_day as (
    -- 每天曝光量最大的版本 = 当天主推版本
    select
        dt,
        iver as leader_iver
    from (
        select
            dt,
            iver,
            row_number() over (partition by dt order by exposure_user_cnt desc) as rn
        from daily
    ) t
    where rn = 1
),

version_window as (
    -- 主推窗口：连续归属该版本的日期段
    select
        leader_iver as iver,
        min(dt) as win_start_dt,
        max(dt) as win_end_dt,
        count(1) as leader_day_cnt
    from leader_day
    group by
        leader_iver
),

own_window as (
    -- 窗口内：该版本自己的日均值
    select
        d.iver as iver,
        w.win_start_dt as win_start_dt,
        w.win_end_dt as win_end_dt,
        w.leader_day_cnt as leader_day_cnt,
        count(1) as day_cnt,
        avg(cast(d.exposure_user_cnt as double)) as avg_exposure_user_cnt_by_day,
        avg(d.exposure_share) as avg_exposure_share_by_day,
        avg(cast(d.pay_user_cnt as double)) as avg_pay_user_cnt_by_day,
        avg(d.ai_amount) as avg_ai_amount_by_day,
        avg(
            case when d.exposure_user_cnt > 0
                 then cast(d.pay_user_cnt as double) / d.exposure_user_cnt end
        ) as avg_conv_rate_by_day
    from daily d
    inner join version_window w
        on d.iver = w.iver
    where d.dt between w.win_start_dt and w.win_end_dt
    group by
        d.iver,
        w.win_start_dt,
        w.win_end_dt,
        w.leader_day_cnt
),

full_window as (
    -- 该版本出现过的全部天（含被取代后的长尾），仅作对照
    select
        iver as iver,
        min(dt) as full_start_dt,
        max(dt) as full_end_dt,
        count(1) as full_day_cnt,
        avg(exposure_share) as full_avg_exposure_share_by_day,
        avg(ai_amount) as full_avg_ai_amount_by_day,
        avg(
            case when exposure_user_cnt > 0
                 then cast(pay_user_cnt as double) / exposure_user_cnt end
        ) as full_avg_conv_rate_by_day
    from daily
    group by
        iver
)

select
    case
        when w.iver like '13.4.%' then '13.4'
        when w.iver like '13.3.%' then '13.3'
        when w.iver like '13.2.%' then '13.2'
        else '其他'
    end as iver_line,
    w.iver as iver,
    w.win_start_dt as win_start_dt,
    w.win_end_dt as win_end_dt,
    w.day_cnt as day_cnt,
    round(w.avg_exposure_user_cnt_by_day, 0) as avg_exposure_user_cnt_by_day,
    round(w.avg_exposure_share_by_day, 4) as avg_exposure_share_by_day,
    round(w.avg_pay_user_cnt_by_day, 1) as avg_pay_user_cnt_by_day,
    round(w.avg_ai_amount_by_day, 0) as avg_ai_amount_by_day,
    round(w.avg_conv_rate_by_day * 100, 4) as avg_conv_rate_by_day_pct,
    f.full_start_dt as full_start_dt,
    f.full_end_dt as full_end_dt,
    f.full_day_cnt as full_day_cnt,
    round(f.full_avg_exposure_share_by_day, 4) as full_avg_exposure_share_by_day,
    round(f.full_avg_ai_amount_by_day, 0) as full_avg_ai_amount_by_day,
    round(f.full_avg_conv_rate_by_day * 100, 4) as full_avg_conv_rate_by_day_pct
from own_window w
left join full_window f
    on w.iver = f.iver
order by
    w.iver
;

-- ============================================================
-- 【附1】核对主推窗口（每天谁最大、占比多少），用来验证上面的窗口切得对不对
--   把最后的 select 整段换成下面这段，CTE 不用动：
--
--   select
--       l.dt as dt,
--       l.leader_iver as leader_iver,
--       d.iver as iver,
--       d.exposure_user_cnt as exposure_user_cnt,
--       round(d.exposure_share, 4) as exposure_share
--   from leader_day l
--   inner join daily d
--       on l.dt = d.dt
--   order by
--       l.dt,
--       d.exposure_user_cnt desc
--   ;
-- ============================================================
