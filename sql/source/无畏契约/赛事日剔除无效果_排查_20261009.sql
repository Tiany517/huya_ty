-- ============================================================
-- 【排查】赛事日剔除为什么"没生效"：两段 SQL 结果一模一样
--
-- 现象：加了 "and dt not in (select dt from excluded_dt)" 的那段，和不加的完全一样
-- 直接结论（推断，见文末核实步骤）：excluded_dt 是空集。
--   NOT IN 空集 = 全部为 TRUE，等于没写这个条件，所以两段结果一模一样。
--
-- 表说明：
--   gamelive.dwd_huya_dim_game_copyright_info_d_a  赛事版权表
--     dt   = 快照分区日（每天一份全量赛事记录，要用「确实存在」的那天，不是赛事日）
--     date = 赛事日期（业务日期），所以要 substr(date,1,10) 卡窗口
--   参考写法见 Desktop\SQL\王者荣耀\王者主播潜力_互动过程指标_日度_20260601_20260922.sql
--   （那份里用的是 a.dt = '2026-09-22' + game_id = 2336）
--
-- 观看表：gamelive.dwt_huya_ayyuid_session_from_server_with_user（igameid = 5937 无畏契约）
--
-- 本文件 5 段 SQL 各自独立，按顺序跑；第 1 段为 0 就不用往下看了。
-- 只读排查，不建表、不写数据。
-- ============================================================


-- ============================================================
-- 第 0 步：先确认「两段结果一样」不是查询工具只跑了最后一段
--   把口径故意改一个必然不同的地方（比如只取 6 月），跑一次；
--   如果结果还是和原来一样，问题不在 SQL，在工具/结果集。
-- ============================================================
select
    substr(dt, 1, 7) as "月份",
    avg(user_cnt) as "日均观看人数"
from (
    select
        dt,
        count(distinct user_ukey) as user_cnt
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where dt between '2026-06-01' and '2026-06-30'   -- 故意只取 6 月
      and tag = 'gameid'
      and htime = 'session'
      and igameid = 5937
      and user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios')
    group by dt
) t
group by substr(dt, 1, 7);


-- ============================================================
-- 第 1 步：赛事版权表的快照分区有没有数据 + 逐层漏斗
--   看哪一列开始掉成 0，就知道是哪个过滤条件把行干掉了。
--   rows_all = 0 → dt='2026-10-31' 这个分区不存在/为空
--   （今天 2026-10-09，这个分区大概率还没产出），换成平台上的最新快照分区再跑。
-- ============================================================
select
    count(*) as "分区总行数",
    count_if(substr(a.date, 1, 10) between '2026-06-01' and '2026-10-31') as "加date窗口",
    count_if(substr(a.date, 1, 10) between '2026-06-01' and '2026-10-31'
             and a.live_type like '%直播%') as "加live_type",
    count_if(substr(a.date, 1, 10) between '2026-06-01' and '2026-10-31'
             and a.live_type like '%直播%'
             and cast(a.game_id as varchar) = '5937') as "加game_id",
    count_if(substr(a.date, 1, 10) between '2026-06-01' and '2026-10-31'
             and a.live_type like '%直播%'
             and cast(a.game_id as varchar) = '5937'
             and a.match_name in (
                 '2026VCTCN第一赛段'
                 , '2026EWC无畏契约项目预选赛'
                 , '26进化者第二幕'
                 , '2026无畏契约不服杯'
                 , '2026伦敦大师赛'
                 , '2026EWC电竞世俱杯无畏契约项目'
                 , '2026VCTCN第二赛段'
                 , '2026进化者第三幕'
                 , '2026上海冠军赛'
             )) as "加match_name"
from gamelive.dwd_huya_dim_game_copyright_info_d_a a
where a.dt = '2026-10-31';


-- ============================================================
-- 第 2 步：看这批赛事名在表里到底长什么样
--   排除"名字对不上"（多空格、大小写、'VCTCN' vs 'VCT CN'、带后缀等）
-- ============================================================
select distinct
    a.match_name as "赛事名",
    a.live_type as "直播类型",
    substr(a.date, 1, 10) as "赛事日期"
from gamelive.dwd_huya_dim_game_copyright_info_d_a a
where a.dt = '2026-10-31'
  and substr(a.date, 1, 10) between '2026-06-01' and '2026-10-31'
  and cast(a.game_id as varchar) = '5937'
order by "赛事日期", "赛事名";


-- ============================================================
-- 第 3 步：excluded_dt 到底有多少天（最直接的判据）
--   days = 0 → 剔除条件空转，两段 SQL 必然一模一样
-- ============================================================
with excluded_dt as (
    select distinct
        substr(a.date, 1, 10) as dt
    from gamelive.dwd_huya_dim_game_copyright_info_d_a a
    where a.dt = '2026-10-31'
      and substr(a.date, 1, 10) between '2026-06-01' and '2026-10-31'
      and a.live_type like '%直播%'
      and a.game_id = 5937
      and a.match_name in (
          '2026VCTCN第一赛段'
          , '2026EWC无畏契约项目预选赛'
          , '26进化者第二幕'
          , '2026无畏契约不服杯'
          , '2026伦敦大师赛'
          , '2026EWC电竞世俱杯无畏契约项目'
          , '2026VCTCN第二赛段'
          , '2026进化者第三幕'
          , '2026上海冠军赛'
      )
)
select
    count(*) as "赛事日天数",
    min(dt) as "最早赛事日",
    max(dt) as "最晚赛事日"
from excluded_dt;


-- ============================================================
-- 第 4 步：即使赛事日不为空，也要看这些天里到底有没有 5937 的观看数据
--   有行 = 这些天真的进了分母，剔除后结果应该变
--   没行 = 剔除的是没有观看数据的空日，结果不变（另一种"看起来没生效"）
-- ============================================================
with excluded_dt as (
    select distinct
        substr(a.date, 1, 10) as dt
    from gamelive.dwd_huya_dim_game_copyright_info_d_a a
    where a.dt = '2026-10-31'
      and substr(a.date, 1, 10) between '2026-06-01' and '2026-10-31'
      and a.live_type like '%直播%'
      and a.game_id = 5937
      and a.match_name in (
          '2026VCTCN第一赛段'
          , '2026EWC无畏契约项目预选赛'
          , '26进化者第二幕'
          , '2026无畏契约不服杯'
          , '2026伦敦大师赛'
          , '2026EWC电竞世俱杯无畏契约项目'
          , '2026VCTCN第二赛段'
          , '2026进化者第三幕'
          , '2026上海冠军赛'
      )
),

daily as (
    select
        dt,
        count(distinct user_ukey) as user_cnt
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where dt between '2026-06-01' and '2026-10-31'
      and tag = 'gameid'
      and htime = 'session'
      and igameid = 5937
      and user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios')
    group by dt
)

select
    e.dt as "赛事日",
    d.user_cnt as "该日5937观看人数"
from excluded_dt e
left join daily d
    on e.dt = d.dt
order by e.dt;


-- ============================================================
-- 第 5 步：确认后的修正版主查询
--   1) a.dt 换成平台上的最新可用快照分区（先填一个确定存在的日期）
--   2) "not in" 换成 not exists 反连接：
--      子查询里只要有 NULL，not in 会让条件整体变 NULL，结果直接变 0 行
--   3) 想看剔除效果，两段同时跑：把 excluded_dt 的过滤注释掉即可
-- ============================================================
with excluded_dt as (
    select distinct
        substr(a.date, 1, 10) as dt
    from gamelive.dwd_huya_dim_game_copyright_info_d_a a
    where a.dt = '2026-10-31'   -- 【待确认】改成最新可用快照分区
      and substr(a.date, 1, 10) between '2026-06-01' and '2026-10-31'
      and a.live_type like '%直播%'
      and a.game_id = 5937
      and a.match_name in (
          '2026VCTCN第一赛段'
          , '2026EWC无畏契约项目预选赛'
          , '26进化者第二幕'
          , '2026无畏契约不服杯'
          , '2026伦敦大师赛'
          , '2026EWC电竞世俱杯无畏契约项目'
          , '2026VCTCN第二赛段'
          , '2026进化者第三幕'
          , '2026上海冠军赛'
      )
),

daily as (
    select
        dt,
        substr(dt, 1, 7) as mth,
        count(distinct user_ukey) as user_cnt
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where dt between '2026-06-01' and '2026-10-31'
      and tag = 'gameid'
      and htime = 'session'
      and igameid = 5937
      and user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios')
    group by dt, substr(dt, 1, 7)
)

select
    d.mth as "月份",
    avg(d.user_cnt) as "月日均观看人数(剔除赛事日)",
    count(distinct d.dt) as "实际参与平均的天数"
from daily d
left join excluded_dt e
    on d.dt = e.dt
where e.dt is null
group by d.mth
order by d.mth;

