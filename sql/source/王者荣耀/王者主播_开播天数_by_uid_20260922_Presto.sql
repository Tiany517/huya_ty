-- ============================================================
-- 王者主播「开播天数」by uid（Presto 版；Spark 版见同目录不带 _Presto 的文件）
--
-- 口径：主播自开播第一天起至 2026-09-22 的开播天数
--      不剔赛事日、不剔短播日、不做任何过滤，只要求当天真的开播（live_mins > 0）
--      起始时间不设下限，取 dm_huya_ayyuid_detail_day 里该主播最早的开播日
--      （如果这张表本身只有近几年分区，那首播日 = 表内最早开播日）
--
-- 输出粒度：主播 uid 一行（不是主播 × 日），可直接和主 SQL 的「主播uid」做 XLOOKUP
--
-- 两套口径一起给：
--   1. 王者开播天数 / 王者首播日 / 王者最近开播日 = 限 gameid = 2336
--   2. 全品类开播天数 / 全品类首播日            = 不限 gameid（不需要可整列删掉）
--
-- 性能说明：这里要把目标主播的全部历史分区扫一遍，已经用 target_anchor 把范围收敛到
--   「2026-06-01 ~ 2026-09-22 在王者有开播」的主播；如果只想要某个 uid，
--   直接在最后加 where 主播uid = xxx；如果想算全量主播（不做收敛），
--   把两个 CTE 里的 inner join target_anchor 去掉、再删掉 target_anchor 即可，但会慢很多。
-- ============================================================
with

-- 目标主播名单：2026-06-01 ~ 2026-09-22 在王者(gameid=2336)有开播的主播
target_anchor as (
  select distinct
    a.ayyuid as luid
  from gamelive.dm_huya_ayyuid_detail_day a
  where a.dt between '2026-06-01' and '2026-09-22'
    and a.gameid = 2336
    and a.live_mins > 0
),

-- 王者历史开播日：截至 2026-09-22，该主播每个有过王者开播的日期
-- 粒度：dt + luid
anchor_day_wzry as (
  select
    substr(a.dt, 1, 10) as dt,
    a.ayyuid as luid,
    max(a.nickname) as nickname
  from gamelive.dm_huya_ayyuid_detail_day a
  inner join target_anchor t
    on a.ayyuid = t.luid
  where a.dt <= '2026-09-22'
    and a.gameid = 2336
    and a.live_mins > 0
  group by
    substr(a.dt, 1, 10),
    a.ayyuid
),

-- 全品类历史开播日：截至 2026-09-22，不限 gameid
-- 粒度：dt + luid
anchor_day_allgame as (
  select
    substr(a.dt, 1, 10) as dt,
    a.ayyuid as luid
  from gamelive.dm_huya_ayyuid_detail_day a
  inner join target_anchor t
    on a.ayyuid = t.luid
  where a.dt <= '2026-09-22'
    and a.live_mins > 0
  group by
    substr(a.dt, 1, 10),
    a.ayyuid
),

-- 王者口径聚合到 uid
wzry_days as (
  select
    luid,
    max(nickname) as nickname,
    count(distinct dt) as wzry_live_days,
    min(dt) as wzry_first_dt,
    max(dt) as wzry_last_dt
  from anchor_day_wzry
  group by luid
),

-- 全品类口径聚合到 uid
allgame_days as (
  select
    luid,
    count(distinct dt) as allgame_live_days,
    min(dt) as allgame_first_dt
  from anchor_day_allgame
  group by luid
)

select
  w.luid as "主播uid",
  w.nickname as "主播昵称",
  w.wzry_live_days as "王者开播天数",
  w.wzry_first_dt as "王者首播日",
  w.wzry_last_dt as "王者最近开播日",
  date_diff('day', cast(w.wzry_first_dt as date), cast('2026-09-22' as date)) + 1 as "王者首播起自然日数",
  a.allgame_live_days as "全品类开播天数",
  a.allgame_first_dt as "全品类首播日"
from wzry_days w
left join allgame_days a
  on w.luid = a.luid
order by
  w.wzry_live_days desc,
  w.luid;





