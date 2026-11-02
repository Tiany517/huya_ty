---【2026世锦赛】
with match_info_2026 as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt = '2026-05-17' 
    and day >= '2026-04-18'
    and day <= '2026-05-05'
)

, laxin_user_info_2026  as (
    select b.dt, b.user_ukey
    from match_info_2026 a
    inner join (
        select dt, luid, user_ukey
        from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
        where dt between '2026-04-18' and '2026-05-05'
            and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
    ) b on a.dt = b.dt and a.luid = b.luid
)


, video_watch_2026 as (
    select 
        a.dt,
        b.user_ukey,
        sum(a.watch_cnt) as video_watch_cnt,
        sum(a.watch_duration) / 600000 as video_watch_duration
    from gamelive.dws_huya_user_behavior_d_i a
    inner join laxin_user_info_2026 b
    on a.user_ukey = b.user_ukey
    where a.dt  between '2026-05-06' and '2026-05-12'
        and data_type in ('video_session')
        and live_content_type = '视频'
        and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        -- and game_id not in (2356) 包含体育和台球
        -- and game_name not in ('体育','台球') 包含体育和台球
        and watch_cnt > 0
        and is_black_ukey = 0 --去黑产
    group by 1,2
)

, live_watch_2026 as (
    select 
        a.dt,
        b.user_ukey,
        sum(a.watch_cnt) as live_watch_cnt,
        sum(a.watch_duration) / 600000 as live_watch_duration
    from gamelive.dws_huya_user_behavior_d_i a
    inner join laxin_user_info_2026 b
    on a.user_ukey = b.user_ukey
    where a.dt  between '2026-05-06' and '2026-05-12'
        and data_type in ('live_watch_session')
        and live_content_type = '直播'
        and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and game_id not in (2356)
        and game_name not in ('体育','台球')
        and watch_cnt > 0
        and is_black_ukey = 0 --去黑产
    group by 1,2
)



---【2025世锦赛】

,match_info_2025 as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt = '2026-05-17' 
    and day >= '2025-04-17'
    and day <= '2025-05-06'
)

, laxin_user_info_2025  as (
    select b.dt, b.user_ukey
    from match_info_2025 a
    inner join (
        select dt, luid, user_ukey
        from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
        where dt between '2025-04-17' and '2025-05-06'
            and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
    ) b on a.dt = b.dt and a.luid = b.luid
)


, video_watch_2025 as (
    select 
        a.dt,
        b.user_ukey,
        sum(a.watch_cnt) as video_watch_cnt,
        sum(a.watch_duration) / 600000 as video_watch_duration
    from gamelive.dws_huya_user_behavior_d_i a
    inner join laxin_user_info_2025 b
    on a.user_ukey = b.user_ukey
    where a.dt between '2025-05-07' and '2025-05-13'
        and data_type in ('video_session')
        and live_content_type = '视频'
        and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        -- and game_id not in (2356) 包含体育和台球
        -- and game_name not in ('体育','台球') 包含体育和台球
        and watch_cnt > 0
        and is_black_ukey = 0 --去黑产
    group by 1,2
)

, live_watch_2025 as (
    select 
        a.dt,
        b.user_ukey,
        sum(a.watch_cnt) as live_watch_cnt,
        sum(a.watch_duration) / 600000 as live_watch_duration
    from gamelive.dws_huya_user_behavior_d_i a
    inner join laxin_user_info_2025 b
    on a.user_ukey = b.user_ukey
    where a.dt between '2025-05-07' and '2025-05-13'
        and data_type in ('live_watch_session')
        and live_content_type = '直播'
        and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and game_id not in (2356)
        and game_name not in ('体育','台球')
        and watch_cnt > 0
        and is_black_ukey = 0 --去黑产
    group by 1,2
)






------- 最终计算

------- 最终计算

select
    '2026世锦赛' as label, 
    -- 基础指标
    total_laxin_cnt,
    total_watch_user_cnt,
    total_watch_user_cnt / total_laxin_cnt as total_watch_user_ratio,
    
    -- 视频观看人数及占比（基于总拉新人数）
    video_watch_user_cnt,
    video_watch_user_cnt / total_laxin_cnt as video_watch_user_ratio_total,
    
    -- 直播观看人数及占比（基于总拉新人数）
    live_watch_user_cnt,
    live_watch_user_cnt / total_laxin_cnt as live_watch_user_ratio_total,
    
    -- 视频观看次数
    video_watch_cnt,
    video_watch_cnt / nullif(video_watch_user_cnt, 0) as video_watch_cnt_per_video_user,  -- 视频用户人均观看次数
    
    -- 直播观看次数
    live_watch_cnt,
    live_watch_cnt / nullif(live_watch_user_cnt, 0) as live_watch_cnt_per_live_user,      -- 直播用户人均观看次数
    
    -- 视频观看时长（分钟）- 基于总拉新人数
    video_watch_duration,
    video_watch_duration / nullif(video_watch_user_cnt, 0) as video_watch_duration_per_video_user,   -- 视频用户人均观看时长
    
    -- 直播观看时长（分钟）- 基于总拉新人数
    live_watch_duration,
    live_watch_duration / nullif(live_watch_user_cnt, 0) as live_watch_duration_per_live_user,   -- 直播用户人均观看时长
    
    -- 总观看时长（视频+直播）
    total_watch_duration,
    total_watch_duration / nullif(total_watch_user_cnt, 0) as total_watch_duration_per_watch_user,  -- 观看用户人均总时长（基于观看用户）
    
    -- 视频时长占比
    video_watch_duration / nullif(total_watch_duration, 0) as video_duration_ratio,
    
    -- 直播时长占比  
    live_watch_duration / nullif(total_watch_duration, 0) as live_duration_ratio

from (
    select
        count(distinct a.user_ukey) as total_laxin_cnt,
        count(distinct case when b.user_ukey is not null or c.user_ukey is not null then a.user_ukey end) as total_watch_user_cnt,
        sum(b.video_watch_cnt) as video_watch_cnt,
        sum(c.live_watch_cnt) as live_watch_cnt,
        sum(b.video_watch_duration) as video_watch_duration,
        sum(c.live_watch_duration) as live_watch_duration,
        sum(b.video_watch_duration) + sum(c.live_watch_duration) as total_watch_duration,
        count(distinct case when b.user_ukey is not null then b.user_ukey end) as video_watch_user_cnt,
        count(distinct case when c.user_ukey is not null then c.user_ukey end) as live_watch_user_cnt
    from laxin_user_info_2026 a
    left join video_watch_2026 b
    on a.user_ukey = b.user_ukey
    left join live_watch_2026 c
    on a.user_ukey = c.user_ukey
)



union all


select
    '2025世锦赛' as label, 
    -- 基础指标
    total_laxin_cnt,
    total_watch_user_cnt,
    total_watch_user_cnt / total_laxin_cnt as total_watch_user_ratio,
    
    -- 视频观看人数及占比（基于总拉新人数）
    video_watch_user_cnt,
    video_watch_user_cnt / total_laxin_cnt as video_watch_user_ratio_total,
    
    -- 直播观看人数及占比（基于总拉新人数）
    live_watch_user_cnt,
    live_watch_user_cnt / total_laxin_cnt as live_watch_user_ratio_total,
    
    -- 视频观看次数
    video_watch_cnt,
    video_watch_cnt / total_laxin_cnt as video_watch_cnt_per_user_total,      -- 总人均视频观看次数
    video_watch_cnt / nullif(video_watch_user_cnt, 0) as video_watch_cnt_per_video_user,  -- 视频用户人均观看次数
    
    -- 直播观看次数
    live_watch_cnt,
    live_watch_cnt / total_laxin_cnt as live_watch_cnt_per_user_total,        -- 总人均直播观看次数
    live_watch_cnt / nullif(live_watch_user_cnt, 0) as live_watch_cnt_per_live_user,      -- 直播用户人均观看次数
    
    -- 视频观看时长（分钟）- 基于总拉新人数
    video_watch_duration,
    -- 视频观看时长（分钟）- 基于观看用户（视频或直播）
    video_watch_duration / nullif(video_watch_user_cnt, 0) as video_watch_duration_per_video_user,   -- 视频用户人均观看时长
    
    -- 直播观看时长（分钟）- 基于总拉新人数
    live_watch_duration,
    -- 直播观看时长（分钟）- 基于观看用户（视频或直播）
    live_watch_duration / nullif(live_watch_user_cnt, 0) as live_watch_duration_per_live_user,   -- 直播用户人均观看时长
    
    -- 总观看时长（视频+直播）
    total_watch_duration,
    total_watch_duration / nullif(total_watch_user_cnt, 0) as total_watch_duration_per_watch_user,  -- 观看用户人均总时长（基于观看用户）
    
    -- 视频时长占比
    video_watch_duration / nullif(total_watch_duration, 0) as video_duration_ratio,
    
    -- 直播时长占比  
    live_watch_duration / nullif(total_watch_duration, 0) as live_duration_ratio

from (
    select
        count(distinct a.user_ukey) as total_laxin_cnt,
        count(distinct case when b.user_ukey is not null or c.user_ukey is not null then a.user_ukey end) as total_watch_user_cnt,
        sum(b.video_watch_cnt) as video_watch_cnt,
        sum(c.live_watch_cnt) as live_watch_cnt,
        sum(b.video_watch_duration) as video_watch_duration,
        sum(c.live_watch_duration) as live_watch_duration,
        sum(b.video_watch_duration) + sum(c.live_watch_duration) as total_watch_duration,
        count(distinct case when b.user_ukey is not null then b.user_ukey end) as video_watch_user_cnt,
        count(distinct case when c.user_ukey is not null then c.user_ukey end) as live_watch_user_cnt
    from laxin_user_info_2025 a
    left join video_watch_2025 b
    on a.user_ukey = b.user_ukey
    left join live_watch_2025 c
    on a.user_ukey = c.user_ukey
)