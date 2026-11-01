with match_info as (
  select
    uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt = '2026-06-30'
    and day between '2025-04-18' and '2025-05-06'
),

user_info as (
  select
    user_ukey
  from (
    select
      user_ukey,
      luid,
      row_number() over (partition by user_ukey order by user_duration desc) as rnk
    from (
      select
        a.user_ukey,
        a.luid,
        sum(a.user_duration) as user_duration
      from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
      where a.dt between '2025-04-18' and '2025-05-06'
      group by a.user_ukey, a.luid
    )
  )
  where cast(luid as varchar) in (select cast(luid as varchar) from match_info) and rnk = 1
)


select
  b.dt,
  case
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
    else '非赛事'
  end as is_match,
  count(distinct b.user_ukey) as user_cnt
from user_info a
inner join zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1 b
on a.user_ukey = b.user_ukey
where b.dt >= '2025-05-06'
group by 
  b.dt,
  case
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
    else '非赛事'
  end