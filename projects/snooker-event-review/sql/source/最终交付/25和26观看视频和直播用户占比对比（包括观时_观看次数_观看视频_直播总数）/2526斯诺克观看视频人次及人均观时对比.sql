with match_info_2026 as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt = '2026-05-12' 
    and day >= '2026-04-18'
    and day <= '2026-05-04'
)

,match_info_2025 as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt = '2026-05-12' 
    and day >= '2025-04-18'
    and day <= '2025-05-04'
)

,laxin_user_info_2026 as(
select 
  b.ukey  ---a.dt ,a.luid , 
from match_info_2026 a 
inner join(---拉新用户
  select dt ,luid ,user_ukey as ukey 
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
  where dt between '2026-04-18' and '2026-05-04' 
      and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')  
)b 
on a.dt=b.dt and a.luid=b.luid 
group by 1
)

,laxin_user_info_2025 as(
select 
  b.ukey  ---a.dt ,a.luid , 
from match_info_2025 a 
inner join(---拉新用户
  select dt ,luid ,user_ukey as ukey 
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
  where dt between '2025-04-18' and '2025-05-04' 
      and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')  
)b 
on a.dt=b.dt and a.luid=b.luid 
group by 1
)

-- 用户行为表里固定的直播和视频的写法
,user_behavior_2026 as(
  select distinct
      '视频' as content_type,
      user_ukey,
      game_id,
      game_name,
      sum(watch_cnt) as watch_cnt,
      sum(watch_duration)/60000 as watch_mins
  from gamelive.dws_huya_user_behavior_d_i
  where dt between '2026-04-18' and '2026-05-04' 
    and data_type in ('video_session')
    and live_content_type = '视频'
    and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
    and game_id not in (2356)
    and game_name not in ('体育', '台球')
    and watch_cnt > 0
  group by 1,2,3,4

  union all

  select distinct
      '直播' as content_type,
      user_ukey,
      game_id,
      game_name,
      sum(watch_cnt) as watch_cnt,
      sum(watch_duration)/60000 as watch_mins
  from gamelive.dws_huya_user_behavior_d_i
  where dt between '2026-04-18' and '2026-05-04'
    and data_type in ('live_watch_session')
    and live_content_type = '直播'
    and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
    and game_id not in (2356)
    and watch_cnt > 0
  group by 1,2,3,4
)

,user_behavior_2025 as(
  select distinct
      '视频' as content_type,
      user_ukey,
      game_id,
      game_name,
      sum(watch_cnt) as watch_cnt,
      sum(watch_duration)/60000 as watch_mins
  from gamelive.dws_huya_user_behavior_d_i
  where dt between '2025-04-18' and '2025-05-04' 
    and data_type in ('video_session')
    and live_content_type = '视频'
    and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
    and game_id not in (2356)
    and game_name not in ('体育', '台球')
    and watch_cnt > 0
  group by 1,2,3,4

  union all

  select distinct
      '直播' as content_type,
      user_ukey,
      game_id,
      game_name,
      sum(watch_cnt) as watch_cnt,
      sum(watch_duration)/60000 as watch_mins
  from gamelive.dws_huya_user_behavior_d_i
  where dt between '2025-04-18' and '2025-05-04'
    and data_type in ('live_watch_session')
    and live_content_type = '直播'
    and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
    and game_id not in (2356)
    and watch_cnt > 0
  group by 1,2,3,4
)


select 
  '2026拉新用户' as user_group,
  count(distinct user_ukey) as snooker_laxin_users,
  count(distinct case when is_video_user = 1 then user_ukey end) as video_users,
  count(distinct case when is_live_user = 1 then user_ukey end) as live_users,
  count(distinct case when is_video_user = 1 then user_ukey end) / count(distinct user_ukey) as video_user_ratio,
  count(distinct case when is_live_user = 1 then user_ukey end) / count(distinct user_ukey) as live_user_ratio,
  sum(case when is_video_user = 1 then watch_cnt end) as total_video_watch_cnt,
  sum(case when is_video_user = 1 then watch_mins end) as total_video_watch_mins,
  sum(case when is_video_user = 1 then watch_mins end) / count(distinct user_ukey) as avg_video_watch_mins_per_user,
  sum(case when is_live_user = 1 then watch_cnt end) as total_live_watch_cnt,
  sum(case when is_live_user = 1 then watch_mins end) as total_live_watch_mins,
  sum(case when is_live_user = 1 then watch_mins end) / count(distinct user_ukey) as avg_live_watch_mins_per_user
from (
  select
    a.ukey as user_ukey,
    case when b.content_type = '视频' then 1 else 0 end as is_video_user,
    case when b.content_type = '直播' then 1 else 0 end as is_live_user,
    b.game_id,
    b.game_name,
    coalesce(b.watch_cnt, 0) as watch_cnt,
    coalesce(b.watch_mins, 0) as watch_mins
  from laxin_user_info_2026 a
  left join user_behavior_2026 b
  on a.ukey = b.user_ukey
  group by 1,2,3,4,5,6,7
)

union all

select 
  '2025斯诺克拉新用户' as user_group,
  count(distinct user_ukey) as snooker_laxin_users,
  count(distinct case when is_video_user = 1 then user_ukey end) as video_users,
  count(distinct case when is_live_user = 1 then user_ukey end) as live_users,
  count(distinct case when is_video_user = 1 then user_ukey end) / count(distinct user_ukey) as video_user_ratio,
  count(distinct case when is_live_user = 1 then user_ukey end) / count(distinct user_ukey) as live_user_ratio,
  sum(case when is_video_user = 1 then watch_cnt end) as total_video_watch_cnt,
  sum(case when is_video_user = 1 then watch_mins end) as total_video_watch_mins,
  sum(case when is_video_user = 1 then watch_mins end) / count(distinct user_ukey) as avg_video_watch_mins_per_user,
  sum(case when is_live_user = 1 then watch_cnt end) as total_live_watch_cnt,
  sum(case when is_live_user = 1 then watch_mins end) as total_live_watch_mins,
  sum(case when is_live_user = 1 then watch_mins end) / count(distinct user_ukey) as avg_live_watch_mins_per_user
from (
  select
    a.ukey as user_ukey,
    case when b.content_type = '视频' then 1 else 0 end as is_video_user,
    case when b.content_type = '直播' then 1 else 0 end as is_live_user,
    b.game_id,
    b.game_name,
    coalesce(b.watch_cnt, 0) as watch_cnt,
    coalesce(b.watch_mins, 0) as watch_mins
  from laxin_user_info_2025 a
  left join user_behavior_2025 b
  on a.ukey = b.user_ukey
  group by 1,2,3,4,5,6,7
)