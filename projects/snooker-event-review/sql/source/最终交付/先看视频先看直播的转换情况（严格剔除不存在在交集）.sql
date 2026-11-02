with match_info as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt = '2026-05-10' 
    and day >= '2025-07-28'
    and day <= '2025-08-03' -- 上海大师赛
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
-- 1. 赛事期间：首次看视频和首次看直播的时间
-- ========================================
, first_video_time as (
    select 
        user_ukey, 
        min(dt) as first_video_dt
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '2025-07-28' and '2025-08-03'
        and data_type in ('video_session')
        and live_content_type = '视频'
        and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and game_id not in (2356)
        and game_name not in ('体育','台球')
        and is_black_ukey = 0
        and watch_cnt > 0
    group by user_ukey
)

, first_live_time as (
    select 
        user_ukey, 
        min(dt) as first_live_dt
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '2025-07-28' and '2025-08-03'
        and data_type in ('live_watch_session')
        and live_content_type = '直播'
        and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and game_id not in (2356)
        and game_name not in ('体育','台球')
        and is_black_ukey = 0
        and watch_cnt > 0
    group by user_ukey
)

-- ========================================
-- 2. 区分用户类型（赛事期间行为）
-- ========================================
, user_first_behavior as (
    select 
        a.user_ukey,
        case 
            when v.first_video_dt is not null and l.first_live_dt is null then '只看视频'
            when v.first_video_dt is null and l.first_live_dt is not null then '只看直播'
            when v.first_video_dt is not null and l.first_live_dt is not null then
                (case when v.first_video_dt < l.first_live_dt then '先看视频' else '先看直播' end)
            else '无行为'
        end as first_behavior
    from laxin_user_info a
    left join first_video_time v on a.user_ukey = v.user_ukey
    left join first_live_time l on a.user_ukey = l.user_ukey
)

-- ========================================
-- 3. 各组用户名单
-- ========================================
, video_first_users as (
    select user_ukey from user_first_behavior where first_behavior = '先看视频'
)

, live_first_users as (
    select user_ukey from user_first_behavior where first_behavior = '先看直播'
)

, only_video_users as (
    select user_ukey from user_first_behavior where first_behavior = '只看视频'
)

, only_live_users as (
    select user_ukey from user_first_behavior where first_behavior = '只看直播'
)

-- ========================================
-- 4. 先看视频：视频→星秀→打赏（严格时序）
-- ========================================
, video_then_xinxiu as (
    select 
        a.user_ukey,
        min(a.dt) as first_xinxiu_after_video_dt
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
    inner join first_video_time b on a.user_ukey = b.user_ukey
        and a.dt >= b.first_video_dt
    where a.dt between '2025-08-04' and '2026-01-31'
        and a.tag = 'gameid'
        and a.htime = 'session'
        and a.user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and a.igameid = 1663
        and a.user_duration > 0
    group by a.user_ukey
)

, video_xinxiu_dashang as (
    select 
        a.ukey as user_ukey,
        min(a.dt) as first_dashang_dt
    from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
    inner join video_then_xinxiu b on a.ukey = b.user_ukey
        and a.dt >= b.first_xinxiu_after_video_dt
    where a.dt between '2025-08-04' and '2026-01-31'
        and a.consume_amt > 0
    group by a.ukey
)

-- ========================================
-- 5. 先看直播：直播→星秀→打赏（严格时序）
-- ========================================
, live_then_xinxiu as (
    select 
        a.user_ukey,
        min(a.dt) as first_xinxiu_after_live_dt
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
    inner join first_live_time b on a.user_ukey = b.user_ukey
        and a.dt >= b.first_live_dt
    where a.dt between '2025-08-04' and '2026-01-31'
        and a.tag = 'gameid'
        and a.htime = 'session'
        and a.user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and a.igameid = 1663
        and a.user_duration > 0
    group by a.user_ukey
)

, live_xinxiu_dashang as (
    select 
        a.ukey as user_ukey,
        min(a.dt) as first_dashang_dt
    from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
    inner join live_then_xinxiu b on a.ukey = b.user_ukey
        and a.dt >= b.first_xinxiu_after_live_dt
    where a.dt between '2025-08-04' and '2026-01-31'
        and a.consume_amt > 0
    group by a.ukey
)

-- ========================================
-- 6. 只看视频：赛后→星秀→打赏（严格时序）
-- ========================================
, only_video_then_xinxiu as (
    select 
        a.user_ukey,
        min(a.dt) as first_xinxiu_dt
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
    inner join only_video_users b on a.user_ukey = b.user_ukey
    where a.dt between '2025-08-04' and '2026-01-31'
        and a.tag = 'gameid'
        and a.htime = 'session'
        and a.user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and a.igameid = 1663
        and a.user_duration > 0
    group by a.user_ukey
)

, only_video_xinxiu_dashang as (
    select 
        a.ukey as user_ukey,
        min(a.dt) as first_dashang_dt
    from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
    inner join only_video_then_xinxiu b on a.ukey = b.user_ukey
        and a.dt >= b.first_xinxiu_dt
    where a.dt between '2025-08-04' and '2026-01-31'
        and a.consume_amt > 0
    group by a.ukey
)

-- ========================================
-- 7. 只看直播：赛后→星秀→打赏（严格时序）
-- ========================================
, only_live_then_xinxiu as (
    select 
        a.user_ukey,
        min(a.dt) as first_xinxiu_dt
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
    inner join only_live_users b on a.user_ukey = b.user_ukey
    where a.dt between '2025-08-04' and '2026-01-31'
        and a.tag = 'gameid'
        and a.htime = 'session'
        and a.user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and a.igameid = 1663
        and a.user_duration > 0
    group by a.user_ukey
)

, only_live_xinxiu_dashang as (
    select 
        a.ukey as user_ukey,
        min(a.dt) as first_dashang_dt
    from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
    inner join only_live_then_xinxiu b on a.ukey = b.user_ukey
        and a.dt >= b.first_xinxiu_dt
    where a.dt between '2025-08-04' and '2026-01-31'
        and a.consume_amt > 0
    group by a.ukey
)

-- ========================================
-- 最终输出：四组漏斗对比
-- ========================================

-- ========================================
-- 最终输出：四组漏斗对比
-- ========================================

-- 先计算总拉新人数（用于计算占比）
, total_laxin_cnt as (
    select count(distinct user_ukey) as total_cnt from laxin_user_info
)

-- 组1：先看视频
select
    '先看视频' as user_group,
    (select total_cnt from total_laxin_cnt) as total_laxin_ucnt,  -- 拉新总人次
    count(distinct a.user_ukey) as group_ucnt,                     -- 本组人数
    count(distinct a.user_ukey)/ (select total_cnt from total_laxin_cnt) as group_ratio,  -- 占拉新比例
    
    count(distinct b.user_ukey) as video_ucnt,
    count(distinct c.user_ukey) as xinxiu_ucnt,
    count(distinct d.user_ukey) as dashang_ucnt,
    
    -- 漏斗转化率（逐级）
    count(distinct b.user_ukey)/ count(distinct a.user_ukey) as step1_rate,
    count(distinct c.user_ukey)/ nullif(count(distinct b.user_ukey), 0) as step2_rate,
    count(distinct d.user_ukey)/ nullif(count(distinct c.user_ukey), 0) as step3_rate

from video_first_users a
left join first_video_time b on a.user_ukey = b.user_ukey
left join video_then_xinxiu c on a.user_ukey = c.user_ukey
left join video_xinxiu_dashang d on a.user_ukey = d.user_ukey

union all

-- 组2：先看直播
select
    '先看直播' as user_group,
    (select total_cnt from total_laxin_cnt) as total_laxin_ucnt,
    count(distinct a.user_ukey) as group_ucnt,
    count(distinct a.user_ukey)/ (select total_cnt from total_laxin_cnt) as group_ratio,
    
    count(distinct b.user_ukey) as live_ucnt,
    count(distinct c.user_ukey) as xinxiu_ucnt,
    count(distinct d.user_ukey) as dashang_ucnt,
    
    count(distinct b.user_ukey)/ count(distinct a.user_ukey) as step1_rate,
    count(distinct c.user_ukey)/ nullif(count(distinct b.user_ukey), 0) as step2_rate,
    count(distinct d.user_ukey)/ nullif(count(distinct c.user_ukey), 0) as step3_rate

from live_first_users a
left join first_live_time b on a.user_ukey = b.user_ukey
left join live_then_xinxiu c on a.user_ukey = c.user_ukey
left join live_xinxiu_dashang d on a.user_ukey = d.user_ukey

union all

-- 组3：只看视频
select
    '只看视频' as user_group,
    (select total_cnt from total_laxin_cnt) as total_laxin_ucnt,
    count(distinct a.user_ukey) as group_ucnt,
    count(distinct a.user_ukey)/ (select total_cnt from total_laxin_cnt) as group_ratio,
    
    count(distinct b.user_ukey) as video_ucnt,
    count(distinct c.user_ukey) as xinxiu_ucnt,
    count(distinct d.user_ukey) as dashang_ucnt,
    
    count(distinct b.user_ukey)/ count(distinct a.user_ukey) as step1_rate,
    count(distinct c.user_ukey)/ nullif(count(distinct a.user_ukey), 0) as step2_rate,
    count(distinct d.user_ukey)/ nullif(count(distinct c.user_ukey), 0) as step3_rate

from only_video_users a
left join first_video_time b on a.user_ukey = b.user_ukey
left join only_video_then_xinxiu c on a.user_ukey = c.user_ukey
left join only_video_xinxiu_dashang d on a.user_ukey = d.user_ukey

union all

-- 组4：只看直播
select
    '只看直播' as user_group,
    (select total_cnt from total_laxin_cnt) as total_laxin_ucnt,
    count(distinct a.user_ukey) as group_ucnt,
    count(distinct a.user_ukey)/ (select total_cnt from total_laxin_cnt) as group_ratio,
    
    count(distinct b.user_ukey) as live_ucnt,
    count(distinct c.user_ukey) as xinxiu_ucnt,
    count(distinct d.user_ukey) as dashang_ucnt,
    
    count(distinct b.user_ukey)/ count(distinct a.user_ukey) as step1_rate,
    count(distinct c.user_ukey)/ nullif(count(distinct a.user_ukey), 0) as step2_rate,
    count(distinct d.user_ukey)/ nullif(count(distinct c.user_ukey), 0) as step3_rate

from only_live_users a
left join first_live_time b on a.user_ukey = b.user_ukey
left join only_live_then_xinxiu c on a.user_ukey = c.user_ukey
left join only_live_xinxiu_dashang d on a.user_ukey = d.user_ukey