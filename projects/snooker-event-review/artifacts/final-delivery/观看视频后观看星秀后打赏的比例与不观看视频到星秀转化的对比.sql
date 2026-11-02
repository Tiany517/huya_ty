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


-- 1. 首次看视频时间
, first_video_time as (
    select 
        user_ukey, 
        min(dt) as first_video_dt
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '2025-08-04' and '2026-01-31'
        and data_type in ('video_session')
        and live_content_type = '视频'
        and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and game_id not in (2356)
        and game_name not in ('体育','台球')
        and watch_cnt > 0
    group by user_ukey
)


-- 2. 视频之后首次看星秀时间
, video_then_xinxiu as (
    select 
        a.user_ukey,
        min(a.dt) as first_xinxiu_after_video_dt
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
    inner join first_video_time b
        on a.user_ukey = b.user_ukey
        and a.dt >= b.first_video_dt -- 关键
    where a.dt between '2025-08-04' and '2026-01-31' -- 拉新后180天
        and a.tag = 'gameid'
        and a.htime = 'session'
        and a.user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and a.igameid = 1663 -- 星秀ID
        and a.user_duration > 0
    group by a.user_ukey
)


-- 3. 视频星秀之后首次打赏时间
, video_xinxiu_dashang as (
    select 
        a.ukey as user_ukey,
        min(a.dt) as first_dashang_dt
    from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
    inner join video_then_xinxiu b
        on a.ukey = b.user_ukey
        and a.dt >= b.first_xinxiu_after_video_dt -- 关键
    where a.dt between '2025-08-04' and '2026-01-31'
        and a.consume_amt > 0
    group by a.ukey
)


-- 4. 没看过视频的人：直接看星秀
, no_video_then_xinxiu as (
    select 
        a.user_ukey,
        min(a.dt) as first_xinxiu_dt
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
    inner join laxin_user_info b
        on a.user_ukey = b.user_ukey
    left join first_video_time c
        on a.user_ukey = c.user_ukey
    where a.dt between '2025-08-04' and '2026-01-31'
        and a.tag = 'gameid'
        and a.htime = 'session'
        and a.user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and a.igameid = 1663
        and a.user_duration > 0
        and c.user_ukey is null  -- 关键：没看过视频的人
    group by a.user_ukey
)

-- 5. 没看过视频，直接星秀之后打赏
, no_video_xinxiu_dashang as (
    select 
        a.ukey as user_ukey,
        min(a.dt) as first_dashang_dt
    from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
    inner join no_video_then_xinxiu b
        on a.ukey = b.user_ukey
        and a.dt >= b.first_xinxiu_dt -- 关键
    where a.dt between '2025-08-04' and '2026-01-31'
        and a.consume_amt > 0
    group by a.ukey
)




-- 分支1：看过视频的人
select
    '看过视频' as user_type,
    count(distinct a.user_ukey) as total_laxin_ucnt,           
    count(distinct b.user_ukey) as video_ucnt,                 -- 有视频的人数
    count(distinct c.user_ukey) as video_then_xinxiu_ucnt,   -- 视频后看星秀
    count(distinct d.user_ukey) as video_then_xinxiu_then_dashang_ucnt,  -- 视频星秀后打赏
    count(distinct b.user_ukey) / count(distinct a.user_ukey) as video_rate,
    count(distinct c.user_ukey)  / count(distinct a.user_ukey) as video_xinxiu_rate,
    count(distinct d.user_ukey)  / count(distinct a.user_ukey) as video_xinxiu_dashang_rate
from laxin_user_info a                                         
left join first_video_time b on a.user_ukey = b.user_ukey     -- 视频行为
left join video_then_xinxiu c on a.user_ukey = c.user_ukey   -- 星秀行为（视频后）
left join video_xinxiu_dashang d on a.user_ukey = d.user_ukey  -- 打赏行为（视频星秀后）


union all


-- 分支2：没看过视频的人
select
    '没看过视频' as user_type,
    count(distinct a.user_ukey) as total_laxin_ucnt,
    0 as video_ucnt,                    
    count(distinct c.user_ukey) as video_then_xinxiu_ucnt, 
    count(distinct d.user_ukey) as video_then_xinxiu_then_dashang_ucnt, 
    0 as video_rate, 
    count(distinct c.user_ukey) * 100.0 / count(distinct a.user_ukey) as video_xinxiu_rate, 
    count(distinct d.user_ukey) * 100.0 / count(distinct a.user_ukey) as video_xinxiu_dashang_rate

from laxin_user_info a                                         
left join first_video_time b on a.user_ukey = b.user_ukey     
left join no_video_then_xinxiu c on a.user_ukey = c.user_ukey   
left join no_video_xinxiu_dashang d on a.user_ukey = d.user_ukey -- 打赏行为（没视频直接星秀后）
