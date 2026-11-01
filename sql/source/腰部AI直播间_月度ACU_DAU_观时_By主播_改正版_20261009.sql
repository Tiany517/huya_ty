-- ============================================================
-- 腰部 AI 直播间：按 主播 x 品类 x 月 的 ACU / PCU / 开播天数 / APP DAU / 观时
--
-- 基准版 = 你 2026-10-09 发来的那份 SQL，本次只改「类型 / 日期边界 / 格式」，
-- 口径、字段名、中文列名、指标拆分方式一律没动。
--
-- 窗口：2026-09-01 ~ 2026-09-30（整月）
--   【每月改日期】一共 7 处，改的时候直接搜 '2026-09' / '2026-09-30'：
--     1) anchor_day_raw        dt between '2026-09-01' and '2026-09-30'
--     2) valid_date_lst        dt between '2026-09-01' and '2026-09-30'
--     3) top6h_info            dt between '2026-09-01' and '2026-09-30'
--     4) top6h_info 游戏快照   a.dt = '2026-09-30'
--     5) dau_info              dt between '2026-09-01' and '2026-09-30'
--     6) detail_info 底表      dt between '2026-09-01' and '2026-09-30'
--     7) detail_info 昵称快照  dt = '2026-09-30'
--
-- 本次改了 6 处（都用「【修正】」标了）：
--   1. ID 类型全部统一成 varchar。
--      原来 valid_date_lst 的 join、top6h_info 的 in 没有 cast，而同一份 SQL 别处
--      （dau_info、detail_info）都 cast 了 —— 说明两侧类型本来就不一致。
--      Presto 不会隐式把 bigint 和 varchar 放一起比，缺 cast 会直接报错；
--      如果没报错，说明类型恰好一致、别处的 cast 是多余动作，两种都该统一。
--      统一成 varchar 还有额外好处：13 位 uid 导出到 Excel 不会变科学计数法。
--   2. valid_date_lst 里 '2026-9-30' 补零成 '2026-09-30'。
--      字符串比较下 '2026-10-01' < '2026-9-30'（第 6 位 '1' < '9'），所以 10/11/12 月
--      全都能通过这个上界 —— 这就是你结果里多出一行「10月」月标签的原因。
--   3. top6h_info / dau_info / detail_info 底表原来只写了 dt >= '2026-09-01'，补上上界，
--      不再依赖下游 valid_date_lst 去兜。
--   4. dt 匹配统一成 substr(cast(dt as varchar), 1, 10)。
--      原来是字符串精确匹配，只要一边 'yyyy-MM-dd'、另一边带 ' 00:00:00'，
--      就会静默匹配不上、detail_info 直接被过滤成空表。
--   5. valid_date_lst 的 row_number 加 dt 做兜底排序（user_cnt 相同时剔除哪几天才确定）。
--   6. 删掉子查询里无意义的 order by（不改变结果集）。
--
-- 口径提醒（未改动，要不要改你说）：
--   a. live_mins 字段名是分钟、实际存小时（见 王者荣耀\王者主播潜力_互动过程指标_日度 SQL 注释），
--      所以「日均直播时长(h)」标签是对的；但 anchor_day 用的是 live_hours_only_live，
--      两处同口径不同字段名，真要统一成一个字段可以告诉我。
--   b. 「日均acu」= 按小时 acu_h 排序取前 6 个小时的 acu_h 均值，不是全天日均 ACU（会偏高）。
--      另外 pcu_h > 10 是在 rank 算完之后才过滤的，不影响排名，只影响最后取哪几个小时。
--   c. valid_date_lst 用 4 个端（不含 hmos_kiwi），dau_info 用 5 个端（含 hmos_kiwi），
--      选有效日期的样本和算 DAU 的样本不完全一致。
--   d. acu_allday（detail_info 里的 max_acu）取了但没用到，是死字段，保留原样。
--   e. 名单表 zhgametemp.zty_ai_liveroom_uid_list_v1 没加分区过滤（蓝鲸上传表）。
--      若这张表是从 Excel 上传的，长数字可能被转成科学计数法导致匹配不上，
--      跑完用文末「校验 1」对一下命中率。
-- ============================================================
with

-- 目标主播名单：蓝鲸上传表，已去重（有更新需重新上传/改表名）
target_anchor as (
    select distinct
        cast(uid as varchar) as luid
    from zhgametemp.zty_ai_liveroom_uid_list_v1
),

-- 主播日明细：先在独立 CTE 里完成分区时间 + 业务条件过滤（不掺主播名单）
anchor_day_raw as (
    select
        dt,
        cast(ayyuid as varchar) as luid,   -- 【修正】统一 varchar
        nickname,
        live_hours_only_live
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2026-09-01' and '2026-09-30'   -- 每月改日期
      and live_hours_only_live > 0
),

-- 收敛到目标名单并汇总到「主播 x 日」：join 条件只保留业务关联键 luid
anchor_day as (
    select
        r.dt,
        r.luid,
        max(r.nickname) as nickname,
        sum(r.live_hours_only_live) as live_hours
    from anchor_day_raw r
    inner join target_anchor t
        on r.luid = t.luid
    group by
        r.dt,
        r.luid
),

-- 有效主播：开播天数 >= 5 且 月日均开播时长 > 1h（分母固定 30 = 9 月天数，换月要一起改）
valid_luid_lst as (
    select distinct
        luid
    from (
        select
            luid,
            nickname,
            count(distinct dt) as live_day_cnt,
            avg(live_hours) as avg_live_hours_by_day,
            avg(live_mins) as avg_live_mins_by_day,
            sum(live_hours) / 30 as avg_live_hours,
            sum(live_mins) / 30 as avg_live_mins
        from (
            select
                a.dt,
                a.luid,
                a.nickname,
                round(a.live_hours, 4) as live_hours,
                round(a.live_hours * 60, 1) as live_mins
            from anchor_day a
        ) t_day
        group by
            luid,
            nickname
    ) t
    where live_day_cnt >= 5
      and avg_live_hours > 1
),

-- 有效日期：有效主播当日观看人数里，剔除观看人数最高的 19 天（留下来的才算 9 月有效天）
valid_date_lst as (
    select distinct
        dt
    from (
        select
            dt,
            user_cnt,
            -- 【修正】加 dt 兜底排序，避免 user_cnt 相同时剔哪天不确定
            row_number() over (order by user_cnt desc, dt) as rnk
        from (
            select
                substr(cast(a.dt as varchar), 1, 10) as dt,   -- 【修正】统一成 yyyy-MM-dd
                count(distinct user_ukey) as user_cnt
            from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
            inner join valid_luid_lst b
                on cast(a.luid as varchar) = b.luid   -- 【修正】补 cast（原来是 a.luid = b.luid）
            where a.dt between '2026-09-01' and '2026-09-30'   -- 【修正】'2026-9-30' 补零
              and a.tag = 'gameid'---固定写法
              and a.htime = 'session'---固定写法
              and a.user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios')
            group by
                substr(cast(a.dt as varchar), 1, 10)
        ) t_daily
    ) t_rnk
    where rnk >= 20
)

---【腰部ai直播间 change:有效天数】
,top6h_info as (
    select
        luid,
        gameid,
        game_full_name,
        dt,
        avg(acu_h) as acu,
        max(coalesce(pcu_h, 0)) as pcu
    from (
        select
            luid,
            gameid,
            game_full_name,
            dt,
            h_tag,
            acu_h,
            pcu_h,
            rank() over (partition by luid, gameid, game_full_name, dt order by acu_h desc) as rk
        from (
            select
                cast(ayyuid as varchar) as luid,   -- 【修正】统一 varchar
                gameid,
                dt,
                substr(time_value, 12, 2) as h_tag,
                avg(all_users) as acu_h,
                max(coalesce(all_users, 0)) as pcu_h
            from gamelive.dw_huya_online_users
            where dt between '2026-09-01' and '2026-09-30'   -- 【修正】补上界，每月改日期
              and tag = 'server_ayyuid_gameid_session'        -- gameid 分区
              ---and tag = 'server_ayyuid_liveid_session'    -- liveid 分区
              and cast(ayyuid as varchar) in (select luid from valid_luid_lst)   -- 【修正】补 cast
            group by
                cast(ayyuid as varchar),
                gameid,
                dt,
                substr(time_value, 12, 2)
        ) a
        left join (
            select
                gid,
                game_full_name
            from gamelive.to_main_games_day
            where dt = '2026-09-30'   -- 每月改日期（游戏快照）
            group by
                gid,
                game_full_name
        ) b
            on a.gameid = b.gid
    ) t1
    where rk <= 6
      and game_full_name != '其他直播'
      and pcu_h > 10
    group by
        luid,
        gameid,
        game_full_name,
        dt
)

,dau_info as (
    select
        dt,
        cast(luid as varchar) as luid,   -- 【修正】统一 varchar
        igameid as gameid,
        count(distinct user_ukey) as app_dau,
        sum(user_duration / 60000 / 60) as user_duration   -- 毫秒 -> 小时
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where dt between '2026-09-01' and '2026-09-30'   -- 【修正】补上界，每月改日期
      and tag = 'gameid'---固定写法
      and htime = 'session'---固定写法
      and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')   -- app 端
      and cast(luid as varchar) in (select luid from valid_luid_lst)   -- 每次检查更新
    group by
        dt,
        cast(luid as varchar),
        igameid
)

,detail_info as (
    select
        m_tag,
        w_tag,
        a.dt,
        a.luid,
        d.nickname,
        a.game_name,
        a.gameid,
        max_acu as acu_allday,
        max_pcu,
        live_mins,
        b.acu,
        c.app_dau,
        c.user_duration as app_view_mins,
        c.user_duration / c.app_dau as gs_rj
    from (
        select
            date_trunc('month', date(dt)) as m_tag,
            date_trunc('week', date(dt)) as w_tag,
            dt,
            cast(ayyuid as varchar) as luid,   -- 【修正】统一 varchar
            gameid,
            game_name,
            max(coalesce(acu, 0)) as max_acu,
            max(coalesce(pcu, 0)) as max_pcu,
            sum(live_mins) as live_mins   -- 字段名是 mins，单位实际是小时
        from gamelive.dm_huya_ayyuid_detail_day
        where dt between '2026-09-01' and '2026-09-30'   -- 【修正】补上界，每月改日期
          and cast(ayyuid as varchar) in (select luid from valid_luid_lst)   -- 每次检查更新
        group by
            date_trunc('month', date(dt)),
            date_trunc('week', date(dt)),
            dt,
            cast(ayyuid as varchar),
            gameid,
            game_name
    ) a
    left join top6h_info b
        on a.luid = b.luid
       and a.dt = b.dt
       and a.gameid = b.gameid
    left join dau_info c
        on a.luid = c.luid
       and a.dt = c.dt
       and a.gameid = c.gameid
    left join (
        -- 昵称维度：若这张表不存在或 uid 不是主播 uid，改成 gamelive.dim_huya_ayyuid_info（nick / yyid / uid）
        select
            cast(uid as varchar) as uid,
            max(nickname) as nickname
        from gamelive.dim_huya_yyuid_info
        where dt = '2026-09-30'   -- 每次检查更新
        group by
            cast(uid as varchar)
    ) d
        on a.luid = d.uid   -- 【修正】两侧都是 varchar
    where max_pcu > 10
      and game_name != '其他直播'
      and substr(cast(a.dt as varchar), 1, 10) in (select dt from valid_date_lst)   -- 9月有效开播日
    group by
        m_tag,
        w_tag,
        a.dt,
        a.luid,
        d.nickname,
        a.game_name,
        a.gameid,
        max_acu,
        max_pcu,
        live_mins,
        b.acu,
        c.app_dau,
        c.user_duration
)   -- 每月改日期

-- 主查询：主播 x 品类 x 月
select
    m_tag as "月标签"
    , game_name as "品类"
    , luid as "主播uid"
    , nickname as "主播昵称"
    , acu as "日均acu"
    , pcu as "最高pcu"
    , kbd_cnt as "开播天数"
    , live_mins as "日均直播时长(h)"
    , app_dau as "日均appdau"
    , app_view_mins as "日均观时(h)"
    , gs_rj as "日均人均观时(min)"
    , first_yb_m as "首次腰部月份"
    , acu_type as "acu分层"
from (
    select
        m_tag,
        game_name,
        luid,
        nickname,
        acu,
        pcu,
        kbd_cnt,
        live_mins,
        app_view_mins,
        app_dau,
        gs_rj,
        min(m_tag) over (partition by game_name, luid) as first_yb_m,
        case
            when acu >= 2000 then '头部'
            when acu >= 1000 then '颈部'
            when acu >= 100 then '腰部'
            else '尾部'
        end as acu_type
    from (
        select
            m_tag,
            game_name,
            luid,
            nickname,
            coalesce(avg(acu), 0) as acu,
            max(max_pcu) as pcu,
            count(distinct dt) as kbd_cnt,
            avg(live_mins) as live_mins,
            avg(app_view_mins) as app_view_mins,
            avg(app_dau) as app_dau,
            avg(gs_rj) * 60 as gs_rj
        from detail_info
        group by
            m_tag,
            game_name,
            luid,
            nickname
    ) t
    where acu >= 100
) t1
order by
    m_tag desc,
    game_name desc,
    first_yb_m desc,
    acu desc;

-- ============================================================
-- 【校验 SQL】把上面的主查询换成下面任意一段即可，with 里的 CTE 都不用动
-- ============================================================
--
-- 校验 1：名单命中率（名单 uid 和窗口内有开播的 uid 对不对得上）
--   两边数差不多 = ID 类型/格式没问题；差很多 = 名单 uid 不是 ayyuid 或上传时被转成了科学计数法
--
-- select
--     (select count(*) from target_anchor) as "名单uid数",
--     (select count(*) from valid_luid_lst) as "有效主播数",
--     (select count(*) from valid_date_lst) as "有效日期数",
--     (select count(distinct dt) from anchor_day) as "窗口内名单开播天数";
--
-- 校验 2：月份分布（改完之后这里应该只剩 2026-09 一种 m_tag）
--   月标签是 date_trunc('month', ...) 的结果，显示成「当月 1 号」，不是某一天的数据
--
-- select
--     date_trunc('month', date(dt)) as "月标签",
--     count(distinct dt) as "天数",
--     min(dt) as "最早日",
--     max(dt) as "最晚日"
-- from detail_info
-- group by date_trunc('month', date(dt))
-- order by "月标签";
--
-- 校验 3：看看 ID / dt 到底是什么类型和格式（先 describe，避免再猜）
--
-- describe gamelive.dwt_huya_ayyuid_session_from_server_with_user;
-- describe gamelive.dm_huya_ayyuid_detail_day;
-- describe gamelive.dw_huya_online_users;
-- describe zhgametemp.zty_ai_liveroom_uid_list_v1;
--
-- select distinct dt from gamelive.dwt_huya_ayyuid_session_from_server_with_user
-- where dt between '2026-09-01' and '2026-09-30' order by dt limit 5;

