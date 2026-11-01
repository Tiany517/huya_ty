-- 目的：斗鱼多品类主播互动候选分析的第一层明细。
-- 数据源：gamelive.dm_mkt_rowner_day。
-- 时间范围：2026-01-01 至 2026-09-30。
-- 平台：douyu；品类：除空值及非业务目录外的全部品类。
-- 粒度：品类 x 主播 x 月。
-- 有效 ACU 日：ext['vaild_acu'] > 0。
-- 月日均 ACU：有效 ACU 日的 avg(vaild_acu)。
-- 月日均弹幕人数：同一批有效 ACU 日的 avg(danmu_ucnt)。
-- 互动强度：月日均弹幕人数 / 月日均 ACU。
-- 互动样本等级：
--   高样本：有效 ACU 天数 >= 3 且月日均弹幕人数 >= 30。
--   中样本：有效 ACU 天数 >= 2 且月日均弹幕人数 >= 20。
--   其余：低样本。
-- 注意：本层不计算留存；候选确定后再仅对候选主播-品类补算下一有效月留存。
-- 引擎：Spark SQL。

with douyu_anchor_day as (
    select
        cast(dt as string) as dt,
        cast(r_lid as string) as anchor_id,
        trim(cast(r_category as string)) as r_category,
        max(cast(r_owner as string)) as r_owner,
        max(coalesce(cast(element_at(ext, 'vaild_acu') as double), 0.0)) as valid_acu,
        max(coalesce(cast(danmu_ucnt as double), 0.0)) as danmu_ucnt,
        max(coalesce(cast(danmu_cnt as double), 0.0)) as danmu_cnt,
        max(coalesce(cast(hour_cnt as bigint), 0)) as observed_hours
    from gamelive.dm_mkt_rowner_day
    where dt between '2026-01-01' and '2026-09-30'
      and pcode = 'douyu'
      and r_category is not null
      and trim(cast(r_category as string)) <> ''
      and r_category not in ('直播列表', '企鹅直播', '心悦专区')
    group by
        cast(dt as string),
        cast(r_lid as string),
        trim(cast(r_category as string))
),

anchor_month_base as (
    select
        substr(dt, 1, 7) as month_key,
        r_category,
        anchor_id,
        max_by(r_owner, dt) as anchor_name,
        count(distinct dt) as observed_days,
        count(distinct if(valid_acu > 0, dt, null)) as valid_acu_days,
        avg(if(valid_acu > 0, valid_acu, null)) as avg_daily_acu,
        avg(if(valid_acu > 0, danmu_ucnt, null)) as avg_daily_danmu_users,
        sum(if(valid_acu > 0, danmu_cnt, 0.0)) as total_danmu_cnt
    from douyu_anchor_day
    group by
        substr(dt, 1, 7),
        r_category,
        anchor_id
    having count(distinct if(valid_acu > 0, dt, null)) > 0
)

select
    month_key as `月份`,
    r_category as `品类`,
    anchor_id as `斗鱼主播ID`,
    anchor_name as `主播名称`,
    observed_days as `当月观测开播日数`,
    valid_acu_days as `有效ACU天数`,
    round(avg_daily_acu, 2) as `月日均ACU`,
    round(avg_daily_danmu_users, 2) as `月日均弹幕人数`,
    round(avg_daily_danmu_users / nullif(avg_daily_acu, 0), 4) as `互动强度`,
    total_danmu_cnt as `月弹幕次数`,
    case
        when valid_acu_days >= 3 and avg_daily_danmu_users >= 30 then '高样本'
        when valid_acu_days >= 2 and avg_daily_danmu_users >= 20 then '中样本'
        else '低样本'
    end as `互动样本等级`,
    case
        when valid_acu_days >= 3 and avg_daily_danmu_users >= 30 then 1
        else 0
    end as `互动可评估`,
    case
        when avg_daily_acu < 100 then '尾部'
        when avg_daily_acu < 1000 then '腰部'
        else '头部'
    end as `ACU层级`
from anchor_month_base
order by r_category, anchor_id, month_key;
