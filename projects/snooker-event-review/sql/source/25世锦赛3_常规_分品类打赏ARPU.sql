with match_info as (
  select
    day as dt,
    uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt = '2026-05-26'
    and day >= '2025-04-18'
    and day <= '2025-05-06' -- 25世锦赛
),

sinuoke_laxin_user_info as (
  select distinct
    b.dt, 
    b.user_ukey
  from match_info a
  inner join (
      select 
        dt, 
        luid, 
        user_ukey
      from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
      where dt between '2025-04-18' and '2025-05-06'  -- 25世锦赛
        and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
  ) b 
  on a.dt = b.dt and a.luid = b.luid
),


session_one_keep as (
  select
      ukey,
      yyuid
  from (
    select
        ukey,
        yyuid,
        row_number() over (partition by ukey order by dt) as rn
    from gamelive.dwt_huya_session_level
    where dt between '2025-05-07' and '2025-11-03'  -- 25世锦赛
      and length(dt) = 10
      and tag = 'product'
  )
  where rn = 1
),

user_pay_info_daily as (
  select
      a.dt,
      case 
        when a.game_label in ('娱乐', '娱乐专区') and a.game_id not in (2356) then '娱乐（非体育）'
        when a.game_label in ('游戏', '游戏专区') then '游戏'
        when a.game_id in (2356) then '体育'
        else '其他'
      end as game_label,
      c.ukey,
      sum(a.user_consume_amount) as user_consume_amount
  from gamelive.dws_huya_revenue_detail_d_i a
  left join session_one_keep c
    on a.user_uid = c.yyuid
  inner join sinuoke_laxin_user_info b
    on c.ukey = b.user_ukey
  where a.dt between '2025-05-07' and '2025-11-03'
    and length(a.dt) = 10
    and user_consume_amount > 0
  group by
      a.dt,
      case 
        when a.game_label in ('娱乐', '娱乐专区') and a.game_id not in (2356) then '娱乐（非体育）'
        when a.game_label in ('游戏', '游戏专区') then '游戏'
        when a.game_id in (2356) then '体育'
        else '其他'
      end,
      c.ukey
)

select
  game_label,
  sum(user_consume_amount) as user_consume_amount,
  count(distinct ukey) as pay_user_cnt,
  sum(user_consume_amount) / count(distinct ukey) as arpu
from user_pay_info_daily
group by game_label