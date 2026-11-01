-- ============================================================
-- 王者荣耀「主播潜力」互动过程指标 —— 日跑调度版（Spark SQL）
--
-- 调度参数：${bizdate}
--   含义：本次跑批的日期，格式 yyyy-MM-dd，一般传 T-1（分区已就绪的那天）
--   例：${bizdate} = '2026-09-22'
--   每天只跑一天、只扫当天分区，所以比全窗口版快很多。
--
-- 口径与全窗口版完全一致，只是把窗口收成一天：
--   1) 主表 = 当天有王者开播：dm_huya_ayyuid_detail_day，dt = ${bizdate}，gameid = 2336，live_mins > 0
--   2) 当天是王者版权赛事日 → 不进样本（是否赛事日 = 1）
--   3) 当天开播分钟 < 10（短播日）→ 不进样本（是否短播日 = 1），
--      避免开播极短的日子弹幕跨到未开播时段，把每分钟弹幕数抬虚
--   4) 开播分钟 = live_end_time - live_start_time，跨天场次按 +24 小时处理
--   5) 观看、弹幕、订阅三类过程指标只统计「是否计入样本 = 1」的主播日
--
-- 输出粒度：主播 × 日（只输出当天；被剔除的赛事日 / 短播日也会出一行，用标记区分）
--
-- 累计口径（开播天数、首播日）不建议放进日调度里全历史回扫，见文件末尾「累计口径」段
-- ============================================================
with

-- 当天是否赛事日：赛事快照取「<= 跑批日的最新分区」，避免某天分区缺失导致漏剔
excluded_dt as (
  select distinct
    substr(a.date, 1, 10) as dt
  from gamelive.dwd_huya_dim_game_copyright_info_d_a a
  where a.dt = (
      select max(b.dt)
      from gamelive.dwd_huya_dim_game_copyright_info_d_a b
      where b.dt <= '${bizdate}'
    )
    and substr(a.date, 1, 10) = '${bizdate}'
    and a.live_type like '%直播%'
    and a.game_id = 2336
    and a.match_name in (
      '2026KPL夏季赛',
      '2026EWC电竞世俱杯王者荣耀项目',
      '钟意FMVP皮肤发布仪式',
      '2027KPL春季资格赛'
    )
),

-- 当天王者开播日（不剔赛事日、不剔短播日）
-- 粒度：dt + luid；开播分钟 = sum(live_end_time - live_start_time)，跨天场次按 +24 小时处理
anchor_live_day as (
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
  where a.dt = '${bizdate}'
    and a.gameid = 2336
    and a.live_mins > 0
  group by
    substr(a.dt, 1, 10),
    a.ayyuid
),

-- 当天全部开播主播打标：是否赛事日 / 是否短播日 / 是否计入样本
anchor_day_out as (
  select
    l.dt,
    l.luid,
    l.nickname,
    l.live_minutes,
    l.acu,
    l.pcu,
    case
      when l.dt in (
        select e.dt
        from excluded_dt e
        where e.dt is not null
      ) then 1 else 0
    end as is_match_day,
    case when l.live_minutes < 10 then 1 else 0 end as is_short_day,
    case
      when l.dt in (
        select e.dt
        from excluded_dt e
        where e.dt is not null
      ) then 0
      when l.live_minutes >= 10 then 1
      else 0
    end as is_valid_day
  from anchor_live_day l
),

-- 有效样本日（剔赛事日 + 剔短播日），过程指标只算这批日子
anchor_live_day_valid as (
  select
    dt,
    luid,
    nickname,
    live_minutes,
    acu,
    pcu
  from anchor_day_out
  where is_valid_day = 1
),

-- 当天观看明细：server session 观看表，先完成分区与业务过滤，再按 dt + luid 关联有效样本日
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
  where w.dt = '${bizdate}'
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

-- 当天观看聚合：观看人数、观看总时长（分钟）
anchor_watch_agg as (
  select
    dt,
    luid,
    count(distinct user_ukey) as watch_user_cnt,
    sum(view_min) as watch_min_total
  from anchor_watch_day
  group by dt, luid
),

-- 当天弹幕聚合：发弹幕人数、有效弹幕条数
-- 粒度：dt + luid；passed='0' 为有效弹幕
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
  where d.dt = '${bizdate}'
    and d.passed = '0'
    and d.lpid is not null
    and d.luid is not null
    and d.time is not null
  group by
    substr(d.dt, 1, 10),
    a.luid
),

-- 订阅快照：只取「跑批日 + 前一自然日」两天，用于算当日新增（不跨分区回扫历史）
-- 粒度：dt + luid；yyuid 为用户 uid，ayyuid 为主播 uid；tag='huya' 为主站订阅
subscribe_snapshot_day as (
  select
    substr(s.dt, 1, 10) as dt,
    s.ayyuid as luid,
    count(distinct s.yyuid) as subscribe_total_cnt
  from gamelive.dwd_huya_dy_user s
  inner join (
    select distinct luid
    from anchor_live_day
  ) t
    on s.ayyuid = t.luid
  where s.dt between date_format(date_add(to_date('${bizdate}'), -1), 'yyyy-MM-dd') and '${bizdate}'
    and s.tag = 'huya'
    and length(s.dt) = 10
    and s.yyuid is not null
  group by
    substr(s.dt, 1, 10),
    s.ayyuid
),

-- 当日新增订阅人数 = 当日快照人数 - 上一自然日快照人数（净增，可能为负）
-- 注意：若前一日快照缺失，lag 拿不到值，当日新增为 NULL
subscribe_new_day as (
  select
    dt,
    luid,
    subscribe_total_cnt,
    subscribe_total_cnt
      - lag(subscribe_total_cnt) over (partition by luid order by dt) as subscribe_new_cnt
  from subscribe_snapshot_day
),

-- 主播日指标拼装（含被剔除的赛事日 / 短播日，指标给 0，靠标记区分）
anchor_day_metric as (
  select
    o.dt,
    o.luid,
    o.nickname,
    o.is_match_day,
    o.is_short_day,
    o.is_valid_day,
    o.live_minutes,
    o.acu,
    o.pcu,
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
      / nullif(o.live_minutes, 0) as danmu_per_minute,
    coalesce(sn.subscribe_total_cnt, 0) as subscribe_total_cnt,
    sn.subscribe_new_cnt as subscribe_new_cnt
  from anchor_day_out o
  left join anchor_watch_agg w
    on o.dt = w.dt
   and o.luid = w.luid
  left join anchor_danmu_day dm
    on o.dt = dm.dt
   and o.luid = dm.luid
  left join subscribe_new_day sn
    on o.dt = sn.dt
   and o.luid = sn.luid
)

-- ============================================================
-- 每日输出：主播 × 日（每次调度出一天）
-- ============================================================
select
  dt as `日期`,
  luid as `主播uid`,
  nickname as `主播昵称`,
  1 as `当日开播标记`,
  is_match_day as `是否赛事日`,
  is_short_day as `是否短播日`,
  is_valid_day as `是否计入样本`,
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
  luid;

-- ============================================================
-- 落地写法（放到调度里，把上面 select 整段塞进去）
-- ============================================================
-- insert overwrite table 你的库.你的表 partition (dt = '${bizdate}')
-- select ... （上面那一段，注意去掉末尾的分号）

-- ============================================================
-- 累计口径（开播天数 / 首播日）：不要放进日跑里全历史回扫
--   方案一（推荐）：按 uid 单独跑一次全历史，见同目录
--                  王者主播_开播天数_by_uid_20260922.sql，再和日表 join / XLOOKUP
--   方案二：建一张累计表，每天把当日结果并进去（示例，按库表名替换）
-- ============================================================
-- insert overwrite table 你的库.anchor_live_days_cum
-- select
--   luid,
--   max(nickname) as nickname,
--   count(distinct dt) as live_days_all,
--   min(dt) as first_live_dt,
--   max(dt) as last_live_dt
-- from (
--   select luid, nickname, dt
--   from 你的库.anchor_live_days_cum
--   union all
--   select luid, nickname, dt
--   from (
--     select substr(a.dt, 1, 10) as dt, a.ayyuid as luid, max(a.nickname) as nickname
--     from gamelive.dm_huya_ayyuid_detail_day a
--     where a.dt = '${bizdate}'
--       and a.gameid = 2336
--       and a.live_mins > 0
--     group by substr(a.dt, 1, 10), a.ayyuid
--   ) d
-- ) t
-- group by luid;

-- 累计表里的首播起自然日数（Spark）：datediff(to_date('${bizdate}'), to_date(first_live_dt)) + 1
-- 累计表里的首播起自然日数（Presto）：date_diff('day', cast(first_live_dt as date), cast('${bizdate}' as date)) + 1

