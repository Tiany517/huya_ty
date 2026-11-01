with
-- ============================================================
-- 斯诺克用户（赛事期间观时最长为体育 igameid=2356）
-- 粒度：user_ukey
-- ============================================================
user_game_belongs as (
  select user_ukey
  from (
    select user_ukey, igameid,
      row_number() over (partition by user_ukey order by user_duration desc, igameid) as rnk
    from (
      select
        a.user_ukey, a.igameid,
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
      group by a.user_ukey, a.igameid,
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

-- ============================================================
-- a 表：回流用户 + 回流日期 + 斯诺克标记
-- 粒度：dt + user_ukey（保留回流日期，用于留存计算）
-- ============================================================
huiliu_base as (
  select distinct
    dt,
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
),

-- ============================================================
-- 活跃用户表（天粒度）
-- 粒度：dt + user_ukey
-- ============================================================
user_active as (
  select dt, user_ukey
  from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
  where dt between '2026-06-12' and '2026-07-13'   -- 覆盖回流日 + 14天
    -- and product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
    and is_black_ukey = 0
  group by dt, user_ukey
)

-- ============================================================
-- 最终：留存率指标
-- ============================================================
select
  -- =====================
  -- 整体
  -- =====================
  count(distinct a.user_ukey) as huiliu_user_cnt,

  count(distinct case when d1.user_ukey is not null then a.user_ukey end) as day1_retention_cnt,
  count(distinct case when d1.user_ukey is not null then a.user_ukey end)
    / nullif(count(distinct a.user_ukey), 0) as day1_retention_rate,

  count(distinct case when d7.user_ukey is not null then a.user_ukey end) as day7_retention_cnt,
  count(distinct case when d7.user_ukey is not null then a.user_ukey end)
    / nullif(count(distinct a.user_ukey), 0) as day7_retention_rate,

  count(distinct case when d14.user_ukey is not null then a.user_ukey end) as day14_retention_cnt,
  count(distinct case when d14.user_ukey is not null then a.user_ukey end)
    / nullif(count(distinct a.user_ukey), 0) as day14_retention_rate,

  -- =====================
  -- 斯诺克
  -- =====================
  count(distinct case when a.is_overlap = 1 then a.user_ukey end) as snooker_user_cnt,

  count(distinct case when a.is_overlap = 1 and d1.user_ukey is not null then a.user_ukey end) as snooker_day1_retention_cnt,
  count(distinct case when a.is_overlap = 1 and d1.user_ukey is not null then a.user_ukey end)
    / nullif(count(distinct case when a.is_overlap = 1 then a.user_ukey end), 0) as snooker_day1_retention_rate,

  count(distinct case when a.is_overlap = 1 and d7.user_ukey is not null then a.user_ukey end) as snooker_day7_retention_cnt,
  count(distinct case when a.is_overlap = 1 and d7.user_ukey is not null then a.user_ukey end)
    / nullif(count(distinct case when a.is_overlap = 1 then a.user_ukey end), 0) as snooker_day7_retention_rate,

  count(distinct case when a.is_overlap = 1 and d14.user_ukey is not null then a.user_ukey end) as snooker_day14_retention_cnt,
  count(distinct case when a.is_overlap = 1 and d14.user_ukey is not null then a.user_ukey end)
    / nullif(count(distinct case when a.is_overlap = 1 then a.user_ukey end), 0) as snooker_day14_retention_rate,

  -- =====================
  -- 非斯诺克
  -- =====================
  count(distinct case when a.is_overlap = 0 then a.user_ukey end) as not_snooker_user_cnt,

  count(distinct case when a.is_overlap = 0 and d1.user_ukey is not null then a.user_ukey end) as not_snooker_day1_retention_cnt,
  count(distinct case when a.is_overlap = 0 and d1.user_ukey is not null then a.user_ukey end)
    / nullif(count(distinct case when a.is_overlap = 0 then a.user_ukey end), 0) as not_snooker_day1_retention_rate,

  count(distinct case when a.is_overlap = 0 and d7.user_ukey is not null then a.user_ukey end) as not_snooker_day7_retention_cnt,
  count(distinct case when a.is_overlap = 0 and d7.user_ukey is not null then a.user_ukey end)
    / nullif(count(distinct case when a.is_overlap = 0 then a.user_ukey end), 0) as not_snooker_day7_retention_rate,

  count(distinct case when a.is_overlap = 0 and d14.user_ukey is not null then a.user_ukey end) as not_snooker_day14_retention_cnt,
  count(distinct case when a.is_overlap = 0 and d14.user_ukey is not null then a.user_ukey end)
    / nullif(count(distinct case when a.is_overlap = 0 then a.user_ukey end), 0) as not_snooker_day14_retention_rate

from huiliu_base a

-- 次日留存：回流日+1天活跃
left join user_active d1
  on a.user_ukey = d1.user_ukey
  and d1.dt = date_add(a.dt, 1)

-- 7日留存：回流日+6天活跃（即回流后第7天）
left join user_active d7
  on a.user_ukey = d7.user_ukey
  and d7.dt = date_add(a.dt, 6)

-- 14日留存：回流日+13天活跃（即回流后第14天）
left join user_active d14
  on a.user_ukey = d14.user_ukey
  and d14.dt = date_add(a.dt, 13)