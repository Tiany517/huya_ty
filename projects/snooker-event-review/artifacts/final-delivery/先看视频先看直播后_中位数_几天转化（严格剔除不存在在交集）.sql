-- ========================================
-- 简化版：只看两条路径 + 只算平均间隔天数
-- ========================================

with match_info as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt = '2026-05-17' 
    and day >= '2025-07-28'
    and day <= '2025-08-03'
)

, laxin_user_info as (
    select distinct b.user_ukey
    from match_info a
    inner join (
        select dt, luid, user_ukey
        from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
        where dt between '2025-07-28' and '2025-08-03'
            and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
    ) b on a.dt = b.dt and a.luid = b.luid
)

-- ========================================
-- 1. 赛事期间首次行为
-- ========================================
, first_video_time as (
    select user_ukey, min(dt) as first_video_dt
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '2025-07-28' and '2025-08-03'
        and data_type = 'video_session'
        and live_content_type = '视频'
        and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and game_id <> 2356
        and game_name not in ('体育','台球')
        and is_black_ukey = 0
        and watch_cnt > 0
    group by user_ukey
)

, first_live_time as (
    select user_ukey, min(dt) as first_live_dt
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '2025-07-28' and '2025-08-03'
        and data_type = 'live_watch_session'
        and live_content_type = '直播'
        and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and game_id <> 2356
        and game_name not in ('体育','台球')
        and is_black_ukey = 0
        and watch_cnt > 0
    group by user_ukey
)

-- ========================================
-- 2. 只保留两条路径的用户
-- ========================================
, user_type as (
    select 
        a.user_ukey,
        case 
            when v.first_video_dt is not null and l.first_live_dt is not null 
                 and v.first_video_dt < l.first_live_dt then '先看视频'
            when v.first_video_dt is not null and l.first_live_dt is not null 
                 and l.first_live_dt < v.first_video_dt then '先看直播'
            else null
        end as first_behavior,
        v.first_video_dt,
        l.first_live_dt
    from laxin_user_info a
    left join first_video_time v on a.user_ukey = v.user_ukey
    left join first_live_time l on a.user_ukey = l.user_ukey
)

, video_first_users as (
    select user_ukey, first_video_dt, first_live_dt
    from user_type 
    where first_behavior = '先看视频'
)

, live_first_users as (
    select user_ukey, first_video_dt, first_live_dt
    from user_type 
    where first_behavior = '先看直播'
)

-- ========================================
-- 3. 先看视频路径：视频→星秀→打赏
-- ========================================
, video_xinxiu as (
    select 
        a.user_ukey,
        min(a.dt) as xinxiu_dt
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
    inner join video_first_users b on a.user_ukey = b.user_ukey
    where a.dt >= b.first_video_dt
        and a.dt between '2025-08-04' and '2026-01-31'
        and a.tag = 'gameid'
        and a.htime = 'session'
        and a.user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and a.igameid = 1663
        and a.user_duration > 0
    group by a.user_ukey
)

, video_dashang as (
    select 
        a.ukey as user_ukey,
        min(a.dt) as dashang_dt
    from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
    inner join video_xinxiu b on a.ukey = b.user_ukey
    where a.dt >= b.xinxiu_dt
        and a.dt between '2025-08-04' and '2026-01-31'
        and a.consume_amt > 0
    group by a.ukey
)

-- ========================================
-- 4. 先看直播路径：直播→星秀→打赏
-- ========================================
, live_xinxiu as (
    select 
        a.user_ukey,
        min(a.dt) as xinxiu_dt
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
    inner join live_first_users b on a.user_ukey = b.user_ukey
    where a.dt >= b.first_live_dt
        and a.dt between '2025-08-04' and '2026-01-31'
        and a.tag = 'gameid'
        and a.htime = 'session'
        and a.user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and a.igameid = 1663
        and a.user_duration > 0
    group by a.user_ukey
)

, live_dashang as (
    select 
        a.ukey as user_ukey,
        min(a.dt) as dashang_dt
    from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
    inner join live_xinxiu b on a.ukey = b.user_ukey
    where a.dt >= b.xinxiu_dt
        and a.dt between '2025-08-04' and '2026-01-31'
        and a.consume_amt > 0
    group by a.ukey
)

-- ========================================
-- 5. 计算间隔天数（最终输出）
-- ========================================
-- 先看视频
select
    '先看视频' as user_group,
    approx_percentile(
        cast((unix_timestamp(b.xinxiu_dt, 'yyyy-MM-dd') - unix_timestamp(a.first_video_dt, 'yyyy-MM-dd')) / 86400 as int), 
        0.5
    ) as median_days_to_xinxiu,
    approx_percentile(
        cast((unix_timestamp(c.dashang_dt, 'yyyy-MM-dd') - unix_timestamp(b.xinxiu_dt, 'yyyy-MM-dd')) / 86400 as int),
        0.5
    ) as median_days_to_dashang
from video_first_users a
left join video_xinxiu b on a.user_ukey = b.user_ukey
left join video_dashang c on a.user_ukey = c.user_ukey
where b.xinxiu_dt is not null

union all

-- 先看直播
select
    '先看直播' as user_group,
    approx_percentile(
        cast((unix_timestamp(b.xinxiu_dt, 'yyyy-MM-dd') - unix_timestamp(a.first_live_dt, 'yyyy-MM-dd')) / 86400 as int), 
        0.5
    ) as median_days_to_xinxiu,
    approx_percentile(
        cast((unix_timestamp(c.dashang_dt, 'yyyy-MM-dd') - unix_timestamp(b.xinxiu_dt, 'yyyy-MM-dd')) / 86400 as int),
        0.5
    ) as median_days_to_dashang
from live_first_users a
left join live_xinxiu b on a.user_ukey = b.user_ukey
left join live_dashang c on a.user_ukey = c.user_ukey
where b.xinxiu_dt is not null;