select mth,avg(avg_user_time) avg_user_time,sum(online_min) online_min
from 
(select mth,dt,sum(online_min) online_min,count(distinct ukey) uv ,sum(online_min)/cast(count(distinct ukey) as double) avg_user_time 
from 
(select substr(dt,1,7) mth,dt,ukey,product,sum(online_duration)/cast(60000 as double) online_min 
from 
gamelive.dwt_huya_session_level 
where dt>='2026-05-01' 
--and dt<='2020-05-31'
and tag='product'
and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
group by substr(dt,1,7) ,dt,ukey,product
)a
group by mth,dt 
)a 
group by mth