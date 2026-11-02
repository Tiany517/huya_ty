with match_info_2026 as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt = '2026-05-13' 
    and day >= '2026-04-18'
    and day <= '2026-05-04' -- 26世锦赛期间
)

,  match_info_2025 as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt = '2026-05-13' 
    and day >= '2025-04-18'
    and day <= '2025-05-04' -- 26世锦赛期间
)

, laxin_user_info_2026 as (
    select distinct b.user_ukey as user_ukey
    from match_info_2026 a
    inner join (
        select dt, luid, user_ukey
        from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
        where dt between '2026-04-18' and '2026-05-04'
            and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
    ) b on a.dt = b.dt and a.luid = b.luid
)

, laxin_user_info_2025 as (
    select distinct b.user_ukey as user_ukey
    from match_info_2025 a
    inner join (
        select dt, luid, user_ukey
        from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
        where dt between '2025-04-18' and '2025-05-04'
            and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
    ) b on a.dt = b.dt and a.luid = b.luid
)

,base_info as (
    select 
        '2026斯诺克拉新用户' as user_group,
        '2026.04.18 - 2026.05.04' as time_label,
        game_name, 
        count(distinct b.user_ukey) as user_cnt,
        sum(watch_cnt) as total_watch_cnt,
        sum(watch_duration)  / 60000 as total_watch_duration -- 这里的单位是毫秒
    from gamelive.dws_huya_user_behavior_d_i a
    inner join laxin_user_info_2026 b
    on a.user_ukey = b.user_ukey
    where dt between '2026-04-18' and '2026-05-04'
        and data_type in ('video_session')
        and live_content_type = '视频'
        and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and game_id not in (2356)
        and game_name not in ('体育','台球')
        and watch_cnt > 0
        and is_black_ukey = 0 --去黑产
    group by 1,2,3

    union all

    select 
        '2025斯诺克拉新用户' as user_group,
        '2025.04.18 - 2025.05.04' as time_label,
        game_name, 
        count(distinct b.user_ukey) as user_cnt,
        sum(watch_cnt) as total_watch_cnt,
        sum(watch_duration) / 60000 as total_watch_duration -- 这里的单位是毫秒
    from gamelive.dws_huya_user_behavior_d_i a
    inner join laxin_user_info_2025 b
    on a.user_ukey = b.user_ukey
    where dt between '2025-04-18' and '2025-05-04'
        and data_type in ('video_session')
        and live_content_type = '视频'
        and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and game_id not in (2356)
        and game_name not in ('体育','台球')
        and watch_cnt > 0
        and is_black_ukey = 0 --去黑产
    group by 1,2,3
)



select
    user_group,
    time_label,
    game_name,
    user_cnt,
    total_watch_cnt,
    total_watch_duration,
    user_cnt / sum(user_cnt) over (partition by time_label)  as user_cnt_pct,
    total_watch_cnt / sum(total_watch_cnt) over (partition by time_label)  as watch_cnt_pct,
    total_watch_duration  / sum(total_watch_duration) over (partition by time_label)  as watch_duration_pct

from base_info
order by 1 desc,9 desc