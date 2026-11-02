with match_info as (
  select
    day as dt,
    uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where 
    dt = '2026-05-26'
    and day >= '2025-07-28'
    and day <= '2025-08-03' -- 25上海大师赛
)

-- 这些在赛事期间播放过斯诺克赛事的主播所拉新的用户为斯诺克拉新用户
, sinuoke_laxin_user_info as (
  select distinct
    b.dt, 
    b.user_ukey
  from match_info a
  inner join (
      select dt, luid, user_ukey
      from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 -- 宽口径拉新表
      where dt between '2025-07-28' and '2025-08-03' -- 赛事期间
          and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
  ) b 
  on a.dt = b.dt and a.luid = b.luid
)



-- 上海大师赛期间付费的用户，并以他们的首次付费时间为基准
, first_pay_info as (
    select
      a.user_uid,
      b.ukey as user_ukey,
      min(a.dt) as first_pay_dt
    from gamelive.dws_huya_revenue_detail_d_i a 
    left join (
      select 
        yyuid,
        ukey
        -- end_time ,rn 
      from(
        select 
          a.yyuid,
          a.ukey
          -- end_time 
          -- ,row_number()over(partition by yyuid order by end_time desc) rn
        from gamelive.dwt_huya_session_level a
        inner join sinuoke_laxin_user_info b
        on a.ukey = b.user_ukey
        where a.dt between '2025-08-04' and '2025-11-02' -- 赛事90天
          and length(a.dt)=10  
          and a.tag = 'product' 
      )t 
      -- where rn=1 
    ) b
    on a.user_uid = b.yyuid
    where a.dt between '2025-08-04' and '2025-11-02' -- 赛事90天
    group by 
      a.user_uid,
      b.ukey
)

, before_payment_user_active_info as ( -- 有付费用户的首付前活跃情况
  select
    a.user_ukey,

    -- 首付前7天内活跃天数（含首付日前第6天，不含首付当天）
    count(distinct case 
        when cast(b.dt as date) < cast(p.first_pay_dt as date)
         and cast(b.dt as date) >= date_add('day', -6, cast(p.first_pay_dt as date))
        then b.dt end) as active_7d,

    -- 首付前30天内活跃天数
    count(distinct case 
        when cast(b.dt as date) < cast(p.first_pay_dt as date)
         and cast(b.dt as date) >= date_add('day', -29, cast(p.first_pay_dt as date))
        then b.dt end) as active_30d,

    -- 首付前90天内活跃天数
    count(distinct case 
        when cast(b.dt as date) < cast(p.first_pay_dt as date)
         and cast(b.dt as date) >= date_add('day', -59, cast(p.first_pay_dt as date))
        then b.dt end) as active_60d,

    -- 首付前90天内活跃天数
    count(distinct case 
        when cast(b.dt as date) < cast(p.first_pay_dt as date)
         and cast(b.dt as date) >= date_add('day', -89, cast(p.first_pay_dt as date))
        then b.dt end) as active_90d

  from sinuoke_laxin_user_info a
  left join first_pay_info p 
    on a.user_ukey = p.user_ukey
  left join (
      select dt, user_ukey
      from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
      where dt between '2025-08-04' and '2025-11-02' -- 赛事90天
        and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and is_black_ukey = 0
  ) b -- 活跃表
    on p.user_ukey = b.user_ukey
  group by a.user_ukey
)


, after_payment_user_active_info as ( -- 有付费用户的首付后活跃情况
  select
    a.user_ukey,

    -- 首付后7天内活跃天数（不含首付当天，含首付后第6天）
    count(distinct case 
        when cast(b.dt as date) > cast(p.first_pay_dt as date)
         and cast(b.dt as date) <= date_add('day', 6, cast(p.first_pay_dt as date))
        then b.dt end) as active_7d,

    -- 首付后30天内活跃天数
    count(distinct case 
        when cast(b.dt as date) > cast(p.first_pay_dt as date)
         and cast(b.dt as date) <= date_add('day', 29, cast(p.first_pay_dt as date))
        then b.dt end) as active_30d,

    -- 首付后90天内活跃天数
    count(distinct case 
        when cast(b.dt as date) > cast(p.first_pay_dt as date)
         and cast(b.dt as date) <= date_add('day', 59, cast(p.first_pay_dt as date))
        then b.dt end) as active_60d,

    -- 首付后90天内活跃天数
    count(distinct case 
        when cast(b.dt as date) > cast(p.first_pay_dt as date)
         and cast(b.dt as date) <= date_add('day', 89, cast(p.first_pay_dt as date))
        then b.dt end) as active_90d

  from sinuoke_laxin_user_info a 
  left join first_pay_info p 
    on a.user_ukey = p.user_ukey
  left join (
      select dt, user_ukey
      from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
      where dt between '2025-08-04' and '2025-11-02' -- 赛事90天
        and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        and is_black_ukey = 0
  ) b -- 活跃表
    on p.user_ukey = b.user_ukey
  group by a.user_ukey
)




select
  '25上海大师赛' as macth_name,
  '2025/07/28 - 2025/08/03' as match_period,
  '2025/08/04 - 2026/01/31' as monitor_period,
  count(distinct a.user_ukey) as laxin_ucnt,
  avg(b.active_7d) as before_payment_avg_active_7d,
  avg(b.active_30d) as before_payment_avg_active_30d,
  avg(b.active_60d) as before_payment_avg_active_60d,
  avg(b.active_90d) as before_payment_avg_active_90d,
  avg(c.active_7d) as after_payment_avg_active_7d,
  avg(c.active_30d) as after_payment_avg_active_30d,
  avg(c.active_60d) as after_payment_avg_active_60d,
  avg(c.active_90d) as after_payment_avg_active_90d
from sinuoke_laxin_user_info a
left join before_payment_user_active_info b
on a.user_ukey = b.user_ukey
left join after_payment_user_active_info c
on a.user_ukey = c.user_ukey





