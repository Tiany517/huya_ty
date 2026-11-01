-- 目的：在抖音“无畏契约”主播中，粗筛可能曾于斗鱼开播的主播，供人工核验。
-- 数据源：gamelive.dm_mkt_rowner_day。
-- 时间范围：2025-01-01 至 2026-10-20。
-- 平台：抖音 pcode = 'douyin_web'，斗鱼 pcode = 'douyu'。
-- 候选口径：清理昵称中的空格、括号和常见品类后缀后做同名匹配；这不是主播身份映射。
-- 数量门槛：抖音无畏契约开播天数 >= 14，斗鱼历史开播天数 >= 5，减少单日偶发账号噪声。
-- 日期判断：仅描述两平台首末开播日先后，不代表已经确认发生迁移。
-- 注意：同名仍可能是两个人，改名主播也会漏掉；所有结果均需回看双方主页、历史直播和外部资料确认。
-- 引擎：Presto。

with douyin_valorant_base as (
    select
        cast(dt as varchar) as dt,
        cast(r_lid as varchar) as r_lid,
        cast(r_owner as varchar) as r_owner,
        cast(r_url as varchar) as r_url,
        cast(online_max_r_name as varchar) as online_max_r_name,
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

-- 抖音无畏契约主播汇总
douyin_anchor as (
    select
        r_lid,
        max(r_owner) as douyin_owner,
        max(owner_key) as owner_key,
        min(dt) as douyin_first_dt,
        max(dt) as douyin_last_dt,
        count(distinct dt) as douyin_live_days,
        avg(valid_acu) as douyin_avg_valid_acu,
        max(r_url) as douyin_r_url,
        max(
            case
                when online_max_r_name like '%斗鱼%'
                  or r_owner like '%斗鱼%'
                    then 1
                else 0
            end
        ) as has_douyu_text
    from douyin_valorant_base
    where length(owner_key) >= 3
    group by r_lid
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

-- 斗鱼同名主播汇总；先只保留抖音持续开播的昵称，降低扫描和结果噪声
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
        where douyin_live_days >= 14
    ) n
        on d.owner_key = n.owner_key
    group by
        d.owner_key,
        d.r_lid
),

same_name_candidate as (
    select
        '同名粗筛' as candidate_type,
        case
            when u.douyu_last_dt < d.douyin_first_dt
             and u.douyu_live_days >= 14
                then 'A-斗鱼有稳定记录且先结束后再出现在抖音'
            when u.douyu_last_dt < d.douyin_first_dt
                then 'B-斗鱼有记录且先结束，但斗鱼记录较短'
            when u.douyu_first_dt < d.douyin_first_dt
                then 'C-两平台记录重叠，需排除同步开播或同名'
            else 'D-抖音早于本次斗鱼窗口出现，方向不符'
        end as candidate_priority,
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
    where d.douyin_live_days >= 14
      and u.douyu_live_days >= 5
),

-- 单独补充“抖音主播名或直播标题直接出现斗鱼”的文字线索
explicit_text_candidate as (
    select
        '名称或房名含斗鱼' as candidate_type,
        'E-仅有文字线索，需人工核验' as candidate_priority,
        d.douyin_owner,
        d.r_lid as douyin_r_lid,
        d.douyin_first_dt,
        d.douyin_last_dt,
        d.douyin_live_days,
        round(d.douyin_avg_valid_acu, 2) as douyin_avg_valid_acu,
        d.douyin_r_url,
        cast(null as varchar) as douyu_owner,
        cast(null as varchar) as douyu_r_lid,
        cast(null as varchar) as douyu_first_dt,
        cast(null as varchar) as douyu_last_dt,
        cast(null as bigint) as douyu_live_days,
        cast(null as double) as douyu_avg_valid_acu,
        cast(null as varchar) as douyu_r_category,
        cast(null as varchar) as douyu_r_url
    from douyin_anchor d
    where d.has_douyu_text = 1
)

select *
from same_name_candidate
union all
select *
from explicit_text_candidate
order by
    candidate_priority,
    douyin_avg_valid_acu desc nulls last,
    douyin_live_days desc,
    douyin_owner
limit 200;
