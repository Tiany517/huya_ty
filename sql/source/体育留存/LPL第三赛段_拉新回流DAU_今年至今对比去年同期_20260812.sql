-- 目的：LPL 第三赛段进行中时，按“当前已进行天数”对比去年同期前 N 天。
-- 口径：
--   1. 今年取截至今天或赛段结束日的已发生天数。
--   2. 去年只取对应赛段前 N 天，N = 今年已发生天数。
--   3. 拉新/回流使用增量口径表：
--      zhgametemp.hss_huya_laxinhuiliu_consume_unified_value_match_day
--   4. DAU 使用赛事观看口径：gamelive.dwt_huya_ayyuid_session_from_server_with_user
--   5. 同比按同一赛段第 N 天对齐，不按自然日期对齐。
--   6. 结果同时输出日明细和累计值。
--
-- 需要你确认后再改成正式可跑版的两个地方：
--   A. 今年/去年 LPL 第三赛段的 match_id
--   B. 今年/去年赛段起止日期
-- 下面先按模板写成可替换骨架。

with event_cfg as (
  select
    '2026LPL第三赛段' as this_match_name,
    '2025LPL第三赛段' as base_match_name,
    cast(2026 as int) as this_year,
    cast(2025 as int) as base_year,
    '2026-01-01' as this_start_dt,
    '2026-12-31' as this_end_dt,
    '2025-01-01' as base_start_dt,
    '2025-12-31' as base_end_dt,
    0 as this_match_id,
    0 as base_match_id
),

event_cut as (
  select
    *,
    least(current_date, to_date(this_end_dt)) as this_cut_dt,
    datediff(least(current_date, to_date(this_end_dt)), to_date(this_start_dt)) + 1 as elapsed_day_cnt
  from event_cfg
),

day_map as (
  select
    '今年' as side,
    this_match_name as match_name,
    this_match_id as match_id,
    date_format(d, 'yyyy-MM-dd') as dt,
    pos + 1 as day_no
  from event_cut
  lateral view posexplode(
    sequence(to_date(this_start_dt), this_cut_dt)
  ) t as pos, d

  union all

  select
    '去年同期' as side,
    base_match_name as match_name,
    base_match_id as match_id,
    date_format(d, 'yyyy-MM-dd') as dt,
    pos + 1 as day_no
  from event_cut
  lateral view posexplode(
    sequence(
      to_date(base_start_dt),
      date_add(to_date(base_start_dt), elapsed_day_cnt - 1)
    )
  ) t as pos, d
),

laxin_huiliu_day as (
  select distinct
    b.day as dt,
    b.match_id,
    a.match_name,
    b.laxin_dau_zengliang,
    b.huiliu_dau_zengliang
  from event_cfg a
  inner join zhgametemp.hss_huya_laxinhuiliu_consume_unified_value_match_day b
    on a.this_match_id = b.match_id or a.base_match_id = b.match_id
  where b.dt = date_format(current_date, 'yyyy-MM-dd')
    and b.day between a.base_start_dt and a.this_end_dt
    and b.live_type like '%直播%'
),

daily_lh as (
  select
    m.side,
    m.match_name,
    m.day_no,
    m.dt,
    sum(coalesce(l.laxin_dau_zengliang, 0)) as daily_laxin_dau_zengliang,
    sum(coalesce(l.huiliu_dau_zengliang, 0)) as daily_huiliu_dau_zengliang
  from day_map m
  left join zhgametemp.hss_huya_laxinhuiliu_consume_unified_value_match_day l
    on m.match_id = l.match_id
   and m.dt = l.day
   and l.live_type like '%直播%'
   and l.dt = date_format(current_date, 'yyyy-MM-dd')
  group by
    m.side,
    m.match_name,
    m.day_no,
    m.dt
),

daily_view as (
  select
    m.side,
    m.match_name,
    m.day_no,
    m.dt,
    count(distinct s.user_ukey) as daily_view_user_cnt
  from day_map m
  inner join gamelive.dwt_huya_ayyuid_session_from_server_with_user s
    on m.dt = s.dt
  where s.tag = 'gameid'
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
    m.side,
    m.match_name,
    m.day_no,
    m.dt
),

daily_base as (
  select
    m.side,
    m.match_name,
    m.day_no,
    m.dt,
    coalesce(v.daily_view_user_cnt, 0) as daily_view_user_cnt,
    coalesce(l.daily_laxin_dau_zengliang, 0) as daily_laxin_dau_zengliang,
    coalesce(l.daily_huiliu_dau_zengliang, 0) as daily_huiliu_dau_zengliang
  from day_map m
  left join daily_view v
    on m.side = v.side
   and m.match_name = v.match_name
   and m.day_no = v.day_no
  left join daily_lh l
    on m.side = l.side
   and m.match_name = l.match_name
   and m.day_no = l.day_no
),

final_daily as (
  select
    *,
    sum(daily_view_user_cnt) over(partition by side, match_name order by day_no) as cum_view_uv,
    sum(daily_laxin_dau_zengliang) over(partition by side, match_name order by day_no) as cum_laxin_dau_zengliang,
    sum(daily_huiliu_dau_zengliang) over(partition by side, match_name order by day_no) as cum_huiliu_dau_zengliang
  from daily_base
),

this_final as (
  select * from final_daily where side = '今年'
),

base_final as (
  select * from final_daily where side = '去年同期'
)

select
  t.day_no as "赛段第N天",
  t.dt as "今年日期",
  t.daily_view_user_cnt as "今年日DAU",
  t.cum_view_uv as "今年累计DAU",
  t.daily_laxin_dau_zengliang as "今年日拉新增量",
  t.cum_laxin_dau_zengliang as "今年累计拉新增量",
  t.daily_huiliu_dau_zengliang as "今年日回流增量",
  t.cum_huiliu_dau_zengliang as "今年累计回流增量",

  b.dt as "去年同期日期",
  b.daily_view_user_cnt as "去年同期日DAU",
  b.cum_view_uv as "去年同期累计DAU",
  b.daily_laxin_dau_zengliang as "去年同期日拉新增量",
  b.cum_laxin_dau_zengliang as "去年同期累计拉新增量",
  b.daily_huiliu_dau_zengliang as "去年同期日回流增量",
  b.cum_huiliu_dau_zengliang as "去年同期累计回流增量",

  t.cum_view_uv * 1.0000 / nullif(b.cum_view_uv, 0) - 1 as "累计DAU同比",
  t.cum_laxin_dau_zengliang * 1.0000 / nullif(b.cum_laxin_dau_zengliang, 0) - 1 as "累计拉新同比",
  t.cum_huiliu_dau_zengliang * 1.0000 / nullif(b.cum_huiliu_dau_zengliang, 0) - 1 as "累计回流同比"
from this_final t
left join base_final b
  on t.day_no = b.day_no
order by t.day_no;
