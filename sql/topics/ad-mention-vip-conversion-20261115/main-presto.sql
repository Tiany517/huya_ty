-- 描述性总体转化；2025-01-01至2026-11-14；最终一行，分母为全期UID并集。
with danmu_base as (
 -- 输入/输出：有效源弹幕记录，按源dt过滤；不关联、不放大。
 select d.dt,cast(d.luid as varchar) as uid,
  try_cast(d.time as timestamp) as danmu_ts,
  coalesce(nullif(trim(d.askscontent),''),nullif(trim(d.scontent),'')) as content
 from gamelive.gamelive_huya_danmu_log d
 where d.dt between '2025-01-01' and '2026-11-14'
 and d.passed='0' and d.lpid is not null
 and coalesce(lower(trim(cast(d.luid as varchar))),'') not in ('0','','null','other','-','-1')
),
ad_user as (
 -- 输入：含广告弹幕记录；输出：UID唯一。无效时间保留分母但标记不可确定先后。
 select uid,min(danmu_ts) as first_ad_ts,min(dt) as first_ad_dt,
  count(*) as ad_message_cnt,count_if(danmu_ts is null) as bad_time_cnt,
  count_if(cast(cast(danmu_ts as date) as varchar)<>dt) as mismatch_cnt
 from danmu_base where content like '%广告%' group by uid
),
vip_source as (
 -- 最新累计订单快照，保留全历史成功正金额订单，不预先按create_time截窗。
 select cast(uid as varchar) as uid,order_id,
  try_cast(create_time as timestamp) as create_ts,try_cast(op_time as timestamp) as op_ts
 from gamelive.dwd_huya_pay_platform_vip_detail_d_a
 where dt='2026-11-14' and status='200' and amount>0
 and coalesce(lower(trim(cast(uid as varchar))),'') not in ('0','','null','other','-','-1')
),
vip_first as (
 -- 订单记录->UID唯一；重复订单不影响最早时间。更新时间仅用于代理敏感性。
 select uid,min(create_ts) as first_vip_ts,min(op_ts) as first_vip_update_ts,
 count_if(create_ts is null) as bad_vip_time_cnt
 from vip_source group by uid
),
user_result as (
 -- UID唯一left join UID唯一，期望行数不变；只用业务UID关联键。
 select a.*,v.uid as vip_uid,v.first_vip_ts,v.first_vip_update_ts,
  coalesce(v.bad_vip_time_cnt,0) as bad_vip_time_cnt,
  case when a.bad_time_cnt>0 then 'ad_time_unresolved'
       when v.uid is null then 'no_paid_vip'
       when v.bad_vip_time_cnt>0 or v.first_vip_ts is null then 'vip_time_unresolved'
       when v.first_vip_ts>=timestamp '2026-11-15 00:00:00' then 'vip_after_cutoff'
       when v.first_vip_ts<a.first_ad_ts then 'vip_before_ad'
       when v.first_vip_ts=a.first_ad_ts then 'same_timestamp'
       else 'converted_after_ad' end as conversion_state
 from ad_user a left join vip_first v on a.uid=v.uid
)
select count(*) as mention_ad_user_cnt,
 count_if(conversion_state='converted_after_ad') as converted_vip_user_cnt,
 100.0*count_if(conversion_state='converted_after_ad')/nullif(count(*),0) as conversion_rate_pct,
 count_if(conversion_state='vip_before_ad') as vip_before_ad_user_cnt,
 count_if(conversion_state='same_timestamp') as same_timestamp_user_cnt,
 count_if(conversion_state='no_paid_vip') as no_paid_vip_user_cnt,
 count_if(conversion_state='ad_time_unresolved') as ad_time_unresolved_user_cnt,
 count_if(conversion_state='vip_time_unresolved') as vip_time_unresolved_user_cnt,
 count_if(conversion_state='vip_after_cutoff') as vip_after_cutoff_user_cnt,
 count_if(bad_time_cnt=0 and bad_vip_time_cnt=0 and first_vip_update_ts>first_ad_ts
  and first_vip_update_ts<timestamp '2026-11-15 00:00:00') as converted_by_update_time_user_cnt,
 count_if(bad_time_cnt=0 and bad_vip_time_cnt=0 and first_vip_ts<=first_ad_ts
  and first_vip_update_ts>first_ad_ts) as create_update_cross_ad_user_cnt,
 sum(ad_message_cnt) as mention_ad_message_cnt,sum(bad_time_cnt) as bad_ad_time_rows,
 sum(mismatch_cnt) as ad_time_dt_mismatch_rows,
 min(first_ad_ts) as min_first_ad_ts,max(first_ad_ts) as max_first_ad_ts,
 (select count(*) from vip_first) as all_paid_vip_users,
 count(distinct uid) as joined_distinct_users,
 slice(array_agg(concat(uid,' | ',cast(first_ad_ts as varchar),' | ',cast(first_vip_ts as varchar),
  ' | ',cast(first_vip_update_ts as varchar))) filter (where conversion_state='converted_after_ad'),1,5) as converted_examples,
 slice(array_agg(concat(uid,' | ',cast(first_ad_ts as varchar),' | ',cast(first_vip_ts as varchar)))
  filter (where conversion_state='vip_before_ad'),1,5) as vip_before_examples
from user_result
