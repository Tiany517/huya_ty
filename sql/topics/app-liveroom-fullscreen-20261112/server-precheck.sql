-- with_user会话口径预检：限定一套分区避免gameid/liveid/hour/session重复相加。
select user_product,count(*) source_rows,
 count(distinct case when user_yyuid is not null and trim(user_yyuid) not in ('','0','-1') then user_yyuid end) record_uid_uv,
 count(distinct case when user_yyuid is not null and trim(user_yyuid) not in ('','0','-1') and user_start_time>='2026-11-12 00:00:00' and user_start_time<'2026-11-13 00:00:00' then user_yyuid end) start_day_uid_uv,
 count(distinct case when user_yyuid is not null and trim(user_yyuid) not in ('','0','-1') and user_duration>0 then user_yyuid end) positive_duration_uid_uv,
 min(user_start_time) min_start,max(user_start_time) max_start,
 min(user_end_time) min_end,max(user_end_time) max_end,
 count_if(user_start_time is null or user_end_time is null) null_time_rows,
 count_if(user_end_time<user_start_time) reversed_rows
from gamelive.dwt_huya_ayyuid_session_from_server_with_user
where dt='2026-11-12' and tag='gameid' and htime='session'
 and user_product in ('huya_andriod','huya_ios','huya_ipad','huya_pad','hmos_kiwi')
group by user_product
