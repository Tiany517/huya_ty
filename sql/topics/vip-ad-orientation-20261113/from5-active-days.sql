-- 轻量探索：沿用成功正金额订单口径。11月12日为2026-11-13查询确认的最新快照。
-- 按订单创建自然日统计，不按快照分区数统计；最终唯一键order_dt。
-- 不限制支付端，避免将web支付端误认为无APP来源。
select substr(cast(create_time as varchar),1,10) order_dt,
 count(*) order_rows,count(distinct order_id) order_n,count(distinct uid) uid_n,
 count_if(pay_terminal='adr') adr_orders,count_if(pay_terminal='ios') ios_orders,
 count_if(pay_terminal='web') web_orders
from gamelive.dwd_huya_pay_platform_vip_detail_d_a
where dt='2026-11-12' and from_id='5'
 and substr(cast(create_time as varchar),1,10) between '2026-08-31' and '2026-11-13'
 and status='200' and try_cast(amount as double)>0
 and uid is not null and lower(cast(uid as varchar)) not in ('','0','other')
group by substr(cast(create_time as varchar),1,10)
order by order_dt
