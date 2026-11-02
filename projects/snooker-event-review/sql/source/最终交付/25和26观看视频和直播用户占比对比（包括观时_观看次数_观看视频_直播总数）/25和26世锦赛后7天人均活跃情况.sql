with match_info_2026 as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt = '2026-05-19' 
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

,match_info_2025 as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt = '2026-05-19' 
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


select
    '2026世锦赛后7天' as period,
    sum(active_day_cnt) /count(distinct b.user_ukey)  as average_active_day_cnt,
    avg(b.active_day_cnt) as avg_active_day_cnt,
    approx_percentile(b.active_day_cnt, 0.5) as median_active_day_cnt
from laxin_user_info_2026 a
inner join (
    select 
        user_ukey,
        count(distinct dt) as active_day_cnt
    from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
    where dt between '2026-05-06' and '2026-05-12'
    and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
    and is_black_ukey = 0 
    group by 1
) b on a.user_ukey = b.user_ukey
group by 1

union all

select
    '2025世锦赛后7天' as period,
    sum(active_day_cnt) /count(distinct b.user_ukey)  as average_active_day_cnt,
    avg(b.active_day_cnt) as avg_active_day_cnt,
    approx_percentile(b.active_day_cnt, 0.5) as median_active_day_cnt
from laxin_user_info_2025 a
inner join (
    select 
        user_ukey,
        count(distinct dt) as active_day_cnt
    from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
    where dt between '2025-05-07' and '2025-05-13'
    and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
    and is_black_ukey = 0 
    group by 1
) b on a.user_ukey = b.user_ukey
group by 1