select v.dt, count(distinct v.user_ukey) as user_cnt
from (
  select dt, user_ukey, sum(watch_duration) as video_watch_duration
  from gamelive.dws_huya_user_behavior_d_i
  where dt between '2026-06-12' and '2026-07-16'
    and product in ('huya_andriod', 'huya_ios', 'hmos_kiwi')
    and data_type = 'video_session' and live_content_type = '视频'
    and content_id <> 0 and vid_can_play = 1 and watch_cnt > 0
    and (implicit_tags like '%美加墨世界杯%' or implicit_tags like '%世界杯%')
  group by dt, user_ukey

  union all 

  select dt, user_ukey, sum(watch_duration) as live_watch_duration
  from gamelive.dws_huya_user_behavior_d_i
  where dt between '2026-06-12' and '2026-07-16'
    and product in ('huya_andriod', 'huya_ios', 'hmos_kiwi')
    and data_type = 'live_watch_session' and live_content_type = '直播'
    and watch_cnt > 0
  group by dt, user_ukey
) v
group by v.dt 
