-- 元数据检查，只读取Hive分区清单，不扫描用户明细。
select 'event' source,dt,count(*) partition_n,count(distinct product) product_n
from gamelive."dwd_huya_event$partitions"
where dt between '2026-08-31' and '2026-11-12'
 and product in ('huya_andriod','huya_ios','huya_ipad','huya_pad','hmos_kiwi')
group by dt
union all
select 'july_watch',dt,count(*),cast(null as bigint)
from gamelive."dwt_huya_ayyuid_session_from_server_with_user$partitions"
where dt between '2026-07-01' and '2026-07-31' and tag='gameid' and htime='session'
group by dt
