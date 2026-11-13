-- Presto独立复算：按日先汇总7月UID观时，再按UID生成标签；事件和支付分别直接聚合，
-- 最后按两个互斥条件直接COUNT DISTINCT UID，不使用主查询cohort/flags或结果表。
with july_days as (
 -- 输入观看区间；输出dt+UID唯一，多设备观时在日内先汇总。
 select dt,user_yyuid uid,sum(cast(user_duration as double)) dur
 from gamelive.dwt_huya_ayyuid_session_from_server_with_user
 where dt between '2026-07-01' and '2026-07-31' and tag='gameid' and htime='session'
 and user_duration>0 and user_yyuid is not null and trim(user_yyuid) not in ('','0','-1')
 group by dt,user_yyuid
), july_users as (
 select uid,count(*) days,avg(dur)/60000.0 mins from july_days group by uid
), thresholds as (
 select approx_percentile(days,0.333333333333) d1,approx_percentile(days,0.666666666667) d2,
 approx_percentile(mins,0.333333333333) m1,approx_percentile(mins,0.666666666667) m2
 from july_users
), heavy as (
 -- 单行阈值关联倍数1；保持与用户原CASE相同的闭区间与边界优先级。
 select uid from july_users cross join thresholds
 where (case when days<=d1 then 1 when days<=d2 then 2 else 3 end)
 +(case when mins<=m1 then 1 when mins<=m2 then 2 else 3 end)>=5
), events as (
 select yyuid uid,
 min(if(eventid='pageview/liveroom',try_cast(stime as timestamp),null)) entered,
 min(if(eventid='click/verticallive/fullscreen',try_cast(stime as timestamp),null)) clicked,
 count(distinct dt) covered_uid_days
 from gamelive.dwd_huya_event
 where dt between '2026-08-31' and '2026-11-12'
 and product in ('huya_andriod','huya_ios','huya_ipad','huya_pad','hmos_kiwi')
 and eventid in ('pageview/liveroom','click/verticallive/fullscreen')
 and stime>=concat(dt,' 00:00:00') and stime<concat(cast(date_add('day',1,cast(dt as date)) as varchar),' 00:00:00')
 and yyuid is not null and trim(yyuid) not in ('','0','-1') group by yyuid
), orders as (
 select cast(uid as varchar) uid,min(try_cast(create_time as timestamp)) paid
 from gamelive.dwd_huya_pay_platform_vip_detail_d_a
 where dt='2026-11-12' and status='200' and amount>0
 and uid is not null and trim(cast(uid as varchar)) not in ('','0','-1')
 and try_cast(create_time as timestamp) is not null group by cast(uid as varchar)
), uid_data as (
 -- 1:1及1:0/1，不放大；尚未按组过滤，保持对总体独立核验。
 select h.uid,e.entered,e.clicked,o.paid,
 (e.entered<=e.clicked and e.clicked<timestamp '2026-10-14 00:00:00'
 and (o.paid is null or o.paid>e.clicked)) a_ok,
 (e.entered<timestamp '2026-10-14 00:00:00'
 and (e.clicked is null or e.clicked>date_add('day',30,e.entered))
 and (o.paid is null or o.paid>e.entered)) b_ok
 from heavy h join events e on h.uid=e.uid left join orders o on h.uid=o.uid
 where e.entered is not null
)
select count(*) entered_heavy_n,count(distinct uid) entered_heavy_uid_n,
 count(distinct if(a_ok,uid,null)) a_n,
 count(distinct if(a_ok and paid>clicked and paid<=date_add('day',7,clicked),uid,null)) a_pay7,
 count(distinct if(a_ok and paid>clicked and paid<=date_add('day',14,clicked),uid,null)) a_pay14,
 count(distinct if(a_ok and paid>clicked and paid<=date_add('day',30,clicked),uid,null)) a_pay30,
 count(distinct if(b_ok and not coalesce(a_ok,false),uid,null)) b_n,
 count(distinct if(b_ok and not coalesce(a_ok,false) and paid>entered and paid<=date_add('day',7,entered),uid,null)) b_pay7,
 count(distinct if(b_ok and not coalesce(a_ok,false) and paid>entered and paid<=date_add('day',14,entered),uid,null)) b_pay14,
 count(distinct if(b_ok and not coalesce(a_ok,false) and paid>entered and paid<=date_add('day',30,entered),uid,null)) b_pay30,
 count_if(a_ok and b_ok) before_priority_overlap_n,
 count_if(a_ok and date_add('day',30,clicked)>=timestamp '2026-11-13 00:00:00') a_incomplete_n,
 count_if(b_ok and not coalesce(a_ok,false) and date_add('day',30,entered)>=timestamp '2026-11-13 00:00:00') b_incomplete_n
from uid_data
