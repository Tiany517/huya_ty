---【25英锦赛】
with match_info as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt = '2026-05-08'
    and day >= '2025-11-29'
    and day <= '2025-12-07'
    ---and match_name like '%斯诺克%'
)

, user_info as ( ---拉新用户
select b.user_ukey 
from match_info a
inner join (
  select dt, luid, user_ukey 
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 -- 宽口径内容拉新表
  where dt between '2025-11-29' and '2025-12-07' -- 25英锦赛时间
    and user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
) b
on a.dt = b.dt and a.luid = b.luid
group by b.user_ukey 
)

, first_video_time as (
  select
    user_ukey,
    min(dt) as first_video_dt
  from gamelive.dws_huya_user_behavior_d_i 
  where dt between '2025-11-29' and '2025-12-07'
    and data_type in ('video_session') -- 视频
    and live_content_type='视频'
    and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')  
    and game_id not in (2356)---剔除体育看影响
    and watch_cnt > 0
  group by user_ukey
)

,video_after_dashang as (
  select 
      a.ukey as user_ukey
  from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
  inner join first_video_time b
    on a.ukey = b.user_ukey 
    and a.dt >= b.first_video_dt -- 排除在观看视频之前打赏的用户
  where 
    a.dt between '2025-11-29' and '2025-12-07'
    and a.consume_amt>0
  group by a.ukey
)

,base_info as(
select a.user_ukey 
  ,if(b.user_ukey is not null ,1,0) is_watch_video_tag 
  ,if(c.user_ukey is not null ,1,0) is_watch_xinxiu_tag 
  ,if(d.user_ukey is not null ,1,0) is_dashang_tag 
from user_info a 
left join(---观看视频
  select user_ukey  
  from gamelive.dws_huya_user_behavior_d_i  
  where dt between '2025-11-29' and '2025-12-07'
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
  where dt between '2025-11-29' and '2025-12-07' 
    and tag = 'gameid' --固定写法
    and htime = 'session' --固定写法
    and user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
    and igameid=1663 -- 星秀
    and user_duration>0
  group by user_ukey  
)c 
on a.user_ukey=c.user_ukey
left join video_after_dashang d 
on a.user_ukey=d.user_ukey
)

-- ========================================
-- 新增：180天长期行为（2025-12-07 到 2026-06-05）
-- 核心：直接在子查询中用case when判断赛事，无额外CTE
-- ========================================

-- 赛事判断函数：直接在select中写死日期区间
, long_video as (---180天观看视频
  select 
    a.user_ukey,
    b.dt,
    -- 直接判断是否为赛事期间
    case 
      when (
        (b.dt between '2025-12-10' and '2025-12-13')   -- 单局限时赛
        or (b.dt between '2025-12-15' and '2025-12-21')  -- 苏格兰公开赛
        or (b.dt between '2026-01-11' and '2026-01-18')  -- 大师赛(邀请赛)
        or (b.dt between '2026-01-26' and '2026-02-01')  -- 德国大师赛
        or (b.dt between '2026-02-03' and '2026-02-08')  -- 世界大奖赛
        or (b.dt between '2026-02-17' and '2026-02-22')  -- 球员锦标赛
        or (b.dt between '2026-02-23' and '2026-03-01')  -- 威尔士公开赛
        or (b.dt between '2026-03-16' and '2026-03-22')  -- 世界公开赛
        or (b.dt between '2026-03-30' and '2026-04-05')  -- 巡回锦标赛
        or (b.dt between '2026-04-18' and '2026-05-04')  -- 世锦赛
      ) then 1 else 0 
    end as is_match_day,
    b.watch_cnt,
    b.watch_duration
  from user_info a
  join gamelive.dws_huya_user_behavior_d_i b
    on a.user_ukey = b.user_ukey
  where b.dt between '2025-12-07' and '2026-06-05'
    and b.data_type = 'video_session'
    and b.live_content_type = '视频'
    and b.product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
    and b.game_id not in (2356)
    and b.watch_cnt > 0
)

, long_xinxiu as (---180天观看星秀
  select 
    a.user_ukey,
    b.dt,
    case 
      when (
        (b.dt between '2025-12-10' and '2025-12-13')
        or (b.dt between '2025-12-15' and '2025-12-21')
        or (b.dt between '2026-01-11' and '2026-01-18')
        or (b.dt between '2026-01-26' and '2026-02-01')
        or (b.dt between '2026-02-03' and '2026-02-08')
        or (b.dt between '2026-02-17' and '2026-02-22')
        or (b.dt between '2026-02-23' and '2026-03-01')
        or (b.dt between '2026-03-16' and '2026-03-22')
        or (b.dt between '2026-03-30' and '2026-04-05')
        or (b.dt between '2026-04-18' and '2026-05-04')
      ) then 1 else 0 
    end as is_match_day,
    b.user_duration
  from user_info a
  join gamelive.dwt_huya_ayyuid_session_from_server_with_user b
    on a.user_ukey = b.user_ukey
  where b.dt between '2025-12-07' and '2026-06-05'
    and b.tag = 'gameid'
    and b.htime = 'session'
    and b.user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
    and b.igameid = 1663
    and b.user_duration > 0
)

, long_dashang as (--180天打赏（视频之后）
  select 
    a.ukey as user_ukey,
    a.dt,
    case 
      when (
        (a.dt between '2025-12-10' and '2025-12-13')
        or (a.dt between '2025-12-15' and '2025-12-21')
        or (a.dt between '2026-01-11' and '2026-01-18')
        or (a.dt between '2026-01-26' and '2026-02-01')
        or (a.dt between '2026-02-03' and '2026-02-08')
        or (a.dt between '2026-02-17' and '2026-02-22')
        or (a.dt between '2026-02-23' and '2026-03-01')
        or (a.dt between '2026-03-16' and '2026-03-22')
        or (a.dt between '2026-03-30' and '2026-04-05')
        or (a.dt between '2026-04-18' and '2026-05-04')
      ) then 1 else 0 
    end as is_match_day,
    a.consume_amt
  from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
  inner join (
    -- 首次看视频时间（180天内）
    select user_ukey, min(dt) as first_video_dt
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '2025-12-07' and '2026-06-05'
      and data_type = 'video_session'
      and live_content_type = '视频'
      and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
      and game_id not in (2356)
      and watch_cnt > 0
    group by 1 
  ) v
    on a.ukey = v.user_ukey
    and a.dt >= v.first_video_dt -- 排除在观看视频之前的打赏
  where a.dt between '2025-12-07' and '2026-06-05'
    and a.consume_amt > 0
)


-- 英锦赛期间
select 
  '25英锦赛' activity_name    
  ,count(distinct user_ukey)/10000 as lx_ucnt 
  ,count(distinct if(is_watch_video_tag =1 ,user_ukey,null))/10000 as watch_video_cnt 
  ,count(distinct if(is_watch_video_tag =1 and is_watch_xinxiu_tag =1 ,user_ukey,null))/10000 as video_xinxiu_cnt 
  ,count(distinct if(is_watch_video_tag =1 and is_watch_xinxiu_tag =1 and is_dashang_tag =1 ,user_ukey,null))/10000 as video_xinxiu_pay_cnt
  ,count(distinct if(is_dashang_tag =1 ,user_ukey,null))/10000 as dashang_cnt
  ,count(distinct if(is_watch_video_tag =0 ,user_ukey,null))/10000 as not_watch_video_cnt 
  ,count(distinct if(is_watch_video_tag =0 and is_watch_xinxiu_tag =1 ,user_ukey,null))/10000 as not_video_xinxiu_cnt 
  ,count(distinct if(is_watch_video_tag =0 and is_watch_xinxiu_tag =1  and is_dashang_tag =1 ,user_ukey,null))/10000 as not_video_xinxiu_pay_cnt 
from base_info

union all

-- 180天整体
select 
  '25英锦赛-180天整体' activity_name    
  ,count(distinct a.user_ukey)/10000 as lx_ucnt 
  ,count(distinct if(b.video_cnt > 0, a.user_ukey, null))/10000 as watch_video_cnt 
  ,count(distinct if(b.video_cnt > 0 and c.xinxiu_cnt > 0, a.user_ukey, null))/10000 as video_xinxiu_cnt 
  ,count(distinct if(b.video_cnt > 0 and c.xinxiu_cnt > 0 and d.consume_amt > 0, a.user_ukey, null))/10000 as video_xinxiu_pay_cnt
  ,count(distinct if(d.consume_amt > 0, a.user_ukey, null))/10000 as dashang_cnt
  ,count(distinct if(b.video_cnt = 0 or b.video_cnt is null, a.user_ukey, null))/10000 as not_watch_video_cnt 
  ,count(distinct if((b.video_cnt = 0 or b.video_cnt is null) and c.xinxiu_cnt > 0, a.user_ukey, null))/10000 as not_video_xinxiu_cnt 
  ,count(distinct if((b.video_cnt = 0 or b.video_cnt is null) and c.xinxiu_cnt > 0 and d.consume_amt > 0, a.user_ukey, null))/10000 as not_video_xinxiu_pay_cnt 
from user_info a
left join (
  select user_ukey, sum(watch_cnt) as video_cnt
  from long_video
  group by 1
) b on a.user_ukey = b.user_ukey
left join (
  select user_ukey, count(*) as xinxiu_cnt
  from long_xinxiu
  group by 1
) c on a.user_ukey = c.user_ukey
left join (
  select user_ukey, sum(consume_amt) as consume_amt
  from long_dashang
  group by 1
) d on a.user_ukey = d.user_ukey

union all

-- 180天_赛事期间
select 
  '25英锦赛-180天_赛事期间' activity_name    
  ,count(distinct a.user_ukey)/10000 as lx_ucnt 
  ,count(distinct if(b.video_cnt > 0, a.user_ukey, null))/10000 as watch_video_cnt 
  ,count(distinct if(b.video_cnt > 0 and c.xinxiu_cnt > 0, a.user_ukey, null))/10000 as video_xinxiu_cnt 
  ,count(distinct if(b.video_cnt > 0 and c.xinxiu_cnt > 0 and d.consume_amt > 0, a.user_ukey, null))/10000 as video_xinxiu_pay_cnt
  ,count(distinct if(d.consume_amt > 0, a.user_ukey, null))/10000 as dashang_cnt
  ,count(distinct if(b.video_cnt = 0 or b.video_cnt is null, a.user_ukey, null))/10000 as not_watch_video_cnt 
  ,count(distinct if((b.video_cnt = 0 or b.video_cnt is null) and c.xinxiu_cnt > 0, a.user_ukey, null))/10000 as not_video_xinxiu_cnt 
  ,count(distinct if((b.video_cnt = 0 or b.video_cnt is null) and c.xinxiu_cnt > 0 and d.consume_amt > 0, a.user_ukey, null))/10000 as not_video_xinxiu_pay_cnt 
from user_info a
left join (
  select user_ukey, sum(watch_cnt) as video_cnt
  from long_video
  where is_match_day = 1
  group by 1
) b on a.user_ukey = b.user_ukey
left join (
  select user_ukey, count(*) as xinxiu_cnt
  from long_xinxiu
  where is_match_day = 1
  group by 1
) c on a.user_ukey = c.user_ukey
left join (
  select user_ukey, sum(consume_amt) as consume_amt
  from long_dashang
  where is_match_day = 1
  group by 1
) d on a.user_ukey = d.user_ukey

union all

-- 180天_非赛事期间
select 
  '25英锦赛-180天_非赛事期间' activity_name    
  ,count(distinct a.user_ukey)/10000 as lx_ucnt 
  ,count(distinct if(b.video_cnt > 0, a.user_ukey, null))/10000 as watch_video_cnt 
  ,count(distinct if(b.video_cnt > 0 and c.xinxiu_cnt > 0, a.user_ukey, null))/10000 as video_xinxiu_cnt 
  ,count(distinct if(b.video_cnt > 0 and c.xinxiu_cnt > 0 and d.consume_amt > 0, a.user_ukey, null))/10000 as video_xinxiu_pay_cnt
  ,count(distinct if(d.consume_amt > 0, a.user_ukey, null))/10000 as dashang_cnt
  ,count(distinct if(b.video_cnt = 0 or b.video_cnt is null, a.user_ukey, null))/10000 as not_watch_video_cnt 
  ,count(distinct if((b.video_cnt = 0 or b.video_cnt is null) and c.xinxiu_cnt > 0, a.user_ukey, null))/10000 as not_video_xinxiu_cnt 
  ,count(distinct if((b.video_cnt = 0 or b.video_cnt is null) and c.xinxiu_cnt > 0 and d.consume_amt > 0, a.user_ukey, null))/10000 as not_video_xinxiu_pay_cnt 
from user_info a
left join (
  select user_ukey, sum(watch_cnt) as video_cnt
  from long_video
  where is_match_day = 0
  group by 1
) b on a.user_ukey = b.user_ukey
left join (
  select user_ukey, count(*) as xinxiu_cnt
  from long_xinxiu
  where is_match_day = 0
  group by 1
) c on a.user_ukey = c.user_ukey
left join (
  select user_ukey, sum(consume_amt) as consume_amt
  from long_dashang
  where is_match_day = 0
  group by 1
) d on a.user_ukey = d.user_ukey