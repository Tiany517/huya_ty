with
user_game_belongs as (
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
      where a.dt between '2025-05-21' and '2026-05-04'
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
-- ============================================================
-- 直播回流
-- ============================================================
live_huiliu as (
  select a.dt, a.user_ukey
  from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1 a
  where a.dt between '2026-06-12' and '2026-06-30'
    and a.luid in (1239543466013, 1239543466014, 1531433300, 1259527226795, 585199800)

  union all

  select a.dt, a.user_ukey
  from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1 a
  where a.dt between '2026-06-16' and '2026-06-17'
    and a.luid = 1199568157971
),

all_huiliu_user as (
  select a.dt, a.user_ukey
  from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1 a
  where a.dt between '2026-06-12' and '2026-06-30'
),

video_preference as (
  select v.dt, v.user_ukey
  from (
    select dt, user_ukey, sum(watch_duration) as video_watch_duration
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '2026-06-12' and '2026-06-30'
      and product in ('huya_andriod', 'huya_ios', 'hmos_kiwi')
      and data_type = 'video_session' and live_content_type = '视频'
      and content_id <> 0 and vid_can_play = 1 and watch_cnt > 0
      and (implicit_tags like '%美加墨世界杯%' or implicit_tags like '%世界杯%')
    group by dt, user_ukey
  ) v
  left join (
    select dt, user_ukey, sum(watch_duration) as live_watch_duration
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '2026-06-12' and '2026-06-30'
      and product in ('huya_andriod', 'huya_ios', 'hmos_kiwi')
      and data_type = 'live_watch_session' and live_content_type = '直播'
      and watch_cnt > 0
    group by dt, user_ukey
  ) l on v.dt = l.dt and v.user_ukey = l.user_ukey
  where v.video_watch_duration > coalesce(l.live_watch_duration, 0)
),

betting_huiliu as (
  select
    from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd') as dt,
    concat('mobile/', shuyadeviceid) as user_ukey
  from gamelive.dwd_huya_t_friendinvinfo_d_a t
  inner join (
    select dt, user_ukey
    from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1
    where dt between '2026-06-12' and '2026-06-30'
  ) b
    on concat('mobile/', shuyadeviceid) = b.user_ukey
    and from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd') = b.dt
  where t.dt = '2026-06-30'
    and from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd') between '2026-06-12' and '2026-06-30'
    and iscenetype1 = 0 and iscenetype2 = 7 and iinvedtype <> 2
  group by from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd'), shuyadeviceid
),
huiliu_user as (
  select
    t1.user_ukey,
    min(t1.dt) as huiliu_date
  from (
    select dt, user_ukey from live_huiliu
    union all
    select alu.dt, alu.user_ukey
    from all_huiliu_user alu
    inner join video_preference p
      on alu.dt = p.dt and alu.user_ukey = p.user_ukey
    union all
    select dt, user_ukey from betting_huiliu
  ) t1
  inner join user_game_belongs t2 
    on t1.user_ukey = t2.user_ukey
  group by t1.user_ukey
),

user_huiliu_info as (
  select 
    a.user_ukey,
    count(distinct b.dt) as active_day_cnt,
    max(case when b.dt = date_add(a.huiliu_date, 6) then 1 else 0 end) as is_7d_retain
  from huiliu_user a 
  left join (
    select distinct dt, user_ukey
    from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
    where dt between '2026-06-12' and '2026-07-06'
      and is_black_ukey = 0
  ) b
    on a.user_ukey = b.user_ukey 
   and b.dt between a.huiliu_date and date_add(a.huiliu_date, 6)
  group by a.user_ukey
)

select
  count(distinct user_ukey) as huiliu_user_cnt,
  sum(is_7d_retain) as huiliu_7d_retained_user_cnt,
  sum(is_7d_retain) / count(distinct user_ukey) as huiliu_7d_retained_rate,
  sum(active_day_cnt) as sum_all_active_days,
  sum(active_day_cnt) / count(distinct user_ukey) as avg_7d_active_days
from user_huiliu_info