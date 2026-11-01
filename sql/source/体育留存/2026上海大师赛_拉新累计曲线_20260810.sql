-- 目的：验证斯诺克赛事拉新是否进入平台期。
-- 核心口径：
-- 1. 拉新用户来自 zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1。
-- 2. 仅保留 guiyin_tag = 'shichang'。
-- 3. 用户去重粒度为 user_ukey。
-- 4. 累计拉新按赛事内 user_ukey 首次出现日期累计去重，不直接累加每日拉新 DAU。
-- 5. 2026上海大师赛主播范围沿用用户提供 SQL 中的 zhgametemp.zty_snooker_shanghai_master_2026。

-- Query 1：2026上海大师赛日累计拉新曲线
with match_dates as (
  -- 生成完整赛事日期，避免无拉新日期被漏掉。
  select '2026上海大师赛' as match_name, '2026-07-27' as dt, 1 as match_day_no
  union all select '2026上海大师赛', '2026-07-28', 2
  union all select '2026上海大师赛', '2026-07-29', 3
  union all select '2026上海大师赛', '2026-07-30', 4
  union all select '2026上海大师赛', '2026-07-31', 5
  union all select '2026上海大师赛', '2026-08-01', 6
  union all select '2026上海大师赛', '2026-08-02', 7
),
match_luid_day as (
  -- 赛事主播范围：沿用用户提供的 2026 上海大师赛主播名单，并展开到赛事每天。
  select distinct
    d.match_name,
    d.dt,
    cast(a.luid as varchar) as luid
  from match_dates d
  inner join zhgametemp.zty_snooker_shanghai_master_2026 a
    on 1 = 1
),
laxin_event_user_day as (
  -- 赛事每日拉新明细，保留 user_ukey 日期粒度，用于计算日去重、滚动去重和累计去重。
  select distinct
    m.match_name,
    m.dt,
    b.user_ukey
  from match_luid_day m
  inner join zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 b
    on m.dt = b.dt
   and m.luid = b.luid
  where b.dt between '2026-07-27' and '2026-08-02'
    and b.guiyin_tag in ('shichang')
    and b.user_ukey is not null
),
laxin_user_first as (
  -- 赛事内每个拉新用户首次归因日期，用于累计去重曲线。
  select
    match_name,
    user_ukey,
    min(dt) as first_laxin_dt
  from laxin_event_user_day
  group by
    match_name,
    user_ukey
),
daily_laxin as (
  select
    d.match_name,
    d.dt,
    d.match_day_no,
    count(distinct m.luid) as daily_event_luid_cnt,
    count(distinct l.user_ukey) as daily_laxin_user_cnt
  from match_dates d
  left join match_luid_day m
    on d.match_name = m.match_name
   and d.dt = m.dt
  left join laxin_event_user_day l
    on d.match_name = l.match_name
   and d.dt = l.dt
  group by
    d.match_name,
    d.dt,
    d.match_day_no
),
daily_new_laxin as (
  select
    d.match_name,
    d.dt,
    count(distinct f.user_ukey) as daily_new_laxin_user_cnt
  from match_dates d
  left join laxin_user_first f
    on d.match_name = f.match_name
   and d.dt = f.first_laxin_dt
  group by
    d.match_name,
    d.dt
),
rolling_laxin as (
  select
    d.match_name,
    d.dt,
    count(distinct case
      when l.dt between date_format(date_add('day', -2, cast(d.dt as date)), '%Y-%m-%d') and d.dt
      then l.user_ukey
    end) as rolling_3d_laxin_user_cnt,
    count(distinct case
      when l.dt between date_format(date_add('day', -6, cast(d.dt as date)), '%Y-%m-%d') and d.dt
      then l.user_ukey
    end) as rolling_7d_laxin_user_cnt
  from match_dates d
  left join laxin_event_user_day l
    on d.match_name = l.match_name
   and l.dt between date_format(date_add('day', -6, cast(d.dt as date)), '%Y-%m-%d') and d.dt
  group by
    d.match_name,
    d.dt
),
daily_view as (
  -- 当日赛事观看 UV：作为曝光/承接强度的辅助观察指标。
  select
    m.match_name,
    m.dt,
    count(distinct s.user_ukey) as daily_view_user_cnt
  from match_luid_day m
  inner join gamelive.dwt_huya_ayyuid_session_from_server_with_user s
    on m.dt = s.dt
   and m.luid = cast(s.luid as varchar)
  where s.dt between '2026-07-27' and '2026-08-02'
    and s.tag = 'gameid'
    and s.htime = 'session'
    and s.user_product in (
      'huya_andriod',
      'huya_ipad',
      'huya_pad',
      'huya_ios',
      'hmos_kiwi'
    )
    and s.user_ukey is not null
  group by
    m.match_name,
    m.dt
),
final_daily as (
  select
    a.match_name,
    a.dt,
    a.match_day_no,
    a.daily_event_luid_cnt,
    coalesce(v.daily_view_user_cnt, 0) as daily_view_user_cnt,
    a.daily_laxin_user_cnt,
    coalesce(r.rolling_3d_laxin_user_cnt, 0) as rolling_3d_laxin_user_cnt,
    coalesce(r.rolling_7d_laxin_user_cnt, 0) as rolling_7d_laxin_user_cnt,
    coalesce(n.daily_new_laxin_user_cnt, 0) as daily_new_laxin_user_cnt,
    sum(coalesce(n.daily_new_laxin_user_cnt, 0)) over (
      partition by a.match_name
      order by a.dt
      rows between unbounded preceding and current row
    ) as cumulative_distinct_laxin_user_cnt,
    max(a.daily_laxin_user_cnt) over (
      partition by a.match_name
      order by a.dt
      rows between unbounded preceding and current row
    ) as peak_daily_laxin_user_cnt_to_date
  from daily_laxin a
  left join daily_new_laxin n
    on a.match_name = n.match_name
   and a.dt = n.dt
  left join rolling_laxin r
    on a.match_name = r.match_name
   and a.dt = r.dt
  left join daily_view v
    on a.match_name = v.match_name
   and a.dt = v.dt
)
select
  match_name as "赛事名称",
  dt as "日期",
  match_day_no as "赛事第N天",
  daily_event_luid_cnt as "当日赛事主播数",
  daily_view_user_cnt as "当日赛事观看UV",
  daily_laxin_user_cnt as "当日拉新用户数",
  rolling_3d_laxin_user_cnt as "近3日滚动去重拉新用户数",
  rolling_7d_laxin_user_cnt as "近7日滚动去重拉新用户数",
  daily_new_laxin_user_cnt as "当日新增拉新用户数_赛事内首次",
  cumulative_distinct_laxin_user_cnt as "累计去重拉新用户数",
  daily_new_laxin_user_cnt * 1.0000 / nullif(cumulative_distinct_laxin_user_cnt, 0) as "当日新增占累计比例",
  peak_daily_laxin_user_cnt_to_date as "截至当日单日拉新峰值",
  case
    when daily_laxin_user_cnt >= peak_daily_laxin_user_cnt_to_date then 1
    else 0
  end as "当日是否刷新单日峰值"
from final_daily
order by
  "日期";


-- Query 2：斯诺克历史各赛事日累计拉新曲线
-- 如只看重点赛事，可在最终 select 前加：where a.match_name = '2026上海大师赛'
with match_calendar as (
  select '2024上海大师赛' as match_name, '2024-07-15' as start_dt, '2024-07-21' as end_dt
  union all select '2024英国公开赛', '2024-08-30', '2024-09-07'
  union all select '2024武汉公开赛', '2024-09-16', '2024-09-22'
  union all select '2024国际锦标赛', '2024-09-23', '2024-09-29'
  union all select '2024北爱尔兰公开赛', '2024-10-06', '2024-10-12'
  union all select '2024英格兰公开赛', '2024-10-20', '2024-10-27'
  union all select '2024冠中冠', '2024-11-03', '2024-11-10'
  union all select '2024英锦赛', '2024-11-23', '2024-12-01'
  union all select '2024苏格兰公开赛', '2024-12-04', '2024-12-07'
  union all select '2025伦敦大师赛', '2025-01-12', '2025-01-19'
  union all select '2025德国大师赛', '2025-01-27', '2025-02-02'
  union all select '2025威尔士公开赛', '2025-02-10', '2025-02-16'
  union all select '2025球员锦标赛', '2025-02-24', '2025-03-02'
  union all select '2025巡回锦标赛', '2025-03-17', '2025-03-23'
  union all select '2025世锦赛资格赛', '2025-03-31', '2025-04-06'
  union all select '2025斯诺克世锦赛正赛', '2025-04-19', '2025-05-05'
  union all select '2025上海大师赛', '2025-07-28', '2025-08-03'
  union all select '2025欧洲大师赛', '2025-08-24', '2025-08-30'
  union all select '2025英国公开赛', '2025-09-15', '2025-09-21'
  union all select '2025武汉公开赛', '2025-09-22', '2025-09-28'
  union all select '2025北爱尔兰公开赛', '2025-10-07', '2025-10-13'
  union all select '2025英格兰公开赛', '2025-10-19', '2025-10-26'
  union all select '2025冠中冠', '2025-11-02', '2025-11-09'
  union all select '2025英锦赛', '2025-11-29', '2025-12-07'
  union all select '2025苏格兰公开赛', '2025-12-10', '2025-12-13'
  union all select '2025大奖赛', '2025-12-15', '2025-12-21'
  union all select '2026伦敦大师赛', '2026-01-11', '2026-01-18'
  union all select '2026德国大师赛', '2026-01-26', '2026-02-01'
  union all select '2026威尔士公开赛', '2026-02-03', '2026-02-08'
  union all select '2026球员锦标赛', '2026-02-17', '2026-02-22'
  union all select '2026大奖赛', '2026-02-23', '2026-03-01'
  union all select '2026巡回锦标赛', '2026-03-16', '2026-03-22'
  union all select '2026世锦赛资格赛', '2026-03-30', '2026-04-05'
  union all select '2026斯诺克世锦赛正赛', '2026-04-18', '2026-05-06'
  union all select '2026上海大师赛', '2026-07-27', '2026-08-02'
),
match_dates as (
  -- 赛事日期维表。这里使用 unnest(sequence()) 是为了保留无拉新日期。
  select
    m.match_name,
    date_format(d.dt, '%Y-%m-%d') as dt,
    date_diff('day', cast(m.start_dt as date), d.dt) + 1 as match_day_no
  from match_calendar m
  cross join unnest(sequence(cast(m.start_dt as date), cast(m.end_dt as date))) as d(dt)
),
match_luid_day as (
  -- 历史赛事按附件 SQL 的赛事主播日表取 uid，并沿用附件中的 dt='2026-07-30' 快照；
  -- 2026上海大师赛按用户指定临时表补全主播名单。
  select distinct
    d.match_name,
    d.dt,
    r.uid as luid
  from match_dates d
  inner join zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a r
    on d.dt = r.day
  where r.dt = '2026-07-30'
    and d.match_name <> '2026上海大师赛'

  union

  select distinct
    d.match_name,
    d.dt,
    cast(a.luid as varchar) as luid
  from match_dates d
  inner join zhgametemp.zty_snooker_shanghai_master_2026 a
    on d.match_name = '2026上海大师赛'
),
laxin_event_user_day as (
  select distinct
    m.match_name,
    m.dt,
    b.user_ukey
  from match_luid_day m
  inner join zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 b
    on m.dt = b.dt
   and m.luid = b.luid
  where b.dt between '2024-07-15' and '2026-08-02'
    and b.guiyin_tag in ('shichang')
    and b.user_ukey is not null
),
laxin_user_first as (
  select
    match_name,
    user_ukey,
    min(dt) as first_laxin_dt
  from laxin_event_user_day
  group by
    match_name,
    user_ukey
),
daily_laxin as (
  select
    d.match_name,
    d.dt,
    d.match_day_no,
    count(distinct m.luid) as daily_event_luid_cnt,
    count(distinct l.user_ukey) as daily_laxin_user_cnt
  from match_dates d
  left join match_luid_day m
    on d.match_name = m.match_name
   and d.dt = m.dt
  left join laxin_event_user_day l
    on d.match_name = l.match_name
   and d.dt = l.dt
  group by
    d.match_name,
    d.dt,
    d.match_day_no
),
daily_new_laxin as (
  select
    d.match_name,
    d.dt,
    count(distinct f.user_ukey) as daily_new_laxin_user_cnt
  from match_dates d
  left join laxin_user_first f
    on d.match_name = f.match_name
   and d.dt = f.first_laxin_dt
  group by
    d.match_name,
    d.dt
),
rolling_laxin as (
  select
    d.match_name,
    d.dt,
    count(distinct case
      when l.dt between date_format(date_add('day', -2, cast(d.dt as date)), '%Y-%m-%d') and d.dt
      then l.user_ukey
    end) as rolling_3d_laxin_user_cnt,
    count(distinct case
      when l.dt between date_format(date_add('day', -6, cast(d.dt as date)), '%Y-%m-%d') and d.dt
      then l.user_ukey
    end) as rolling_7d_laxin_user_cnt
  from match_dates d
  left join laxin_event_user_day l
    on d.match_name = l.match_name
   and l.dt between date_format(date_add('day', -6, cast(d.dt as date)), '%Y-%m-%d') and d.dt
  group by
    d.match_name,
    d.dt
),
final_daily as (
  select
    a.match_name,
    a.dt,
    a.match_day_no,
    a.daily_event_luid_cnt,
    a.daily_laxin_user_cnt,
    coalesce(r.rolling_3d_laxin_user_cnt, 0) as rolling_3d_laxin_user_cnt,
    coalesce(r.rolling_7d_laxin_user_cnt, 0) as rolling_7d_laxin_user_cnt,
    coalesce(n.daily_new_laxin_user_cnt, 0) as daily_new_laxin_user_cnt,
    sum(coalesce(n.daily_new_laxin_user_cnt, 0)) over (
      partition by a.match_name
      order by a.dt
      rows between unbounded preceding and current row
    ) as cumulative_distinct_laxin_user_cnt,
    max(a.daily_laxin_user_cnt) over (
      partition by a.match_name
      order by a.dt
      rows between unbounded preceding and current row
    ) as peak_daily_laxin_user_cnt_to_date
  from daily_laxin a
  left join daily_new_laxin n
    on a.match_name = n.match_name
   and a.dt = n.dt
  left join rolling_laxin r
    on a.match_name = r.match_name
   and a.dt = r.dt
)
select
  match_name as "赛事名称",
  dt as "日期",
  match_day_no as "赛事第N天",
  daily_event_luid_cnt as "当日赛事主播数",
  daily_laxin_user_cnt as "当日拉新用户数",
  rolling_3d_laxin_user_cnt as "近3日滚动去重拉新用户数",
  rolling_7d_laxin_user_cnt as "近7日滚动去重拉新用户数",
  daily_new_laxin_user_cnt as "当日新增拉新用户数_赛事内首次",
  cumulative_distinct_laxin_user_cnt as "累计去重拉新用户数",
  daily_new_laxin_user_cnt * 1.0000 / nullif(cumulative_distinct_laxin_user_cnt, 0) as "当日新增占累计比例",
  peak_daily_laxin_user_cnt_to_date as "截至当日单日拉新峰值",
  case
    when daily_laxin_user_cnt >= peak_daily_laxin_user_cnt_to_date then 1
    else 0
  end as "当日是否刷新单日峰值"
from final_daily
order by
  "赛事名称",
  "日期";
