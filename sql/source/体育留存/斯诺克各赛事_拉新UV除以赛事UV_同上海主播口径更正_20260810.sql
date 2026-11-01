-- 目的：输出斯诺克各赛事的 拉新UV/赛事UV。
-- 指标定义：
--   拉新UV/赛事UV = 赛事期累计去重拉新 user_ukey / 赛事期累计去重观看 user_ukey。
--   注意：这里的赛事UV是赛事期累计去重UV，不是每日赛事DAU相加，也不是日均DAU。
--
-- 拉新口径：
--   zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
--   guiyin_tag <> 'mailiang'
--   赛事期内 user_ukey 去重
--
-- 赛事UV口径：
--   gamelive.dwt_huya_ayyuid_session_from_server_with_user
--   tag = 'gameid'
--   htime = 'session'
--   user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
--   user_ukey is not null
--   赛事期内 user_ukey 去重
--
-- 主播范围：
--   2025上海大师赛、2026上海大师赛：均使用 zhgametemp.zty_snooker_shanghai_master_2026 同一批 luid。
--   其他赛事：使用 zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a，
--             dt='2026-07-30' 快照，并按 day 关联赛事日期。
--
-- 执行方式：
--   Presto 全量任务因 per-node memory limit 失败。
--   最终使用 Spark 按年份拆分执行后本地合并。
--   2024 rid = 1206954927676115968
--   2025 rid = 1206954800519043072
--   2026 rid = 1206954661853711360
--
-- 复跑方式：
--   将下面 match_calendar 替换为对应年份赛事列表后执行；
--   2025/2026 的上海大师赛会自动使用 zty_snooker_shanghai_master_2026，
--   其他赛事使用历史赛事主播日表。

with match_calendar as (
  -- 示例：替换为需要复跑的年份赛事列表。
  select 17 as match_seq, '2025上海大师赛' as match_name, '2025-07-28' as start_dt, '2025-08-03' as end_dt
  union all select 35, '2026上海大师赛', '2026-07-27', '2026-08-02'
),
match_dates as (
  select
    m.match_seq,
    m.match_name,
    m.start_dt,
    m.end_dt,
    date_format(d.dt, 'yyyy-MM-dd') as dt
  from match_calendar m
  lateral view explode(sequence(to_date(m.start_dt), to_date(m.end_dt))) d as dt
),
luid_event_day as (
  select distinct
    d.match_seq,
    d.match_name,
    d.start_dt,
    d.end_dt,
    d.dt,
    cast(r.uid as string) as luid,
    '历史赛事主播日表' as luid_source
  from match_dates d
  join zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a r
    on d.dt = r.day
  where r.dt = '2026-07-30'
    and d.match_name not in ('2025上海大师赛', '2026上海大师赛')

  union

  select distinct
    d.match_seq,
    d.match_name,
    d.start_dt,
    d.end_dt,
    d.dt,
    cast(a.luid as string) as luid,
    'zty_2026上海大师赛主播名单' as luid_source
  from match_dates d
  join zhgametemp.zty_snooker_shanghai_master_2026 a
  where d.match_name in ('2025上海大师赛', '2026上海大师赛')
),
event_base as (
  select
    match_seq,
    match_name,
    start_dt,
    end_dt,
    datediff(to_date(end_dt), to_date(start_dt)) + 1 as observed_day,
    count(distinct luid) as event_luid_cnt,
    max(luid_source) as luid_source
  from luid_event_day
  group by
    match_seq,
    match_name,
    start_dt,
    end_dt
),
laxin_agg as (
  select
    m.match_seq,
    count(distinct b.user_ukey) as laxin_uv
  from luid_event_day m
  join zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 b
    on m.dt = b.dt
   and m.luid = cast(b.luid as string)
  where b.guiyin_tag <> 'mailiang'
    and b.user_ukey is not null
  group by
    m.match_seq
),
view_agg as (
  select
    m.match_seq,
    count(distinct b.user_ukey) as event_view_uv
  from luid_event_day m
  join gamelive.dwt_huya_ayyuid_session_from_server_with_user b
    on m.dt = b.dt
   and m.luid = cast(b.luid as string)
  where b.tag = 'gameid'
    and b.htime = 'session'
    and b.user_product in (
      'huya_andriod',
      'huya_ipad',
      'huya_pad',
      'huya_ios',
      'hmos_kiwi'
    )
    and b.user_ukey is not null
  group by
    m.match_seq
)
select
  b.match_seq,
  b.match_name,
  b.start_dt,
  b.end_dt,
  b.observed_day,
  b.event_luid_cnt,
  b.luid_source,
  coalesce(l.laxin_uv, 0) as laxin_uv,
  coalesce(v.event_view_uv, 0) as event_view_uv,
  coalesce(l.laxin_uv, 0) * 1.0000 / nullif(coalesce(v.event_view_uv, 0), 0) as laxin_uv_per_event_view_uv
from event_base b
left join laxin_agg l
  on b.match_seq = l.match_seq
left join view_agg v
  on b.match_seq = v.match_seq
order by
  b.match_seq;
