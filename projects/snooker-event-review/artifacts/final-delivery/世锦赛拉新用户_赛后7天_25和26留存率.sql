-- 2025年世锦赛
with match_info_2025 as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt = '2026-05-19'
    and day >= '2025-04-19'
    and day <= '2025-05-07'
)

, laxin_user_info_2025 as(
  select b.ukey as user_ukey
  from match_info_2025 a 
  inner join(
    select dt, luid, user_ukey as ukey 
    from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
    where dt between '2025-04-19' and '2025-05-07'
      and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')  
  ) b on a.dt = b.dt and a.luid = b.luid 
  group by b.ukey 
)

-- 2025年拉新总人数
, laxin_cnt_2025 as (
  select count(distinct user_ukey) as laxin_cnt from laxin_user_info_2025
)

-- 2025年赛后7天留存人数
, retention_users_2025 as (
  select count(distinct user_ukey) as retention_cnt
  from laxin_user_info_2025
  where user_ukey in (
    select user_ukey
    from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
    where dt between '2025-05-08' and '2025-05-15'
      and product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
      and is_black_ukey = 0
  )
)


-- 2026年世锦赛
, match_info_2026 as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt = '2026-05-19'
    and day >= '2026-04-18'
    and day <= '2026-05-06'
)

, laxin_user_info_2026 as(
  select b.ukey as user_ukey
  from match_info_2026 a 
  inner join(
    select dt, luid, user_ukey as ukey 
    from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
    where dt between '2026-04-18' and '2026-05-06'
      and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')  
  ) b on a.dt = b.dt and a.luid = b.luid 
  group by b.ukey 
)

-- 2026年拉新总人数
, laxin_cnt_2026 as (
  select count(distinct user_ukey) as laxin_cnt from laxin_user_info_2026
)

-- 2026年赛后7天留存人数
, retention_users_2026 as (
  select count(distinct user_ukey) as retention_cnt
  from laxin_user_info_2026
  where user_ukey in (
    select user_ukey
    from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
    where dt between '2026-05-07' and '2026-05-14'
      and product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
      and is_black_ukey = 0
  )
)


-- 主查询
select
    '2025世锦赛' as year_label,
    (select laxin_cnt from laxin_cnt_2025) as total_laxin_cnt,
    (select retention_cnt from retention_users_2025) as retention_cnt,
    (select retention_cnt from retention_users_2025) * 1.0 / (select laxin_cnt from laxin_cnt_2025) as retention_rate

union all

select
    '2026世锦赛' as year_label,
    (select laxin_cnt from laxin_cnt_2026) as total_laxin_cnt,
    (select retention_cnt from retention_users_2026) as retention_cnt,
    (select retention_cnt from retention_users_2026) * 1.0 / (select laxin_cnt from laxin_cnt_2026) as retention_rate