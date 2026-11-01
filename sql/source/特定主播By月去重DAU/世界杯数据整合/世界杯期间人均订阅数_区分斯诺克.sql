with
-- ============================================================
-- 斯诺克用户：赛事期间观时最长为体育 igameid=2356
-- 粒度：user_ukey
-- ============================================================
user_game_belongs as (
  select user_ukey
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
  where rnk = 1 and igameid = 2356
),

-- ============================================================
-- 直播回流
-- 粒度：dt + user_ukey
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

-- ============================================================
-- 全量回流用户池
-- 粒度：dt + user_ukey
-- ============================================================
all_huiliu_user as (
  select a.dt, a.user_ukey
  from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1 a
  where a.dt between '2026-06-12' and '2026-06-30'
),

-- ============================================================
-- 视频偏好：世界杯视频观看时长 > 直播观看时长
-- 粒度：dt + user_ukey
-- ============================================================
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
    where dt between '2026-06-12' and '2026-06-30'
      and product in ('huya_andriod','huya_ios','hmos_kiwi')
      and data_type = 'live_watch_session'
      and live_content_type = '直播'
      and watch_cnt > 0
    group by dt, user_ukey
  ) l
    on v.dt = l.dt and v.user_ukey = l.user_ukey
  where v.video_watch_duration > coalesce(l.live_watch_duration, 0)
),

-- ============================================================
-- 竞猜回流
-- 粒度：dt + user_ukey
-- ============================================================
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
    and iscenetype1 = 0
    and iscenetype2 = 7
    and iinvedtype <> 2
  group by from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd'), shuyadeviceid
),

-- ============================================================
-- 核心：回流用户 + 斯诺克标记
-- 粒度：dt + user_ukey
-- ============================================================
huiliu_base as (
  select distinct
    dt,
    t1.user_ukey,
    case when t2.user_ukey is not null then 1 else 0 end as is_overlap
  from (
    select dt, user_ukey from live_huiliu
    union
    select alu.dt, alu.user_ukey
    from all_huiliu_user alu
    inner join video_preference p
      on alu.dt = p.dt and alu.user_ukey = p.user_ukey
    union
    select dt, user_ukey from betting_huiliu
  ) t1
  left join user_game_belongs t2
    on t1.user_ukey = t2.user_ukey
),

-- ============================================================
-- 用户订阅映射（统一 6.12~6.30）
-- 粒度：ukey + ayyuid
-- ============================================================
user_subscribe_map as (
  select distinct
    b.ukey,
    a.ayyuid
  from gamelive.dwd_huya_dy_user a
  join zhgametemp.lj_dim_ukey_yyuid b
    on a.yyuid = b.yyuid
  where length(a.dt) = 10
    and a.dt >= '2026-06-12'
    and a.dt <= '2026-06-30'
    and a.tag = 'huya'
),

-- ============================================================
-- 回流用户订阅明细
-- 粒度：dt + user_ukey + ayyuid
-- ============================================================
huiliu_subscribe as (
  select distinct
    h.dt,
    h.user_ukey,
    h.is_overlap,
    m.ayyuid
  from huiliu_base h
  inner join user_subscribe_map m
    on h.user_ukey = m.ukey
),

-- ============================================================
-- 每个回流用户的订阅数
-- 粒度：dt + user_ukey
-- ============================================================
user_subscribe_cnt as (
  select
    dt,
    user_ukey,
    is_overlap,
    count(distinct ayyuid) as subscribe_cnt
  from huiliu_subscribe
  group by dt, user_ukey, is_overlap
)

select
  -- 整体回流人数
  count(distinct user_ukey) as huiliu_user_cnt,

  -- 整体订阅主播总数
  sum(subscribe_cnt) as total_subscribe_cnt,

  -- 整体人均订阅数
  sum(subscribe_cnt) / nullif(count(distinct user_ukey), 0) as total_avg_subscribe_cnt,

  -- 斯诺克回流人数
  count(distinct case when is_overlap = 1 then user_ukey end) as snooker_user_cnt,

  -- 斯诺克订阅主播总数
  sum(case when is_overlap = 1 then subscribe_cnt else 0 end) as snooker_subscribe_cnt,

  -- 斯诺克人均订阅数
  sum(case when is_overlap = 1 then subscribe_cnt else 0 end)
    / nullif(count(distinct case when is_overlap = 1 then user_ukey end), 0) as snooker_avg_subscribe_cnt,

  -- 非斯诺克回流人数
  count(distinct case when is_overlap = 0 then user_ukey end) as not_snooker_user_cnt,

  -- 非斯诺克订阅主播总数
  sum(case when is_overlap = 0 then subscribe_cnt else 0 end) as not_snooker_subscribe_cnt,

  -- 非斯诺克人均订阅数
  sum(case when is_overlap = 0 then subscribe_cnt else 0 end)
    / nullif(count(distinct case when is_overlap = 0 then user_ukey end), 0) as not_snooker_avg_subscribe_cnt

from user_subscribe_cnt