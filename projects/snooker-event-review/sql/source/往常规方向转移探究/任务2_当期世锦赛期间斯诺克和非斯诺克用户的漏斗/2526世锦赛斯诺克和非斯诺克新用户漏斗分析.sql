---【25世锦赛】
with match_info as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a --体育运动直播表
  where dt = '2026-05-08' 
    and day >= '2026-04-18'
    and day <= '2026-05-04'
    ---and match_name like '%斯诺克%'
)

, shijin_laxin_user_info as ( ---斯诺克拉新用户
select b.user_ukey 
from match_info a
join (
  select dt, luid, user_ukey 
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 -- 宽口径内容拉新表
  where dt between '2026-04-18' and '2026-05-04'
    and user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
) b
on a.dt = b.dt and a.luid = b.luid
group by b.user_ukey 
)

, not_shijin_laxin_user_info as ( ---非斯诺克拉新用户
select a.user_ukey
from (
  select user_ukey
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
  where dt between '2026-04-18' and '2026-05-04'
      and user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
  group by user_ukey
) a
left join shijin_laxin_user_info b
  on a.user_ukey = b.user_ukey
where b.user_ukey is null  -- 保留非斯诺克用户
)

, user_watch_behavor_info as( ---用户观看行为表
  select 
    user_ukey  
  from gamelive.dws_huya_user_behavior_d_i  
  where dt between '2026-04-18' and '2026-05-04'
    and data_type in ('video_session') -- 视频
    and live_content_type='视频'
    and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')  ---app端
    and game_id not in (2356)---剔除体育看影响
    and watch_cnt > 0
  group by user_ukey
)

, first_video_time as (
  select
    user_ukey,
    min(dt) as first_video_dt
  from gamelive.dws_huya_user_behavior_d_i  
  where dt between '2026-04-18' and '2026-05-04'
    and data_type in ('video_session') -- 视频
    and live_content_type='视频'
    and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')  ---app端
    and game_id not in (2356)---剔除体育看影响
    and watch_cnt > 0
  group by user_ukey
)

, video_after_dashang as (
  select 
    a.ukey as user_ukey
  from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a -- 直播打赏表
  inner join first_video_time b
    on a.ukey = b.user_ukey
    and a.dt >= b.first_video_dt -- 排除在观看视频之前打赏的用户
  where a.dt between '2026-04-18' and '2026-05-04'
    and a.consume_amt > 0 
  group by a.ukey
)

, xinxiu_watch_behavor_info as( ---用户观看星秀行为表
  select user_ukey 
  from gamelive.dwt_huya_ayyuid_session_from_server_with_user
  where dt between '2026-04-18' and '2026-05-04' 
    and tag = 'gameid'
    and htime = 'session'
    and user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
    and igameid=1663
    and user_duration > 0 
  group by user_ukey
)

, shijin_laxin_base_info as(
select a.user_ukey 
  ,if(b.user_ukey is not null ,1,0) is_watch_video_tag 
  ,if(c.user_ukey is not null ,1,0) is_watch_xinxiu_tag 
  ,if(d.user_ukey is not null ,1,0) is_dashang_tag 
from shijin_laxin_user_info a 
left join user_watch_behavor_info b 
  on a.user_ukey = b.user_ukey 
left join xinxiu_watch_behavor_info c 
  on a.user_ukey = c.user_ukey
left join video_after_dashang d 
  on a.user_ukey = d.user_ukey
)

, not_shijin_laxin_base_info as(
select a.user_ukey 
  ,if(b.user_ukey is not null ,1,0) is_watch_video_tag 
  ,if(c.user_ukey is not null ,1,0) is_watch_xinxiu_tag 
  ,if(d.user_ukey is not null ,1,0) is_dashang_tag 
from not_shijin_laxin_user_info a 
left join user_watch_behavor_info b 
  on a.user_ukey = b.user_ukey 
left join xinxiu_watch_behavor_info c 
  on a.user_ukey = c.user_ukey
left join video_after_dashang d 
  on a.user_ukey = d.user_ukey
)


select
  '2026世锦赛期间' as time_label
  ,'斯诺克拉新用户' as laxin_label
  ,count(distinct user_ukey)/10000 as lx_ucnt 
  ,count(distinct if(is_watch_video_tag = 1, user_ukey, null))/10000 as watch_video_cnt 
  ,count(distinct if(is_watch_video_tag = 1 and is_watch_xinxiu_tag = 1, user_ukey, null))/10000 as video_xinxiu_cnt 
  ,count(distinct if(is_watch_video_tag = 1 and is_watch_xinxiu_tag = 1 and is_dashang_tag = 1, user_ukey, null))/10000 as video_xinxiu_pay_cnt
  ,count(distinct if(is_dashang_tag = 1, user_ukey, null))/10000 as dashang_cnt
  ,count(distinct if(is_watch_video_tag = 0, user_ukey, null))/10000 as not_watch_video_cnt 
  ,count(distinct if(is_watch_video_tag = 0 and is_watch_xinxiu_tag = 1, user_ukey, null))/10000 as not_video_xinxiu_cnt 
  ,count(distinct if(is_watch_video_tag = 0 and is_watch_xinxiu_tag = 1 and is_dashang_tag = 1, user_ukey, null))/10000 as not_video_xinxiu_pay_cnt 
from shijin_laxin_base_info

union all

select
  '2026世锦赛期间' as time_label
  ,'非斯诺克拉新用户' as laxin_label
  ,count(distinct user_ukey)/10000 as lx_ucnt 
  ,count(distinct if(is_watch_video_tag = 1, user_ukey, null))/10000 as watch_video_cnt 
  ,count(distinct if(is_watch_video_tag = 1 and is_watch_xinxiu_tag = 1, user_ukey, null))/10000 as video_xinxiu_cnt 
  ,count(distinct if(is_watch_video_tag = 1 and is_watch_xinxiu_tag = 1 and is_dashang_tag = 1, user_ukey, null))/10000 as video_xinxiu_pay_cnt
  ,count(distinct if(is_dashang_tag = 1, user_ukey, null))/10000 as dashang_cnt
  ,count(distinct if(is_watch_video_tag = 0, user_ukey, null))/10000 as not_watch_video_cnt 
  ,count(distinct if(is_watch_video_tag = 0 and is_watch_xinxiu_tag = 1, user_ukey, null))/10000 as not_video_xinxiu_cnt 
  ,count(distinct if(is_watch_video_tag = 0 and is_watch_xinxiu_tag = 1 and is_dashang_tag = 1, user_ukey, null))/10000 as not_video_xinxiu_pay_cnt 
from not_shijin_laxin_base_info;