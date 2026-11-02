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
    where dt between '2026-02-17' and '2026-02-22' -- 球员锦标赛
      and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
  ) b
    on a.dt = b.dt
   and a.luid = b.luid
),

-- 支付总人数
pay_total_user as (
  select distinct
    a.user_uid,
    b.ukey as user_ukey
  from gamelive.dws_huya_revenue_detail_d_i a
  inner join (
    select distinct yyuid, ukey
    from gamelive.dwt_huya_session_level
    where dt between '2026-02-17' and '2026-05-25'
      and length(dt) = 10
      and tag = 'product'
  ) b
    on a.user_uid = b.yyuid
  inner join sinuoke_laxin_user_info c
    on b.ukey = c.user_ukey
  where a.dt between '2026-02-17' and '2026-05-25' 
),

-- 游戏首次付费用户
game_first_pay_user as (
  select
    a.user_uid,
    b.ukey as user_ukey,
    min(a.dt) as first_pay_dt
  from gamelive.dws_huya_revenue_detail_d_i a
  inner join (
    select distinct yyuid, ukey
    from gamelive.dwt_huya_session_level
    where dt between '2026-02-17' and '2026-05-25'
      and length(dt) = 10
      and tag = 'product'
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


-- 娱乐首次付费用户


entertainment_first_pay_user as (
  select
    a.user_uid,
    b.ukey as user_ukey,
    min(a.dt) as first_pay_dt
  from gamelive.dws_huya_revenue_detail_d_i a
  inner join (
    select distinct yyuid, ukey
    from gamelive.dwt_huya_session_level
    where dt between '2026-02-17' and '2026-05-25'
      and length(dt) = 10
      and tag = 'product'
  ) b
    on a.user_uid = b.yyuid
  inner join sinuoke_laxin_user_info c
    on b.ukey = c.user_ukey
  where a.dt between '2026-02-17' and '2026-05-25'
    and a.game_label in ('娱乐', '娱乐专区')
  group by
    a.user_uid,
    b.ukey
),

entertainment_first_pay_user_not_include_sport as (
  select
    a.user_uid,
    b.ukey as user_ukey,
    min(a.dt) as first_pay_dt
  from gamelive.dws_huya_revenue_detail_d_i a
  inner join (
    select distinct yyuid, ukey
    from gamelive.dwt_huya_session_level
    where dt between '2026-02-17' and '2026-05-25'
      and length(dt) = 10
      and tag = 'product'
  ) b
    on a.user_uid = b.yyuid
  inner join sinuoke_laxin_user_info c
    on b.ukey = c.user_ukey
  where a.dt between '2026-02-17' and '2026-05-25'
    and a.game_label in ('娱乐', '娱乐专区')
    and a.game_id not in (2356)
  group by
    a.user_uid,
    b.ukey
),


entertainment_first_pay_user_include_sport as (
  select
    a.user_uid,
    b.ukey as user_ukey,
    min(a.dt) as first_pay_dt
  from gamelive.dws_huya_revenue_detail_d_i a
  inner join (
    select distinct yyuid, ukey
    from gamelive.dwt_huya_session_level
    where dt between '2026-02-17' and '2026-05-25'
      and length(dt) = 10
      and tag = 'product'
  ) b
    on a.user_uid = b.yyuid
  inner join sinuoke_laxin_user_info c
    on b.ukey = c.user_ukey
  where a.dt between '2026-02-17' and '2026-05-25'
    and a.game_label in ('娱乐', '娱乐专区')
    and a.game_id in (2356)
  group by
    a.user_uid,
    b.ukey
),




-- 星秀/户外首次付费用户
xingxiu_pay_user as (
  select
    a.user_uid,
    b.ukey as user_ukey,
    min(a.dt) as first_pay_dt
  from gamelive.dws_huya_revenue_detail_d_i a
  inner join (
    select distinct yyuid, ukey
    from gamelive.dwt_huya_session_level
    where dt between '2026-02-23' and '2026-05-25'
      and length(dt) = 10
      and tag = 'product'
  ) b
    on a.user_uid = b.yyuid
  inner join sinuoke_laxin_user_info c
    on b.ukey = c.user_ukey
  where a.dt between '2026-02-23' and '2026-05-25'
    and a.game_id in (2165, 1663) -- 户外、星秀
    and a.game_label in ('娱乐', '娱乐专区')
  group by
    a.user_uid,
    b.ukey
)


select
  counts.laxin_user_cnt,
  counts.pay_total_user_cnt,
  counts.game_first_pay_user_cnt,
  counts.entertainment_pay_first_pay_user_cnt,
  counts.xingxiu_first_pay_user_cnt,
  counts.pay_total_user_cnt / counts.laxin_user_cnt as laxin_payment_ratio,
  counts.game_first_pay_user_cnt/counts.pay_total_user_cnt as game_first_payment_ratio,
  counts.entertainment_pay_first_pay_user_cnt/counts.pay_total_user_cnt as entertainment_first_payment_ratio,
  counts.xingxiu_first_pay_user_cnt/counts.pay_total_user_cnt as xingxiu_first_payment_ratio
from (
  select
    (select count(distinct user_ukey) from sinuoke_laxin_user_info) as laxin_user_cnt,
    (select count(distinct user_ukey) from pay_total_user) as pay_total_user_cnt,
    (select count(distinct user_ukey) from game_first_pay_user) as game_first_pay_user_cnt,
    (select count(distinct user_ukey) from entertainment_first_pay_user) as entertainment_pay_first_pay_user_cnt,
    (select count(distinct user_ukey) from entertainment_first_pay_user_not_include_sport) as entertainment_first_not_include_sport_pay_user_cnt,
    (select count(distinct user_ukey) from entertainment_first_pay_user_include_sport) as entertainment_first_include_sport_pay_user_cnt
    (select count(distinct user_ukey) from xingxiu_pay_user) as xingxiu_first_pay_user_cnt
) counts





