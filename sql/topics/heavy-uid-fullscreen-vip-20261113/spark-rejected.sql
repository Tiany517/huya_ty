-- Spark（Presto单节点8GB内存超限后回退）。描述性比较：7月全端观看UID分层；项目期五APP进房/横屏行为。
-- 优化版：重度UID关联前置到事件聚合前，减少非目标UID聚合；不变更样本和窗口。
-- 源过滤优先；不写目标表、不覆盖原始数据。全期仅扫描两类eventid，不限制ety。
with july_uid as (
 -- 输入：用户观看区间行；输出UID唯一。正观时，日数去重、多设备观时相加。
 select user_yyuid uid,count(distinct dt) watch_day_cnt,
 sum(cast(user_duration as double))/60000.0/count(distinct dt) avg_watch_min
 from gamelive.dwt_huya_ayyuid_session_from_server_with_user
 where dt between '2026-07-01' and '2026-07-31' and tag='gameid' and htime='session'
 and user_duration>0 and user_yyuid is not null and trim(user_yyuid) not in ('','0','-1')
 group by user_yyuid
), july_threshold as (
 -- 输入UID唯一；输出1行阈值。与用户表cross join预期倍数1。
 select percentile_approx(watch_day_cnt,0.333333333333) day_p33,
 percentile_approx(watch_day_cnt,0.666666666667) day_p67,
 percentile_approx(avg_watch_min,0.333333333333) min_p33,
 percentile_approx(avg_watch_min,0.666666666667) min_p67,count(*) july_uid_n
 from july_uid
), heavy_uid as (
 -- 输出重度UID唯一；两个1—3分之和>=5；不沿用ukey阈值。
 select j.*,t.* from july_uid j cross join july_threshold t
 where (case when j.watch_day_cnt<=t.day_p33 then 1 when j.watch_day_cnt<=t.day_p67 then 2 else 3 end)
 +(case when j.avg_watch_min<=t.min_p33 then 1 when j.avg_watch_min<=t.min_p67 then 2 else 3 end)>=5
), event_uid as (
 -- 输入项目期事件行；输出UID唯一的首次进房/首次横屏；不按房间关联。
 select yyuid uid,
 max(h.watch_day_cnt) watch_day_cnt,max(h.avg_watch_min) avg_watch_min,
 max(h.day_p33) day_p33,max(h.day_p67) day_p67,max(h.min_p33) min_p33,max(h.min_p67) min_p67,max(h.july_uid_n) july_uid_n,
 min(case when eventid='pageview/liveroom' then cast(stime as timestamp) end) first_entry,
 min(case when eventid='click/verticallive/fullscreen' then cast(stime as timestamp) end) first_click,
 count(*) source_event_rows,count(distinct dt) source_days
 from gamelive.dwd_huya_event e join heavy_uid h on e.yyuid=h.uid
 where dt between '2026-08-31' and '2026-11-12'
 and product in ('huya_andriod','huya_ios','huya_ipad','huya_pad','hmos_kiwi')
 and eventid in ('pageview/liveroom','click/verticallive/fullscreen')
 and stime>=concat(dt,' 00:00:00')
 and stime<concat(cast(date_add(cast(dt as date),1) as string),' 00:00:00')
 and yyuid is not null and trim(yyuid) not in ('','0','-1')
 group by yyuid
), vip_uid as (
 -- 快照含项目上线前订单；不截掉历史，避免把此前已购买者当新转化。
 -- create_time沿用原VIP SQL，为创建时间，并非独立验证的支付完成时间。
 select cast(uid as string) uid,min(cast(create_time as timestamp)) first_paid
 from gamelive.dwd_huya_pay_platform_vip_detail_d_a
 where dt='2026-11-12' and status='200' and amount>0
 and uid is not null and trim(cast(uid as string)) not in ('','0','-1')
 and cast(create_time as timestamp) is not null
 group by cast(uid as string)
), candidates as (
 -- 三侧UID唯一；heavy N:1 event、N:0/1 vip，关联不放大。
 select e.*,v.first_paid,
 case when e.first_click is not null and e.first_entry<=e.first_click
 and e.first_click<timestamp '2026-10-14 00:00:00'
 and (v.first_paid is null or v.first_paid>e.first_click) then 'A'
 when e.first_entry<timestamp '2026-10-14 00:00:00'
 and (e.first_click is null or e.first_click>(e.first_entry + INTERVAL 30 DAYS))
 and (v.first_paid is null or v.first_paid>e.first_entry) then 'B' end grp
 from event_uid e
 left join vip_uid v on e.uid=v.uid
 where e.first_entry is not null
), cohort as (
 -- UID唯一、A优先归组，确保互斥；每个UID始终一个起点，三窗口同分母。
 select *,case when grp='A' then first_click else first_entry end index_ts
 from candidates where grp is not null
), flags as (
 select *,case when first_paid>index_ts and first_paid<=(index_ts + INTERVAL 7 DAYS) then 1 else 0 end pay7,
 case when first_paid>index_ts and first_paid<=(index_ts + INTERVAL 14 DAYS) then 1 else 0 end pay14,
 case when first_paid>index_ts and first_paid<=(index_ts + INTERVAL 30 DAYS) then 1 else 0 end pay30
 from cohort where (index_ts + INTERVAL 30 DAYS)<timestamp '2026-11-13 00:00:00'
)
select grp,cast(index_ts as date) index_dt,count(*) cohort_n,count(distinct uid) distinct_uid_n,
 sum(pay7) paid7_n,sum(pay14) paid14_n,sum(pay30) paid30_n,
 sum(case when pay7>pay14 or pay14>pay30 then 1 else 0 end) nonmonotonic_n,
 sum(case when first_paid<=index_ts then 1 else 0 end) preexisting_paid_n,
 sum(case when (index_ts + INTERVAL 30 DAYS)>=timestamp '2026-11-13 00:00:00' then 1 else 0 end) incomplete_n,
 min(index_ts) min_index,max(index_ts) max_index,
 avg(watch_day_cnt) mean_july_watchdays,avg(avg_watch_min) mean_july_daily_watchmin,
 max(day_p33) day_p33,max(day_p67) day_p67,max(min_p33) min_p33,max(min_p67) min_p67,
 max(july_uid_n) july_uid_n
from flags group by grp,cast(index_ts as date) order by grp,index_dt
