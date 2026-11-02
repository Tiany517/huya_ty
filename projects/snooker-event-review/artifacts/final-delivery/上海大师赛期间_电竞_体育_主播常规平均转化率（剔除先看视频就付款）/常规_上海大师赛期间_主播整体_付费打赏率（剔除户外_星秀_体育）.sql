with match_info as (
  select uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a -- 体育赛事主播
  where dt = '2026-05-17' 
    and day >= '2025-07-28'
    and day <= '2025-08-03' -- 2025年上海大师赛期间
  group by uid
)

,copyright_match_info as (
    select a.uid as luid
    from gamelive.dwd_huya_dim_game_copyright_info_d_a a --赛事版权表 -- 版权赛事主播
    where a.dt='2026-05-17'
    and substr(date,1,10) between '2025-07-28' and '2025-08-03'
    and a.live_type like '%直播%' --只计算直播
    and a.room_type = '独立直播间' --官方直播间 
    group by a.uid
)

,user_info as (
  select user_ukey 
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a 
  left join match_info b on a.luid = b.luid
  left join copyright_match_info c on a.luid = c.luid
  where dt between '2025-07-28' and '2025-08-03' --英锦赛期间拉新的用户
  and user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
  and game_id not in (1663, 2165, 2356)
  and b.luid is null 
  and c.luid is null
  group by user_ukey
)


select count(distinct a.user_ukey) as dau, count(distinct case when total_consume_amt > 0 then a.user_ukey else null end) as lc_dau, count(distinct case when total_consume_amt > 0 then a.user_ukey else null end)/count(distinct a.user_ukey)
from user_info a 
left join (
  select 
      a.ukey as user_ukey,
      sum(a.consume_amt) as total_consume_amt
  from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
  where a.dt between '2025-08-04' and '2026-05-17' --英锦赛结束180天后
  group by 1
) b on a.user_ukey = b.user_ukey