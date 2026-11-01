with match_days as (
    select
        substr(day, 1, 10) as dt,
        match_name,
        match_id,
        game_id,
        uid as luid
    from zhgametemp.hss_huya_dim_game_copyright_info_d_a
    where dt = '2026-08-18'
      and substr(day, 1, 10) >= '2025-01-01'
      and substr(day, 1, 10) <= '2026-08-19'
      and match_name like '%EWC%'
      and game_id in (862)
    group by
        substr(day, 1, 10),
        match_name,
        match_id,
        game_id,
        uid
),

daily_app_dau as (
  select distinct
      s.dt,
      s.gameid,
      s.ayyuid as luid,
      s.ukey
  from bp.yyzc_dws_with_user_by_gameid_ayyuid_ukey_day s
  inner join match_days k
      on s.dt = k.dt
      and s.gameid = k.game_id
      and s.ayyuid = k.luid
  where s.dt >= '2025-01-01'
    and s.dt <= '2026-08-19'
    and s.gameid in (862)
    and s.is_app = 1
    and s.is_watch > 0
    and s.is_black = 0
),

match_daily_dau as (
  select
      b.dt,
      b.match_name,
      b.match_id,
      b.game_id,
      count(distinct a.ukey) as app_dau
  from match_days b
  left join daily_app_dau a
      on a.dt = b.dt
      and a.luid = b.luid
  group by
      b.dt,
      b.match_name,
      b.match_id,
      b.game_id
)

select
  match_name,
  match_id,
  game_id,
  min(dt) as min_dt,
  max(dt) as max_dt,
  avg(app_dau) as avg_dau
from match_daily_dau
group by
  match_name,
  match_id,
  game_id
order by
  match_name,
  match_id