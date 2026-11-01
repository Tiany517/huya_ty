with
soonker_belongs_user as (
  select user_ukey
  from (
    select
      user_ukey,
      igameid,
      row_number() over (partition by user_ukey order by user_duration desc, igameid) as rnk
    from (
      select
        a.user_ukey,
        a.igameid,
        case
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
          when a.dt between '2025-01-12' and '2025-01-19' then '赛事期间'
          when a.dt between '2025-01-27' and '2025-02-02' then '赛事期间'
          when a.dt between '2025-02-10' and '2025-02-16' then '赛事期间'
          when a.dt between '2025-02-24' and '2025-03-02' then '赛事期间'
          when a.dt between '2025-03-17' and '2025-03-23' then '赛事期间'
          when a.dt between '2025-03-31' and '2025-04-06' then '赛事期间'
          when a.dt between '2025-04-19' and '2025-05-05' then '赛事期间'
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
          when a.dt between '2026-06-12' and '2026-07-13' then '世界杯期间'
          else '非赛事'
        end as is_match,
        sum(a.user_duration) as user_duration
      from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
      where a.dt between '2024-05-31' and '2025-05-31'
      group by a.user_ukey, a.igameid,
        case
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
          when a.dt between '2025-01-12' and '2025-01-19' then '赛事期间'
          when a.dt between '2025-01-27' and '2025-02-02' then '赛事期间'
          when a.dt between '2025-02-10' and '2025-02-16' then '赛事期间'
          when a.dt between '2025-02-24' and '2025-03-02' then '赛事期间'
          when a.dt between '2025-03-17' and '2025-03-23' then '赛事期间'
          when a.dt between '2025-03-31' and '2025-04-06' then '赛事期间'
          when a.dt between '2025-04-19' and '2025-05-05' then '赛事期间'
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
          when a.dt between '2026-06-12' and '2026-07-13' then '世界杯期间'
          else '非赛事'
        end
    ) t1
    where is_match = '赛事期间'
  ) t2
  where rnk = 1 and igameid = 2356
),


snooker_active_user as (
  select
      a.user_ukey
  from soonker_belongs_user a
  inner join (
  select distinct user_ukey
  from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
  where dt between '2026-06-12' and '2026-07-13'
    and is_black_ukey = 0
  ) b
  on a.user_ukey = b.user_ukey 
)



select
  b.dt,
  a.user_ukey,
  case
    when b.dt between '2024-06-10' and '2024-07-03' then '赛事期间'
    when b.dt between '2024-07-15' and '2024-07-21' then '赛事期间'
    when b.dt between '2024-08-19' and '2024-08-25' then '赛事期间'
    when b.dt between '2024-08-30' and '2024-09-07' then '赛事期间'
    when b.dt between '2024-09-16' and '2024-09-22' then '赛事期间'
    when b.dt between '2024-09-23' and '2024-09-29' then '赛事期间'
    when b.dt between '2024-10-06' and '2024-10-12' then '赛事期间'
    when b.dt between '2024-10-20' and '2024-10-27' then '赛事期间'
    when b.dt between '2024-11-03' and '2024-11-10' then '赛事期间'
    when b.dt between '2024-11-11' and '2024-11-17' then '赛事期间'
    when b.dt between '2024-11-23' and '2024-12-01' then '赛事期间'
    when b.dt between '2024-12-04' and '2024-12-07' then '赛事期间'
    when b.dt between '2024-12-09' and '2024-12-15' then '赛事期间'
    when b.dt between '2025-01-12' and '2025-01-19' then '赛事期间'
    when b.dt between '2025-01-27' and '2025-02-02' then '赛事期间'
    when b.dt between '2025-02-10' and '2025-02-16' then '赛事期间'
    when b.dt between '2025-02-24' and '2025-03-02' then '赛事期间'
    when b.dt between '2025-03-17' and '2025-03-23' then '赛事期间'
    when b.dt between '2025-03-31' and '2025-04-06' then '赛事期间'
    when b.dt between '2025-04-19' and '2025-05-05' then '赛事期间'
    when b.dt between '2025-05-21' and '2025-06-01' then '赛事期间'
    when b.dt between '2025-06-30' and '2025-07-23' then '赛事期间'
    when b.dt between '2025-07-28' and '2025-08-03' then '赛事期间'
    when b.dt between '2025-08-08' and '2025-08-16' then '赛事期间'
    when b.dt between '2025-08-24' and '2025-08-30' then '赛事期间'
    when b.dt between '2025-09-15' and '2025-09-21' then '赛事期间'
    when b.dt between '2025-09-22' and '2025-09-28' then '赛事期间'
    when b.dt between '2025-10-07' and '2025-10-13' then '赛事期间'
    when b.dt between '2025-10-19' and '2025-10-26' then '赛事期间'
    when b.dt between '2025-11-02' and '2025-11-09' then '赛事期间'
    when b.dt between '2025-11-10' and '2025-11-16' then '赛事期间'
    when b.dt between '2025-11-29' and '2025-12-07' then '赛事期间'
    when b.dt between '2025-12-10' and '2025-12-13' then '赛事期间'
    when b.dt between '2025-12-15' and '2025-12-21' then '赛事期间'
    when b.dt between '2026-01-11' and '2026-01-18' then '赛事期间'
    when b.dt between '2026-01-26' and '2026-02-01' then '赛事期间'
    when b.dt between '2026-02-03' and '2026-02-08' then '赛事期间'
    when b.dt between '2026-02-17' and '2026-02-22' then '赛事期间'
    when b.dt between '2026-02-23' and '2026-03-01' then '赛事期间'
    when b.dt between '2026-03-16' and '2026-03-22' then '赛事期间'
    when b.dt between '2026-03-30' and '2026-04-05' then '赛事期间'
    when b.dt between '2026-04-18' and '2026-05-04' then '赛事期间'
    when b.dt between '2026-06-12' and '2026-07-13' then '世界杯期间'
    else '非赛事'
  end as is_match,
  b.keyword,
  b.cnt,
  b.result_cnt
from snooker_active_user a
left join zhgametemp.yty_huya_sousuo2 b 
  on a.user_ukey = b.ukey
where b.dt between '2025-01-01' and '2026-07-12'
