with match_info as ( -- 找出25年巡回锦标赛的比赛信息，主要是为了找到播过斯诺克赛事的主播
  select distinct
    dt
    ,match_year
    ,live_type
    ,room_type
    ,game_id
    ,match_id
    ,match_name
    ,uid as luid
    ,day
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt='2026-05-05'  
    and day>='2025-03-31'
    and day<='2025-04-06' 
    and match_name like '%斯诺克%'
)
-- 要找到的是通过哪一位主播拉新的，所以要找到播过斯诺克赛事的主播，而不是直接将斯诺克赛事和拉新用户进行关联
, luid_info as( 
  select distinct
    a.dt
    ,b.luid
    ,a.ukey
  from zhgametemp.cwq_huya_ukey_shichang_luid_gameid_guishu_day_v1 a -- 日时长归因底表，找出用户单日观看最长时长的主播
  inner join match_info as b
  on 
    a.luid = b.luid
    and a.dt = b.day -- 如果是看赛事的话，记得把日期对上，才会归到赛事日上，主播关联的话，不代表赛事日的主播的用户，而是单纯的主播的用户
  where 
    a.dt between '2025-03-31' and '2025-04-06' -- 25年巡回锦标赛的比赛日期
    and a.nick like '%斯诺克%'
) 
, acquisition_user_info as -- 拉新用户表，找出在25年巡回锦标赛期间被主播拉新的用户
(
  select distinct
    a.user_ukey 
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a -- 拉新用户表
  inner join match_info as b
    on a.dt = b.day
  and a.game_id = b.game_id
    -- 要增加关联的主播ID，参考之前
  inner join luid_info c
    on a.user_ukey = c.ukey
  where 
    a.dt between'2025-03-31'and '2025-04-06'
)

select
  count(distinct a.user_ukey) as total_laxin_users,
  count(distinct b.user_ukey) as retained_users,
  round(count(distinct b.user_ukey) * 100.0 / count(distinct a.user_ukey), 2) as retention_rate
from acquisition_user_info a
left join gamelive.dws_huya_active_product_ukey_info_withsdk_d_i b -- 活跃用户表，找出拉新用户中活跃的用户
on 
  a.user_ukey = b.user_ukey 
  and b.dt between '2025-04-18' and '2025-05-04' -- 25年世锦赛的比赛日期，拉新用户在世锦赛的比赛日期内是否活跃
