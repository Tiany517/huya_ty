-- 探索：成功正金额订单行，按入口汇总；测试日10月24日，沿用已确认11月12日完整快照。
-- 支付端ios不等于曝光端，本查询只作入口分布诊断，不是转化率。
select from_id,from_name,count(*) order_rows,count(distinct order_id) order_n,count(distinct uid) uid_n
from gamelive.dwd_huya_pay_platform_vip_detail_d_a
where dt='2026-11-12' and status='200' and try_cast(amount as double)>0
 and pay_terminal='ios' and substr(create_time,1,10)='2026-10-24'
 and uid is not null and lower(cast(uid as varchar)) not in ('','0','other')
group by from_id,from_name order by order_n desc
