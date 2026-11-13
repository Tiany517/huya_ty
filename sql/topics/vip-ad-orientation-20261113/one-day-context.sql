-- 可行性诊断，不是转化率分析；不应用7月重度标签、不计算分母，不将未发现点击判为竖屏。
-- 测试日2026-10-24，11月12日快照中安卓from_id=5成功正金额订单22条/22UID。
-- 仅用订单创建时间代理触发时刻，不代表支付完成时间。只读；输出order_id+UID用户订单上下文。
with orders_day as (
 -- 输入订单行，输出当日订单；唯一键预期order_id，先保留原始记录诊断重复。
 select order_id,uid,pid,from_id,from_name,pay_terminal,try_cast(create_time as timestamp) order_ts
 from gamelive.dwd_huya_pay_platform_vip_detail_d_a
 where dt='2026-11-12' and status='200' and try_cast(amount as double)>0
 and from_id='5' and pay_terminal='adr'
 and substr(create_time,1,10)='2026-10-24'
 and uid is not null and lower(cast(uid as varchar)) not in ('','0','other')
), events_day as (
 -- 输入用户事件；先限定日期和五APP，半关联仅保留目标UID，不按主播/房间串人。
 select yyuid uid,try_cast(stime as timestamp) event_ts,eventid,eventid_desc,product
 from gamelive.dwd_huya_event
 where dt='2026-10-24'
 and product in ('huya_andriod','huya_ios','huya_ipad','huya_pad','hmos_kiwi')
 and stime>='2026-10-24 00:00:00' and stime<'2026-10-25 00:00:00'
 and yyuid in (select uid from orders_day)
), before_order as (
 -- 输出订单×该UID同日创建前事件；按UID+order_id关联，预期一对多。
 select o.order_id,e.uid,e.event_ts,e.eventid,e.eventid_desc,e.product
 from orders_day o join events_day e on o.uid=e.uid
 where e.event_ts<=o.order_ts
), event_rank as (
 select *,row_number() over(partition by order_id,uid order by event_ts desc,eventid,product) rn
 from before_order
), history as (
 -- 聚合回order_id+UID唯一；没有点击只能说未观察到，不能证明竖屏。
 select order_id,uid,count(*) before_event_n,
 max(case when eventid='click/verticallive/fullscreen' then event_ts end) last_fullscreen_click,
 max(case when eventid='pageview/liveroom' then event_ts end) last_room_entry,
 count_if(eventid='click/verticallive/fullscreen') fullscreen_click_n,
 count_if(eventid='pageview/liveroom') room_entry_n,
 array_join(array_distinct(array_agg(case when lower(eventid) like '%fullscreen%'
 or lower(eventid) like '%landscape%' or lower(eventid) like '%rotate%'
 or eventid_desc like '%横屏%' or eventid_desc like '%竖屏%' or eventid_desc like '%全屏%'
 then concat(eventid,'|',coalesce(eventid_desc,'')) end)), '; ') screen_event_ids
 from before_order group by order_id,uid
), recent as (
 select order_id,uid,array_join(array_agg(concat(cast(event_ts as varchar),'|',eventid,'|',coalesce(eventid_desc,''),'|',product) order by rn),'; ') recent_30_events
 from event_rank where rn<=30 group by order_id,uid
)
select o.*,coalesce(h.before_event_n,0) before_event_n,
 h.last_fullscreen_click,h.last_room_entry,coalesce(h.fullscreen_click_n,0) fullscreen_click_n,
 coalesce(h.room_entry_n,0) room_entry_n,
 date_diff('second',h.last_fullscreen_click,o.order_ts) click_to_order_seconds,
 h.screen_event_ids,r.recent_30_events
from orders_day o left join history h on o.order_id=h.order_id and o.uid=h.uid
left join recent r on o.order_id=r.order_id and o.uid=r.uid
order by o.order_ts,o.order_id
