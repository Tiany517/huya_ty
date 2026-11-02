with match_info as (
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
  where dt='2026-04-29' 
    and day>='2026-04-01'
    and day<='2026-04-29'
    and match_name like '%斯诺克%'
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
    a.dt between '2026-04-01' and '2026-04-29'
    and a.nick like '%斯诺克%'
) 
, user_info as 
(
  select distinct
    a.user_ukey 
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a
  inner join match_info as b
    on a.dt = b.day
  and a.game_id = b.game_id
    -- 要增加关联的主播ID，参考之前
  inner join luid_info c
    on a.user_ukey = c.ukey
  where a.dt between '2026-04-01' and '2026-04-29'
)

select
    substr(a.dt, 1, 7) as year_month,  
    ·c.user_ukey,
    a.live_content_type,
    a.game_id,
    a.game_label,
    case 
      when a.live_content_type = '视频' then '视频' 
      else '非视频' 
    end as content_level,
    case 
      when a.live_content_type = '视频' and b.vid is not null then '赛事回放'
      when a.live_content_type = '视频' 
          and (a.vid_upload_type = 'live_record' or a.vid_create_channel in ('81','17')) then '主播回放'
      when a.live_content_type = '视频' then '普通'
      else '非视频'
    end as video_type,
    sum(coalesce(a.watch_cnt, 0)) as video_watch_vv,
    sum(coalesce(a.watch_valid_cnt, 0)) as valid_video_watch_cnt,
    sum(coalesce(a.watch_duration, 0))/60000 as video_watch_min 
from user_info c
left join gamelive.dws_huya_user_behavior_d_i a
    on c.user_ukey = a.user_ukey
    and a.dt >= '2026-04-01'
    and a.dt <= '2026-04-29'
    and a.data_type in ('video_session', 'live_watch_session') --只限制video即视频，live_watch即直播
    and a.product in ('huya_andriod','huya_ipad','huya_pad','huya_ios') --app端
left join (
    select vid
    from gamelive.dwd_hysp_match_video_replay_d_a
    where dt between '2026-04-01' and '2026-04-29'
    group by vid
) b 
    on a.content_id = b.vid
group by
    substr(a.dt, 1, 7),  
    c.user_ukey,
    a.live_content_type,
    a.game_id,
    a.game_label,
    case 
      when a.live_content_type = '视频' then '视频' 
      else '非视频' 
    end,
    case 
      when a.live_content_type = '视频' and b.vid is not null then '赛事回放'
      when a.live_content_type = '视频' 
          and (a.vid_upload_type = 'live_record' or a.vid_create_channel in ('81','17')) then '主播回放'
      when a.live_content_type = '视频' then '普通'
      else '非视频'
    end