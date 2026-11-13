-- 独立复算：各源直接COUNT DISTINCT，并单独披露分区日、当日进入及与当日重叠。
-- UNION ALL为3条最终汇总行拼接；无明细展开、无join。
select 'event' source,count(*) rows,
 count(distinct yyuid) partition_uv,
 count(distinct case when stime>='2026-11-12 00:00:00' and stime<'2026-11-13 00:00:00' then yyuid end) same_day_uv,
 count(distinct case when stime>='2026-11-12 00:00:00' and stime<'2026-11-13 00:00:00' then yyuid end) overlap_day_uv,
 count(distinct case when stime>='2026-11-12 00:00:00' and stime<'2026-11-13 00:00:00' then yyuid end) positive_overlap_day_uv,
 count_if(stime is null) null_time_rows
from gamelive.dwd_huya_event
where dt='2026-11-12' and eventid='pageview/liveroom'
and product in ('huya_andriod','huya_ios','huya_ipad','huya_pad','hmos_kiwi')
and yyuid is not null and trim(yyuid) not in ('','0','-1')
union all
select 'behavior',count(*),count(distinct user_uid),
 count(distinct case when ext['user_start_time']>='2026-11-12 00:00:00' and ext['user_start_time']<'2026-11-13 00:00:00' then user_uid end),
 count(distinct case when ext['user_start_time']<'2026-11-13 00:00:00' and ext['user_end_time']>='2026-11-12 00:00:00' then user_uid end),
 count(distinct case when ext['user_start_time']<'2026-11-13 00:00:00' and ext['user_end_time']>'2026-11-12 00:00:00' and watch_duration>0 then user_uid end),
 count_if(ext['user_start_time'] is null or ext['user_end_time'] is null)
from gamelive.dws_huya_user_behavior_d_i
where dt='2026-11-12' and data_type='live_watch_session' and watch_cnt>0
and product in ('huya_andriod','huya_ios','huya_ipad','huya_pad','hmos_kiwi')
and user_uid is not null and trim(user_uid) not in ('','0','-1')
union all
select 'server',count(*),count(distinct user_yyuid),
 count(distinct case when user_start_time>='2026-11-12 00:00:00' and user_start_time<'2026-11-13 00:00:00' then user_yyuid end),
 count(distinct case when user_start_time<'2026-11-13 00:00:00' and user_end_time>='2026-11-12 00:00:00' then user_yyuid end),
 count(distinct case when user_start_time<'2026-11-13 00:00:00' and user_end_time>'2026-11-12 00:00:00' and user_duration>0 then user_yyuid end),
 count_if(user_start_time is null or user_end_time is null)
from gamelive.dwt_huya_ayyuid_session_from_server_with_user
where dt='2026-11-12' and tag='gameid' and htime='session'
and user_product in ('huya_andriod','huya_ios','huya_ipad','huya_pad','hmos_kiwi')
and user_yyuid is not null and trim(user_yyuid) not in ('','0','-1')
