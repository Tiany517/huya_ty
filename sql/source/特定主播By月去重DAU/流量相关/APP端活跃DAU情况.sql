select 
    dt
    ,count(distinct user_ukey )as dau  
from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
where dt >= '2026-01-01' and dt <= '2026-05-31' --修改这里即可
and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
and is_black_ukey = 0 
group by dt
