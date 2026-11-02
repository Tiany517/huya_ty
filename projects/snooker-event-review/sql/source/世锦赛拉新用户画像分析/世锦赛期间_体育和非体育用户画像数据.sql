with match_info as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a -- 体育赛事主播
  where dt = '2026-05-17' 
    and day >= '2026-04-18'
    and day <= '2026-05-04' -- 2025年世锦赛期间
)

, shijin_laxin_user as ( ---拉新用户
  select 
      b.user_ukey
  from match_info a
  inner join (
      select dt, luid, user_ukey 
      from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 -- 宽口径内容拉新表
      where dt between '2026-04-18' and '2026-05-04' --世锦赛期间拉新的用户
          and user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
  ) b
  on a.dt = b.dt 
  and a.luid = b.luid
  group by 1
)

, not_shijin_laxin_user as (
  select a.user_ukey 
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a-- 宽口径内容拉新表
  left join shijin_laxin_user b
  on a.user_ukey = b.user_ukey
  where a.dt between '2026-04-18' and '2026-05-04' --世锦赛期间拉新的用户
      and a.user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
      and b.user_ukey is null
)


select distinct
  '世锦赛拉新用户' as user_type,
  a.user_ukey
  ,b.gender
  ,b.age
  ,b.education_background
  ,b.life_status
  ,b.has_children
  ,b.travel_type
  ,b.current_university
  ,b.is_travel_abroad
  ,b.is_in_famouse_company
  ,b.is_school_staff
  ,b.is_in_university
  ,b.has_elite_house
  ,b.has_house
  ,b.has_car
  ,b.has_high_level_app
  ,b.is_from_village
  ,b.has_high_level_device
  ,b.device_brand
  ,b.device_machine_type
  ,b.device_marketed_price
  ,b.game_like
  ,b.game_act_degree
  ,b.app_level_1_category
  ,b.app_level_2_category
  ,b.app_level_3_category
from shijin_laxin_user a
inner join gamelive.dws_tx_portrait_active_ukey_d_i b
on a.user_ukey = b.ukey
where b.dt between '2026-04-18' and '2026-05-04'

union all

select distinct
  '非世锦赛拉新用户' as user_type,
  a.user_ukey
  ,b.gender
  ,b.age
  ,b.education_background
  ,b.life_status
  ,b.has_children
  ,b.travel_type
  ,b.current_university
  ,b.is_travel_abroad
  ,b.is_in_famouse_company
  ,b.is_school_staff
  ,b.is_in_university
  ,b.has_elite_house
  ,b.has_house
  ,b.has_car
  ,b.has_high_level_app
  ,b.is_from_village
  ,b.has_high_level_device
  ,b.device_brand
  ,b.device_machine_type
  ,b.device_marketed_price
  ,b.game_like
  ,b.game_act_degree
  ,b.app_level_1_category
  ,b.app_level_2_category
  ,b.app_level_3_category
from not_shijin_laxin_user a
inner join gamelive.dws_tx_portrait_active_ukey_d_i b
on a.user_ukey = b.ukey
where b.dt between '2026-04-18' and '2026-05-04'
