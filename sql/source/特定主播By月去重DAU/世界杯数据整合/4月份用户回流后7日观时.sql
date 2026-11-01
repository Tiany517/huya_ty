with
-- ============================================================
-- 回流用户（4月份）
-- ============================================================
huiliu_user as (
  select distinct
    a.dt,
    a.user_ukey
  from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1 a
  where a.dt between '2026-04-01' and '2026-04-30'
),

-- ============================================================
-- 斯诺克用户：赛事期间观看时长最长为体育(igameid=2356)
-- ============================================================
sport_top_user as (
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
    and igameid = 2356
),

-- ============================================================
-- a 表：回流用户 + 回流日期 + 斯诺克标记
-- ============================================================
user_info as (
  select distinct
    h.dt,
    h.user_ukey,
    case when s.user_ukey is not null then 1 else 0 end as is_overlap
  from huiliu_user h
  left join sport_top_user s
    on h.user_ukey = s.user_ukey
)

-- ============================================================
-- 最终指标
-- ============================================================
select
  count(distinct a.user_ukey) as huiliu_user_cnt,
  count(distinct case when a.is_overlap = 1 then a.user_ukey end) as snooker_overlap_user_cnt,
  count(distinct case when a.is_overlap = 0 then a.user_ukey end) as not_snooker_user_cnt,

  sum(b.watch_duration) as total_7d_duration,
  sum(case when a.is_overlap = 1 then b.watch_duration else 0 end) as snooker_7d_duration,
  sum(case when a.is_overlap = 0 then b.watch_duration else 0 end) as not_snooker_7d_duration,

  sum(case when b.game_label = '体育' then b.watch_duration else 0 end) as sports_7d_duration,
  sum(case when b.game_label = '娱乐' then b.watch_duration else 0 end) as entertainment_7d_duration,
  sum(case when b.game_label = '游戏' then b.watch_duration else 0 end) as game_7d_duration,
  sum(case when b.game_label = '其他' then b.watch_duration else 0 end) as other_7d_duration,

  sum(case when a.is_overlap = 1 and b.game_label = '体育' then b.watch_duration else 0 end) as snooker_sports_7d_duration,
  sum(case when a.is_overlap = 1 and b.game_label = '娱乐' then b.watch_duration else 0 end) as snooker_entertainment_7d_duration,
  sum(case when a.is_overlap = 1 and b.game_label = '游戏' then b.watch_duration else 0 end) as snooker_game_7d_duration,
  sum(case when a.is_overlap = 1 and b.game_label = '其他' then b.watch_duration else 0 end) as snooker_other_7d_duration,

  sum(case when a.is_overlap = 0 and b.game_label = '体育' then b.watch_duration else 0 end) as not_snooker_sports_7d_duration,
  sum(case when a.is_overlap = 0 and b.game_label = '娱乐' then b.watch_duration else 0 end) as not_snooker_entertainment_7d_duration,
  sum(case when a.is_overlap = 0 and b.game_label = '游戏' then b.watch_duration else 0 end) as not_snooker_game_7d_duration,
  sum(case when a.is_overlap = 0 and b.game_label = '其他' then b.watch_duration else 0 end) as not_snooker_other_7d_duration,

  count(distinct case when b.game_label = '体育' then a.user_ukey end) as sports_user_cnt,
  count(distinct case when b.game_label = '娱乐' then a.user_ukey end) as entertainment_user_cnt,
  count(distinct case when b.game_label = '游戏' then a.user_ukey end) as game_user_cnt,
  count(distinct case when b.game_label = '其他' then a.user_ukey end) as other_user_cnt,

  count(distinct case when a.is_overlap = 1 and b.game_label = '体育' then a.user_ukey end) as snooker_sports_user_cnt,
  count(distinct case when a.is_overlap = 1 and b.game_label = '娱乐' then a.user_ukey end) as snooker_entertainment_user_cnt,
  count(distinct case when a.is_overlap = 1 and b.game_label = '游戏' then a.user_ukey end) as snooker_game_user_cnt,
  count(distinct case when a.is_overlap = 1 and b.game_label = '其他' then a.user_ukey end) as snooker_other_user_cnt,

  count(distinct case when a.is_overlap = 0 and b.game_label = '体育' then a.user_ukey end) as not_snooker_sports_user_cnt,
  count(distinct case when a.is_overlap = 0 and b.game_label = '娱乐' then a.user_ukey end) as not_snooker_entertainment_user_cnt,
  count(distinct case when a.is_overlap = 0 and b.game_label = '游戏' then a.user_ukey end) as not_snooker_game_user_cnt,
  count(distinct case when a.is_overlap = 0 and b.game_label = '其他' then a.user_ukey end) as not_snooker_other_user_cnt

from user_info a
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
  where dt between '2026-04-01' and '2026-05-07'
    and data_type in ('live_watch_session', 'video_session')
    and is_black_ukey = 0
    and product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
  group by dt, user_ukey,
    case
      when game_label in ('娱乐', '娱乐专区') and game_id = 2356 then '体育'
      when game_label in ('娱乐', '娱乐专区') then '娱乐'
      when game_label in ('游戏', '游戏专区') then '游戏'
      else '其他'
    end
) b
  on a.user_ukey = b.user_ukey
  and b.dt between a.dt and date_add(a.dt, 6)