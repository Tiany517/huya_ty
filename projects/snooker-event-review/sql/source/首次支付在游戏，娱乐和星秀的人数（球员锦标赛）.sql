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

-- 拉新用户中，全局有过付费的人
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

-- 每个用户的全局首次付费日
first_pay_user as (
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
  group by
    a.user_uid,
    b.ukey
),

-- 取首次付费日当天的明细，并归类到类目
first_pay_classify as (
  select
    p.user_uid,
    p.user_ukey,
    p.first_pay_dt,
    case
      when a.game_label in ('游戏', '游戏专区') then '游戏'
      when a.game_label in ('娱乐', '娱乐专区') then '娱乐'
      when a.game_id in (2165, 1663) then '星秀户外'
      else '其他'
    end as first_pay_cat
  from first_pay_user p
  inner join gamelive.dws_huya_revenue_detail_d_i a
    on p.user_uid = a.user_uid
   and p.first_pay_dt = a.dt
  where a.dt between '2026-02-17' and '2026-05-25'
),

-- 如果同一天有多个类目，去重后再统计
first_pay_classify_dedup as (
  select distinct
    user_ukey,
    first_pay_dt,
    first_pay_cat
  from first_pay_classify
)

select
  counts.laxin_user_cnt,
  counts.pay_total_user_cnt,
  counts.first_pay_game_user_cnt,
  counts.first_pay_entertainment_user_cnt,
  counts.first_pay_xingxiu_outdoor_user_cnt,
  round(counts.pay_total_user_cnt / counts.laxin_user_cnt, 4) as laxin_payment_ratio,
  round(counts.first_pay_game_user_cnt / counts.pay_total_user_cnt, 4) as game_first_payment_ratio,
  round(counts.first_pay_entertainment_user_cnt / counts.pay_total_user_cnt, 4) as entertainment_first_payment_ratio,
  round(counts.first_pay_xingxiu_outdoor_user_cnt / counts.pay_total_user_cnt, 4) as xingxiu_outdoor_first_payment_ratio
from (
  select
    (select count(distinct user_ukey) from sinuoke_laxin_user_info) as laxin_user_cnt,
    (select count(distinct user_ukey) from pay_total_user) as pay_total_user_cnt,
    (select count(distinct user_ukey) from first_pay_classify_dedup where first_pay_cat = '游戏') as first_pay_game_user_cnt,
    (select count(distinct user_ukey) from first_pay_classify_dedup where first_pay_cat = '娱乐') as first_pay_entertainment_user_cnt,
    (select count(distinct user_ukey) from first_pay_classify_dedup where first_pay_cat = '星秀户外') as first_pay_xingxiu_outdoor_user_cnt
) counts