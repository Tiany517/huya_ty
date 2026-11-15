-- 独立路径：分母直接COUNT DISTINCT源发送人；分子从VIP历史首单出发，
-- 检查是否存在早于首单的广告弹幕。不同于主查询先聚合广告首提再left join。
with valid_ad as (
 -- 输入源记录，严格复用同一源范围和原业务过滤，不允许放大。
 select dt,cast(luid as varchar) as uid,try_cast(time as timestamp) as ad_ts
 from gamelive.gamelive_huya_danmu_log
 where dt between '2025-01-01' and '2026-11-14'
 and passed='0' and lpid is not null
 and coalesce(lower(trim(cast(luid as varchar))),'') not in ('0','','null','other','-','-1')
 and coalesce(nullif(trim(askscontent),''),nullif(trim(scontent),'')) like '%广告%'
),
first_paid as (
 -- 全历史成功订单->UID唯一，保留创建/更新时间，不能只读分析窗内的续费。
 select cast(uid as varchar) as uid,min(try_cast(create_time as timestamp)) as first_paid_ts,
 min(try_cast(op_time as timestamp)) as first_update_ts,
 count_if(try_cast(create_time as timestamp) is null) as bad_order_time
 from gamelive.dwd_huya_pay_platform_vip_detail_d_a
 where dt='2026-11-14' and status='200' and amount>0
 and coalesce(lower(trim(cast(uid as varchar))),'') not in ('0','','null','other','-','-1')
 group by cast(uid as varchar)
),
paid_ad_history as (
 -- 付费UID->该UID广告记录，1:N有意展开；下一层回到付费UID唯一，不能累加人数。
 select p.uid,p.first_paid_ts,p.first_update_ts,
 count(*) as ad_rows,
 count_if(a.ad_ts is null) as bad_ad_time,
 count_if(a.ad_ts<p.first_paid_ts) as ads_before_first_pay,
 count_if(a.ad_ts<p.first_update_ts) as ads_before_update
 from first_paid p join valid_ad a on p.uid=a.uid
 where p.bad_order_time=0
 group by p.uid,p.first_paid_ts,p.first_update_ts
),
coverage as (
 -- UID去重直接来自基础记录；日期检查单独count distinct，不能拿日UV之和当全期UV。
 select count(distinct uid) as denominator,count(*) as ad_rows,
 count(distinct dt) as covered_days,min(dt) as min_dt,max(dt) as max_dt,
 count_if(ad_ts is null) as bad_ad_rows,
 count_if(cast(cast(ad_ts as date) as varchar)<>dt) as mismatch_rows
 from valid_ad
)
select c.*,
 (select count(*) from paid_ad_history where bad_ad_time=0 and ads_before_first_pay>0
  and first_paid_ts<timestamp '2026-11-15 00:00:00') as independent_numerator,
 (select count(*) from paid_ad_history where bad_ad_time=0 and ads_before_update>0
  and first_update_ts<timestamp '2026-11-15 00:00:00') as independent_update_numerator,
 (select count(*) from paid_ad_history) as matched_paid_ad_users,
 (select sum(ad_rows) from paid_ad_history) as matched_paid_ad_message_rows
from coverage c
