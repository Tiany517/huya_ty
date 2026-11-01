select mth,sum(online_min) online_min,count(distinct ukey) uv 
from 
(select substr(dt,1,7) mth,dt,ukey,product,sum(online_duration)/cast(60000 as double) online_min 
from 
gamelive.dwt_huya_session_level 
where dt>='2025-10-01' 
--and dt<='2020-05-31'
and tag='product'
and product in ('huya_pc','huya_pcexe','huya_flashexternal','huya_flash','huyawap','huya_web','huya_andriod','huya_android_tv','huya_ipad','huya_pad','huya_ios','huya_applet','smtv_androidtv','huyapcmini_pc','huya_applet_qq','huya_applet_baidu','huya_toutiao_android','hmos_kiwi')--全端
group by substr(dt,1,7) ,dt,ukey,product
)a
group by mth