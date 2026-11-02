-- ========================================
-- 2024/25赛季：视频偏好与长期留存关系分析
-- 探究上海大师赛拉新用户中，视频/娱乐视频消费是否与长期留存正相关
-- 
-- 2024年上海大师赛(邀请赛)比赛日期：2024.07.15-21
-- 2025年世锦赛比赛日期：2025.04.18-05.04（长期留存观察点）
-- ========================================

with match_info as ( -- 找出上海大师赛(邀请赛)的比赛信息，主要是为了找到播过斯诺克赛事的主播
  select distinct
    dt
    ,match_year
    ,live_type
    ,room_type
    ,game_id
    ,match_id
    ,match_name
    ,uid as luid
    ,day
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt='2026-05-12'  -- 用最新的日期分区
    and day>='2025-07-28'
    and day<='2025-08-03'  -- 上海大师赛(邀请赛)的比赛日期：2024.07.15-21
    -- and match_name like '%斯诺克%'
)
-- 要找到的是通过哪一位主播拉新的，所以要找到播过斯诺克赛事的主播，而不是直接将斯诺克赛事和拉新用户进行关联
, luid_info as( 
  select distinct
    a.dt
    ,b.luid
    ,a.ukey
  from zhgametemp.cwq_huya_ukey_shichang_luid_gameid_guishu_day_v1 a -- 日时长归因底表，找出用户单日观看最长时长的主播
  inner join match_info as b
  on 
    a.luid = b.luid
    and a.dt = b.day -- 如果是看赛事的话，记得把日期对上，才会归到赛事日上，主播关联的话，不代表赛事日的主播的用户，而是单纯的主播的用户
  where 
    a.dt between '2025-07-28' and '2025-08-03' -- 上海大师赛(邀请赛)的比赛日期：2024.07.15-21
    and a.nick like '%斯诺克%'
) 
, acquisition_user_info as -- 拉新用户表，找出在上海大师赛(邀请赛)期间被主播拉新的用户
(
  select distinct
    a.user_ukey 
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a -- 拉新用户表
  inner join match_info as b
    on a.dt = b.day
  and a.game_id = b.game_id
    -- 要增加关联的主播ID，参考之前
  inner join luid_info c
    on a.user_ukey = c.ukey
  where 
    a.dt between '2024-07-15' and '2024-07-21'  -- 上海大师赛(邀请赛)拉新日期：2024.07.15-21
)
-- ========================================
-- 上海大师赛期间观看行为（起点：视频偏好定义）
-- ========================================
, shanghai_behavior as (
  select
    a.user_ukey,
    -- 视频观看指标（所有视频）
    sum(case when b.live_content_type = '视频' then coalesce(b.watch_cnt, 0) else 0 end) as video_watch_vv,
    sum(case when b.live_content_type = '视频' then coalesce(b.watch_duration, 0) else 0 end)/60000 as video_watch_min,
    -- 娱乐专区视频观看指标
    sum(case when b.live_content_type = '视频' and b.game_label = '娱乐专区' then coalesce(b.watch_cnt, 0) else 0 end) as ent_video_watch_vv,
    sum(case when b.live_content_type = '视频' and b.game_label = '娱乐专区' then coalesce(b.watch_duration, 0) else 0 end)/60000 as ent_video_watch_min,
    sum(case when b.live_content_type = '视频' and b.game_label = '娱乐' then coalesce(b.watch_cnt, 0) else 0 end) as entertainment_video_watch_vv,
    sum(case when b.live_content_type = '视频' and b.game_label = '娱乐' then coalesce(b.watch_duration, 0) else 0 end)/60000 as entertainment_video_watch_min,
    -- 总观看指标（视频+直播）
    sum(coalesce(b.watch_cnt, 0)) as total_watch_vv,
    sum(coalesce(b.watch_duration, 0))/60000 as total_watch_min
  from acquisition_user_info a
  inner join gamelive.dws_huya_user_behavior_d_i b
    on a.user_ukey = b.user_ukey 
    and b.dt between '2024-07-15' and '2024-07-21' --上海新用户的观看行为观察期：2024.07.15-21
    and b.data_type in ('live_watch_session') -- 视频和直播
    and live_content_type = '视频'
    and is_black_ukey = 0 -- 去除黑名单用户
    and b.product in ('huya_andriod','huya_ipad','huya_pad','huya_ios') -- app端
  group by a.user_ukey
)
-- ========================================
-- 各阶段留存判断（0/1标记）
-- ========================================
, england_retention as ( -- 英格兰公开赛留存（短期）
  select distinct a.user_ukey, 1 as is_retained
  from acquisition_user_info a
  inner join gamelive.dws_huya_active_product_ukey_info_withsdk_d_i b
    on a.user_ukey = b.user_ukey 
  where b.dt between '2024-09-16' and '2024-09-22'
)
, uk_retention as ( -- 英锦赛留存（中期）
  select distinct a.user_ukey, 1 as is_retained
  from acquisition_user_info a
  inner join gamelive.dws_huya_active_product_ukey_info_withsdk_d_i b
    on a.user_ukey = b.user_ukey 
  where b.dt between '2024-11-23' and '2024-12-01'
)
, world_retention as ( -- 世锦赛留存（长期）
  select distinct a.user_ukey, 1 as is_retained
  from acquisition_user_info a
  inner join gamelive.dws_huya_active_product_ukey_info_withsdk_d_i b
    on a.user_ukey = b.user_ukey 
  where b.dt between '2025-04-18' and '2025-05-04'
)

-- ========================================
-- 输出：用户维度，视频偏好与留存关系
-- ========================================
select
  '2024/25赛季' as season,
  sb.user_ukey,
  
  -- 上海期间视频偏好指标
  sb.video_watch_vv,
  sb.video_watch_min,
  sb.ent_video_watch_vv,
  sb.ent_video_watch_min,
  sb.entertainment_video_watch_vv,
  sb.entertainment_video_watch_min,
  sb.total_watch_vv,
  sb.total_watch_min,
  
  -- 视频偏好标记（用于分组分析）
  case when sb.video_watch_min > 0 then 1 else 0 end as is_watch_video,
  case when sb.ent_video_watch_min > 0 then 1 else 0 end as is_watch_ent_video,
  case when sb.entertainment_video_watch_min > 0 then 1 else 0 end as is_watch_entertainment_video,
  
  -- 各阶段留存标记（0/1）
  coalesce(er.is_retained, 0) as is_england_retained,
  coalesce(ur.is_retained, 0) as is_uk_retained,
  coalesce(wr.is_retained, 0) as is_world_retained

from shanghai_behavior sb
left join england_retention er on sb.user_ukey = er.user_ukey
left join uk_retention ur on sb.user_ukey = ur.user_ukey
left join world_retention wr on sb.user_ukey = wr.user_ukey

