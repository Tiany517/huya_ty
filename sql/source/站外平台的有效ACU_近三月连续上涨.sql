with t1 as (
  select distinct
    substr(a.date, 1, 10) as dt
  from gamelive.dwd_huya_dim_game_copyright_info_d_a a
  where a.dt = '2026-09-22'
    and substr(a.date, 1, 10) between '2026-06-01' and '2026-09-22'
    and a.live_type like '%直播%'
    and a.game_id = 2336
    and a.match_name in (
      '2026KPL夏季赛',
      '2026EWC电竞世俱杯王者荣耀项目',
      '钟意FMVP皮肤发布仪式',
      '2027KPL春季资格赛'
    )
)

,monthly_acu as (
  select 
    mth,
    pcode,
    r_lid,
    r_owner,
    r_category,
    avg(valid_acu_value) as avg_valid_acu
  from(
    select
      dt,
      substr(dt, 1, 7) as mth,
      pcode,
      r_lid,
      r_owner,
      r_category,
      sum(cast(regexp_extract(ext['vaild_acu'], '([0-9]+)', 1) as bigint)) AS valid_acu_value
    from 
      gamelive.dm_mkt_rowner_day 
    where 
      dt between '2026-06-01' and '2026-09-22' 
      and r_category in ('王者荣耀')
      and dt not in (
        select distinct dt from t1
      )
      -- and pcode like ('%douyin%')
    group by dt,substr(dt, 1, 7), r_lid,r_owner,r_category,pcode
  )
  group by mth,pcode, r_lid, r_owner, r_category
)

,anchor_pcode as (
  select 
    pcode,
    r_lid,
    r_owner,
    r_category,
    max(case when mth = '2026-07' then avg_valid_acu end) as avg_acu_07,
    max(case when mth = '2026-08' then avg_valid_acu end) as avg_acu_08,
    max(case when mth = '2026-09' then avg_valid_acu end) as avg_acu_09
  from monthly_acu
  where mth in ('2026-07', '2026-08', '2026-09')
  group by pcode, r_lid, r_owner, r_category   
)

select 
  pcode,
  r_lid,
  r_owner,
  r_category,
  avg_acu_07,
  avg_acu_08,
  avg_acu_09,
  avg_acu_08 - avg_acu_07 as acu_growth_08,
  avg_acu_09 - avg_acu_08 as acu_growth_09
from anchor_pcode
where avg_acu_07 < avg_acu_08 and avg_acu_08 < avg_acu_09
order by
  pcode,
  r_lid,
  r_owner,
  r_category,
  avg_acu_09