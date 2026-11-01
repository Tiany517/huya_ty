select 
  dt
  ,sum(case when type = '虎牙app端dau' then user_cnt else 0 end) as "虎牙app端dau"
  ,sum(case when type = '虎牙app端mau' then user_cnt else 0 end) as "虎牙app端mau"
from zhgametemp.zzz_huya_app_dau_v1
where dt >= '2026-06-01' 
group by dt 
order by dt