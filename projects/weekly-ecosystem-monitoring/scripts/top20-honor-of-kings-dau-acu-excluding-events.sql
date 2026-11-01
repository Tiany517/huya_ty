with match_date as (
    select distinct
        substr(date, 1, 10) as match_dt
    from gamelive.dwd_huya_dim_game_copyright_info_d_a
    where dt = '2026-09-08'
      and substr(date, 1, 10) >=  '2026-05-01'
      and game_id in (2336)
      and live_type like '%直播%'
      and room_type = '独立直播间'
      and content_type = '游戏赛事'
),

t1 as (
  select
    dt,
    substr(dt, 1, 7) as mth,
    luid,
    snick,
    avg_acu,
    dau,
    attribution_user_cnt,
    interest_user_cnt
  from zhgametemp.zty_category_ecology_health_daily_d_i_0827_v1 a
  left join match_date b
    on a.dt = b.match_dt
  where
    dt >= '2026-05-01'
    and gameid = 2336
    and b.match_dt is null
),
t_month_agg as (
  select
    mth,
    luid,
    snick,
    avg(avg_acu) as avg_acu,
    avg(dau) as dau,
    avg(attribution_user_cnt) as attribution_user_cnt,
    avg(interest_user_cnt) as interest_user_cnt
  from t1
  group by mth,luid,snick
)
select *
from t_month_agg
-- 筛选逻辑：同一个luid+snick，【2026-08月份的avg_acu>50】
where (luid, snick) in (
    select luid, snick
    from t_month_agg
    where mth = '2026-08' and avg_acu > 50
)
order by mth,luid,snick
