with user_game_belongs as (
  select user_ukey
  from (
    select user_ukey, igameid,
      row_number() over (partition by user_ukey order by user_duration desc, igameid) as rnk
    from (
      select
        a.user_ukey, a.igameid,
      case
          -- 2024赛季完整赛事
          when a.dt between '2024-06-10' and '2024-07-03' then '赛事期间'
          when a.dt between '2024-07-15' and '2024-07-21' then '赛事期间'
          when a.dt between '2024-08-19' and '2024-08-25' then '赛事期间'
          when a.dt between '2024-08-30' and '2024-09-07' then '赛事期间'
          when a.dt between '2024-09-16' and '2024-09-22' then '赛事期间'
          when a.dt between '2024-09-23' and '2024-09-29' then '赛事期间'
          when a.dt between '2024-10-06' and '2024-10-12' then '赛事期间'
          when a.dt between '2024-10-20' and '2024-10-27' then '赛事期间'
          when a.dt between '2024-11-03' and '2024-11-10' then '赛事期间'
          when a.dt between '2024-11-11' and '2024-11-17' then '赛事期间'
          when a.dt between '2024-11-23' and '2024-12-01' then '赛事期间'
          when a.dt between '2024-12-04' and '2024-12-07' then '赛事期间'
          when a.dt between '2024-12-09' and '2024-12-15' then '赛事期间'
          -- 2025年1-5月20日（你原有第一条起始2025-05-21）
          when a.dt between '2025-01-12' and '2025-01-19' then '赛事期间'
          when a.dt between '2025-01-27' and '2025-02-02' then '赛事期间'
          when a.dt between '2025-02-10' and '2025-02-16' then '赛事期间'
          when a.dt between '2025-02-24' and '2025-03-02' then '赛事期间'
          when a.dt between '2025-03-17' and '2025-03-23' then '赛事期间'
          when a.dt between '2025-03-31' and '2025-04-06' then '赛事期间'
          when a.dt between '2025-04-19' and '2025-05-05' then '赛事期间'
          -- 你原有2025-05-21及之后全部区间
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
        end as is_match,
        sum(a.user_duration) as user_duration
      from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
      where a.dt between '2024-06-01' and '2025-05-31' --过去一年
      group by a.user_ukey, a.igameid,
      case
          -- 2024赛季完整赛事
          when a.dt between '2024-06-10' and '2024-07-03' then '赛事期间'
          when a.dt between '2024-07-15' and '2024-07-21' then '赛事期间'
          when a.dt between '2024-08-19' and '2024-08-25' then '赛事期间'
          when a.dt between '2024-08-30' and '2024-09-07' then '赛事期间'
          when a.dt between '2024-09-16' and '2024-09-22' then '赛事期间'
          when a.dt between '2024-09-23' and '2024-09-29' then '赛事期间'
          when a.dt between '2024-10-06' and '2024-10-12' then '赛事期间'
          when a.dt between '2024-10-20' and '2024-10-27' then '赛事期间'
          when a.dt between '2024-11-03' and '2024-11-10' then '赛事期间'
          when a.dt between '2024-11-11' and '2024-11-17' then '赛事期间'
          when a.dt between '2024-11-23' and '2024-12-01' then '赛事期间'
          when a.dt between '2024-12-04' and '2024-12-07' then '赛事期间'
          when a.dt between '2024-12-09' and '2024-12-15' then '赛事期间'
          -- 2025年1-5月20日（你原有第一条起始2025-05-21）
          when a.dt between '2025-01-12' and '2025-01-19' then '赛事期间'
          when a.dt between '2025-01-27' and '2025-02-02' then '赛事期间'
          when a.dt between '2025-02-10' and '2025-02-16' then '赛事期间'
          when a.dt between '2025-02-24' and '2025-03-02' then '赛事期间'
          when a.dt between '2025-03-17' and '2025-03-23' then '赛事期间'
          when a.dt between '2025-03-31' and '2025-04-06' then '赛事期间'
          when a.dt between '2025-04-19' and '2025-05-05' then '赛事期间'
          -- 你原有2025-05-21及之后全部区间
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
        end
    ) t1
    where is_match = '赛事期间'
  ) t2
  where rnk = 1 and igameid = 2356 --体育
),

huiliu_user as (
  select
      a.user_ukey,
      min(a.dt) as huiliu_date
  from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1 a --回流用户表
  inner join user_game_belongs b 
  on a.user_ukey = b.user_ukey
  where a.dt between '2025-06-01' and '2025-06-30'
  group by a.user_ukey
),


user_huiliu_info as (
  select
    a.user_ukey,
    count(distinct b.dt) as active_day_cnt,
    max(case when b.dt = date_add(a.huiliu_date, 6) then 1 else 0 end) as is_7d_retain 
  from huiliu_user a
  left join (
    select distinct dt, user_ukey
    from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i --用户活跃表
    where dt between '2025-06-01' and '2025-07-06'
      and is_black_ukey = 0
  ) b
  on a.user_ukey = b.user_ukey
  and b.dt between a.huiliu_date and date_add(a.huiliu_date, 6)
  group by a.user_ukey
)

select 
  count(distinct user_ukey) as huiliu_user_cnt,
  sum(is_7d_retain) as huiliu_7d_retained_user_cnt,
  sum(is_7d_retain)/count(distinct user_ukey) as huiliu_7d_retained_rate,
  sum(active_day_cnt) as sum_all_active_days,
  sum(active_day_cnt)/count(distinct user_ukey) as avg_7d_active_days
from user_huiliu_info



