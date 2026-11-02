with t1 as (
  select 
    dt
    ,match_year
    ,live_type
    ,room_type
    ,game_id
    ,match_id
    ,match_name
    ,uid as luid
    ,day
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a -- 体育对应赛事和主播关系宽表
  where dt='2026-04-27' 
    and day>='2025-01-01'
    and match_name like '%斯诺克%'
), t2 as (
  select distinct
    a.dt
    ,b.luid
    ,a.ukey
  from zhgametemp.cwq_huya_ukey_shichang_luid_gameid_guishu_day_v1 a -- 日时长归因底表，找出用户单日观看最长时长的主播
  inner join t1 as b
  on 
    a.luid = b.luid
    and a.dt = b.day -- 如果是看赛事的话，记得把日期对上，才会归到赛事日上，主播关联的话，不代表赛事日的主播的用户，而是单纯的主播的用户
  where 
    a.dt >= '2025-01-01' 
    and a.nick like '%斯诺克%'
) 

select
  a.dt
  ,a.user_ukey
  ,count(distinct a.igameid) as category_cnt
  ,a.user_duration/60000 as view_min 
from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
inner join t2
on 
  a.user_ukey = t2.ukey
  and a.dt = t2.dt -- 如果是看赛事的话，记得把日期对上，才会归到赛事日上，主播关联的话，不代表赛事日的主播的用户，而是单纯的主播的用户
where 
  a.dt >= '2025-01-01' 
group by 
  a.dt
  ,a.user_ukey
  ,a.user_duration/60000
order by 
 a.dt asc