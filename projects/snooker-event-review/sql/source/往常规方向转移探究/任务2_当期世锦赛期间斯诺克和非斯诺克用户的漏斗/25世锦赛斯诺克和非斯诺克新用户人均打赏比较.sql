---【2025世锦赛】
-- 2025年4月18日-2025年5月4日
with match_info as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a --体育运动直播表
  where dt = '2026-05-08' 
    and day >= '2025-04-18'
    and day <= '2025-05-04'
    ---and match_name like '%斯诺克%'
)

, shijin_laxin_user_info as ( ---斯诺克拉新用户
select b.user_ukey 
from match_info a
inner join (
  select dt, luid, user_ukey 
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 -- 宽口径内容拉新表
  where dt between '2025-04-18' and '2025-05-04'
    and user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
) b
on a.dt = b.dt and a.luid = b.luid
group by b.user_ukey 
)

, not_shijin_laxin_user_info as ( ---非斯诺克拉新用户
select a.user_ukey
from (
  select user_ukey 
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 -- 宽口径内容拉新表
  where dt between '2025-04-18' and '2025-05-04'
    and user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
) a
left join shijin_laxin_user_info b
on a.user_ukey = b.user_ukey
where b.user_ukey is null -- 表示非斯诺克拉新用户
group by a.user_ukey 
)

, first_video_time as (
  select
    user_ukey,
    min(dt) as first_video_dt
  from gamelive.dws_huya_user_behavior_d_i  
  where dt between '2025-04-18' and '2025-05-04'
    and data_type in ('video_session') -- 视频
    and live_content_type='视频'
    and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')  ---app端
    and game_id not in (2356)---剔除体育看影响
    and watch_cnt > 0
  group by user_ukey
)

, dashang_agg as (
  select 
    a.ukey as user_ukey,             
    sum(a.consume_amt) as total_consume,  -- 总打赏金额
    avg(a.consume_amt) as avg_consume     -- 平均打赏金额
  from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
  inner join first_video_time b        -- 只保留看过视频且之后打赏的
    on a.ukey = b.user_ukey 
    and a.dt >= b.first_video_dt       -- 打赏在首次看视频之后
  where a.dt between '2025-04-18' and '2025-05-04'
    and a.consume_amt > 0
  group by a.ukey
)


select
  '2025世锦赛期间' as event_label,
  '2025-04-18' as time_label,
  '斯诺克拉新用户' as user_label,
  count(distinct a.user_ukey)/10000 as lx_ucnt,
  count(distinct b.user_ukey)/10000 as dashang_ucnt,  
  count(distinct b.user_ukey) / count(distinct a.user_ukey) as dashang_rate,
  sum(b.total_consume)/10000 as total_consume,
  avg(b.total_consume) as avg_total_consume,
  avg(b.avg_consume) as avg_per_dashang
from shijin_laxin_user_info a
left join dashang_agg b
  on a.user_ukey = b.user_ukey
group by 1,2,3

union all

select
  '2025世锦赛期间' as event_label,
  '2025-04-18' as time_label,
  '非斯诺克拉新用户' as user_label,
  count(distinct a.user_ukey)/10000 as lx_ucnt,
  count(distinct b.user_ukey)/10000 as dashang_ucnt,
  count(distinct b.user_ukey) / count(distinct a.user_ukey) as dashang_rate,
  sum(b.total_consume)/10000 as total_consume,
  avg(b.total_consume) as avg_total_consume,
  avg(b.avg_consume) as avg_per_dashang
from not_shijin_laxin_user_info a
left join dashang_agg b
  on a.user_ukey = b.user_ukey
group by 1,2,3;