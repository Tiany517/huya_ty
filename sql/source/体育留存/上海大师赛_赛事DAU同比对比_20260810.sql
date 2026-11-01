-- 目的：对比 2025/2026 上海大师赛赛事 DAU。
-- 赛事 DAU 口径：赛事期间每天观看该赛事相关直播间的去重 user_ukey 数。
-- 观看数据源：gamelive.dws_huya_user_behavior_d_i。
-- 过滤条件：data_type='live_watch_session'、live_content_type='直播'、APP/iOS/HMOS 产品、
--           is_black_ukey=0、watch_cnt>0、watch_duration>0。
-- 2025 赛事主播范围：zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a，
--                 dt='2026-07-30' 快照，按 day 关联赛事日期。
-- 2026 赛事主播范围：zhgametemp.zty_snooker_shanghai_master_2026，沿用用户给定 SQL 的 luid 名单。

-- Query 1：2025 上海大师赛每日赛事 DAU
with match_luid_day as (
  select distinct
    r.day as dt,
    cast(r.uid as varchar) as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a r
  where r.dt = '2026-07-30'
    and r.day between '2025-07-28' and '2025-08-03'
)
select
  '2025上海大师赛' as match_name,
  s.dt,
  count(distinct s.user_ukey) as event_dau
from gamelive.dws_huya_user_behavior_d_i s
where s.dt between '2025-07-28' and '2025-08-03'
  and s.data_type = 'live_watch_session'
  and s.live_content_type = '直播'
  and s.product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
  and cast(s.is_black_ukey as varchar) = '0'
  and s.watch_cnt > 0
  and s.watch_duration > 0
  and s.user_ukey is not null
  and concat(s.dt, '#', cast(s.creator_uid as varchar)) in (
    select concat(dt, '#', luid)
    from match_luid_day
  )
group by s.dt
order by s.dt;

-- Query 2：2026 上海大师赛每日赛事 DAU
select
  '2026上海大师赛' as match_name,
  s.dt,
  count(distinct s.user_ukey) as event_dau
from gamelive.dws_huya_user_behavior_d_i s
where s.dt between '2026-07-27' and '2026-08-02'
  and s.data_type = 'live_watch_session'
  and s.live_content_type = '直播'
  and s.product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
  and cast(s.is_black_ukey as varchar) = '0'
  and s.watch_cnt > 0
  and s.watch_duration > 0
  and s.user_ukey is not null
  and cast(s.creator_uid as varchar) in (
    select distinct cast(luid as varchar)
    from zhgametemp.zty_snooker_shanghai_master_2026
  )
group by s.dt
order by s.dt;
