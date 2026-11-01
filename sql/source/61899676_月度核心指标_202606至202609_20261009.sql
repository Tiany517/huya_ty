-- ============================================================
-- 单主播月度核心指标：61899676（2026-06 ~ 2026-09，按月）
--
-- 指标（6 个，全部按月输出）：
--   1. 有效acu       = 当月「开播日」的日均 ACU（avg(acu)，分母 = 当月开播天数）
--   2. 日均互动人数  = 当月每日去重发弹幕人数之和 / 当月开播天数
--   3. 订阅总量      = 当月最后一个快照日的累计订阅人数（订阅表是全量关系快照）
--   4. 开播时长      = sum(live_hours_only_live)，单位小时（不限品类汇总）
--   5. 付费礼物人数  = count(distinct ext['ukey'])，当月送礼用户去重数
--   6. 礼物收入      = sum(user_consume_amount)，单位元
--
-- 数据源（都沿用你们已有 SQL 的口径）：
--   开播/人气   gamelive.dm_huya_ayyuid_detail_day            参考 特定主播By月去重DAU\主播有效开播时长_打赏流水_有效支付人数查询.sql
--   弹幕人数    gamelive.gamelive_huya_danmu_log               参考 王者荣耀\王者主播潜力_互动过程指标_日度_20260601_20260922.sql
--   订阅快照    gamelive.dwd_huya_dy_user（tag='huya'）        同上
--   礼物流水    gamelive.dws_huya_revenue_detail_d_i           参考 主机游戏\主机品类Top20主播打赏流水.sql
--   主播映射    gamelive.dim_huya_ayyuid_info（nick/yyid/uid） 参考 特定主播By月去重DAU\赛事版权_赛事ID_主播对应关系.sql
--
-- 关于 61899676 这个号（重要）：
--   你们底表里的主播 uid（dim_huya_ayyuid_info.uid / 流水表 creator_uid / 主播日表 ayyuid）通常是 13 位，
--   8 位的号很可能是 yyid（虎牙号）而不是 ayyuid。所以这里先用 dim 表把 uid / yyid 两种情况都试一遍：
--     - dim 表命中  -> 用映射出来的 uid 去查所有指标（推荐）
--     - dim 表没命中 -> 兜底直接把它当 ayyuid 用
--   跑之前/跑之后都建议先执行文末「校验 1」看映射结果，确认查的是对的主播。
--
-- 口径说明与待确认项：
--   a. 「有效acu」这里 = 当月开播日的日均 ACU。如果你们的「有效」是指
--      剔除赛事日 / 剔除短播日（开播 < 10 分钟）后的日均 ACU，告诉我品类 gameid，我加赛事日剔除。
--   b. 「互动」这里 = 发弹幕去重人数（弹幕表 luid 去重，passed='0'，过滤空值），
--      不含点赞/分享；如果口径不同需要换表，跟我说。
--   c. 日均互动人数分母用「当月开播天数」；同时把 互动人数合计 / 有弹幕天数 一并输出，方便你换分母核对。
--   d. 订阅表只按 dt 长度 = 10 的天级分区取，tag='huya'（主站订阅）；「订阅总量」是快照口径（累计），
--      不是当月新增。要当月净增在 subscribe_month 里加 lag 即可（文末给了片段）。
--   e. 礼物收入不限品类（全平台）且未剔刷单。要限品类加 game_id；要去刷单换成
--      zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i（户外公会流水 SQL 用的就是这张）。
--   f. 时间窗 2026-06-01 ~ 2026-09-30；交付时请以各表实际最新可用分区为准。
--
-- 输出：月份 / 主播uid / 主播昵称 / 有效acu / 日均互动人数 / 订阅总量 / 开播时长(h) /
--       付费礼物人数 / 礼物收入(元) / 开播天数 / 互动人数合计 / 有弹幕天数 / 订阅快照日
-- ============================================================
with

-- 1) 主播映射：把 61899676 按 uid / yyid 两种可能都试一遍
anchor_map as (
    select distinct
        cast(uid as varchar) as luid,
        max(nick) as nick
    from gamelive.dim_huya_ayyuid_info
    where dt = '2026-09-30'
      and (
          cast(uid as varchar) = '61899676'
          or cast(yyid as varchar) = '61899676'
      )
    group by
        cast(uid as varchar)
),

-- 2) 目标主播集合：dim 命中就用映射结果；没命中就兜底把原号当 ayyuid（兜底支路在命中时为空）
target_anchor as (
    select luid from anchor_map
    union all
    select '61899676' as luid
    where not exists (select 1 from anchor_map)
),

-- 3) 开播：按月 开播天数 / 开播时长 / 日均acu（只算真的开播的日子）
live_month as (
    select
        substr(cast(dt as varchar), 1, 7) as month,
        cast(ayyuid as varchar) as luid,
        max_by(nickname, dt) as nickname,
        count(distinct substr(cast(dt as varchar), 1, 10)) as live_days,
        sum(live_hours_only_live) as live_hours,
        avg(acu) as avg_acu
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2026-06-01' and '2026-09-30'
      and live_hours_only_live > 0
      and cast(ayyuid as varchar) in (select luid from target_anchor)
    group by
        substr(cast(dt as varchar), 1, 7),
        cast(ayyuid as varchar)
),

-- 4) 互动：每日去重发弹幕人数（弹幕表 dt 带时分秒，所以统一截前 10 位）
interact_day as (
    select
        substr(cast(d.dt as varchar), 1, 10) as dt,
        count(distinct d.luid) as interact_user_cnt
    from gamelive.gamelive_huya_danmu_log d
    where d.dt between '2026-06-01' and '2026-09-30'
      and d.passed = '0'
      and d.lpid is not null
      and d.luid is not null
      and d.time is not null
      and cast(d.lpid as varchar) in (select luid from target_anchor)
    group by
        substr(cast(d.dt as varchar), 1, 10)
),

interact_month as (
    select
        substr(dt, 1, 7) as month,
        sum(interact_user_cnt) as interact_user_sum,
        count(distinct dt) as interact_days
    from interact_day
    group by
        substr(dt, 1, 7)
),

-- 5) 订阅：每日全量关系快照 -> 取当月最后一天的人数 = 累计订阅总量
--    多取 2026-05-31 一天，方便需要时算 6 月净增
subscribe_snap as (
    select
        substr(cast(s.dt as varchar), 1, 10) as dt,
        count(distinct s.yyuid) as subscribe_total_cnt
    from gamelive.dwd_huya_dy_user s
    where s.dt between '2026-05-31' and '2026-09-30'
      and s.tag = 'huya'
      and length(cast(s.dt as varchar)) = 10
      and s.yyuid is not null
      and cast(s.ayyuid as varchar) in (select luid from target_anchor)
    group by
        substr(cast(s.dt as varchar), 1, 10)
),

subscribe_month as (
    select
        substr(dt, 1, 7) as month,
        max_by(subscribe_total_cnt, dt) as subscribe_total_cnt,   -- 当月最后一次快照
        max(dt) as snapshot_dt
    from subscribe_snap
    group by
        substr(dt, 1, 7)
),

-- 6) 礼物：付费人数 + 礼物收入（creator_uid = 主播 uid；ext['ukey'] = 送礼用户）
revenue_month as (
    select
        substr(cast(dt as varchar), 1, 7) as month,
        sum(user_consume_amount) as gift_income,
        count(distinct ext['ukey']) as pay_user_cnt
    from gamelive.dws_huya_revenue_detail_d_i
    where dt between '2026-06-01' and '2026-09-30'
      and user_consume_amount > 0
      and creator_uid is not null
      and cast(creator_uid as varchar) in (select luid from target_anchor)
    group by
        substr(cast(dt as varchar), 1, 7)
)

-- 主查询：按月拼装 6 个指标
select
    m.month as "月份"
    , m.luid as "主播uid"
    , max(m.nickname) as "主播昵称"
    , round(m.avg_acu, 1) as "有效acu"
    , round(i.interact_user_sum / nullif(m.live_days, 0), 1) as "日均互动人数"
    , s.subscribe_total_cnt as "订阅总量"
    , round(m.live_hours, 1) as "开播时长(h)"
    , r.pay_user_cnt as "付费礼物人数"
    , round(r.gift_income, 2) as "礼物收入(元)"
    , m.live_days as "开播天数"
    , i.interact_user_sum as "互动人数合计"
    , i.interact_days as "有弹幕天数"
    , s.snapshot_dt as "订阅快照日"
from live_month m
left join interact_month i
    on m.month = i.month
left join subscribe_month s
    on m.month = s.month
left join revenue_month r
    on m.month = r.month
group by
    m.month,
    m.luid,
    m.avg_acu,
    m.live_hours,
    m.live_days,
    i.interact_user_sum,
    i.interact_days,
    s.subscribe_total_cnt,
    s.snapshot_dt,
    r.pay_user_cnt,
    r.gift_income
order by
    m.month;


-- ============================================================
-- 【校验 / 可选】把上面的主查询换成下面任意一段即可，with 里的 CTE 都不用动
-- ============================================================
--
-- 校验 1：61899676 到底映射到哪个主播 uid（最关键的一步）
--   mapped_uid 有值 = dim 表命中（可能是按 yyid 命中的）；
--   同时看 nickname 是不是你要的那个主播，别把同名/同号的号查串了。
--
-- select
--     m.luid as "映射出的主播uid",
--     m.nick as "主播昵称",
--     (select count(*) from target_anchor) as "目标主播数"
-- from anchor_map m;
--
-- 校验 2：按天明细（月度数字对不上时，用这个逐日核对）
--   互动是按天去重的，不会出现跨天重复计数
--
-- select
--     l.dt as "日期",
--     l.live_hours as "当日开播时长(h)",
--     l.acu as "当日acu",
--     l.live_mins as "当日开播时长(min)",
--     i.interact_user_cnt as "当日互动人数"
-- from (
--     select
--         substr(cast(dt as varchar), 1, 10) as dt,
--         sum(live_hours_only_live) as live_hours,
--         sum(live_hours_only_live) * 60 as live_mins,
--         avg(acu) as acu
--     from gamelive.dm_huya_ayyuid_detail_day
--     where dt between '2026-06-01' and '2026-09-30'
--       and live_hours_only_live > 0
--       and cast(ayyuid as varchar) in (select luid from target_anchor)
--     group by substr(cast(dt as varchar), 1, 10)
-- ) l
-- left join interact_day i
--     on l.dt = i.dt
-- order by l.dt;
--
-- 校验 3：各源表在 6~9 月的实际可用分区（确认没有缺月）
--
-- select 'detail_day' as tbl, min(dt) as min_dt, max(dt) as max_dt, count(distinct dt) as days
-- from gamelive.dm_huya_ayyuid_detail_day
-- where dt between '2026-06-01' and '2026-09-30'
-- union all
-- select 'revenue', min(dt), max(dt), count(distinct dt)
-- from gamelive.dws_huya_revenue_detail_d_i
-- where dt between '2026-06-01' and '2026-09-30'
-- union all
-- select 'subscribe', min(substr(cast(dt as varchar),1,10)), max(substr(cast(dt as varchar),1,10)), count(distinct substr(cast(dt as varchar),1,10))
-- from gamelive.dwd_huya_dy_user
-- where dt between '2026-06-01' and '2026-09-30'
--   and tag = 'huya'
--   and length(cast(dt as varchar)) = 10;
--
-- 可选：当月订阅净增（本月末快照 - 上月末快照）
-- 在 subscribe_month 里把最后一列换成：
--     max_by(subscribe_total_cnt, dt)
--       - lag(max_by(subscribe_total_cnt, dt)) over (order by substr(dt, 1, 7)) as subscribe_net_add

