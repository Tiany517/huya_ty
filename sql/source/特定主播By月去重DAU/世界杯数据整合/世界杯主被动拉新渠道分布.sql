

with wactch_world_cup_info as (
  select
    dt,
    user_ukey,
    implicit_tags
  from (
    select
      dt,
      user_ukey,
      implicit_tags,
      row_number() over (partition by dt, user_ukey order by watch_duration desc) as rnk
    from (
      select
        dt,
        user_ukey,
        implicit_tags,
        sum(watch_duration) as watch_duration
      from gamelive.dws_huya_user_behavior_d_i
      where dt between '2026-06-12' and '2026-06-30'
        and product in ('huya_andriod','huya_ios','hmos_kiwi')
        and data_type in ('video_session', 'live_watch_session')
        and live_content_type in ('视频', '直播')
        and content_id <> 0
        and vid_can_play = 1
        and watch_cnt > 0
      group by dt, user_ukey,implicit_tags
    )
  )
  where rnk = 1 and (implicit_tags like '%美加墨世界杯%' or implicit_tags like '%世界杯%')
),
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
)

, laxin_tag as (
  select
    a.dt,
    a.user_ukey,
    'live' as user_type
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a
  where a.dt between '2026-06-12' and '2026-06-30'
    and a.guiyin_tag <> 'mailiang'
    and a.luid in (1239543466013,1239543466014,1531433300,1259527226795,585199800)
  
  union all

  select
    a.dt,
    a.user_ukey,
    'live' as user_type
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a
  where a.dt between '2026-06-16' and '2026-06-17'
    and a.guiyin_tag <> 'mailiang'
    and a.luid = 1199568157971 --童锦程只在16日和17日有直播
  
  union all

  select
    t1.dt,
    t1.user_ukey,
    'video' as user_type
  from (
    select
      a.dt,
      a.user_ukey
    from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a
    where a.dt between '2026-06-12' and '2026-06-30'
      and a.guiyin_tag <> 'mailiang'
  ) t1
  inner join video_preference p --看视频的是长要比任何直播都要长
    on t1.dt = p.dt and t1.user_ukey = p.user_ukey
)

, referral_user_info as (
  select 
    from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd') as dt 
    ,'[uid]worldcup_fission_active_new_user' as tag 
    ,concat('mobile/', shuyadeviceid) as user_ukey
    ,'裂变' as label
  from gamelive.dwd_huya_t_friendinvinfo_d_a t
  where t.dt = '2026-06-24'
    and from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd') between '2026-06-12' and '2026-06-30'
    and iscenetype1 = 0
    and iscenetype2 = 7 
    and iinvedtype = 2 --新用户
  group by from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd'),shuyadeviceid
)

,search_user_info as (
  select distinct
    a.dt,
    a.user_ukey,
    '主动搜索' as label
  from laxin_tag a
  inner join zhgametemp.zty_huya_world_cup_actual_new_user_v4 b 
    on a.user_ukey = b.ukey and a.dt = b.dt
  where
    a.dt between '2026-06-12' and '2026-06-30'
    and b.source in ('用户手动输入', '自发搜索')
  
  union all 

  select distinct 
    a.dt,
    a.user_ukey,
    '被动搜索' as label
  from laxin_tag a
  inner join zhgametemp.zty_huya_world_cup_actual_new_user_v4 b
    on a.dt = b.dt
    and a.user_ukey = b.ukey
  inner join wactch_world_cup_info c
    on a.dt = c.dt --当天观看时长最长为世界杯的内容
    and a.user_ukey = c.user_ukey
  where
    a.dt between '2026-06-12' and '2026-06-30'
    and b.source not in ('用户手动输入', '自发搜索')
)

select
  label,
  count(distinct user_ukey) as user_cnt
from (
  select
    dt,
    user_ukey,
    label
  from search_user_info

  union all 

  select
    dt,
    user_ukey,
    label
  from referral_user_info
)
group by label




