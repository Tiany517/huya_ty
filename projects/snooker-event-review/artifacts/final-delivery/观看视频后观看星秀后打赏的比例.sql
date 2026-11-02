-- ========================================
-- 上海大师赛
-- 拉新用户严格时序行为：视频 → 星秀 → 打赏
-- ========================================

with match_info as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt = '2026-05-10' 
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

-- 1. 首次看视频时间（锚点）
, first_video_time as (
    select 
        user_ukey, 
        min(dt) as first_video_dt
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '2025-08-04' and '2026-01-31'  -- 赛后180天
        and data_type in ('video_session')
        and live_content_type = '视频'
        and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and game_id not in (2356)
        and game_name not in ('体育','台球')
        and watch_cnt > 0
    group by user_ukey
)

-- 2. 视频之后首次看星秀时间
, first_xinxiu_after_video as (
    select 
        a.user_ukey,
        min(a.dt) as first_xinxiu_dt
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
    inner join first_video_time b -- 观看了视频的用户
        on a.user_ukey = b.user_ukey
        and a.dt >= b.first_video_dt  -- 关键：星秀在视频之后
    where a.dt between '2025-08-04' and '2026-01-31'
        and a.tag = 'gameid'
        and a.htime = 'session'
        and a.user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and a.igameid = 1663
        and a.user_duration > 0
    group by a.user_ukey
)


-- 3. 视频星秀之后首次打赏时间
, first_dashang_after_xinxiu as (
    select 
        a.ukey as user_ukey,
        min(a.dt) as first_dashang_dt
    from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
    inner join first_xinxiu_after_video b
        on a.ukey = b.user_ukey
        and a.dt >= b.first_xinxiu_dt  -- 关键：打赏在星秀之后
    where a.dt between '2025-08-04' and '2026-01-31'
        and a.consume_amt > 0
    group by a.ukey
)


select
    '2025上海大师赛' as time_label, 
    count(distinct a.user_ukey)/10000 as total_laxin_ucnt,
    count(distinct b.user_ukey)/10000 as video_ucnt,
    count(distinct c.user_ukey)/10000 as video_then_xinxiu_ucnt,
    count(distinct d.user_ukey)/10000 as video_then_xinxiu_then_dashang_ucnt,
    round(count(distinct b.user_ukey) * 100.0 / count(distinct a.user_ukey), 2) as video_rate,
    round(count(distinct c.user_ukey) * 100.0 / count(distinct a.user_ukey), 2) as video_xinxiu_rate,
    round(count(distinct d.user_ukey) * 100.0 / count(distinct a.user_ukey), 2) as video_xinxiu_dashang_rate
from laxin_user_info a -- 拉新用户
left join first_video_time b -- 视频用户
    on a.user_ukey = b.user_ukey
left join first_xinxiu_after_video c -- 观看视频后看星秀用户
    on a.user_ukey = c.user_ukey
left join first_dashang_after_xinxiu d -- 视频星秀之后打赏用户
    on a.user_ukey = d.user_ukey