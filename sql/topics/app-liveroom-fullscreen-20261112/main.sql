-- APP范围已由用户确认；Presto，2026-11-12事件分区与服务器自然日。
-- base：事件上报粒度，保留UID、端、事件、时间；不关联不放大。
with base as (
 select product,yyuid,eventid,stime,thour
 from gamelive.dwd_huya_event
 where dt='2026-11-12' and ety='custom_event'
 and product in ('huya_andriod','huya_ios','huya_ipad','huya_pad','hmos_kiwi')
 and eventid in ('pageview/liveroom','click/verticallive/fullscreen')
), valid as (
 -- 输入事件行；输出有效UID事件行。排除NULL、空、0、-1；不以UID非空额外保证登录状态。
 select * from base where yyuid is not null and trim(yyuid) not in ('','0','-1')
), user_flags as (
 -- 输入事件行，输出UID唯一行；两行为各自去重。以服务器同日事件计入正式UV。
 select yyuid,
 max(case when eventid='pageview/liveroom' and stime>='2026-11-12 00:00:00' and stime<'2026-11-13 00:00:00' then 1 else 0 end) entered,
 max(case when eventid='click/verticallive/fullscreen' and stime>='2026-11-12 00:00:00' and stime<'2026-11-13 00:00:00' then 1 else 0 end) clicked
 from valid group by yyuid
)
select sum(entered) entered_uid_uv,sum(clicked) fullscreen_click_uid_uv,
 sum(case when entered=1 and clicked=1 then 1 else 0 end) both_uid_uv,
 sum(case when entered=0 and clicked=1 then 1 else 0 end) click_without_entry_uid_uv,
 count(*) union_uid_uv
from user_flags
