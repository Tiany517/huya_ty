select product,count(*) source_rows,
 count(distinct case when user_uid is not null and trim(user_uid) not in ('','0','-1') then user_uid end) record_uid_uv,
 count(distinct case when user_uid is not null and trim(user_uid) not in ('','0','-1') and watch_cnt>0 then user_uid end) watchcnt_uid_uv,
 count(distinct case when user_uid is not null and trim(user_uid) not in ('','0','-1') and watch_duration>0 then user_uid end) duration_uid_uv,
 min(watch_duration) min_duration,max(watch_duration) max_duration,
 count_if(watch_duration is null) null_duration_rows,count_if(watch_cnt is null) null_watchcnt_rows
from gamelive.dws_huya_user_behavior_d_i
where dt='2026-11-12' and data_type='live_watch_session'
 and product in ('huya_andriod','huya_ios','huya_ipad','huya_pad','hmos_kiwi')
group by product
