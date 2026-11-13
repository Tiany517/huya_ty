-- 轻量探索：订单行粒度；输出入口ID+名称+支付端，UID跨组可重复，分组UV不得直接相加。
-- 沿用用户成功正金额订单口径；11月12日是本任务已确认完整快照，不截掉首次购前历史。
select from_id,from_name,pay_terminal,count(*) order_rows,count(distinct order_id) order_n,
 count(distinct uid) paid_uid_n,min(create_time) min_create,max(create_time) max_create
from gamelive.dwd_huya_pay_platform_vip_detail_d_a
where dt='2026-11-12'
 and substr(cast(create_time as varchar),1,10) between '2026-08-31' and '2026-11-12'
 and status='200' and try_cast(amount as double)>0
 and uid is not null and lower(cast(uid as varchar)) not in ('','0','other')
group by from_id,from_name,pay_terminal
order by from_id,from_name,pay_terminal
