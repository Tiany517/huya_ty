with
live_tag as (
  select
    a.dt,
    a.user_ukey
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a
  where a.dt between '2026-06-12' and '2026-06-30'
    and a.guiyin_tag <> 'mailiang'
    and a.luid in (1239543466013,1239543466014,1531433300,1259527226795,585199800)

  union all

  select
    a.dt,
    a.user_ukey
  from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1 a
  where a.dt between '2026-06-12' and '2026-06-30'
    and a.luid in (1239543466013,1239543466014,1531433300,1259527226795,585199800)

  union all

  select
    a.dt,
    a.user_ukey
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a
  where a.dt between '2026-06-16' and '2026-06-17' --固定日期
    and a.guiyin_tag <> 'mailiang'
    and a.luid = 1199568157971 --童锦程

  union all

  select
    a.dt,
    a.user_ukey
  from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1 a
  where a.dt between '2026-06-16' and '2026-06-17' --固定日期
    and a.luid = 1199568157971
),

all_laxin_user as (
  select
    a.dt,
    a.user_ukey
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a
  where a.dt between '2026-06-12' and '2026-06-30'
    and a.guiyin_tag <> 'mailiang'

  union all

  select
    a.dt,
    a.user_ukey
  from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1 a
  where a.dt between '2026-06-12' and '2026-06-30'
),

-- 视频观看时长 > 直播观看时长
video_preference as (
  select
    v.dt,
    v.user_ukey
  from (
    select
      dt,
      user_ukey,
      sum(watch_duration) as video_watch_duration
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '2026-06-12' and '2026-06-30'
      and product in ('huya_andriod','huya_ios','hmos_kiwi')
      and data_type = 'video_session'
      and live_content_type = '视频'
      and content_id <> 0
      and vid_can_play = 1
      and watch_cnt > 0
      and (implicit_tags like '%美加墨世界杯%' or implicit_tags like '%世界杯%')
    group by dt, user_ukey
  ) v
  left join (
    select
      dt,
      user_ukey,
      sum(watch_duration) as live_watch_duration
    from gamelive.dws_huya_user_behavior_d_i
    where  dt between '2026-06-12' and '2026-06-30'
      and product in ('huya_andriod','huya_ios','hmos_kiwi')
      and data_type = 'live_watch_session'
      and live_content_type = '直播'
      and watch_cnt > 0
    group by dt, user_ukey
  ) l
    on v.dt = l.dt and v.user_ukey = l.user_ukey
  where v.video_watch_duration > coalesce(l.live_watch_duration, 0) --看世界杯的视频要比看任何直播间视频长
),

betting_tag as (
  select 
    from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd') as dt 
    ,'[uid]worldcup_fission_active_user' as tag 
    , concat('mobile/', shuyadeviceid) as user_ukey
  from gamelive.dwd_huya_t_friendinvinfo_d_a t
  inner join (
    select
      a.dt,
      a.user_ukey
    from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1 a
    where a.dt between '2026-06-12' and '2026-06-30'
  ) b
    on concat('mobile/', shuyadeviceid) = b.user_ukey
    and from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd') = b.dt
  where t.dt = '2026-06-30'
    and from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd') between '2026-06-12' and '2026-06-30'
    and iscenetype1 = 0
    and iscenetype2 = 7 
    and iinvedtype <> 2
  group by from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd'),shuyadeviceid
  
  union all 
  -- 世界杯裂变新用户
  select 
    from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd') as dt 
    ,'[uid]worldcup_fission_active_new_user' as tag 
    ,concat('mobile/', shuyadeviceid) as user_ukey
  from gamelive.dwd_huya_t_friendinvinfo_d_a t
  where t.dt = '2026-06-30'
    and from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd') between '2026-06-12' and '2026-06-30'
    and iscenetype1 = 0
    and iscenetype2 = 7 
    and iinvedtype = 2 --新用户
  group by from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd'),shuyadeviceid
)




select
  count(distinct user_ukey) as dau,
  count(distinct case when label = 'live' then user_ukey end) as live_laxin_huiliu_dau,
  count(distinct case when label = 'video' then user_ukey end) as video_laxin_huiliu_dau,
  count(distinct case when label = 'bet' then user_ukey end) as betting_laxin_huiliu_dau
from (
  select
    dt,
    user_ukey,
    'live' as label
  from live_tag

  union all

  select
    alu.dt,
    alu.user_ukey,
    'video' as label
  from all_laxin_user alu
  inner join video_preference p
    on alu.dt = p.dt and alu.user_ukey = p.user_ukey

  union all 

  select
    dt,
    user_ukey,
    'bet' as label
  from betting_tag
) 