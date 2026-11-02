with match_info as (
  select
    day as dt,
    uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt = '2026-05-26'
    and day between '2026-02-17' and '2026-02-22' -- 25球员锦标赛
),

sinuoke_laxin_user_info as (
  select distinct
    b.user_ukey
  from match_info a
  inner join (
    select dt, luid, user_ukey
    from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 -- 宽口径拉新表
    where dt between '2026-02-17' and '2026-02-22' -- 赛事期间
      and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
  ) b
    on a.dt = b.dt
   and a.luid = b.luid
),

user_pay_info as (
  select
    a.user_uid,
    b.ukey as user_ukey,
    min(a.dt) as first_pay_dt,
    sum(a.user_consume_cnt) as user_consume_cnt,
    sum(a.user_consume_amount) as user_consume_amt
  from gamelive.dws_huya_revenue_detail_d_i a
  inner join (
    select distinct yyuid, ukey
    from gamelive.dwt_huya_session_level
    where dt between '2026-02-17' and '2026-05-25' -- 球员锦标赛开始至昨日
      and tag = 'product'
  ) b
    on a.user_uid = b.yyuid
  inner join sinuoke_laxin_user_info c
    on b.ukey = c.user_ukey
  where a.dt between '2026-02-17' and '2026-05-25' -- 球员锦标赛开始至昨日
  group by
    a.user_uid,
    b.ukey
),

first_pay_behavior as (
  select
    p.user_ukey,
    p.first_pay_dt,
    case
      when p.first_pay_dt between '2025-05-21' and '2025-06-01' then '赛事期间'
      when p.first_pay_dt between '2025-06-30' and '2025-07-23' then '赛事期间'
      when p.first_pay_dt between '2025-07-28' and '2025-08-03' then '赛事期间'
      when p.first_pay_dt between '2025-08-08' and '2025-08-16' then '赛事期间'
      when p.first_pay_dt between '2025-08-24' and '2025-08-30' then '赛事期间'
      when p.first_pay_dt between '2025-09-15' and '2025-09-21' then '赛事期间'
      when p.first_pay_dt between '2025-09-22' and '2025-09-28' then '赛事期间'
      when p.first_pay_dt between '2025-10-07' and '2025-10-13' then '赛事期间'
      when p.first_pay_dt between '2025-10-19' and '2025-10-26' then '赛事期间'
      when p.first_pay_dt between '2025-11-02' and '2025-11-09' then '赛事期间'
      when p.first_pay_dt between '2025-11-10' and '2025-11-16' then '赛事期间'
      when p.first_pay_dt between '2025-11-29' and '2025-12-07' then '赛事期间'
      when p.first_pay_dt between '2025-12-10' and '2025-12-13' then '赛事期间'
      when p.first_pay_dt between '2025-12-15' and '2025-12-21' then '赛事期间'
      when p.first_pay_dt between '2026-01-11' and '2026-01-18' then '赛事期间'
      when p.first_pay_dt between '2026-01-26' and '2026-02-01' then '赛事期间'
      when p.first_pay_dt between '2026-02-03' and '2026-02-08' then '赛事期间'
      when p.first_pay_dt between '2026-02-17' and '2026-02-22' then '赛事期间' -- 球员锦标赛
      when p.first_pay_dt between '2026-02-23' and '2026-03-01' then '赛事期间'
      when p.first_pay_dt between '2026-03-16' and '2026-03-22' then '赛事期间'
      when p.first_pay_dt between '2026-03-30' and '2026-04-05' then '赛事期间'
      when p.first_pay_dt between '2026-04-18' and '2026-05-04' then '赛事期间'
      else '非赛事'
    end as is_match,
    a.game_label,
    a.game_id,
    a.game_name,
    p.user_consume_cnt,
    p.user_consume_amt
  from user_pay_info p
  left join (
    select
      dt,
      user_ukey,
      game_label,
      game_id,
      game_name
    from gamelive.dws_huya_user_behavior_d_i 
    where dt between '2026-02-17' and '2026-05-25' -- 球员锦标赛开始至昨日
  ) a 
    on p.user_ukey = a.user_ukey
  where p.first_pay_dt = a.dt
  
)

select
  is_match,
  case
    when game_label in ('娱乐', '娱乐专区') then '娱乐'
    when game_label in ('游戏', '游戏专区') then '游戏'
    else '其他'
  end as game_label,
  game_id,
  game_name,
  sum(user_consume_cnt) as user_consume_cnt,
  sum(user_consume_amt) as user_consume_amt
from first_pay_behavior
group by
  is_match,
  case
    when game_label in ('娱乐', '娱乐专区') then '娱乐'
    when game_label in ('游戏', '游戏专区') then '游戏'
    else '其他'
  end,
  game_id,
  game_name