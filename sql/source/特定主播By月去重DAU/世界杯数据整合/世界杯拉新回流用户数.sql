with
-- ============================================================
-- 基础：世界杯内容观看
-- ============================================================
watch_world_cup_info as (
  select dt, user_ukey
  from (
    select dt, user_ukey, implicit_tags,
      row_number() over (partition by dt, user_ukey order by watch_duration desc) as rnk
    from (
      select dt, user_ukey, implicit_tags, sum(watch_duration) as watch_duration
      from gamelive.dws_huya_user_behavior_d_i
      where dt between '2026-06-12' and '2026-07-14'
        and product in ('huya_andriod', 'huya_ios', 'hmos_kiwi')
        and data_type in ('video_session', 'live_watch_session')
        and live_content_type in ('视频', '直播')
        and content_id <> 0 and vid_can_play = 1 and watch_cnt > 0
      group by dt, user_ukey, implicit_tags
    ) t1
  ) t2
  where rnk = 1
    and (implicit_tags like '%美加墨世界杯%' or implicit_tags like '%世界杯%')
),

-- ============================================================
-- 视频偏好
-- ============================================================
video_preference as (
  select v.dt, v.user_ukey
  from (
    select dt, user_ukey, sum(watch_duration) as video_watch_duration
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '2026-06-12' and '2026-07-14'
      and product in ('huya_andriod', 'huya_ios', 'hmos_kiwi')
      and data_type = 'video_session' and live_content_type = '视频'
      and content_id <> 0 and vid_can_play = 1 and watch_cnt > 0
      and (implicit_tags like '%美加墨世界杯%' or implicit_tags like '%世界杯%')
    group by dt, user_ukey
  ) v
  left join (
    select dt, user_ukey, sum(watch_duration) as live_watch_duration
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '2026-06-12' and '2026-07-14'
      and product in ('huya_andriod', 'huya_ios', 'hmos_kiwi')
      and data_type = 'live_watch_session' and live_content_type = '直播'
      and watch_cnt > 0
    group by dt, user_ukey
  ) l on v.dt = l.dt and v.user_ukey = l.user_ukey
  where v.video_watch_duration > coalesce(l.live_watch_duration, 0)
),

-- ============================================================
-- 拉新用户池
-- ============================================================
new_user_pool as (
  select a.dt, a.user_ukey, a.luid
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a
  where a.dt between '2026-06-12' and '2026-07-14'
    and a.guiyin_tag <> 'mailiang'
),

-- 直播拉新原始（未关联搜索）
live_new_raw as (
  select dt, user_ukey, 'live' as user_type
  from new_user_pool
  where luid in ('1239543466013','1239543466014','1531433300','1259527226795','585199800')

  union all

  select dt, user_ukey, 'live' as user_type
  from new_user_pool
  where dt between '2026-06-16' and '2026-06-17'
    and luid = '1199568157971'
),

-- 视频拉新原始（未关联搜索）
video_new_raw as (
  select n.dt, n.user_ukey, 'video' as user_type
  from new_user_pool n
  inner join video_preference p on n.dt = p.dt and n.user_ukey = p.user_ukey
),

-- ============================================================
-- 搜索拉新基表：live + video inner join 搜索表
-- ============================================================
search_new_base as (
  select a.dt, a.user_ukey, a.user_type, b.source
  from (
    select dt, user_ukey, user_type from live_new_raw
    union all
    select dt, user_ukey, user_type from video_new_raw
  ) a
  inner join zhgametemp.zty_huya_world_cup_actual_new_user_v4 b
    on a.user_ukey = b.ukey and a.dt = b.dt
),

-- ============================================================
-- 【核心】有效搜索拉新 = 主动搜索 + 被动搜索（含 watch_world_cup_info）
-- ============================================================
valid_search_new_user as (
  -- 主动搜索
  select distinct user_ukey, user_type
  from search_new_base
  where source in ('用户手动输入', '自发搜索')

  union

  -- 被动搜索
  select distinct a.user_ukey, a.user_type
  from search_new_base a
  inner join watch_world_cup_info c
    on a.dt = c.dt and a.user_ukey = c.user_ukey
  where a.source not in ('用户手动输入', '自发搜索')
),

-- 主动搜索（拉新用户级别，去重）
active_search_new_user as (
  select distinct user_ukey from valid_search_new_user
  where user_type in ('live', 'video')  -- 其实 valid_search_new_user 只有 live 和 video
),

-- 但我们还保留了原来的定义用于区分主动/被动
active_search_new_user_label as (
  select distinct user_ukey
  from search_new_base
  where source in ('用户手动输入', '自发搜索')
),

passive_search_new_user_label as (
  select distinct a.user_ukey
  from search_new_base a
  inner join watch_world_cup_info c
    on a.dt = c.dt and a.user_ukey = c.user_ukey
  where a.source not in ('用户手动输入', '自发搜索')
),

-- ============================================================
-- 直播拉新 / 视频拉新（仅从有效搜索中取）
-- ============================================================
live_new_user as (
  select user_ukey, 'live_new' as tag
  from valid_search_new_user
  where user_type = 'live'
),

video_new_user as (
  select user_ukey, 'video_new' as tag
  from valid_search_new_user
  where user_type = 'video'
),

-- ============================================================
-- 竞猜拉新（裂变 iinvedtype = 2）
-- ============================================================
bet_new_user as (
  select
    from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd') as dt,
    concat('mobile/', t.shuyadeviceid) as user_ukey,
    'bet_new' as tag
  from gamelive.dwd_huya_t_friendinvinfo_d_a t
  where t.dt = '2026-07-14'
    and from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd') between '2026-06-12' and '2026-07-14'
    and t.iscenetype1 = 0 and t.iscenetype2 = 7 and t.iinvedtype = 2
  group by from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd'), t.shuyadeviceid
),

-- ============================================================
-- 回流用户池
-- ============================================================
huiliu_user_pool as (
  select a.dt, a.user_ukey, a.luid
  from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1 a
  where a.dt between '2026-06-12' and '2026-07-14'
),

live_huiliu_user as (
  select dt, user_ukey, 'live_huiliu' as tag
  from huiliu_user_pool
  where luid in ('1239543466013','1239543466014','1531433300','1259527226795','585199800')

  union all

  select dt, user_ukey, 'live_huiliu' as tag
  from huiliu_user_pool
  where dt between '2026-06-16' and '2026-06-17'
    and luid = '1199568157971'
),

video_huiliu_user as (
  select h.dt, h.user_ukey, 'video_huiliu' as tag
  from huiliu_user_pool h
  inner join video_preference p on h.dt = p.dt and h.user_ukey = p.user_ukey
),

bet_huiliu_user as (
  select
    from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd') as dt,
    concat('mobile/', t.shuyadeviceid) as user_ukey,
    'bet_huiliu' as tag
  from gamelive.dwd_huya_t_friendinvinfo_d_a t
  inner join huiliu_user_pool h
    on concat('mobile/', t.shuyadeviceid) = h.user_ukey
    and from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd') = h.dt
  where t.dt = '2026-07-14'
    and from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd') between '2026-06-12' and '2026-07-14'
    and t.iscenetype1 = 0 and t.iscenetype2 = 7 and t.iinvedtype <> 2
  group by from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd'), t.shuyadeviceid
),

-- 裂变拉新（去重）
fission_new_user as (
  select distinct user_ukey from bet_new_user
),

-- ============================================================
-- 全量用户大宽表
-- ============================================================
all_user_union as (
  select user_ukey, tag from live_new_user
  union all
  select user_ukey, tag from video_new_user
  union all
  select user_ukey, tag from bet_new_user
  union all
  select user_ukey, tag from live_huiliu_user
  union all
  select user_ukey, tag from video_huiliu_user
  union all
  select user_ukey, tag from bet_huiliu_user
)



select
    count(distinct user_ukey) as total_new_user_cnt,
    count(distinct user_ukey)/32 as avg_user_cnt
from all_user_union