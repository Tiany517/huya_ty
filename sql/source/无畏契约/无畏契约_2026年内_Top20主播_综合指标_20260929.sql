-- ============================================================
-- 无畏契约（游戏ID = 5937，品类=网游竞技）2026 年内 Top20 主播 综合指标
--
-- 取数窗口：2026-01-01 ~ 2026-09-28
--   两段数据源最新可用分区均为 2026-09-28：
--     gamelive.dm_huya_ayyuid_detail_day
--     gamelive.dws_huya_revenue_detail_d_i
--
-- 输出粒度：主播 uid 一行（不是主播 x 日）
--
-- 口径：
--   1) 开播/人气/弹幕/拉新来自 gamelive.dm_huya_ayyuid_detail_day
--      - 限 gameid = '5937'（无畏契约）
--      - 仅保留当日真的开播：live_hours_only_live > 0
--      - 开播天数 = 该主播在窗口内有效开播的自然日数（count distinct dt）
--      - 日均 acu = 窗口内按天 acu 的算术平均（avg(acu)）
--      - 注：live_mins 与 live_hours_only_live 在本表样本中取值一致，单位均为小时
--   2) 打赏流水来自 gamelive.dws_huya_revenue_detail_d_i
--      - 限 game_id = 5937、user_consume_amount > 0、creator_uid 非空
--      - 付费人数 = count(distinct ext['ukey'])
--   3) 两段各自先在独立 CTE 内完成分区时间与业务条件过滤，再按主播 uid 聚合后关联
--      （明细事实表的业务过滤写在 CTE 内，join 条件只保留业务关联键 ayyuid）
--   4) 主播昵称取窗口内最后一次开播日的昵称（max_by(nickname, dt)）
--
-- 说明：用户仅要求「Top20 主播」，未指定排序指标，故本 SQL 同时给出
--       流水 / 日均acu / 开播时长 三套排名，主表按打赏流水排序（沿用
--       Desktop\SQL\主机游戏\主机品类Top20主播打赏流水.sql 的排序口径）。
-- ============================================================

with

-- 主播开播 / 人气 / 弹幕 / 拉新指标：限无畏契约
anchor_live as (
    select
        ayyuid,
        max_by(nickname, dt) as nickname,
        count(distinct dt) as live_days,
        sum(live_hours_only_live) as total_live_hours,
        avg(acu) as avg_acu,
        max(pcu) as max_pcu,
        sum(dau) as sum_dau,
        sum(view_mins) as total_view_hours,
        sum(chatalk_cnt) as total_chat_cnt,
        sum(platform_new_adus) as platform_new_users
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2026-01-01' and '2026-09-28'
      and gameid = '5937'
      and live_hours_only_live > 0
    group by ayyuid
),

-- 主播打赏流水：限无畏契约
anchor_revenue as (
    select
        creator_uid as ayyuid,
        sum(user_consume_amount) as total_consume_amt,
        count(distinct ext['ukey']) as pay_users
    from gamelive.dws_huya_revenue_detail_d_i
    where dt between '2026-01-01' and '2026-09-28'
      and game_id = 5937
      and user_consume_amount > 0
      and creator_uid is not null
    group by creator_uid
),

-- 两侧并集：以开播侧为主，流水侧可能有少量只在流水表出现的主播
anchor_all as (
    select
        coalesce(l.ayyuid, r.ayyuid) as ayyuid,
        l.nickname,
        coalesce(l.live_days, 0) as live_days,
        coalesce(l.total_live_hours, 0) as total_live_hours,
        coalesce(l.avg_acu, 0) as avg_acu,
        coalesce(l.max_pcu, 0) as max_pcu,
        coalesce(l.sum_dau, 0) as sum_dau,
        coalesce(l.total_view_hours, 0) as total_view_hours,
        coalesce(l.total_chat_cnt, 0) as total_chat_cnt,
        coalesce(l.platform_new_users, 0) as platform_new_users,
        coalesce(r.total_consume_amt, 0) as total_consume_amt,
        coalesce(r.pay_users, 0) as pay_users
    from anchor_live l
    full outer join anchor_revenue r
      on l.ayyuid = r.ayyuid
),

-- 三套排名
ranked as (
    select
        *,
        row_number() over (order by total_consume_amt desc, ayyuid) as rn_revenue,
        row_number() over (order by avg_acu desc, ayyuid) as rn_acu,
        row_number() over (order by total_live_hours desc, ayyuid) as rn_live_hours
    from anchor_all
)

select
    ayyuid as "主播uid",
    nickname as "主播昵称",
    live_days as "开播天数",
    round(total_live_hours, 1) as "有效开播时长_小时",
    round(total_live_hours / nullif(live_days, 0), 2) as "日均开播时长_小时",
    round(avg_acu, 0) as "日均acu",
    max_pcu as "最高pcu",
    sum_dau as "累计观看dau",
    round(total_view_hours, 0) as "累计观看时长_小时",
    total_chat_cnt as "累计弹幕次数",
    platform_new_users as "平台新增用户数",
    round(total_consume_amt, 2) as "打赏流水_元",
    pay_users as "付费人数",
    rn_revenue as "流水排名",
    rn_acu as "acu排名",
    rn_live_hours as "开播时长排名"
from ranked
where rn_revenue <= 30
   or rn_acu <= 30
   or rn_live_hours <= 30
order by rn_revenue;
