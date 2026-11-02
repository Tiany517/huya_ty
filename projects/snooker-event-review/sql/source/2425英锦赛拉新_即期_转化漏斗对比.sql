---【24英锦赛】
with match_info_2024 as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt = '2026-05-08'
    and day >= '2024-11-23'
    and day <= '2024-12-01'
    ---and match_name like '%斯诺克%'
)

, user_info_2024 as ( ---拉新用户
select b.user_ukey 
from match_info_2024 a
inner join (
  select dt, luid, user_ukey 
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 -- 宽口径内容拉新表
  where dt between '2024-11-23' and '2024-12-01' -- 24英锦赛时间
    and user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
) b
on a.dt = b.dt and a.luid = b.luid
group by b.user_ukey 
)

, first_video_time_2024 as (
  select
    user_ukey,
    min(dt) as first_video_dt
  from gamelive.dws_huya_user_behavior_d_i 
  where dt between'2024-11-23' and '2024-12-01'
    and data_type in ('video_session') -- 视频
    and live_content_type='视频'
    and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')  
    and game_id not in (2356)---剔除体育看影响
    and watch_cnt > 0
  group by user_ukey
)

,video_after_dashang_2024 as (
  select 
      a.ukey as user_ukey
  from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
  inner join first_video_time_2024 b
    on a.ukey = b.user_ukey 
    and a.dt >= b.first_video_dt -- 排除在观看视频之前打赏的用户
  where 
    a.dt between '2024-11-23' and '2024-12-01'
    and a.consume_amt>0
  group by a.ukey
)

,base_info_2024 as(
select a.user_ukey 
  ,if(b.user_ukey is not null ,1,0) is_watch_video_tag 
  ,if(c.user_ukey is not null ,1,0) is_watch_xinxiu_tag 
  ,if(d.user_ukey is not null ,1,0) is_dashang_tag 
from user_info_2024 a 
left join(---观看视频
  select user_ukey  
  from gamelive.dws_huya_user_behavior_d_i  
  where dt between'2024-11-23' and '2024-12-01'
    and data_type in ('video_session') -- 视频
    and live_content_type='视频'
    and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')  ---app端
    and game_id not in (2356)---剔除体育看影响
    and watch_cnt > 0
  group by user_ukey
)b 
on a.user_ukey=b.user_ukey 
left join(---观看星秀
  select user_ukey 
  from gamelive.dwt_huya_ayyuid_session_from_server_with_user
  where dt between'2024-11-23' and '2024-12-01' 
    and tag = 'gameid' --固定写法
    and htime = 'session' --固定写法
    and user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
    and igameid=1663 -- 星秀
    and user_duration>0
  group by user_ukey  
)c 
on a.user_ukey=c.user_ukey
left join video_after_dashang_2024 d 
on a.user_ukey=d.user_ukey
)


---【25英锦赛】
,match_info_2025 as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt = '2026-05-08'
    and day >= '2025-11-29'
    and day <= '2025-12-07'
    ---and match_name like '%斯诺克%'
)

, user_info_2025 as ( ---拉新用户
select b.user_ukey 
from match_info_2025 a
inner join (
  select dt, luid, user_ukey 
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 -- 宽口径内容拉新表
  where dt between '2025-11-29' and '2025-12-07' -- 25英锦赛时间
    and user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
) b
on a.dt = b.dt and a.luid = b.luid
group by b.user_ukey 
)


, first_video_time_2025 as (
  select
    user_ukey,
    min(dt) as first_video_dt
  from gamelive.dws_huya_user_behavior_d_i 
  where dt between'2025-11-29' and '2025-12-07'
    and data_type in ('video_session') -- 视频
    and live_content_type='视频'
    and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')  
    and game_id not in (2356)---剔除体育看影响
    and watch_cnt > 0
  group by user_ukey
)

,video_after_dashang_2025 as (
  select 
      a.ukey as user_ukey
  from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
  inner join first_video_time_2025 b
    on a.ukey = b.user_ukey 
    and a.dt >= b.first_video_dt -- 排除在观看视频之前打赏的用户
  where 
    a.dt between '2025-11-29' and '2025-12-07'
    and a.consume_amt>0
  group by a.ukey
)


,base_info_2025 as(
select a.user_ukey 
  ,if(b.user_ukey is not null ,1,0) is_watch_video_tag 
  ,if(c.user_ukey is not null ,1,0) is_watch_xinxiu_tag 
  ,if(d.user_ukey is not null ,1,0) is_dashang_tag 
from user_info_2025 a 
left join(---观看视频
  select user_ukey  
  from gamelive.dws_huya_user_behavior_d_i  
  where dt between'2025-11-29' and '2025-12-07'
    and data_type in ('video_session') -- 视频
    and live_content_type='视频'
    and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')  ---app端
    and game_id not in (2356)---剔除体育看影响
    and watch_cnt > 0
  group by user_ukey
)b 
on a.user_ukey=b.user_ukey 
left join(---观看星秀
  select user_ukey 
  from gamelive.dwt_huya_ayyuid_session_from_server_with_user
  where dt between'2025-11-29' and '2025-12-07' 
    and tag = 'gameid' --固定写法
    and htime = 'session' --固定写法
    and user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
    and igameid=1663 -- 星秀
    and user_duration>0  
  group by user_ukey
)c 
on a.user_ukey=c.user_ukey
left join video_after_dashang_2025 d 
on a.user_ukey=d.user_ukey
)


select 
  '24英锦赛' activity_name    
  ,count(distinct user_ukey)/10000 as lx_ucnt 
  ,count(distinct if(is_watch_video_tag =1 ,user_ukey,null))/10000 as watch_video_cnt 
  ,count(distinct if(is_watch_video_tag =1 and is_watch_xinxiu_tag =1 ,user_ukey,null))/10000 as video_xinxiu_cnt 
  ,count(distinct if(is_watch_video_tag =1 and is_watch_xinxiu_tag =1 and is_dashang_tag =1 ,user_ukey,null))/10000 as video_xinxiu_pay_cnt
  ,count(distinct if(is_dashang_tag =1 ,user_ukey,null))/10000 as dashang_cnt
  ,count(distinct if(is_watch_video_tag =0 ,user_ukey,null))/10000 as not_watch_video_cnt 
  ,count(distinct if(is_watch_video_tag =0 and is_watch_xinxiu_tag =1 ,user_ukey,null))/10000 as not_video_xinxiu_cnt 
  ,count(distinct if(is_watch_video_tag =0 and is_watch_xinxiu_tag =1  and is_dashang_tag =1 ,user_ukey,null))/10000 as not_video_xinxiu_pay_cnt 
from base_info_2024

union all

select 
  '25英锦赛' as activity_name    
  ,count(distinct user_ukey)/10000 as lx_ucnt 
  ,count(distinct if(is_watch_video_tag =1 ,user_ukey,null))/10000 as watch_video_cnt 
  ,count(distinct if(is_watch_video_tag =1 and is_watch_xinxiu_tag =1 ,user_ukey,null))/10000 as video_xinxiu_cnt 
  ,count(distinct if(is_watch_video_tag =1 and is_watch_xinxiu_tag =1  and is_dashang_tag =1 ,user_ukey,null))/10000 as video_xinxiu_pay_cnt 
  ,count(distinct if(is_dashang_tag =1 ,user_ukey,null))/10000 as dashang_cnt
  ,count(distinct if(is_watch_video_tag =0 ,user_ukey,null))/10000 as not_watch_video_cnt 
  ,count(distinct if(is_watch_video_tag =0 and is_watch_xinxiu_tag =1 ,user_ukey,null))/10000 as not_video_xinxiu_cnt 
  ,count(distinct if(is_watch_video_tag =0 and is_watch_xinxiu_tag =1  and is_dashang_tag =1 ,user_ukey,null))/10000 as not_video_xinxiu_pay_cnt
from base_info_2025