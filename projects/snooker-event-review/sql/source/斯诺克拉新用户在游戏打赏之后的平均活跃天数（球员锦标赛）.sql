with match_info as (
  select
    day as dt,
    uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt = '2026-05-26'
    and day >= '2026-02-17'
    and day <= '2026-02-22' -- 25球员锦标赛
),

sinuoke_laxin_user_info as (
  select distinct
    b.user_ukey
  from match_info a
  inner join (
    select dt, luid, user_ukey
    from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
    where dt between '2026-02-17' and '2026-02-22'
      and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
  ) b
    on a.dt = b.dt
   and a.luid = b.luid
),

-- 首次游戏付费用户
pay_info as (
  select
    a.user_uid,
    b.ukey as user_ukey,
    min(a.dt) as first_pay_dt
  from gamelive.dws_huya_revenue_detail_d_i a
  left join (
    select
      a.yyuid,
      a.ukey
    from gamelive.dwt_huya_session_level a
    inner join sinuoke_laxin_user_info b
      on a.ukey = b.user_ukey
    where a.dt between '2026-02-17' and '2026-05-25'
      and a.tag = 'product'
  ) b
    on a.user_uid = b.yyuid
  inner join sinuoke_laxin_user_info c
    on b.ukey = c.user_ukey
  where a.dt between '2026-02-17' and '2026-05-25'
    and a.game_label in ('游戏', '游戏专区')
  group by
    a.user_uid,
    b.ukey
),

-- 首付费后活跃明细：加上“赛事期间/非赛事”和具体赛事名
user_active_detail as (
  select
    a.user_ukey,
    a.dt,
    case
      when a.dt between '2025-05-21' and '2025-06-01' then '赛事期间'
      when a.dt between '2025-06-30' and '2025-07-23' then '赛事期间'
      when a.dt between '2025-07-28' and '2025-08-03' then '赛事期间'
      when a.dt between '2025-08-08' and '2025-08-16' then '赛事期间'
      when a.dt between '2025-08-24' and '2025-08-30' then '赛事期间'
      when a.dt between '2025-09-15' and '2025-09-21' then '赛事期间'
      when a.dt between '2025-09-22' and '2025-09-28' then '赛事期间'
      when a.dt between '2025-10-07' and '2025-10-13' then '赛事期间'
      when a.dt between '2025-10-19' and '2025-10-26' then '赛事期间'
      when a.dt between '2025-11-02' and '2025-11-09' then '赛事期间'
      when a.dt between '2025-11-10' and '2025-11-16' then '赛事期间'
      when a.dt between '2025-11-29' and '2025-12-07' then '赛事期间'
      when a.dt between '2025-12-10' and '2025-12-13' then '赛事期间'
      when a.dt between '2025-12-15' and '2025-12-21' then '赛事期间'
      when a.dt between '2026-01-11' and '2026-01-18' then '赛事期间'
      when a.dt between '2026-01-26' and '2026-02-01' then '赛事期间'
      when a.dt between '2026-02-03' and '2026-02-08' then '赛事期间'
      when a.dt between '2026-02-17' and '2026-02-22' then '赛事期间'
      when a.dt between '2026-02-23' and '2026-03-01' then '赛事期间'
      when a.dt between '2026-03-16' and '2026-03-22' then '赛事期间'
      when a.dt between '2026-03-30' and '2026-04-05' then '赛事期间'
      when a.dt between '2026-04-18' and '2026-05-04' then '赛事期间'
      else '非赛事'
    end as is_match
  from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i a
  inner join sinuoke_laxin_user_info b
    on a.user_ukey = b.user_ukey
  inner join pay_info p
    on a.user_ukey = p.user_ukey
  where a.dt between '2026-02-17' and '2026-05-25'
    and a.dt > p.first_pay_dt -- 打赏后
    and a.product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
    and a.is_black_ukey = 0
),

-- 每个用户在每个区间的活跃天数
user_active_cnt as (
  select
    user_ukey,
    is_match,
    count(distinct dt) as active_days_cnt
  from user_active_detail
  group by
    user_ukey,
    is_match
)

select
  is_match,
  -- match_name,
  count(distinct user_ukey) as user_cnt,
  avg(active_days_cnt) as avg_active_days_cnt
from user_active_cnt
group by
  is_match
  --match_name
