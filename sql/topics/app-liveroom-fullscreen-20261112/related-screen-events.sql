-- 诊断：全ety、五APP，搜索同类事件ID，不直接将同类事件混入截图口径。
select ety,eventid,eventid_desc,product,count(*) event_rows,
 count(distinct case when yyuid is not null and trim(yyuid) not in ('','0','-1') then yyuid end) uid_uv
from gamelive.dwd_huya_event
where dt='2026-11-12'
 and product in ('huya_andriod','huya_ios','huya_ipad','huya_pad','hmos_kiwi')
 and (lower(eventid) like '%fullscreen%' or lower(eventid) like '%full_screen%'
 or lower(eventid) like '%landscape%' or lower(eventid) like '%rotate%'
 or (lower(eventid) like '%horizontal%' and (lower(eventid) like '%click%' or lower(eventid) like '%switch%'))
 or eventid_desc like '%横屏%' or eventid_desc like '%全屏%')
group by 1,2,3,4 order by event_rows desc
