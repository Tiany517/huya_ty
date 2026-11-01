select mth,sum(watch_min) watch_min,sum(app_watch_min) app_watch_min
from 
(select
substr(dt,1,7) mth,
dt,
sum(case when product in ('huya_pc','huya_pcexe','huya_flashexternal','huya_flash','huyawap','huya_web','huya_andriod','huya_android_tv','huya_ipad','huya_pad','huya_ios','huya_applet','smtv_androidtv','huyapcmini_pc','huya_applet_qq','huya_applet_baidu','huya_toutiao_android','hmos_kiwi') then watch_duration else 0 end)/cast(60000 as double) watch_min ,
sum(case when product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi') then watch_duration else 0 end)/cast(60000 as double) app_watch_min 
from
  gamelive.dws_huya_user_behavior_d_i
where
  dt  >= '2026-05-01' 
  --and dt <= '2025-04-30'
  and data_type = 'live_watch_session'
  --and watch_duration >= 300000 --限制有效 
  and is_black_ukey=0 --去除黑产 
--  and creator_uid in (1677942333)
group by
substr(dt,1,7),
dt
)a 
group by mth