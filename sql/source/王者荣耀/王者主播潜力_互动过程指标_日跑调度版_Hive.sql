-- ============================================================
-- 王者荣耀「主播潜力」互动过程指标 —— 按天调度（Hive）
-- 调度变量：${tdate?string('yyyy-MM-dd')}
-- 输出表：zhgametemp.zty_ads_huya_wzry_anchor_potential_daily_v1
-- 粒度：dt × 主播uid（每次调度只写当天一个分区）
--
-- 【本次修改】上一版建表失败：中文列名 + 中文注释让元数据库 COLUMNS_V2 的字段长度超限。
--   处理办法：列名全部换成短英文名，建表语句里不写任何 comment，
--             口径说明移到任务备注 / 口径文档里，元数据长度降到最低。
--   字段含义见文件末尾「字段口径对照」，字段名和含义不要随意改，下游透视表依赖它。
--
-- 【口径】
--   1) 主表 = 当天有王者开播：dm_huya_ayyuid_detail_day，dt = 调度日，gameid = 2336，live_mins > 0
--   2) 当天是王者版权赛事日 → 不进样本（is_match_day = 1）
--   3) 当天开播分钟 < 10（短播日）→ 不进样本（is_short_day = 1），
--      避免开播极短的日子弹幕跨到未开播时段，把每分钟弹幕数抬虚
--   4) 开播分钟 = sum(live_end_time - live_start_time)，跨天场次按 +24 小时处理
--   5) 观看、弹幕、订阅三类过程指标只统计 is_valid_day = 1 的主播日
--
-- 【Hive 适配】
--   a. 不用 nullif，改成 case when 分母 = 0 then null else 分母 end；
--   b. 不用 lag，当日新增订阅用「调度日 left join 前一自然日」两张快照相减；
--   c. 赛事日判断用 left join，不在 select 列里写 in (子查询)；
--   d. 前一自然日用 date_sub('调度日', 1)；
--   e. 日期由 dt 分区承载，不单独出一列；
--   f. 若调度平台的 Hive 版本不接受 insert 后面直接跟 with，
--      把 with 到 select 整段外面包一层：select * from ( with ... select ... ) t 即可。
-- ============================================================

create table if not exists zhgametemp.zty_ads_huya_wzry_anchor_potential_daily_v1 (
    anchor_uid       bigint,
    anchor_name      string,
    is_match_day     int,
    is_short_day     int,
    is_valid_day     int,
    live_min         double,
    acu              double,
    pcu              bigint,
    watch_user_cnt   bigint,
    danmu_user_cnt   bigint,
    danmu_user_rate  double,
    danmu_cnt        bigint,
    danmu_per_user   double,
    danmu_per_min    double,
    avg_watch_min    double,
    sub_total_cnt    bigint,
    sub_new_cnt      bigint
)
partitioned by (
    dt string
)
stored as orc;

insert overwrite table zhgametemp.zty_ads_huya_wzry_anchor_potential_daily_v1
partition (dt = '${tdate?string('yyyy-MM-dd')}')

with

-- 当天是否赛事日：王者版权赛事直播日（赛事快照取当天分区）
-- 注意：若当天赛事快照分区缺失，这里会为空、赛事日不会被剔除，建议调度前置校验该分区
excluded_dt as (
  select distinct
    substr(a.date, 1, 10) as dt
  from gamelive.dwd_huya_dim_game_copyright_info_d_a a
  where a.dt = '${tdate?string('yyyy-MM-dd')}'
    and substr(a.date, 1, 10) = '${tdate?string('yyyy-MM-dd')}'
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
        when unix_timestamp(cast(a.live_end_time as string), 'yyyy-MM-dd HH:mm:ss')
             >= unix_timestamp(cast(a.live_start_time as string), 'yyyy-MM-dd HH:mm:ss')
          then (unix_timestamp(cast(a.live_end_time as string), 'yyyy-MM-dd HH:mm:ss')
                - unix_timestamp(cast(a.live_start_time as string), 'yyyy-MM-dd HH:mm:ss')) / 60.0
        else (unix_timestamp(cast(a.live_end_time as string), 'yyyy-MM-dd HH:mm:ss')
              - unix_timestamp(cast(a.live_start_time as string), 'yyyy-MM-dd HH:mm:ss')) / 60.0 + 1440
      end
    ) as live_minutes,
    avg(a.acu) as acu,
    max(a.pcu) as pcu
  from gamelive.dm_huya_ayyuid_detail_day a
  where a.dt = '${tdate?string('yyyy-MM-dd')}'
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
    case when e.dt is not null then 1 else 0 end as is_match_day,
    case when l.live_minutes < 10 then 1 else 0 end as is_short_day,
    case when e.dt is null and l.live_minutes >= 10 then 1 else 0 end as is_valid_day
  from anchor_live_day l
  left join excluded_dt e
    on l.dt = e.dt
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
  where w.dt = '${tdate?string('yyyy-MM-dd')}'
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
  where d.dt = '${tdate?string('yyyy-MM-dd')}'
    and d.passed = '0'
    and d.lpid is not null
    and d.luid is not null
    and d.time is not null
  group by
    substr(d.dt, 1, 10),
    a.luid
),

-- 订阅快照：只取「调度日 + 前一自然日」两天，不跨分区回扫历史
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
  where s.dt in (
      '${tdate?string('yyyy-MM-dd')}',
      date_sub('${tdate?string('yyyy-MM-dd')}', 1)
    )
    and s.tag = 'huya'
    and length(s.dt) = 10
    and s.yyuid is not null
  group by
    substr(s.dt, 1, 10),
    s.ayyuid
),

-- 当日新增订阅人数 = 当日快照人数 - 前一自然日快照人数（净增，可能为负）
-- 前一自然日快照缺失时，当日新增为 NULL
subscribe_new_day as (
  select
    cur.dt,
    cur.luid,
    cur.subscribe_total_cnt,
    cur.subscribe_total_cnt - prev.subscribe_total_cnt as subscribe_new_cnt
  from (
    select dt, luid, subscribe_total_cnt
    from subscribe_snapshot_day
    where dt = '${tdate?string('yyyy-MM-dd')}'
  ) cur
  left join (
    select dt, luid, subscribe_total_cnt
    from subscribe_snapshot_day
    where dt = date_sub('${tdate?string('yyyy-MM-dd')}', 1)
  ) prev
    on cur.luid = prev.luid
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
    coalesce(dm.danmu_user_cnt, 0) as danmu_user_cnt,
    coalesce(dm.danmu_cnt, 0) as danmu_cnt,
    coalesce(w.watch_min_total, 0)
      / case when coalesce(w.watch_user_cnt, 0) = 0 then null else w.watch_user_cnt end
      as avg_watch_duration_min,
    coalesce(dm.danmu_user_cnt, 0) * 1.0000
      / case when coalesce(w.watch_user_cnt, 0) = 0 then null else w.watch_user_cnt end
      as danmu_user_rate,
    coalesce(dm.danmu_cnt, 0) * 1.0000
      / case when coalesce(w.watch_user_cnt, 0) = 0 then null else w.watch_user_cnt end
      as avg_danmu_cnt_per_user,
    coalesce(dm.danmu_cnt, 0) * 1.0000
      / case when coalesce(o.live_minutes, 0) = 0 then null else o.live_minutes end
      as danmu_per_minute,
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

select
    m.luid                    as anchor_uid,
    m.nickname                as anchor_name,
    m.is_match_day            as is_match_day,
    m.is_short_day            as is_short_day,
    m.is_valid_day            as is_valid_day,
    round(m.live_minutes, 2)  as live_min,
    m.acu                     as acu,
    m.pcu                     as pcu,
    m.watch_user_cnt          as watch_user_cnt,
    m.danmu_user_cnt          as danmu_user_cnt,
    round(m.danmu_user_rate, 4)         as danmu_user_rate,
    m.danmu_cnt                         as danmu_cnt,
    round(m.avg_danmu_cnt_per_user, 4)  as danmu_per_user,
    round(m.danmu_per_minute, 4)        as danmu_per_min,
    round(m.avg_watch_duration_min, 2)  as avg_watch_min,
    m.subscribe_total_cnt               as sub_total_cnt,
    m.subscribe_new_cnt                 as sub_new_cnt
from anchor_day_metric m
;

-- ============================================================
-- 字段口径对照（导出 Excel 时按这个改表头；建表里不写 comment 就是为了避开元数据长度限制）
--   dt              日期分区，yyyy-MM-dd
--   anchor_uid      主播uid（ayyuid）
--   anchor_name     主播昵称（取当天最大值）
--   is_match_day    是否赛事日：1=当天是王者版权赛事日，不进样本
--   is_short_day    是否短播日：1=当天开播分钟 < 10，不进样本
--   is_valid_day    是否计入样本：1=既非赛事日也非短播日，过程指标只统计这批日子
--   live_min        开播分钟数 = sum(live_end_time - live_start_time)/60，跨天场次 +24 小时
--   acu             当日平均在线观看人数
--   pcu             当日最高在线观看人数
--   watch_user_cnt  当日去重观看用户数（app 端、王者、session 口径）
--   danmu_user_cnt  当日去重发弹幕人数
--   danmu_user_rate 观众发弹幕率 = 发弹幕人数 / 观看人数
--   danmu_cnt       当日有效弹幕条数
--   danmu_per_user  人均弹幕数 = 弹幕条数 / 观看人数
--   danmu_per_min   每分钟弹幕数 = 弹幕条数 / 开播分钟数
--   avg_watch_min   人均观看时长（分钟）= 观看时长合计 / 观看人数
--   sub_total_cnt   累计订阅人数 = 当日订阅快照去重用户数
--   sub_new_cnt     当日新增订阅人数 = 当日快照 - 前一自然日快照（净增，可为负）
--
-- 累计口径（开播天数 / 首播日）不在本任务里，按 uid 单独跑
--   王者主播_开播天数_by_uid_20260922.sql，再和本表按 anchor_uid 关联。
-- ============================================================

