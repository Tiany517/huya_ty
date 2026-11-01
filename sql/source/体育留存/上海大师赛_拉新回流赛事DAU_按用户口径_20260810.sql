-- 目的：按用户给定 SQL 口径，对比 2025/2026 上海大师赛拉新、回流、赛事 DAU。
-- 赛事 DAU 口径：
--   1. 来源表：gamelive.dwt_huya_ayyuid_session_from_server_with_user。
--   2. 每日观看用户：dt + user_ukey 去重。
--   3. view_user_cnt：每日去重观看人数相加。
--   4. avg_view_user_cnt：view_user_cnt / view_observed_day，即赛事日均 DAU。
-- 端口径：APP 端，user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')。
-- 拉新口径：zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1，guiyin_tag <> 'mailiang'。
-- 回流口径：zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1。
-- 2025 上海大师赛主播范围：历史赛事主播日表 hss_huya_sport_movie_liveroom_register_info_d_a，
--   使用 dt='2026-07-30' 快照，并按 day 关联 2025-07-28 至 2025-08-03。
-- 2026 上海大师赛主播范围：zhgametemp.zty_snooker_shanghai_master_2026，展开到 2026-07-27 至 2026-08-02。
-- 执行记录：bigdata MCP Presto，rid=1206948154739182592。

with match_dates as (
  select '2025上海大师赛' as match_name, '2025-07-28' as dt
  union all select '2025上海大师赛', '2025-07-29'
  union all select '2025上海大师赛', '2025-07-30'
  union all select '2025上海大师赛', '2025-07-31'
  union all select '2025上海大师赛', '2025-08-01'
  union all select '2025上海大师赛', '2025-08-02'
  union all select '2025上海大师赛', '2025-08-03'
  union all select '2026上海大师赛', '2026-07-27'
  union all select '2026上海大师赛', '2026-07-28'
  union all select '2026上海大师赛', '2026-07-29'
  union all select '2026上海大师赛', '2026-07-30'
  union all select '2026上海大师赛', '2026-07-31'
  union all select '2026上海大师赛', '2026-08-01'
  union all select '2026上海大师赛', '2026-08-02'
),
luid_list as (
  select distinct
    d.match_name,
    d.dt,
    cast(r.uid as varchar) as luid
  from match_dates d
  inner join zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a r
    on d.dt = r.day
  where d.match_name = '2025上海大师赛'
    and r.dt = '2026-07-30'

  union

  select distinct
    d.match_name,
    d.dt,
    cast(a.luid as varchar) as luid
  from match_dates d
  inner join zhgametemp.zty_snooker_shanghai_master_2026 a
    on d.match_name = '2026上海大师赛'
),
sinuoke_laxin_user_info as (
  select distinct
    a.match_name,
    b.dt,
    b.label,
    b.user_ukey
  from luid_list a
  inner join (
    select
      dt,
      cast(luid as varchar) as luid,
      user_ukey,
      '拉新' as label
    from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
    where (
        dt between '2025-07-28' and '2025-08-03'
        or dt between '2026-07-27' and '2026-08-02'
      )
      and guiyin_tag <> 'mailiang'

    union all

    select
      dt,
      cast(luid as varchar) as luid,
      user_ukey,
      '回流' as label
    from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1
    where (
        dt between '2025-07-28' and '2025-08-03'
        or dt between '2026-07-27' and '2026-08-02'
      )
  ) b
    on a.dt = b.dt
   and a.luid = b.luid
),
view_user_info as (
  select distinct
    a.match_name,
    b.dt,
    b.user_ukey
  from luid_list a
  inner join gamelive.dwt_huya_ayyuid_session_from_server_with_user b
    on a.dt = b.dt
   and a.luid = cast(b.luid as varchar)
  where (
      b.dt between '2025-07-28' and '2025-08-03'
      or b.dt between '2026-07-27' and '2026-08-02'
    )
    and b.tag = 'gameid'
    and b.htime = 'session'
    and b.user_product in (
      'huya_andriod',
      'huya_ipad',
      'huya_pad',
      'huya_ios',
      'hmos_kiwi'
    )
    and b.user_ukey is not null
),
user_data as (
  select
    match_name,
    count(distinct dt) as observed_day,
    sum(laxin_huiliu_user_cnt) as laxin_huiliu_user_cnt,
    sum(laxin_user_cnt) as laxin_user_cnt,
    sum(huiliu_user_cnt) as huiliu_user_cnt
  from (
    select
      match_name,
      dt,
      count(distinct user_ukey) as laxin_huiliu_user_cnt,
      count(distinct case when label = '拉新' then user_ukey end) as laxin_user_cnt,
      count(distinct case when label = '回流' then user_ukey end) as huiliu_user_cnt
    from sinuoke_laxin_user_info
    group by match_name, dt
  ) t
  group by match_name
),
view_data as (
  select
    match_name,
    sum(view_user_cnt) as view_user_cnt,
    count(distinct dt) as view_observed_day
  from (
    select
      match_name,
      dt,
      count(distinct user_ukey) as view_user_cnt
    from view_user_info
    group by match_name, dt
  ) t
  group by match_name
)
select
  coalesce(u.match_name, v.match_name) as match_name,
  u.observed_day,
  u.laxin_huiliu_user_cnt,
  u.laxin_user_cnt,
  u.huiliu_user_cnt,
  u.laxin_huiliu_user_cnt * 1.0000 / u.observed_day as avg_laxin_huiliu_user_cnt,
  u.laxin_user_cnt * 1.0000 / u.observed_day as avg_laxin_user_cnt,
  u.huiliu_user_cnt * 1.0000 / u.observed_day as avg_huiliu_user_cnt,
  v.view_observed_day,
  v.view_user_cnt,
  v.view_user_cnt * 1.0000 / v.view_observed_day as avg_view_user_cnt
from user_data u
full outer join view_data v
  on u.match_name = v.match_name
order by match_name;
