-- 诊断：不限制ety，核对两个已确认事件在全部事件类型下的分布。
select ety,eventid,product,count(*) event_rows,
 count(distinct case when yyuid is not null and trim(yyuid) not in ('','0','-1') then yyuid end) uid_uv,
 min(stime) min_stime,max(stime) max_stime
from gamelive.dwd_huya_event
where dt='2026-11-12'
 and product in ('huya_andriod','huya_ios','huya_ipad','huya_pad','hmos_kiwi')
 and eventid in ('pageview/liveroom','click/verticallive/fullscreen')
group by 1,2,3 order by 2,1,3
