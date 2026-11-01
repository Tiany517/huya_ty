-- ============================================================
-- 无畏契约（gameid = 5937）各赛事「日均观看人数」（2026-07-01 ~ 2026-09-30）
--
-- 基准版 = 你 2026-10-09 发来的那份 SQL，本次修正的问题：
--
--   1【致命】原 SQL 用 "a.dt = b.dt" 关联观看表。
--      t1 里的 a.dt 是版权表的「快照分区日」，被 where a.dt='2026-09-30' 写死，
--      所以 join 等价于 "b.dt = '2026-09-30'" —— 整月窗口退化成 9/30 单日，
--      外层 "b.dt between '2026-09-01' and '2026-09-30'" 完全不起作用，
--      最后的 avg(user_cnt) 其实是对单个值求平均 = 9月30日当天的观看人数。
--      正确做法：用版权表的「赛事日期」substr(a.date,1,10) 去和观看表的 dt 对齐
--      （参考 体育留存\斯诺克各赛事_DAU观看UV拉新回流_统一主播表_20260812.sql 的
--        "s.dt between m.start_dt and m.end_dt" 写法）。
--   2【结构】原 SQL 的 start_dt / max_dt 是按「赛事 x 主播」取的，
--      同一赛事里主播覆盖日期不同时，同一个赛事会输出多行（窗口还不一样）。
--      改成按「赛事」取窗口（match_window），主播只用来收敛观看数据。
--   3【窗口】原 SQL 外层保留 start_dt >= '2026-07-01' 的赛事，但观看数据只取 9 月，
--      修好 join 后 7/8 月的赛事会取不到观看数据。观看窗口这里统一放到 7-9 月。
--   4【口径】avg(user_cnt) 的分母原来没写清，这里同时给两个口径：
--        a) 按「有观看数据的天数」平均
--        b) 按「赛事窗口自然日数」平均（缺数据的天按 0 计）
--   5【类型】统一成 varchar：a.uid / session.luid cast 成 varchar；
--      game_id 也 cast 成 varchar 再比（版权表 game_id 与 session.igameid / to_main_games_day.gid 类型不一定一致）。
--   6【写法】原来 left join + where 过滤 b，实际等价 inner join，这里直接写 inner join；
--      substr(date,1,10) 补上上界。
--
-- 口径说明：
--   - 样本 = live_type like '%直播%' 且 room_type = '独立直播间'（官方独立直播间），
--     非官方转播直播间不计入 → 确认这是你要的「赛事观看人数」口径
--   - 观看 = dwt_huya_ayyuid_session_from_server_with_user，tag='gameid'、htime='session'、
--     igameid=5937、user_product 为 4 个 App 端（沿用你原 SQL 的端口径）
--   - 用户按 user_ukey 当天去重；同一赛事内跨主播重复观看只算 1 人
--   - 输出粒度：赛事 x 一行
--
-- 输出：赛事ID / 赛事名 / 品类 / 赛事开始日 / 赛事结束日 / 赛事窗口自然日数 /
--       赛事登记天数 / 有观看数据天数 / 日均观看人数(按有数据天数) /
--       日均观看人数(按窗口自然日) / 观看人数合计 / 实际有数据起止
-- ============================================================
with

-- 1) 赛事 x 主播 x 赛事日期：主播只用于把观看数据收敛到赛事
match_anchor as (
    select distinct
        a.match_id,
        a.match_name,
        cast(a.game_id as varchar) as game_id,
        substr(cast(a.date as varchar), 1, 10) as dt,   -- 关键：赛事日期，不是快照分区 a.dt
        cast(a.uid as varchar) as luid
    from gamelive.dwd_huya_dim_game_copyright_info_d_a a
    where a.dt = '2026-09-30'                           -- 快照分区日
      and substr(cast(a.date as varchar), 1, 10) between '2026-07-01' and '2026-09-30'
      and a.live_type like '%直播%'                     -- 只算直播
      and a.room_type = '独立直播间'                     -- 只算官方独立直播间
      and cast(a.game_id as varchar) = '5937'           -- 无畏契约
),

-- 2) 赛事窗口：按「赛事」取起止日（不按主播，避免同一赛事拆成多行）
match_window as (
    select
        m.match_id,
        m.match_name,
        max(m.game_id) as game_id,
        min(m.dt) as start_dt,
        max(m.dt) as max_dt,
        count(distinct m.dt) as event_reg_days            -- 版权表登记有直播的天数
    from match_anchor m
    group by
        m.match_id,
        m.match_name
),

-- 3) 赛事 x 日 观看人数（用户当天去重，赛事内跨主播去重）
event_day_view as (
    select
        m.match_id,
        m.match_name,
        substr(cast(s.dt as varchar), 1, 10) as dt,
        count(distinct s.user_ukey) as user_cnt
    from match_anchor m
    inner join gamelive.dwt_huya_ayyuid_session_from_server_with_user s
        on cast(s.luid as varchar) = m.luid
       and substr(cast(s.dt as varchar), 1, 10) = m.dt     -- 按赛事日期对齐
    where s.dt between '2026-07-01' and '2026-09-30'       -- 与赛事窗口一致
      and s.tag = 'gameid'---固定写法
      and s.htime = 'session'---固定写法
      and s.igameid = 5937
      and s.user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios')
    group by
        m.match_id,
        m.match_name,
        substr(cast(s.dt as varchar), 1, 10)
),

-- 4) 赛事维度汇总
event_view as (
    select
        match_id,
        match_name,
        count(distinct dt) as data_days,
        sum(user_cnt) as user_cnt_sum,
        min(dt) as data_start_dt,
        max(dt) as data_end_dt
    from event_day_view
    group by
        match_id,
        match_name
),

-- 5) 品类名（游戏维度快照）
game_dim as (
    select
        cast(gid as varchar) as gid,
        max(game_full_name) as game_full_name
    from gamelive.to_main_games_day
    where dt = '2026-09-30'
    group by
        cast(gid as varchar)
)

-- 主查询：赛事 x 一行
select
    w.match_id as "赛事ID",
    w.match_name as "赛事名",
    d.game_full_name as "品类",
    w.start_dt as "赛事开始日",
    w.max_dt as "赛事结束日",
    date_diff('day', cast(w.start_dt as date), cast(w.max_dt as date)) + 1 as "赛事窗口自然日数",
    w.event_reg_days as "赛事登记天数",
    v.data_days as "有观看数据天数",
    round(v.user_cnt_sum / nullif(v.data_days, 0), 0) as "日均观看人数_按有数据天数",
    round(
        v.user_cnt_sum
        / (date_diff('day', cast(w.start_dt as date), cast(w.max_dt as date)) + 1)
    , 0) as "日均观看人数_按窗口自然日",
    v.user_cnt_sum as "观看人数合计",
    v.data_start_dt as "实际有数据开始日",
    v.data_end_dt as "实际有数据结束日"
from match_window w
left join event_view v
    on w.match_id = v.match_id
   and w.match_name = v.match_name
left join game_dim d
    on w.game_id = d.gid
order by
    w.start_dt,
    w.match_name;


-- ============================================================
-- 【校验 SQL】把主查询换成下面任意一段即可，with 里的 CTE 都不用动
-- ============================================================
--
-- 校验 1：每个赛事的窗口 vs 实际有数据的天数（差得多 = 窗口里有没数据的天，
--          这时"按有数据天数"和"按窗口自然日"两个日均会差很多）
--
-- select
--     w.match_id as "赛事ID",
--     w.match_name as "赛事名",
--     w.start_dt as "赛事开始日",
--     w.max_dt as "赛事结束日",
--     w.event_reg_days as "登记天数",
--     coalesce(v.data_days, 0) as "有数据天数"
-- from match_window w
-- left join event_view v
--     on w.match_id = v.match_id and w.match_name = v.match_name
-- order by w.start_dt;
--
-- 校验 2：赛事 x 日 明细（看日均有没有被某一天的极端值带偏）
--
-- select * from event_day_view order by match_name, dt;
--
-- 校验 3：确认快照分区有数据、字段类型对得上
--
-- describe gamelive.dwd_huya_dim_game_copyright_info_d_a;
-- select count(*) as cnt from gamelive.dwd_huya_dim_game_copyright_info_d_a where dt = '2026-09-30';

