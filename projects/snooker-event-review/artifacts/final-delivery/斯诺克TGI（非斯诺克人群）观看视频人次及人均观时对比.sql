with match_info as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt = '2026-05-12' 
    and day >= '2026-04-18'
    and day <= '2026-05-04'
)

,snooker_laxin_user_info as(
select 
  b.ukey  ---a.dt ,a.luid , 
from match_info a 
inner join(---拉新用户
  select dt ,luid ,user_ukey as ukey 
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
  where dt between '2026-04-18' and '2026-05-04' 
      and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')  
)b 
on a.dt=b.dt and a.luid=b.luid 
group by 1
)

,not_sooker_laxin_user_info as(
  select 
    user_ukey as ukey 
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a
  left join snooker_laxin_user_info b
    on a.user_ukey = b.ukey
  where dt between '2026-04-18' and '2026-05-04' 
      and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi') 
      and b.ukey is null
  group by 1
) 

-- 用户行为表里固定的直播和视频的写法
,user_behavior as(
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


, base_info as (
  select
      '世锦赛期间_斯诺克拉新用户' as user_group,
      -- game_id,
      game_name,
      sum(watch_cnt) as total_video_watch_cnt,
      sum(watch_cnt) / count(distinct user_ukey) as avg_video_watch_cnt_per_user,
      sum(watch_mins) as total_video_watch_mins,
      sum(watch_mins) / count(distinct user_ukey) as avg_video_watch_mins_per_user
  from (
    select
        a.ukey as user_ukey,
        case when b.content_type = '视频' then 1 else 0 end as is_video_user,
        case when b.content_type = '直播' then 1 else 0 end as is_live_user,
        b.game_id,
        b.game_name,
        coalesce(b.watch_cnt, 0) as watch_cnt,
        coalesce(b.watch_mins, 0) as watch_mins
      from snooker_laxin_user_info a
      left join user_behavior b
      on a.ukey = b.user_ukey
      group by 1,2,3,4,5,6,7
  )
  where is_video_user = 1
  group by 1,2

  union all

  select
      '世锦赛期间_非斯诺克拉新用户' as user_group,
      -- game_id,
      game_name,
      sum(watch_cnt) as total_video_watch_cnt,
      sum(watch_cnt) / count(distinct user_ukey) as avg_video_watch_cnt_per_user,
      sum(watch_mins) as total_video_watch_mins,
      sum(watch_mins) / count(distinct user_ukey) as avg_video_watch_mins_per_user
  from (
    select
      a.ukey as user_ukey,
      case when b.content_type = '视频' then 1 else 0 end as is_video_user,
      case when b.content_type = '直播' then 1 else 0 end as is_live_user,
      b.game_id,
      b.game_name,
      coalesce(b.watch_cnt, 0) as watch_cnt,
      coalesce(b.watch_mins, 0) as watch_mins
    from not_sooker_laxin_user_info a
    left join user_behavior b
    on a.ukey = b.user_ukey
    group by 1,2,3,4,5,6,7
  )
  where is_video_user = 1
  group by 1,2
)

select
  user_group,
  game_name,
  total_video_watch_cnt,
  avg_video_watch_cnt_per_user,
  total_video_watch_mins,
  avg_video_watch_mins_per_user,
  round(total_video_watch_cnt / sum(total_video_watch_cnt) over(partition by user_group), 4) as video_watch_cnt_ratio,
  round(total_video_watch_mins / sum(total_video_watch_mins) over(partition by user_group), 4) as video_watch_mins_ratio
from base_info
group by 1,2,3,4,5,6
order by 7,8 desc