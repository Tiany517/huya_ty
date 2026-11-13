-- 三来源对账：源各自先分区/APP/有效UID过滤，再各自聚合到UID。
-- UNION ALL是来源堆叠：每个来源每UID最多1行，输入总行数=三来源UV之和，非按原始会话关联。
-- 最后按UID聚合唯一，避免同用户多主播、多房间、多端重复计数。不设观看时长门槛。
with event_users as (
 select yyuid uid,1 e,0 b,0 s,0 positive_b,0 start_s
 from gamelive.dwd_huya_event
 where dt='2026-11-12' and eventid='pageview/liveroom'
 and product in ('huya_andriod','huya_ios','huya_ipad','huya_pad','hmos_kiwi')
 and stime>='2026-11-12 00:00:00' and stime<'2026-11-13 00:00:00'
 and yyuid is not null and trim(yyuid) not in ('','0','-1') group by yyuid
), behavior_users as (
 select user_uid uid,0 e,1 b,0 s,max(case when watch_duration>0 then 1 else 0 end) positive_b,0 start_s
 from gamelive.dws_huya_user_behavior_d_i
 where dt='2026-11-12' and data_type='live_watch_session'
 and product in ('huya_andriod','huya_ios','huya_ipad','huya_pad','hmos_kiwi')
 and watch_cnt>0 and user_uid is not null and trim(user_uid) not in ('','0','-1') group by user_uid
), server_users as (
 select user_yyuid uid,0 e,0 b,1 s,0 positive_b,
 max(case when user_start_time>='2026-11-12 00:00:00' and user_start_time<'2026-11-13 00:00:00' then 1 else 0 end) start_s
 from gamelive.dwt_huya_ayyuid_session_from_server_with_user
 where dt='2026-11-12' and tag='gameid' and htime='session'
 and user_product in ('huya_andriod','huya_ios','huya_ipad','huya_pad','hmos_kiwi')
 and user_yyuid is not null and trim(user_yyuid) not in ('','0','-1') group by user_yyuid
), stacked as (
 select * from event_users union all select * from behavior_users union all select * from server_users
), uid_flags as (
 -- 输出UID唯一；来源标志取max，不能对来源堆叠直接按行当总用户。
 select uid,max(e) e,max(b) b,max(s) s,max(positive_b) positive_b,max(start_s) start_s
 from stacked group by uid
)
select sum(e) entry_uv,sum(b) behavior_watch_uv,sum(s) server_watch_uv,
 sum(positive_b) positive_duration_behavior_uv,sum(start_s) start_today_server_uv,
 count_if(e=1 and b=1) entry_behavior_both,
 count_if(e=1 and b=0) entry_only_vs_behavior,count_if(e=0 and b=1) behavior_only_vs_entry,
 count_if(e=1 and s=1) entry_server_both,
 count_if(e=1 and s=0) entry_only_vs_server,count_if(e=0 and s=1) server_only_vs_entry,
 count_if(b=1 and s=1) behavior_server_both,
 count(*) union_three_uv,
 (sum(e)+sum(b)+sum(s)) stacked_input_rows,
 abs(sum(e)-sum(b))*1.0/nullif(sum(b),0) diff_vs_behavior,
 abs(sum(e)-sum(s))*1.0/nullif(sum(s),0) diff_vs_server
from uid_flags
