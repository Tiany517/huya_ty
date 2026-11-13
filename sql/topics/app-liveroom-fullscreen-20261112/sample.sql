-- 用户级小样检查：12点安卓，两事件各自聚合后同一UID只计一次；UID仅返回哈希，原ID不导出。
select to_hex(md5(to_utf8(yyuid))) uid_hash,
 count_if(eventid='pageview/liveroom') entry_rows,
 count_if(eventid='click/verticallive/fullscreen') click_rows,
 max(case when eventid='pageview/liveroom' then 1 else 0 end) entry_flag,
 max(case when eventid='click/verticallive/fullscreen' then 1 else 0 end) click_flag,
 min(stime) min_stime,max(stime) max_stime
from gamelive.dwd_huya_event
where dt='2026-11-12' and ety='custom_event' and product='huya_andriod' and thour='12'
and eventid in ('pageview/liveroom','click/verticallive/fullscreen')
and yyuid is not null and trim(yyuid) not in ('','0','-1')
and stime>='2026-11-12 00:00:00' and stime<'2026-11-13 00:00:00'
group by yyuid
having count_if(eventid='pageview/liveroom')>1 and count_if(eventid='click/verticallive/fullscreen')>1
limit 5
