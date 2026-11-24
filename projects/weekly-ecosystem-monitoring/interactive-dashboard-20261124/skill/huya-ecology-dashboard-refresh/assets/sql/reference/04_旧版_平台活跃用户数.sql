with daily_active as (
  select
      dt,
      count(distinct user_ukey) as user_cnt
  from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
  where dt between '2026-08-24' and '2026-09-06'
    and product in (
        'huya_andriod',
        'huya_ipad',
        'huya_pad',
        'huya_ios'
    )
    and is_black_ukey = 0
  group by dt
)

select 
  case
    when dt between '2026-08-24' and '2026-08-30' then 'last_week'
    when dt between '2026-08-31' and '2026-09-06' then 'this_week'
  end as "时间段",
  avg(user_cnt) as dau
from daily_active
group by 
  case
    when dt between '2026-08-24' and '2026-08-30' then 'last_week'
    when dt between '2026-08-31' and '2026-09-06' then 'this_week'
  end