-- 目的：提取 A 级候选，即抖音“无畏契约”主播中，存在同名斗鱼主播，
--       斗鱼开播天数 >= 14 天，且斗鱼最后开播日早于抖音首次开播日。
-- 数据源：gamelive.dm_mkt_rowner_day。
-- 时间范围：2025-01-01 至 2026-10-20。
-- 平台：抖音 pcode = 'douyin_web'，斗鱼 pcode = 'douyu'。
-- 候选口径：清理昵称中的空格、括号和常见品类后缀后做同名匹配。
-- 注意：A 级只代表时间顺序较符合迁移，不代表身份已经确认；同名仍需人工核验。
-- 引擎：Presto。

with douyin_valorant_base as (
    select
        cast(dt as varchar) as dt,
        cast(r_lid as varchar) as r_lid,
        cast(r_owner as varchar) as r_owner,
        cast(r_url as varchar) as r_url,
        coalesce(try_cast(element_at(ext, 'vaild_acu') as double), 0.0) as valid_acu,
        regexp_replace(
            regexp_replace(
                lower(trim(cast(r_owner as varchar))),
                '[\\s　（）()【】\\[\\]·._-]+',
                ''
            ),
            '(无畏契约|瓦罗兰特|valorant)$',
            ''
        ) as owner_key
    from gamelive.dm_mkt_rowner_day
    where dt between '2025-01-01' and '2026-10-20'
      and pcode = 'douyin_web'
      and r_category = '无畏契约'
),

douyin_anchor as (
    select
        r_lid,
        max(r_owner) as douyin_owner,
        max(owner_key) as owner_key,
        min(dt) as douyin_first_dt,
        max(dt) as douyin_last_dt,
        count(distinct dt) as douyin_live_days,
        avg(valid_acu) as douyin_avg_valid_acu,
        max(r_url) as douyin_r_url
    from douyin_valorant_base
    where length(owner_key) >= 3
    group by r_lid
    having count(distinct dt) >= 14
),

douyu_base as (
    select
        cast(dt as varchar) as dt,
        cast(r_lid as varchar) as r_lid,
        cast(r_owner as varchar) as r_owner,
        cast(r_category as varchar) as r_category,
        cast(r_url as varchar) as r_url,
        coalesce(try_cast(element_at(ext, 'vaild_acu') as double), 0.0) as valid_acu,
        regexp_replace(
            regexp_replace(
                lower(trim(cast(r_owner as varchar))),
                '[\\s　（）()【】\\[\\]·._-]+',
                ''
            ),
            '(无畏契约|瓦罗兰特|valorant)$',
            ''
        ) as owner_key
    from gamelive.dm_mkt_rowner_day
    where dt between '2025-01-01' and '2026-10-20'
      and pcode = 'douyu'
),

-- 先在斗鱼侧汇总同名主播，只扫描抖音持续开播主播对应的昵称
douyu_anchor as (
    select
        d.owner_key,
        d.r_lid as douyu_r_lid,
        max(d.r_owner) as douyu_owner,
        min(d.dt) as douyu_first_dt,
        max(d.dt) as douyu_last_dt,
        count(distinct d.dt) as douyu_live_days,
        avg(d.valid_acu) as douyu_avg_valid_acu,
        max(d.r_category) as douyu_r_category,
        max(d.r_url) as douyu_r_url
    from douyu_base d
    inner join (
        select distinct owner_key
        from douyin_anchor
    ) n
        on d.owner_key = n.owner_key
    group by
        d.owner_key,
        d.r_lid
    having count(distinct d.dt) >= 14
)

select
    'A' as candidate_level,
    d.douyin_owner,
    d.r_lid as douyin_r_lid,
    d.douyin_first_dt,
    d.douyin_last_dt,
    d.douyin_live_days,
    round(d.douyin_avg_valid_acu, 2) as douyin_avg_valid_acu,
    d.douyin_r_url,
    u.douyu_owner,
    u.douyu_r_lid,
    u.douyu_first_dt,
    u.douyu_last_dt,
    u.douyu_live_days,
    round(u.douyu_avg_valid_acu, 2) as douyu_avg_valid_acu,
    u.douyu_r_category,
    u.douyu_r_url
from douyin_anchor d
inner join douyu_anchor u
    on d.owner_key = u.owner_key
where u.douyu_last_dt < d.douyin_first_dt
order by
    d.douyin_avg_valid_acu desc nulls last,
    d.douyin_live_days desc,
    d.douyin_owner;
