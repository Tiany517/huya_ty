with match_info as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a --体育运动直播表
  where dt = '2026-05-17'
    and day >= '2025-07-28'
    and day <= '2025-08-03' -- 2025年上海大师赛期间
)

,laxin_user_info as(--- 25年世锦赛 拉新的人数
  select b.ukey as user_ukey ---a.dt ,a.luid , 
  from match_info a 
  inner join(---拉新用户
    select dt ,luid ,user_ukey as ukey 
    from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
    where dt between '2025-07-28' and '2025-08-03' -- 2025年上海大师赛拉新时间
      and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')  
  )b 
  on a.dt=b.dt and a.luid=b.luid 
  group by b.ukey 
)



   
, dashang_agg as (
    select 
      substr(a.dt,1,7) as yearmonth,
      a.ukey as user_ukey,
      sum(a.consume_amt) as total_consume_amt
    from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
    where a.dt between '2025-08-04' and '2026-02-10' --英锦赛结束180天后
    group by 1,2
)



select 
    '体育整体' as match_name,
    b.yearmonth,
    (select count(distinct user_ukey) from laxin_user_info) as total_laxin_users,  -- 拉新总人数
    round(sum(b.total_consume_amt), 2) as total_dashang_amt,      -- 180天后总打赏金额
    count(distinct case when b.total_consume_amt > 0 then a.user_ukey end) as dashang_user_cnt,  -- 180天后打赏人数
    count(distinct case when b.total_consume_amt > 0 then a.user_ukey end) / (select count(distinct user_ukey) from laxin_user_info) as retention_rate,  -- 180天后打赏率
    sum(b.total_consume_amt) / count(distinct case when b.total_consume_amt > 0 then a.user_ukey end) as arppu
from laxin_user_info a
left join dashang_agg b
on a.user_ukey = b.user_ukey
group by 2
order by 2 asc