-- ============================================================
-- 王者荣耀「主播潜力」互动过程指标（Spark SQL）
--
-- 目的：王者荣耀品类大盘流量下滑，单看 DAU / 平均弹幕数会被大盘拖累，
--      因此改用过程 / 互动指标（发弹幕率、人均弹幕数、每分钟弹幕数、
--      人均观看时长、订阅、ACU / PCU、开播天数）识别有潜力的主播。
--
-- 观察窗口：2026-06-01 ~ 2026-09-22（赛事快照分区取 2026-09-22）
--
-- 三套天数口径（互不混用，输出里都带出来）：
--   1. 开播天数        = 主播自开播第一天起至 2026-09-22 的开播天数，
--                        不剔赛事日、不剔短播日、不做任何过滤，只要求 gameid=2336 且当天有开播；
--                        （若主播 6/1 之前就开播，这里是窗口内天数，需要全量历史把起始日期往前调）
--   2. 首播起自然日数  = 首次开播日到 2026-09-22 的自然日天数（含首尾），用于看「播龄」
--   3. 有效样本天数    = 剔除赛事日 + 剔除短播日（开播分钟 < 10）后剩下的天数，
--                        过程指标（发弹幕率、弹幕数、观看时长、订阅）都只统计这批日子
--   注：窗口 2026-06-01 ~ 2026-09-22 共 114 天，其中 69 天是王者版权赛事日。
--
-- 开播时长口径：不用 live_mins（该字段名是分钟、实际存小时），
--   改为 live_end_time - live_start_time；跨天场次（如 2026-09-21 23:59:56 ~ 2026-09-22 00:19:07）
--   会出现 end < start，此时按 +24 小时处理，避免负时长。
--
-- 输出粒度：
--   第一段（默认执行）= 主播 × 日 明细，便于逐日复盘 / 透视
--   第二段（已注释）= 主播级汇总，用于排名筛选；把第一段 select 整段替换即可
--
-- 指标口径：
--   1. 观众发弹幕率     = 当日发弹幕人数 / 当日观看人数
--   2. 人均弹幕数       = 当日有效弹幕条数 / 当日观看人数
--   3. 每分钟弹幕数     = 当日有效弹幕条数 / 当日开播分钟数
--   4. 人均观看时长     = 当日观看时长合计 / 当日观看人数，单位：分钟
--   5. 累计订阅人数     = 当日订阅快照去重用户数（截至该日的累计订阅人数）
--   6. 当日新增订阅人数 = 当日快照人数 - 上一自然日快照人数（净增，含取关影响，可能为负）
--   7. 每日 ACU / PCU
--
-- 数据源：
--   主播日表   gamelive.dm_huya_ayyuid_detail_day（gameid = 2336）
--   观看       gamelive.dwt_huya_ayyuid_session_from_server_with_user
--   弹幕       gamelive.gamelive_huya_danmu_log
--   订阅       gamelive.dwd_huya_dy_user（字段：aid / yyuid / ayyuid / dt / tag）
--   赛事版权   gamelive.dwd_huya_dim_game_copyright_info_d_a
--
-- 重要备注：
--   a. 观看时长口径：user_duration 单位毫秒，/60000 得分钟。
--   b. 弹幕表用户标识是 luid，观看表是 user_ukey，两套 ID 体系不同；
--      发弹幕率与人均弹幕数都是「人数比」口径，不保证分子分母是同一批用户。
--   c. 本版本不含「归属用户数」（要回扫上一自然月全平台观看，耗时太长）。
--   d. 订阅表实测是「每日全量订阅关系快照」：1199663500101 在 2026-09-21 / 09-22 的
--      ayyuid 去重用户数为 20526 / 20742，逐日递增且 id 不复用，因此
--      「累计订阅人数」= 当日快照人数，「当日新增订阅人数」= 当日 - 上一自然日。
--      注意两点：一是该表按天连续才有意义，若某天缺快照，lag 会跨天比较；
--                二是这是净增（关注 - 取关），可能出现负值，做排名前建议先看分布。
--   e. 建议先缩小主播范围：可在 anchor_live_day_all 里加主播名单。
--   f. 若 lpid 本身已经是 bigint，可去掉 anchor_danmu_day 里的 cast。
-- ============================================================
with

-- 赛事日：王者荣耀版权赛事直播日（快照分区 2026-09-22），只影响「有效样本天数」，不影响「开播天数」
excluded_dt as (
  select distinct
    substr(a.date, 1, 10) as dt
  from gamelive.dwd_huya_dim_game_copyright_info_d_a a
  where a.dt = '2026-09-22'
    and substr(a.date, 1, 10) between '2026-06-01' and '2026-09-22'
    and a.live_type like '%直播%'
    and a.game_id = 2336
    and a.match_name in (
      '2026KPL夏季赛',
      '2026EWC电竞世俱杯王者荣耀项目',
      '钟意FMVP皮肤发布仪式',
      '2027KPL春季资格赛'
    )
),

-- 全部开播日（不剔赛事日、不剔短播日）：gameid=2336 且当天有开播
-- 粒度：dt + luid；开播分钟 = sum(live_end_time - live_start_time)，跨天场次按 +24 小时处理
anchor_live_day_all as (
  select
    substr(a.dt, 1, 10) as dt,
    a.ayyuid as luid,
    max(a.nickname) as nickname,
    sum(
      case
        when a.live_start_time is null or a.live_end_time is null then null
        when unix_timestamp(a.live_end_time) >= unix_timestamp(a.live_start_time)
          then (unix_timestamp(a.live_end_time) - unix_timestamp(a.live_start_time)) / 60.0
        else (unix_timestamp(a.live_end_time) - unix_timestamp(a.live_start_time)) / 60.0 + 1440
      end
    ) as live_minutes,
    avg(a.acu) as acu,
    max(a.pcu) as pcu
  from gamelive.dm_huya_ayyuid_detail_day a
  where a.dt between '2026-06-01' and '2026-09-22'
    and a.gameid = 2336
    and a.live_mins > 0
  group by
    substr(a.dt, 1, 10),
    a.ayyuid
),

-- 开播天数（不剔任何东西）：自开播第一天起至 2026-09-22 的去重开播天数 + 首播日
anchor_live_days as (
  select
    luid,
    count(distinct dt) as live_days_all,
    min(dt) as first_live_dt,
    max(dt) as last_live_dt
  from anchor_live_day_all
  group by luid
),

-- 剔除赛事日后的开播日（用于过程指标，不再剔短播日）
anchor_live_day as (
  select
    dt,
    luid,
    nickname,
    live_minutes,
    acu,
    pcu
  from anchor_live_day_all
  where dt not in (
    select e.dt
    from excluded_dt e
    where e.dt is not null
  )
),

-- 统一有效样本日：再剔短播日（开播分钟 < 10 剔除，阈值可改）
-- 原因：开播极短的日子弹幕会跨到未开播时段，会让每分钟弹幕数虚高
-- 观看、弹幕、订阅三类过程指标都只在这批日子上算，保证分子分母同一批样本
anchor_live_day_valid as (
  select
    dt,
    luid,
    nickname,
    live_minutes,
    acu,
    pcu
  from anchor_live_day
  where live_minutes >= 10
),

-- 主播级有效样本天数（剔赛事日 + 剔短播日），等于该主播在明细里的行数
anchor_valid_days as (
  select
    luid,
    count(distinct dt) as valid_days
  from anchor_live_day_valid
  group by luid
),

-- 观看明细：server session 观看表，先完成分区与业务过滤，再按 dt + luid 关联有效样本日
-- 粒度：dt + luid + user_ukey；user_duration 单位毫秒，/60000 得分钟
anchor_watch_day as (
  select
    substr(w.dt, 1, 10) as dt,
    w.luid,
    w.user_ukey,
    sum(w.user_duration) / 60000 as view_min
  from gamelive.dwt_huya_ayyuid_session_from_server_with_user w
  inner join anchor_live_day_valid a
    on substr(w.dt, 1, 10) = a.dt
   and w.luid = a.luid
  where w.dt between '2026-06-01' and '2026-09-22'
    and w.tag = 'gameid'
    and w.htime = 'session'
    and w.igameid = 2336
    and w.user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios')
    and w.user_duration > 0
    and w.user_ukey is not null
  group by
    substr(w.dt, 1, 10),
    w.luid,
    w.user_ukey
),

-- 主播日观看聚合：观看人数、观看总时长（分钟）
anchor_watch_agg as (
  select
    dt,
    luid,
    count(distinct user_ukey) as watch_user_cnt,
    sum(view_min) as watch_min_total
  from anchor_watch_day
  group by dt, luid
),

-- 主播日弹幕聚合：发弹幕人数、有效弹幕条数
-- 粒度：dt + luid；passed='0' 为有效弹幕；仅保留有效样本日
anchor_danmu_day as (
  select
    substr(d.dt, 1, 10) as dt,
    a.luid,
    count(distinct d.luid) as danmu_user_cnt,
    count(*) as danmu_cnt
  from gamelive.gamelive_huya_danmu_log d
  inner join anchor_live_day_valid a
    on substr(d.dt, 1, 10) = a.dt
   and cast(d.lpid as bigint) = a.luid
  where d.dt between '2026-06-01' and '2026-09-22'
    and d.passed = '0'
    and d.lpid is not null
    and d.luid is not null
    and d.time is not null
  group by
    substr(d.dt, 1, 10),
    a.luid
),

-- 订阅快照（按天）：只取目标主播，多取 2026-05-31 一天用于算首日差值
-- 粒度：dt + luid；yyuid 为用户 uid，ayyuid 为主播 uid；tag='huya' 为主站订阅
subscribe_snapshot_day as (
  select
    substr(s.dt, 1, 10) as dt,
    s.ayyuid as luid,
    count(distinct s.yyuid) as subscribe_total_cnt
  from gamelive.dwd_huya_dy_user s
  inner join (
    select distinct luid
    from anchor_live_day_all
  ) t
    on s.ayyuid = t.luid
  where s.dt between '2026-05-31' and '2026-09-22'
    and s.tag = 'huya'
    and length(s.dt) = 10
    and s.yyuid is not null
  group by
    substr(s.dt, 1, 10),
    s.ayyuid
),

-- 当日新增订阅人数 = 当日快照人数 - 上一自然日快照人数（净增）
subscribe_new_day as (
  select
    dt,
    luid,
    subscribe_total_cnt,
    subscribe_total_cnt
      - lag(subscribe_total_cnt) over (partition by luid order by dt) as subscribe_new_cnt
  from subscribe_snapshot_day
),

-- 主播日指标拼装
anchor_day_metric as (
  select
    a.dt,
    a.luid,
    a.nickname,
    coalesce(dc.live_days_all, 0) as live_days_all,
    dc.first_live_dt as first_live_dt,
    coalesce(vd.valid_days, 0) as valid_days,
    a.live_minutes,
    a.acu,
    a.pcu,
    coalesce(w.watch_user_cnt, 0) as watch_user_cnt,
    coalesce(w.watch_min_total, 0) as watch_min_total,
    coalesce(w.watch_min_total, 0) / nullif(w.watch_user_cnt, 0) as avg_watch_duration_min,
    coalesce(dm.danmu_user_cnt, 0) as danmu_user_cnt,
    coalesce(dm.danmu_cnt, 0) as danmu_cnt,
    coalesce(dm.danmu_user_cnt, 0) * 1.0000
      / nullif(w.watch_user_cnt, 0) as danmu_user_rate,
    coalesce(dm.danmu_cnt, 0) * 1.0000
      / nullif(w.watch_user_cnt, 0) as avg_danmu_cnt_per_user,
    coalesce(dm.danmu_cnt, 0) * 1.0000
      / nullif(a.live_minutes, 0) as danmu_per_minute,
    coalesce(sn.subscribe_total_cnt, 0) as subscribe_total_cnt,
    sn.subscribe_new_cnt as subscribe_new_cnt
  from anchor_live_day_valid a
  left join anchor_live_days dc
    on a.luid = dc.luid
  left join anchor_valid_days vd
    on a.luid = vd.luid
  left join anchor_watch_agg w
    on a.dt = w.dt
   and a.luid = w.luid
  left join anchor_danmu_day dm
    on a.dt = dm.dt
   and a.luid = dm.luid
  left join subscribe_new_day sn
    on a.dt = sn.dt
   and a.luid = sn.luid
)

-- ============================================================
-- 第一段：主播 × 日 明细（默认执行）
-- ============================================================
select
  dt as `日期`,
  luid as `主播uid`,
  nickname as `主播昵称`,
  live_days_all as `开播天数`,
  first_live_dt as `首播日`,
  datediff(to_date('2026-09-22'), to_date(first_live_dt)) + 1 as `首播起自然日数`,
  valid_days as `有效样本天数`,
  round(live_minutes, 2) as `开播分钟数`,
  acu as `acu`,
  pcu as `pcu`,
  watch_user_cnt as `观看人数`,
  danmu_user_cnt as `发弹幕人数`,
  round(danmu_user_rate, 4) as `观众发弹幕率`,
  danmu_cnt as `弹幕条数`,
  round(avg_danmu_cnt_per_user, 4) as `人均弹幕数`,
  round(danmu_per_minute, 4) as `每分钟弹幕数`,
  round(avg_watch_duration_min, 2) as `人均观看时长_分钟`,
  subscribe_total_cnt as `累计订阅人数`,
  subscribe_new_cnt as `当日新增订阅人数`
from anchor_day_metric
order by
  luid,
  dt;

-- ============================================================
-- 第二段：主播级汇总（用于排名筛选）
-- 用法：把上面第一段从 select 到末尾分号整段替换为以下内容（去掉每行行首的 --）
-- 说明：比率型指标同时给「先日再平均」和「累计口径」两列，前者是日均，
--      后者是窗口整体值，做排名前请先固定用哪一列，避免两个口径混用。
-- ============================================================
-- select
--   luid as `主播uid`,
--   max(nickname) as `主播昵称`,
--   max(live_days_all) as `开播天数`,
--   min(first_live_dt) as `首播日`,
--   max(valid_days) as `有效样本天数`,
--   min(dt) as `样本内首日`,
--   max(dt) as `样本内末日`,
--   count(distinct dt) as `明细行天数`,
--   round(avg(watch_user_cnt), 1) as `日均观看人数`,
--   round(avg(danmu_user_cnt), 1) as `日均发弹幕人数`,
--   round(avg(danmu_user_rate), 4) as `日均观众发弹幕率_先日再平均`,
--   round(sum(danmu_user_cnt) * 1.0000 / nullif(sum(watch_user_cnt), 0), 4) as `整体观众发弹幕率_累计口径`,
--   round(avg(avg_danmu_cnt_per_user), 4) as `日均人均弹幕数_先日再平均`,
--   round(sum(danmu_cnt) * 1.0000 / nullif(sum(watch_user_cnt), 0), 4) as `整体人均弹幕数_累计口径`,
--   round(avg(danmu_per_minute), 4) as `日均每分钟弹幕数_先日再平均`,
--   round(sum(danmu_cnt) * 1.0000 / nullif(sum(live_minutes), 0), 4) as `整体每分钟弹幕数_累计口径`,
--   round(avg(avg_watch_duration_min), 2) as `日均人均观看时长_分钟`,
--   round(sum(watch_min_total) / nullif(sum(watch_user_cnt), 0), 2) as `整体人均观看时长_分钟`,
--   round(avg(subscribe_new_cnt), 2) as `日均当日新增订阅人数`,
--   sum(subscribe_new_cnt) as `累计当日新增订阅人数`,
--   max(subscribe_total_cnt) as `期末累计订阅人数`,
--   round(avg(acu), 2) as `日均acu`,
--   round(avg(pcu), 2) as `日均pcu`,
--   max(pcu) as `窗口内pcu峰值`
-- from anchor_day_metric
-- group by luid
-- order by `日均观众发弹幕率_先日再平均` desc;

