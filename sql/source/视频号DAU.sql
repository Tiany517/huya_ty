--基础数据
select dt
,count(distinct userid) as luid_num--主播数
,sum(cast(onlinetimeduration as double)) as online_duration--开播时长
,sum(cast(audiencecnt as bigint)) as dau--总DAU
,sum(cast(audiencecnt as bigint))*0.26 as dau_youxiao --总有效DAU，系数0.26 
from  gamelive.dwd_spider_wxmcn_anchor_livedata_list_d_i 
where dt>='2026-06-01'
and cast(onlinetimeduration as double) > 0 -- 开播 
group by dt
order by dt