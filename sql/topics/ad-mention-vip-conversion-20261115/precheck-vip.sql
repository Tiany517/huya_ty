-- 探索预检：核对成功正金额订单快照、时间字段及订单重复；不据此给出转化率。
select count(*) as order_rows, count(distinct order_id) as order_ids,
 count(distinct uid) as uid_cnt,
 min(create_time) as min_create_time,max(create_time) as max_create_time,
 min(op_time) as min_op_time,max(op_time) as max_op_time,
 count_if(try_cast(create_time as timestamp) is null) as bad_create_rows,
 count_if(try_cast(op_time as timestamp) is null) as bad_op_rows,
 count_if(try_cast(op_time as timestamp)<try_cast(create_time as timestamp)) as op_before_create,
 count_if(try_cast(op_time as timestamp)>try_cast(create_time as timestamp)+interval '1' day) as op_lag_over_day,
 count_if(coalesce(lower(trim(cast(uid as varchar))),'') in ('0','','null','other','-','-1')) as bad_uid_rows
from gamelive.dwd_huya_pay_platform_vip_detail_d_a
where dt='2026-11-14' and status='200' and amount>0
