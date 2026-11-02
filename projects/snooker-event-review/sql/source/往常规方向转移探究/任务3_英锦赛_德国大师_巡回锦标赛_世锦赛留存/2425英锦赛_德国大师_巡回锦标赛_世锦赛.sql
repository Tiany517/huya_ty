-- ========================================
-- 2024英锦赛拉新用户 → 德国大师赛/巡回锦标赛/世锦赛留存分析
-- ========================================

with match_info as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a --体育运动直播表
  where dt = '2026-05-06'
    and day >= '2024-11-23'
    and day <= '2024-12-01'
    -- and match_name like '%斯诺克%' 不用这个了
)

,user_info as(--- 英锦赛 拉新用户  
select b.ukey  ---a.dt ,a.luid , 
from match_info a 
join(---拉新用户
  select dt ,luid ,user_ukey as ukey 
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
  where dt between '2024-11-23' and '2024-12-01' 
    and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')  
)b 
on a.dt=b.dt and a.luid=b.luid 
group by b.ukey 
)

-- ========================================
-- 英锦赛期间留存（2024.11.23-12.01）基准
-- ========================================
select
  '基准期' as phase_tag,
  '英锦赛' as tournament,
  '2024.11.23-12.01' as tournament_date,
  count(distinct a.ukey) as lx_ucnt,
  count(distinct b.ukey) as lc_ucnt,
  count(distinct b.ukey) * 1.0 / count(distinct a.ukey) as lc_rate
from user_info a
left join (
  select user_ukey as ukey
  from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
  where dt between '2024-11-23' and '2024-12-01'
    and product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
    and is_black_ukey = 0
) b on a.ukey = b.ukey

union all

-- ========================================
-- 德国大师赛留存（2025.01.27-02.02）
-- ========================================
select
  '短期' as phase_tag,
  '德国大师赛' as tournament,
  '2025.01.27-02.02' as tournament_date,
  count(distinct a.ukey) as lx_ucnt,
  count(distinct b.ukey) as lc_ucnt,
  count(distinct b.ukey) * 1.0 / count(distinct a.ukey) as lc_rate
from user_info a
left join (
  select user_ukey as ukey
  from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
  where dt between '2025-01-27' and '2025-02-02'
    and product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
    and is_black_ukey = 0
) b on a.ukey = b.ukey

union all

-- ========================================
-- 巡回锦标赛留存（2025.03.31-04.06）
-- ========================================
select
  '中期' as phase_tag,
  '巡回锦标赛' as tournament,
  '2025.03.31-04.06' as tournament_date,
  count(distinct a.ukey) as lx_ucnt,
  count(distinct b.ukey) as lc_ucnt,
  count(distinct b.ukey) * 1.0 / count(distinct a.ukey) as lc_rate
from user_info a
left join (
  select user_ukey as ukey
  from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
  where dt between '2025-03-31' and '2025-04-06'
    and product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
    and is_black_ukey = 0
) b on a.ukey = b.ukey

union all

-- ========================================
-- 世锦赛留存（2025.04.18-05.04）
-- ========================================
select
  '长期' as phase_tag,
  '世锦赛' as tournament,
  '2025.04.18-05.04' as tournament_date,
  count(distinct a.ukey) as lx_ucnt,
  count(distinct b.ukey) as lc_ucnt,
  count(distinct b.ukey) * 1.0 / count(distinct a.ukey) as lc_rate
from user_info a
left join (
  select user_ukey as ukey
  from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
  where dt between '2025-04-18' and '2025-05-04'
    and product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
    and is_black_ukey = 0
) b on a.ukey = b.ukey