-- ============================================================
-- AI工坊 × 指定 App 版本：转换率（版本 × 天 明细）
-- 目标版本：13.2.64（要换版本只改下面 IN 里的值即可）
-- 时间窗口：2026-07-13 ~ 2026-09-14（调度表起始分区为 07-13，无法再往前）
-- 口径与现有「曝光占比表 / 周日均转换率表」完全一致：
--   版本归属：dw_huya_session_level，4 个 App 端 + tag = 'product'，同一 ukey 同一天只保留一个版本
--   曝光 / 支付：调度表 zty_ads_huya_ai_gift_user_detail_0901_v1 的人天标记，支付走漏斗口径
-- ============================================================

with funnel_user_day as (
    -- AI工坊漏斗：人天粒度的曝光 / 支付标记
    select
        t.dt as dt,
        cast(t.user_ukey as varchar) as ukey,
        max(case when t.is_exposure then 1 else 0 end) as is_exposure,
        max(case when t.is_pay then 1 else 0 end) as is_pay
    from zhgametemp.zty_ads_huya_ai_gift_user_detail_0901_v1 t
    where t.dt between '2026-07-13' and '2026-09-14'
      and t.user_ukey is not null
      and lower(cast(t.user_ukey as varchar)) not in ('', '0', 'other')
    group by
        t.dt,
        cast(t.user_ukey as varchar)
),

version_user_day as (
    -- 版本归属：只看目标版本；同一 ukey 同一天只保留一个版本
    select
        s.dt as dt,
        cast(s.ukey as varchar) as ukey,
        max(cast(s.iver as varchar)) as iver
    from gamelive.dw_huya_session_level s
    where s.dt between '2026-07-13' and '2026-09-14'
      and s.product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios')
      and s.tag = 'product'
      and s.ukey is not null
      and cast(s.iver as varchar) in ('13.2.64')
    group by
        s.dt,
        cast(s.ukey as varchar)
),

version_user_day_flag as (
    -- 版本 × 人天：曝光标记 / 支付标记
    select
        v.dt as dt,
        v.iver as iver,
        v.ukey as ukey,
        coalesce(f.is_exposure, 0) as is_exposure,
        coalesce(f.is_pay, 0) as is_pay
    from version_user_day v
    left join funnel_user_day f
        on v.dt = f.dt
       and v.ukey = f.ukey
)

select
    dt as dt,
    iver as iver,
    count(distinct case when is_exposure = 1 then ukey end) as exposure_user_cnt,
    count(distinct case when is_exposure = 1 and is_pay = 1 then ukey end) as pay_user_cnt,
    case
        when count(distinct case when is_exposure = 1 then ukey end) > 0
        then round(
            cast(count(distinct case when is_exposure = 1 and is_pay = 1 then ukey end) as double)
            / count(distinct case when is_exposure = 1 then ukey end),
            6
        )
    end as conv_rate
from version_user_day_flag
group by
    dt,
    iver
order by
    dt
;

