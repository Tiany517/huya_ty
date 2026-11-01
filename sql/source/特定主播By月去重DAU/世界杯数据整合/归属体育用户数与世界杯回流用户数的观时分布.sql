with user_game_belongs as (
    select 
        user_ukey
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
            group by
                a.user_ukey,
                a.igameid,
                case
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
    where rnk = 1 
      and igameid = 2356 -- 赛事期间观看时长最长为体育的用户（归属体育）
),

live_huiliu as (
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
  from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1 a
  where a.dt between '2026-06-16' and '2026-06-17'
    and a.luid = 1199568157971 --童锦程固定日期
),

all_huiliu_user as (
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

betting_huiliu as (
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
  ) b --与回流用户表内关联，表示回流用户
    on concat('mobile/', shuyadeviceid) = b.user_ukey
    and from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd') = b.dt
  where t.dt = '2026-06-30'
    and from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd') between '2026-06-12' and '2026-06-30'
    and iscenetype1 = 0
    and iscenetype2 = 7 
    and iinvedtype <> 2 -- 不是新用户
  group by from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd'),shuyadeviceid
)


select
  -- 1. 总去重人数
  count(distinct a.user_ukey) as total_user_cnt,

  -- 2. 体育斯诺克重合去重人数
  count(distinct case when a.is_overlap = 1 then a.user_ukey end) as snooker_overlap_user_cnt,

  -- 3. 非体育斯诺克去重人数
  count(distinct case when a.is_overlap = 0 then a.user_ukey end) as not_snooker_user_cnt,

  -- 7. 整体去重用户的观看时长
  sum(b.watch_duration) as total_watch_duration,

  -- 4. 所有去重用户的各品类观时
  sum(case when b.game_label = '体育' then b.watch_duration else 0 end) as all_sports_duration,
  sum(case when b.game_label = '娱乐' then b.watch_duration else 0 end) as all_entertainment_duration,
  sum(case when b.game_label = '游戏' then b.watch_duration else 0 end) as all_game_duration,
  sum(case when b.game_label = '其他' then b.watch_duration else 0 end) as all_other_duration,

  -- 5. 斯诺克重合用户的各品类观时
  sum(case when a.is_overlap = 1 and b.game_label = '体育' then b.watch_duration else 0 end) as snooker_sports_duration,
  sum(case when a.is_overlap = 1 and b.game_label = '娱乐' then b.watch_duration else 0 end) as snooker_entertainment_duration,
  sum(case when a.is_overlap = 1 and b.game_label = '游戏' then b.watch_duration else 0 end) as snooker_game_duration,
  sum(case when a.is_overlap = 1 and b.game_label = '其他' then b.watch_duration else 0 end) as snooker_other_duration,

  -- 6. 非斯诺克重合用户的各品类观时
  sum(case when a.is_overlap = 0 and b.game_label = '体育' then b.watch_duration else 0 end) as not_snooker_sports_duration,
  sum(case when a.is_overlap = 0 and b.game_label = '娱乐' then b.watch_duration else 0 end) as not_snooker_entertainment_duration,
  sum(case when a.is_overlap = 0 and b.game_label = '游戏' then b.watch_duration else 0 end) as not_snooker_game_duration,
  sum(case when a.is_overlap = 0 and b.game_label = '其他' then b.watch_duration else 0 end) as not_snooker_other_duration,

  -- 8. 所有去重用户的各品类观看人数
  count(distinct case when b.game_label = '体育' then a.user_ukey end) as all_sports_user_cnt,
  count(distinct case when b.game_label = '娱乐' then a.user_ukey end) as all_entertainment_user_cnt,
  count(distinct case when b.game_label = '游戏' then a.user_ukey end) as all_game_user_cnt,
  count(distinct case when b.game_label = '其他' then a.user_ukey end) as all_other_user_cnt,

  -- 9. 斯诺克重合用户的各品类观看人数
  count(distinct case when a.is_overlap = 1 and b.game_label = '体育' then a.user_ukey end) as snooker_sports_user_cnt,
  count(distinct case when a.is_overlap = 1 and b.game_label = '娱乐' then a.user_ukey end) as snooker_entertainment_user_cnt,
  count(distinct case when a.is_overlap = 1 and b.game_label = '游戏' then a.user_ukey end) as snooker_game_user_cnt,
  count(distinct case when a.is_overlap = 1 and b.game_label = '其他' then a.user_ukey end) as snooker_other_user_cnt,

  -- 10. 非斯诺克重合用户的各品类观看人数
  count(distinct case when a.is_overlap = 0 and b.game_label = '体育' then a.user_ukey end) as not_snooker_sports_user_cnt,
  count(distinct case when a.is_overlap = 0 and b.game_label = '娱乐' then a.user_ukey end) as not_snooker_entertainment_user_cnt,
  count(distinct case when a.is_overlap = 0 and b.game_label = '游戏' then a.user_ukey end) as not_snooker_game_user_cnt,
  count(distinct case when a.is_overlap = 0 and b.game_label = '其他' then a.user_ukey end) as not_snooker_other_user_cnt

from (
  -- 【修复】去重到 user_ukey 级别，去掉 label，避免 join 后观时翻倍
  select distinct
    t1.user_ukey,
    case when t2.user_ukey is not null then 1 else 0 end as is_overlap
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
    left join user_game_belongs t2
      on t1.user_ukey = t2.user_ukey
) a
left join (
  select
    dt,
    user_ukey,
    case
      when game_label in ('娱乐', '娱乐专区') and game_id = 2356 then '体育'
      when game_label in ('娱乐', '娱乐专区') then '娱乐'
      when game_label in ('游戏', '游戏专区') then '游戏'
      else '其他'
    end as game_label,
    sum(watch_duration) as watch_duration
  from gamelive.dws_huya_user_behavior_d_i
  where dt between '2026-06-12' and '2026-06-30'
    and product in ('huya_andriod', 'huya_ios', 'hmos_kiwi')
    and data_type in ('video_session', 'live_watch_session')
    and live_content_type in ('视频', '直播')
  group by dt, user_ukey,
    case
      when game_label in ('娱乐', '娱乐专区') and game_id = 2356 then '体育'
      when game_label in ('娱乐', '娱乐专区') then '娱乐'
      when game_label in ('游戏', '游戏专区') then '游戏'
      else '其他'
    end
) b
  on a.user_ukey = b.user_ukey