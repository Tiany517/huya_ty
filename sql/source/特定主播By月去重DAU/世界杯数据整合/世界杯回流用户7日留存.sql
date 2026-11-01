with
-- ============================================================
-- 直播回流
-- ============================================================
live_huiliu as (
  select a.dt, a.user_ukey
  from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1 a
  where a.dt between '2026-06-12' and '2026-07-08'
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
  where a.dt between '2026-06-12' and '2026-07-08'
),

video_preference as (
  select v.dt, v.user_ukey
  from (
    select dt, user_ukey, sum(watch_duration) as video_watch_duration
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '2026-06-12' and '2026-07-08'
      and product in ('huya_andriod', 'huya_ios', 'hmos_kiwi')
      and data_type = 'video_session' and live_content_type = '视频'
      and content_id <> 0 and vid_can_play = 1 and watch_cnt > 0
      and (implicit_tags like '%美加墨世界杯%' or implicit_tags like '%世界杯%')
    group by dt, user_ukey
  ) v
  left join (
    select dt, user_ukey, sum(watch_duration) as live_watch_duration
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '2026-06-12' and '2026-07-08'
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
    where dt between '2026-06-12' and '2026-07-08'
  ) b
    on concat('mobile/', shuyadeviceid) = b.user_ukey
    and from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd') = b.dt
  where t.dt = '2026-07-08'
    and from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd') between '2026-06-12' and '2026-07-08'
    and iscenetype1 = 0 and iscenetype2 = 7 and iinvedtype <> 2
  group by from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd'), shuyadeviceid
),

all_user_union as (
  select dt, user_ukey from live_huiliu
  union all
  select alu.dt, alu.user_ukey
  from all_huiliu_user alu
  inner join video_preference p
    on alu.dt = p.dt and alu.user_ukey = p.user_ukey
  union all
  select dt, user_ukey from betting_huiliu
), 


new_user as (
  select distinct 
    dt as new_dt, 
    '世界杯回流' as luid,
    '世界杯回流' as luid_name,
    user_ukey
  from all_user_union 
),

user_days as (
    select
        nu.luid,
        nu.luid_name,
        nu.user_ukey,
        count(distinct b.dt) as active_days_7d,
        max(case when b.dt = date_add(nu.new_dt, 6) then 1 else 0 end) as is_retain
        -- max(case when b.dt = date_add(nu.new_dt, 14) then 1 else 0 end) as is_retain
    from new_user nu
    left join (
        select distinct dt, user_ukey
        from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
        where dt between '2026-06-01' and '2026-07-16'
          and is_black_ukey = 0
    ) b
        on nu.user_ukey = b.user_ukey
        and b.dt between nu.new_dt and date_add(nu.new_dt, 6)
    group by nu.luid, nu.luid_name, nu.user_ukey
)

select
    luid,
    luid_name,
    count(distinct user_ukey) as total_new,
    sum(is_retain) as retain_7d_cnt,
    sum(is_retain) / count(distinct user_ukey) as retain_7d_rate,
    sum(active_days_7d) as sum_all_active_days,
    sum(active_days_7d) / count(distinct user_ukey) as avg_7d_active_day
from user_days
group by luid, luid_name