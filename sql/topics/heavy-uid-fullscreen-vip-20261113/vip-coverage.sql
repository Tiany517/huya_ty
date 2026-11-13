select dt,count(*) rows,min(create_time) min_create,max(create_time) max_create,
 min(op_time) min_op,max(op_time) max_op,
 count_if(status='200' and amount>0) successful_paid_rows,
 count_if(try_cast(create_time as timestamp) is null) bad_time_rows
from gamelive.dwd_huya_pay_platform_vip_detail_d_a
where dt='2026-11-12' group by dt
