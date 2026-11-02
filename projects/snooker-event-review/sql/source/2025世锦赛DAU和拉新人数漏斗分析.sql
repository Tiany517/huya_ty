---【2025世锦赛】
with match_info as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt = '2026-05-10' 
    and day >= '2025-04-18'
    and day <= '2025-05-04'
)

-- ========================================
-- 看过世锦赛的全体用户（去重）
-- ========================================
, shijin_watched_user_info as (
    select distinct b.user_ukey
    from match_info a
    inner join (
        select distinct dt, creator_uid, user_ukey
        from gamelive.dws_huya_user_behavior_d_i
        where dt between '2025-04-18' and '2025-05-04'
            and data_type in ('live_watch_session')
            and is_black_ukey = 0
            and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
    ) b on a.dt = b.dt and a.luid = b.creator_uid
)

-- ========================================
-- 斯诺克拉新用户
-- ========================================
, shijin_laxin_user_info as (
    select distinct b.user_ukey
    from match_info a
    inner join (
        select dt, luid, user_ukey
        from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
        where dt between '2025-04-18' and '2025-05-04'
            and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
    ) b on a.dt = b.dt and a.luid = b.luid
)

-- ========================================
-- 用户标签表（视频、星秀、打赏）
-- ========================================
, user_watch_behavor_info as (
    select distinct user_ukey
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '2025-04-18' and '2025-05-04'
        and data_type in ('video_session')
        and live_content_type = '视频'
        and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and game_id not in (2356)
        and watch_cnt > 0
)

, first_video_time as (
    select user_ukey, min(dt) as first_video_dt
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '2025-04-18' and '2025-05-04'
        and data_type in ('video_session')
        and live_content_type = '视频'
        and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and game_id not in (2356)
        and watch_cnt > 0
    group by user_ukey
)

, video_after_dashang as (
    select distinct a.ukey as user_ukey
    from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
    inner join first_video_time b
        on a.ukey = b.user_ukey
        and a.dt >= b.first_video_dt
    where a.dt between '2025-04-18' and '2025-05-04'
        and a.consume_amt > 0
)

, xinxiu_watch_behavor_info as (
    select distinct user_ukey
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where dt between '2025-04-18' and '2025-05-04'
        and tag = 'gameid'
        and htime = 'session'
        and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and igameid = 1663
        and user_duration > 0
)

-- ========================================
-- 群体1：看过世锦赛的全体用户（DAU）
-- ========================================
select
    '2026世锦赛期间' as time_label,
    '看赛用户' as user_group,
    count(distinct a.user_ukey)/10000 as ucnt,
    count(distinct if(b.user_ukey is not null, a.user_ukey, null))/10000 as watch_video_cnt,
    count(distinct if(c.user_ukey is not null, a.user_ukey, null))/10000 as watch_xinxiu_cnt,
    count(distinct if(d.user_ukey is not null, a.user_ukey, null))/10000 as dashang_cnt
from shijin_watched_user_info a
left join user_watch_behavor_info b on a.user_ukey = b.user_ukey
left join xinxiu_watch_behavor_info c on a.user_ukey = c.user_ukey
left join video_after_dashang d on a.user_ukey = d.user_ukey

union all

-- ========================================
-- 群体2：斯诺克拉新用户
-- ========================================
select
    '2026世锦赛期间' as time_label,
    '拉新用户' as user_group,
    count(distinct a.user_ukey)/10000 as ucnt,
    count(distinct if(b.user_ukey is not null, a.user_ukey, null))/10000 as watch_video_cnt,
    count(distinct if(c.user_ukey is not null, a.user_ukey, null))/10000 as watch_xinxiu_cnt,
    count(distinct if(d.user_ukey is not null, a.user_ukey, null))/10000 as dashang_cnt
from shijin_laxin_user_info a
left join user_watch_behavor_info b on a.user_ukey = b.user_ukey
left join xinxiu_watch_behavor_info c on a.user_ukey = c.user_ukey
left join video_after_dashang d on a.user_ukey = d.user_ukey;