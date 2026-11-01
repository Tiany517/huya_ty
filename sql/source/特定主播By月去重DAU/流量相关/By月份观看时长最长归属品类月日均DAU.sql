-- ============================================================
-- 指标：观看时长最长归属品类的 月日均用户数（纵表，月份做行）
-- 表：  gamelive.dwt_huya_ayyuid_session_from_server_with_user
-- 引擎：Spark（沿用参考 SQL 的 Spark 写法）
-- 时间窗：2025-01-01 至 2026-07-28（7月统计至28日，受分区限制）
-- 归属口径：用户当天在各品类的 sum(user_duration)，取时长最长的品类为当天归属品类；
--          时长并列时按 igameid 升序取小（沿用 4月份用户回流后7日观时.sql 的口径）。
-- 月日均分母：该月在 tag='gameid' and htime='session' 下实际有数据的天数（count distinct dt）。
-- 说明：sgamename 直接取自源表，同一 igameid 若存在名称变体会拆成多行，保留明细便于复盘。
-- ============================================================

-- 每月在 tag='gameid'/htime='session' 下实际有数据的天数（月日均分母）
with month_days as (
  select
    substr(a.dt, 1, 7) as month,
    count(distinct a.dt) as observed_days
  from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
  where a.dt between '2025-01-01' and '2026-07-28'
    and a.tag = 'gameid'
    and a.htime = 'session'
  group by
    substr(a.dt, 1, 7)
),

-- 用户当天在每个品类的总观看时长（去重前，先按 天+用户+品类 聚合时长）
user_day_game_dur as (
  select
    a.dt,
    substr(a.dt, 1, 7) as month,
    a.user_ukey,
    a.igameid as game_id,
    a.sgamename as game_name,
    sum(a.user_duration) as user_duration
  from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
  where a.dt between '2025-01-01' and '2026-07-28'
    and a.tag = 'gameid'
    and a.htime = 'session'
    and a.user_ukey is not null
    and a.igameid is not null
  group by
    a.dt,
    substr(a.dt, 1, 7),
    a.user_ukey,
    a.igameid,
    a.sgamename
),

-- 用户当天归属品类：时长最长，并列取 igameid 小（每个用户每天只保留一个归属品类）
user_day_main_game as (
  select
    dt,
    month,
    user_ukey,
    game_id,
    game_name
  from (
    select
      dt,
      month,
      user_ukey,
      game_id,
      game_name,
      row_number() over (partition by dt, user_ukey order by user_duration desc, game_id) as rnk
    from user_day_game_dur
  ) t
  where rnk = 1
),

-- 每天每个归属品类的去重用户数（用户每天只归属一个品类，此处即归属该品类的用户数）
game_day_dau as (
  select
    dt,
    month,
    game_id,
    game_name,
    count(distinct user_ukey) as daily_dau
  from user_day_main_game
  group by
    dt,
    month,
    game_id,
    game_name
),

-- 按月计算日均：该品类各天归属用户数之和 / 该月实际有数据天数
game_month_dau as (
  select
    d.month,
    d.game_id,
    d.game_name,
    sum(d.daily_dau) * 1.0000 / max(m.observed_days) as avg_daily_dau
  from game_day_dau d
  left join month_days m
    on d.month = m.month
  group by
    d.month,
    d.game_id,
    d.game_name
)

select
  month,
  game_id,
  game_name,
  avg_daily_dau
from game_month_dau
order by
  month,
  avg_daily_dau desc
