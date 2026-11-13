-- 单日探索：全部iOS支付订单，避免先筛安卓from_id=5而漏掉iOS入口。
-- order_id+UID为订单上下文；订单×前3分钟该UID事件一对多，只诊断，不把事件行当用户数。
with orders_day as (
 select order_id,uid,from_id,from_name,try_cast(create_time as timestamp) order_ts
 from gamelive.dwd_huya_pay_platform_vip_detail_d_a
 where dt='2026-11-12' and status='200' and try_cast(amount as double)>0
 and pay_terminal='ios' and substr(create_time,1,10)='2026-10-24'
 and uid is not null and lower(cast(uid as varchar)) not in ('','0','other')
), events_day as (
 -- 保留iOS/iPad事件；支付端不能替代事件产品字段。
 select yyuid uid,try_cast(stime as timestamp) event_ts,eventid,product,session_id,
 curpage,curlocation,prepage,prelocation,ayyuid,
 element_at(ext,'orientation') orientation,
 json_extract_scalar(element_at(ext,'prop'),'$.source') event_source,
 json_extract_scalar(element_at(ext,'prop'),'$.ad_scene') ad_scene,
 json_extract_scalar(element_at(ext,'prop'),'$.vip_status') vip_status,
 json_extract_scalar(element_at(ext,'prop'),'$.slot_code') slot_code
 from gamelive.dwd_huya_event
 where dt='2026-10-24' and product in ('huya_ios','huya_ipad')
 and stime>='2026-10-24 00:00:00' and stime<'2026-10-25 00:00:00'
 and yyuid in (select uid from orders_day)
 and (eventid in ('state/ad_request','state/ad_return','state/call_ad_display','state/call_ad_sdkdisplay',
 'show/universal_ad','click/universal_ad','click/verticallive/fullscreen','show/activate_vip_rentra')
 or lower(eventid) like '%vip%' or lower(eventid) like '%member%' or lower(eventid) like '%horizontallive/ad%')
), matched as (
 select o.order_id,o.from_id,o.from_name,o.order_ts,e.*,
 row_number() over(partition by o.order_id,e.eventid order by e.event_ts desc) rn
 from orders_day o join events_day e on o.uid=e.uid
 where e.event_ts between date_add('minute',-3,o.order_ts) and o.order_ts
)
select order_id,from_id,from_name,order_ts,event_ts,eventid,product,session_id,curpage,curlocation,
 prepage,prelocation,ayyuid,orientation,event_source,ad_scene,vip_status,slot_code
from matched where rn<=3 order by order_ts,event_ts
