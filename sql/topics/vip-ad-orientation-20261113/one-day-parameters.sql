-- 单日探索：同一批22笔订单，创建前3分钟广告/会员/横屏事件原参数；用户明细仅本地诊断。
with orders_day as (
 select order_id,uid,try_cast(create_time as timestamp) order_ts
 from gamelive.dwd_huya_pay_platform_vip_detail_d_a
 where dt='2026-11-12' and status='200' and try_cast(amount as double)>0
 and from_id='5' and pay_terminal='adr' and substr(create_time,1,10)='2026-10-24'
), events_day as (
 select yyuid uid,try_cast(stime as timestamp) event_ts,eventid,product,session_id,
 curpage,curlocation,prepage,prelocation,ayyuid,ext
 from gamelive.dwd_huya_event
 where dt='2026-10-24' and product in ('huya_andriod','huya_ios','huya_ipad','huya_pad','hmos_kiwi')
 and stime>='2026-10-24 00:00:00' and stime<'2026-10-25 00:00:00'
 and yyuid in (select uid from orders_day)
 and (eventid in ('state/ad_request','state/ad_return','click/verticallive/fullscreen','show/activate_vip_rentra')
 or lower(eventid) like '%vip%' or lower(eventid) like '%horizontallive/ad%')
), matched as (
 select o.order_id,o.uid,o.order_ts,e.*,row_number() over(partition by o.order_id,e.eventid order by e.event_ts desc) rn
 from orders_day o join events_day e on o.uid=e.uid
 where e.event_ts between date_add('minute',-3,o.order_ts) and o.order_ts
)
select order_id,order_ts,event_ts,eventid,product,session_id,curpage,curlocation,prepage,prelocation,ayyuid,
 json_format(cast(ext as json)) event_parameters
from matched where rn<=3 order by order_ts,event_ts