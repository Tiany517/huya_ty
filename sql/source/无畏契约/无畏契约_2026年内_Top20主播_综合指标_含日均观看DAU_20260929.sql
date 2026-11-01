-- ============================================================
-- 无畏契约（游戏ID = 5937，品类 = 网游竞技）2026 年内 Top20 主播 综合指标（含日均观看DAU）
--
-- 取数窗口：2026-01-01 ~ 2026-09-28
--   三张源表最新可用分区均为 2026-09-28：
--     gamelive.dm_huya_ayyuid_detail_day                              （主播 x 日 开播/人气）
--     gamelive.dwt_huya_ayyuid_session_from_server_with_user           （主播 x 日 观看会话）
--     gamelive.dws_huya_revenue_detail_d_i                             （礼物流水明细）
--
-- 输出粒度：主播 uid 一行（不是主播 x 日）
--
-- 口径：
--   1) 开播/人气：gamelive.dm_huya_ayyuid_detail_day，限 gameid='5937' 且 live_hours_only_live > 0
--        开播天数 = count(distinct dt)
--        日均acu  = 窗口内按天 acu 的算术平均 avg(acu)
--   2) 日均观看DAU：沿用 Desktop\SQL\特定主播By月去重DAU\流量相关\
--         By月份主播观看月日均DAU_及对应的归属游戏.sql 的口径
--        - 每日去重观看人数：count(distinct user_ukey)，按 dt + luid 粒度
--        - 日均观看DAU = 窗口内各天去重观看人数之和 / 该主播有观看记录的天数
--          （即 sum(day_uv) / count(distinct dt)，与参考 SQL 的 sum(user_cnt)/count(distinct dt) 一致）
--        - 观看表过滤：tag='gameid'、htime='session'、igameid=5937
--   3) 打赏流水：gamelive.dws_huya_revenue_detail_d_i，限 game_id=5937、user_consume_amount>0、
--        creator_uid 非空；付费人数 = count(distinct ext['ukey'])
--   4) 三张表各自先在独立 CTE 内完成分区时间与业务条件过滤，再在 CTE 内聚合到主播 uid，
--      最后通过统一的 uid 名单 left join（join 条件只保留业务关联键 ayyuid）
--   5) 主播昵称取窗口内最后一次开播日的昵称 max_by(nickname, dt)
--
-- 三套排名：
--   rn_revenue   按打赏流水降序（全量主播），主表排序口径，沿用 主机游戏\主机品类Top20主播打赏流水.sql
--   rn_acu_valid 按日均acu 降序，限开播天数 >= 30（剔除偶发开播）
--   rn_dau_valid 按日均观看DAU 降序，限有观看记录天数 >= 30（剔除偶发开播）
-- ============================================================

with

-- 1) 主播开播 / 人气 / 弹幕 / 拉新指标：限无畏契约
anchor_live as (
    select
        ayyuid,
        max_by(nickname, dt) as nickname,
        count(distinct dt) as live_days,
        sum(live_hours_only_live) as total_live_hours,
        avg(acu) as avg_acu,
        max(pcu) as max_pcu,
        sum(view_mins) as total_view_hours,
        sum(chatalk_cnt) as total_chat_cnt,
        sum(platform_new_adus) as platform_new_users
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2026-01-01' and '2026-09-28'
      and gameid = '5937'
      and live_hours_only_live > 0
    group by ayyuid
),

-- 2) 主播每日去重观看人数（观察表口径）：限无畏契约
daily_view as (
    select
        dt,
        cast(luid as varchar) as ayyuid,   -- 观看表 luid 与主播日表 ayyuid 类型不一致，统一转 varchar
        count(distinct user_ukey) as day_uv
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where dt between '2026-01-01' and '2026-09-28'
      and tag = 'gameid'
      and htime = 'session'
      and igameid = 5937
    group by dt, luid
),

-- 3) 主播观看DAU：日均 = 各天去重观看人数之和 / 有观看记录的天数
anchor_view as (
    select
        ayyuid,
        count(distinct dt) as view_days,
        sum(day_uv) as total_view_uv,
        sum(day_uv) / count(distinct dt) as avg_view_dau
    from daily_view
    group by ayyuid
),

-- 4) 主播打赏流水：限无畏契约
anchor_revenue as (
    select
        cast(creator_uid as varchar) as ayyuid,   -- 流水表 creator_uid 为 bigint，统一转 varchar
        sum(user_consume_amount) as total_consume_amt,
        count(distinct ext['ukey']) as pay_users
    from gamelive.dws_huya_revenue_detail_d_i
    where dt between '2026-01-01' and '2026-09-28'
      and game_id = 5937
      and user_consume_amount > 0
      and creator_uid is not null
    group by creator_uid
),

-- 5) 统一 uid 名单：三张表任一侧出现的主播都保留
uid_list as (
    select ayyuid from anchor_live
    union
    select ayyuid from anchor_view
    union
    select ayyuid from anchor_revenue
),

-- 6) 合并三侧指标
base as (
    select
        u.ayyuid,
        l.nickname,
        coalesce(l.live_days, 0) as live_days,
        coalesce(l.total_live_hours, 0) as total_live_hours,
        coalesce(l.avg_acu, 0) as avg_acu,
        coalesce(l.max_pcu, 0) as max_pcu,
        coalesce(l.total_view_hours, 0) as total_view_hours,
        coalesce(l.total_chat_cnt, 0) as total_chat_cnt,
        coalesce(l.platform_new_users, 0) as platform_new_users,
        coalesce(v.view_days, 0) as view_days,
        coalesce(v.total_view_uv, 0) as total_view_uv,
        v.avg_view_dau,
        coalesce(r.total_consume_amt, 0) as total_consume_amt,
        coalesce(r.pay_users, 0) as pay_users
    from uid_list u
    left join anchor_live l
      on u.ayyuid = l.ayyuid
    left join anchor_view v
      on u.ayyuid = v.ayyuid
    left join anchor_revenue r
      on u.ayyuid = r.ayyuid
),

-- 7) 三套排名（不符合门槛的主播被排到后面，不影响达标主播的名次）
ranked as (
    select
        *,
        row_number() over (order by total_consume_amt desc, ayyuid) as rn_revenue,
        row_number() over (
            order by case when live_days >= 30 then 0 else 1 end,
                     avg_acu desc,
                     ayyuid
        ) as rn_acu_valid,
        row_number() over (
            order by case when view_days >= 30 then 0 else 1 end,
                     coalesce(avg_view_dau, 0) desc,
                     ayyuid
        ) as rn_dau_valid
    from base
)

select
    ayyuid as "主播uid",
    nickname as "主播昵称",
    live_days as "开播天数",
    round(total_live_hours, 1) as "有效开播时长_小时",
    round(total_live_hours / nullif(live_days, 0), 2) as "日均开播时长_小时",
    round(avg_acu, 0) as "日均acu",
    max_pcu as "最高pcu",
    view_days as "有观看记录天数",
    round(avg_view_dau, 0) as "日均观看dau",
    total_view_uv as "累计观看uv",
    round(total_view_hours, 0) as "累计观看时长_小时",
    total_chat_cnt as "累计弹幕次数",
    platform_new_users as "平台新增用户数",
    round(total_consume_amt, 2) as "打赏流水_元",
    pay_users as "付费人数",
    rn_revenue as "流水排名",
    rn_acu_valid as "acu排名_开播30天以上",
    rn_dau_valid as "dau排名_观看30天以上"
from ranked
where rn_revenue <= 30
   or rn_acu_valid <= 30
   or rn_dau_valid <= 30
order by rn_revenue;
