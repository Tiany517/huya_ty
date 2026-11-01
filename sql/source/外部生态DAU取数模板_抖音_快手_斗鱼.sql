with shengtai_info as (
  select
    '抖音' as platform,
    mth,
    coalesce(avg(total_dau),0) as total_dau
    -- round(avg(valid_dau),0) as valid_dau
  from
  (
    select
      substr(dt,1,7) as mth,
      dt,
      sum(total_dau) as total_dau,
      sum(valid_dau) as valid_dau
    from zhgametemp.huya_eco_dau_other_platform_dau
    where
      dt>='2025-07-01' and dt <= '2026-05-18' --修改这里
      and platform in ('douyin','douyin-huxiao','douyin-hushi') -- 抖音三个渠道
    group by 1,2
  )a
  group by 1,2


  union all


  select
    platform,
    substr(dt,1,7) as mth,
    coalesce(avg(total_dau),0) as total_dau
    -- avg(valid_dau) as valid_dau
  from zhgametemp.huya_eco_dau_other_platform_dau
  where
    dt>='2025-07-01' and dt <= '2026-05-18' --修改这里
    and platform in ('kuaishou') -- 快手
  group by
    1,2


  union all

  select
    '斗鱼' as platform,
    substr(a.dt,1,7) as mth,
    coalesce(avg(douyu_dau),0) as total_dau
  from (
    select
      dt
      ,sum(totalduration)/60/0.116 as douyu_dau  -- 用停留时长系数计算斗鱼DAU
    from gamelive.ads_huya_to_douyu_anchor_index_d_i  -- 斗鱼DAU特定表
    where dt>='2025-07-01' and dt <= '2026-05-18' --修改这里
    group by dt
  ) a
  group by 1,2
)

select
  mth,
  sum(case when platform = '抖音' then total_dau else 0 end) as douyin,
  sum(case when platform = '快手' then total_dau else 0 end) as kuaishou,
  sum(case when platform = '斗鱼' then total_dau else 0 end) as douyu
from shengtai_info
group by mth
order by mth
