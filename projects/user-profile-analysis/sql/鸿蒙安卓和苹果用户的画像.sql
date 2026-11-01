with user_active_info as (
  select distinct
    user_ukey,
    case
      when product in ('huya_android', 'huya_pad') then 'Android'
      when product in ('huya_ios', 'huya_ipad') then 'IOS'
      when product in ('hmos_kiwi') then 'Harmony'
      else '其他'
    end as device_os
  from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
  where dt between '2026-03-01' and '2026-03-31'
    and product in (
      'huya_andriod',
      'huya_ipad',
      'huya_pad',
      'huya_ios',
      'hmos_kiwi'
  )
)



select distinct
  '鸿蒙用户' as user_type,
  a.user_ukey,
  a.device_os,
  b.gender,
  b.age,
  b.education_background,
  b.life_status,
  b.has_children,
  b.travel_type,
  b.current_university,
  b.is_travel_abroad,
  b.is_in_famouse_company,
  b.is_school_staff,
  b.is_in_university,
  b.has_elite_house,
  b.has_house,
  b.has_car,
  b.has_high_level_app,
  b.is_from_village,
  b.has_high_level_device,
  b.device_brand,
  b.device_machine_type,
  b.device_marketed_price,
  b.game_like,
  b.game_act_degree,
  b.app_level_1_category,
  b.app_level_2_category,
  b.app_level_3_category
from gamelive.dws_tx_portrait_active_ukey_d_i b
inner join (
  select user_ukey, device_os from user_active_info where device_os = 'Harmony'
) a
  on a.user_ukey = b.ukey
where b.dt between '2026-03-01' and '2026-03-31'

union all 

select distinct
  'IOS用户' as user_type,
  a.user_ukey,
  a.device_os,
  b.gender,
  b.age,
  b.education_background,
  b.life_status,
  b.has_children,
  b.travel_type,
  b.current_university,
  b.is_travel_abroad,
  b.is_in_famouse_company,
  b.is_school_staff,
  b.is_in_university,
  b.has_elite_house,
  b.has_house,
  b.has_car,
  b.has_high_level_app,
  b.is_from_village,
  b.has_high_level_device,
  b.device_brand,
  b.device_machine_type,
  b.device_marketed_price,
  b.game_like,
  b.game_act_degree,
  b.app_level_1_category,
  b.app_level_2_category,
  b.app_level_3_category
from gamelive.dws_tx_portrait_active_ukey_d_i b
inner join (
  select user_ukey, device_os from user_active_info where device_os = 'IOS'
) a
  on a.user_ukey = b.ukey
where b.dt between '2026-03-01' and '2026-03-31'

union all

select distinct
  '安卓用户' as user_type,
  a.user_ukey,
  a.device_os,
  b.gender,
  b.age,
  b.education_background,
  b.life_status,
  b.has_children,
  b.travel_type,
  b.current_university,
  b.is_travel_abroad,
  b.is_in_famouse_company,
  b.is_school_staff,
  b.is_in_university,
  b.has_elite_house,
  b.has_house,
  b.has_car,
  b.has_high_level_app,
  b.is_from_village,
  b.has_high_level_device,
  b.device_brand,
  b.device_machine_type,
  b.device_marketed_price,
  b.game_like,
  b.game_act_degree,
  b.app_level_1_category,
  b.app_level_2_category,
  b.app_level_3_category
from gamelive.dws_tx_portrait_active_ukey_d_i b
inner join (
  select user_ukey, device_os from user_active_info where device_os = 'Android'
) a
  on a.user_ukey = b.ukey
where b.dt between '2026-03-01' and '2026-03-31'



