-- ============================================================
-- 王者荣耀「主播潜力」互动过程指标 —— 按天调度（Hive）v3
-- 调度变量：${tdate?string('yyyy-MM-dd')}
-- 输出表：zhgametemp.zty_ads_huya_wzry_anchor_potential_daily_v3
-- 粒度：dt × 主播uid（每次调度只写当天一个分区）
--
-- 【v3 相对 v2 的改动】
--   1. 赛事日不再剔除样本，只标注：is_match_day = 1；
--      is_valid_day 只表示「是否不是短播日」（开播分钟 >= 10）。
--   2. 新增 DAU 与环比：dau / dau_prev / dau_dod_diff / dau_dod_rate，
--      acu_prev / acu_dod_diff / acu_dod_rate，pcu_prev / pcu_dod_diff / pcu_dod_rate。
--      环比 = 当天 - 前一自然日（同主播），差值和变化率都给。
--      算法：主播日表和观看表都扩成「跑批日 + 前一日」两天扫，
--            不依赖自己表昨天分区，首次上线当天也能算出环比。
--   3. 新增订阅转化率 sub_rate = 当日新增订阅人数 / DAU，
--      用率替代绝对量，避免新增粉丝被 DAU 涨跌带着走。
--   4. 补充互动深度 danmu_per_danmu_user = 弹幕条数 / 发弹幕人数。
--      （可选列，若不想加直接删掉建表列、anchor_day_metric 里的计算和最后 select 那一行即可）
--
-- 【口径】
--   DAU  = 主播当天去重观看人数（app 端、王者、session 口径，按 user_ukey 去重），
--          与 watch_user_cnt 同值，单独给一列是为了看环比时名字直观。
--   ACU  = 当天平均在线观看人数；PCU = 当天最高在线观看人数（dm_huya_ayyuid_detail_day）。
--   观看 = gamelive.dwt_huya_ayyuid_session_from_server_with_user，
--          app 端（huya_andriod/huya_ipad/huya_pad/huya_ios）+ igameid=2336 + htime=session。
--   弹幕 = gamelive.gamelive_huya_danmu_log，passed='0'；
--          发弹幕人数走「观看用户 ∩ 弹幕用户」同用户口径（弹幕限 app 端 + 王者），必然 <= DAU；
--          弹幕条数仍是房间全部有效弹幕（热度口径）。
--   订阅 = gamelive.dwd_huya_dy_user（每日全量订阅关系快照），
--          累计订阅人数 = 当日快照去重用户数；当日新增 = 当日快照 - 前一自然日快照。
--   开播分钟 = sum(live_end_time - live_start_time)，跨天场次 +24 小时；短播阈值 10 分钟。
--
-- 【注意事项】
--   a. 前一日没有开播 / 没有观看记录时，prev 列为 NULL，环比也为 NULL，不要当成 0；
--   b. 环比是「同主播当天 vs 前一天」，不看赛事日标记，即使前一天是赛事日也照常比；
--   c. 订阅前一自然日快照缺失时 sub_new_cnt 为 NULL；
--   d. 建表不写 comment、列名用短英文，避开元数据库 COLUMNS_V2 长度限制；
--   e. 若调度平台的 Hive 版本不接受 insert 后面直接跟 with，
--      把 with 到 select 整段外面包一层：select * from ( with ... select ... ) t 即可。
-- ============================================================

create table if not exists zhgametemp.zty_ads_huya_wzry_anchor_potential_daily_v3 (
    anchor_uid       bigint,
    anchor_name      string,
    is_match_day     int,
    is_short_day     int,
    is_valid_day     int,
    live_min         double,
    acu              double,
    pcu              bigint,
    watch_user_cnt   bigint,
    dau              bigint,
    dau_prev         bigint,
    dau_dod_diff     bigint,
    dau_dod_rate     double,
    acu_prev         double,
    acu_dod_diff     double,
    acu_dod_rate     double,
    pcu_prev         bigint,
    pcu_dod_diff     bigint,
    pcu_dod_rate     double,
    danmu_user_cnt   bigint,
    danmu_user_rate  double,
    danmu_cnt        bigint,
    danmu_per_user   double,
    danmu_per_danmu_user double,
    danmu_per_min    double,
    avg_watch_min    double,
    sub_total_cnt    bigint,
    sub_new_cnt      bigint,
    sub_rate         double
)
partitioned by (
    dt string
)
stored as orc;

with

-- 当天是否赛事日：王者版权赛事直播日（只做标注，不再剔出样本）
-- 注意：若当天赛事快照分区缺失，这里会为空、赛事日标注不到，建议调度前置校验该分区
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

-- 主播日表：跑批日 + 前一自然日两天，王者开播
-- 粒度：dt + luid；开播分钟 = sum(live_end_time - live_start_time)，跨天场次按 +24 小时处理
anchor_live_day_2d as (
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
  where a.dt in (
      '${tdate?string('yyyy-MM-dd')}',
      date_sub('${tdate?string('yyyy-MM-dd')}', 1)
    )
    and a.gameid = 2336
    and a.live_mins > 0
  group by
    substr(a.dt, 1, 10),
    a.ayyuid
),

-- 当天开播主播打标：是否赛事日 / 是否短播日 / 是否计入样本（只剔短播日）
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
    case when l.live_minutes >= 10 then 1 else 0 end as is_valid_day
  from anchor_live_day_2d l
  left join excluded_dt e
    on l.dt = e.dt
  where l.dt = '${tdate?string('yyyy-MM-dd')}'
),

-- 有效样本日（当天，只剔短播日）
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

-- 前一日主播日指标（ACU / PCU 环比用）
anchor_prev_day as (
  select
    luid,
    acu,
    pcu
  from anchor_live_day_2d
  where dt = date_sub('${tdate?string('yyyy-MM-dd')}', 1)
),

-- 观看明细：跑批日 + 前一自然日两天，多带 user_yyuid（用于和弹幕对齐用户）
-- 粒度：dt + luid + user_ukey + user_yyuid；user_duration 单位毫秒，/60000 得分钟
anchor_watch_day as (
  select
    substr(w.dt, 1, 10) as dt,
    w.luid,
    w.user_ukey,
    w.user_yyuid,
    sum(w.user_duration) / 60000 as view_min
  from gamelive.dwt_huya_ayyuid_session_from_server_with_user w
  inner join anchor_live_day_2d a
    on substr(w.dt, 1, 10) = a.dt
   and w.luid = a.luid
  where w.dt in (
      '${tdate?string('yyyy-MM-dd')}',
      date_sub('${tdate?string('yyyy-MM-dd')}', 1)
    )
    and w.tag = 'gameid'
    and w.htime = 'session'
    and w.igameid = 2336
    and w.user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios')
    and w.user_duration > 0
    and w.user_ukey is not null
  group by
    substr(w.dt, 1, 10),
    w.luid,
    w.user_ukey,
    w.user_yyuid
),

-- 观看聚合（两天）：观看人数（按 user_ukey 去重）、观看总时长（分钟）
anchor_watch_agg_2d as (
  select
    dt,
    luid,
    count(distinct user_ukey) as watch_user_cnt,
    sum(view_min) as watch_min_total
  from anchor_watch_day
  group by dt, luid
),

-- 前一日观看聚合（DAU 环比用）
anchor_watch_agg_prev as (
  select
    luid,
    watch_user_cnt
  from anchor_watch_agg_2d
  where dt = date_sub('${tdate?string('yyyy-MM-dd')}', 1)
),

-- 当天观看用户去重到账号维度（yyuid），作为发弹幕人数的分母成员
anchor_viewer_user as (
  select distinct
    dt,
    luid,
    cast(user_yyuid as bigint) as yyuid
  from anchor_watch_day
  where dt = '${tdate?string('yyyy-MM-dd')}'
    and user_yyuid is not null
    and cast(user_yyuid as bigint) is not null
    and cast(user_yyuid as bigint) > 0
),

-- 弹幕用户（当天）：弹幕表 luid 就是用户 yyuid；限 app 端 + 王者品类
-- platform 取值和观看表 user_product 不是一套命名：adr≈huya_andriod、ios≈huya_ios、ipad≈huya_ipad
anchor_danmu_user as (
  select distinct
    substr(d.dt, 1, 10) as dt,
    cast(d.lpid as bigint) as luid,
    cast(d.luid as bigint) as yyuid
  from gamelive.gamelive_huya_danmu_log d
  where d.dt = '${tdate?string('yyyy-MM-dd')}'
    and d.passed = '0'
    and d.lpid is not null
    and d.luid is not null
    and cast(d.lpid as bigint) is not null
    and cast(d.luid as bigint) is not null
    and cast(d.luid as bigint) > 0
    and d.platform in ('adr', 'ios', 'ipad')
    and d.live_gameid = 2336
),

-- 发弹幕人数 = 既在观看表里、又在弹幕表里发过言的用户数（必然是 DAU 的子集）
anchor_danmu_day as (
  select
    v.dt,
    v.luid,
    count(distinct v.yyuid) as danmu_user_cnt
  from anchor_viewer_user v
  inner join anchor_danmu_user du
    on v.dt = du.dt
   and v.luid = du.luid
   and v.yyuid = du.yyuid
  inner join anchor_live_day_valid a
    on v.dt = a.dt
   and v.luid = a.luid
  group by
    v.dt,
    v.luid
),

-- 弹幕条数（当天）：房间全部有效弹幕（热度口径，未做端/品类过滤）
anchor_danmu_cnt_day as (
  select
    substr(d.dt, 1, 10) as dt,
    a.luid,
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
-- 粒度：dt + luid；yyuid 为用户 uid，ayyuid 为主播 uid；tag=huya 为主站订阅
subscribe_snapshot_day as (
  select
    substr(s.dt, 1, 10) as dt,
    s.ayyuid as luid,
    count(distinct s.yyuid) as subscribe_total_cnt
  from gamelive.dwd_huya_dy_user s
  inner join (
    select distinct luid
    from anchor_day_out
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

-- 主播日指标拼装
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
    coalesce(w.watch_user_cnt, 0) as dau,
    pw.watch_user_cnt as dau_prev,
    w.watch_user_cnt - pw.watch_user_cnt as dau_dod_diff,
    case
      when pw.watch_user_cnt is null or pw.watch_user_cnt = 0 then null
      else (w.watch_user_cnt - pw.watch_user_cnt) * 1.0000 / pw.watch_user_cnt
    end as dau_dod_rate,
    pl.acu as acu_prev,
    o.acu - pl.acu as acu_dod_diff,
    case
      when pl.acu is null or pl.acu = 0 then null
      else (o.acu - pl.acu) * 1.0000 / pl.acu
    end as acu_dod_rate,
    pl.pcu as pcu_prev,
    o.pcu - pl.pcu as pcu_dod_diff,
    case
      when pl.pcu is null or pl.pcu = 0 then null
      else (o.pcu - pl.pcu) * 1.0000 / pl.pcu
    end as pcu_dod_rate,
    coalesce(dm.danmu_user_cnt, 0) as danmu_user_cnt,
    coalesce(dc.danmu_cnt, 0) as danmu_cnt,
    coalesce(w.watch_min_total, 0)
      / case when coalesce(w.watch_user_cnt, 0) = 0 then null else w.watch_user_cnt end
      as avg_watch_duration_min,
    coalesce(dm.danmu_user_cnt, 0) * 1.0000
      / case when coalesce(w.watch_user_cnt, 0) = 0 then null else w.watch_user_cnt end
      as danmu_user_rate,
    coalesce(dc.danmu_cnt, 0) * 1.0000
      / case when coalesce(w.watch_user_cnt, 0) = 0 then null else w.watch_user_cnt end
      as avg_danmu_cnt_per_user,
    coalesce(dc.danmu_cnt, 0) * 1.0000
      / case when coalesce(dm.danmu_user_cnt, 0) = 0 then null else dm.danmu_user_cnt end
      as danmu_per_danmu_user,
    coalesce(dc.danmu_cnt, 0) * 1.0000
      / case when coalesce(o.live_minutes, 0) = 0 then null else o.live_minutes end
      as danmu_per_minute,
    coalesce(sn.subscribe_total_cnt, 0) as subscribe_total_cnt,
    sn.subscribe_new_cnt as subscribe_new_cnt,
    sn.subscribe_new_cnt * 1.0000
      / case when coalesce(w.watch_user_cnt, 0) = 0 then null else w.watch_user_cnt end
      as sub_rate
  from anchor_day_out o
  left join anchor_watch_agg_2d w
    on o.dt = w.dt
   and o.luid = w.luid
  left join anchor_watch_agg_prev pw
    on o.luid = pw.luid
  left join anchor_prev_day pl
    on o.luid = pl.luid
  left join anchor_danmu_day dm
    on o.dt = dm.dt
   and o.luid = dm.luid
  left join anchor_danmu_cnt_day dc
    on o.dt = dc.dt
   and o.luid = dc.luid
  left join subscribe_new_day sn
    on o.dt = sn.dt
   and o.luid = sn.luid
)

insert overwrite table zhgametemp.zty_ads_huya_wzry_anchor_potential_daily_v3
partition (dt = '${tdate?string('yyyy-MM-dd')}')

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
    m.dau                     as dau,
    m.dau_prev                as dau_prev,
    m.dau_dod_diff            as dau_dod_diff,
    round(m.dau_dod_rate, 4)  as dau_dod_rate,
    m.acu_prev                as acu_prev,
    round(m.acu_dod_diff, 2)  as acu_dod_diff,
    round(m.acu_dod_rate, 4)  as acu_dod_rate,
    m.pcu_prev                as pcu_prev,
    m.pcu_dod_diff            as pcu_dod_diff,
    round(m.pcu_dod_rate, 4)  as pcu_dod_rate,
    m.danmu_user_cnt          as danmu_user_cnt,
    round(m.danmu_user_rate, 4)         as danmu_user_rate,
    m.danmu_cnt                         as danmu_cnt,
    round(m.avg_danmu_cnt_per_user, 4)  as danmu_per_user,
    round(m.danmu_per_danmu_user, 4)    as danmu_per_danmu_user,
    round(m.danmu_per_minute, 4)        as danmu_per_min,
    round(m.avg_watch_duration_min, 2)  as avg_watch_min,
    m.subscribe_total_cnt               as sub_total_cnt,
    m.subscribe_new_cnt                 as sub_new_cnt,
    round(m.sub_rate, 6)                as sub_rate
from anchor_day_metric m
;

-- ============================================================
-- 字段口径对照（导出 Excel 时按这个改表头）
--   dt              日期分区，yyyy-MM-dd
--   anchor_uid      主播uid（ayyuid）
--   anchor_name     主播昵称（取当天最大值）
--   is_match_day    是否赛事日：1=当天是王者版权赛事日（只标注，不剔样本）
--   is_short_day    是否短播日：1=当天开播分钟 < 10
--   is_valid_day    是否计入样本：1=当天不是短播日（赛事日也算样本）
--   live_min        开播分钟数 = sum(live_end_time - live_start_time)/60，跨天 +24 小时
--   acu / pcu       当日平均 / 最高在线观看人数
--   watch_user_cnt  当日去重观看人数（app 端、王者、session，按 user_ukey 去重）
--   dau             = watch_user_cnt（同值，单独给一列便于看环比）
--   dau_prev        前一自然日 DAU（前一日没开播/没观看时为 NULL）
--   dau_dod_diff    DAU 环比差值 = 当天 - 昨天
--   dau_dod_rate    DAU 环比变化率 = 差值 / 昨天，昨天为 0 或 NULL 时为空
--   acu_prev / acu_dod_diff / acu_dod_rate    ACU 的昨日值与环比
--   pcu_prev / pcu_dod_diff / pcu_dod_rate    PCU 的昨日值与环比
--   danmu_user_cnt  当日观看用户中发过弹幕的人数（app 端 + 王者，按 yyuid 对齐）
--   danmu_user_rate 观众发弹幕率 = danmu_user_cnt / watch_user_cnt（<= 1）
--   danmu_cnt       当日房间全部有效弹幕条数（热度口径）
--   danmu_per_user  人均弹幕数 = 弹幕条数 / 观看人数
--   danmu_per_danmu_user 发弹幕用户人均条数 = 弹幕条数 / 发弹幕人数（互动深度）
--   danmu_per_min   每分钟弹幕数 = 弹幕条数 / 开播分钟数
--   avg_watch_min   人均观看时长（分钟）
--   sub_total_cnt   累计订阅人数 = 当日订阅快照去重用户数
--   sub_new_cnt     当日新增订阅人数 = 当日快照 - 前一自然日快照（净增，可为负）
--   sub_rate        订阅转化率 = 当日新增订阅人数 / DAU（用率替代绝对量）
-- ============================================================
