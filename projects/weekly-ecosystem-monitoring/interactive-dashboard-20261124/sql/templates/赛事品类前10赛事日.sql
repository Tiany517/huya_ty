-- Presto 可复用模板：按品类选取赛事关联 DAU 最高的前 10% 赛事日。
-- 替换参数：{{SNAPSHOT_DATE}}、{{START_DATE}}、{{END_DATE}}。
-- 结果契约：输出粒度 dt × gameid；必须唯一。event_day_count 为该品类有赛事关联观看的正向赛事日数。
-- 选取规则：event_dau 降序、dt 升序打破并列；rn <= ceil(event_day_count * 0.10)。
-- 口径边界：赛事 DAU 为 APP 四端 is_app=1，不含鸿蒙；这是赛事关联热度日，不等同官方赛程窗口。
-- DEPRECATED：前10%只保留历史高流量日期，会漏掉中型但真实赛事。
-- 新流程：`赛事品类登记日.sql` + `赛事单周期统计.sql` -> `build_major_event_days.py`
-- -> `build_daily_v12.py --event-days <major_event_days.csv> --event-meta <major_event_manifest.json>`。
WITH copyright_raw AS (
    SELECT
        substr(cast(day AS varchar), 1, 10) AS dt,
        CASE
            WHEN cast(game_id AS varchar) = '无畏契约' THEN '5937'
            WHEN cast(game_id AS varchar) = '王者万象棋' THEN '8127'
            ELSE cast(game_id AS varchar)
        END AS gameid,
        cast(uid AS varchar) AS luid,
        cast(match_id AS varchar) AS match_id
    FROM zhgametemp.hss_huya_dim_game_copyright_info_d_a
    WHERE dt = '{{SNAPSHOT_DATE}}'
      AND substr(cast(day AS varchar), 1, 10) BETWEEN '{{START_DATE}}' AND '{{END_DATE}}'
      AND live_type LIKE '%直播%'
      AND uid IS NOT NULL
      AND match_id IS NOT NULL
),
anchor_day AS (
    -- 同一主播同一天同一品类只保留一条赛事关联记录，避免多赛事放大观看用户行。
    SELECT DISTINCT dt, gameid, luid
    FROM copyright_raw
    WHERE trim(luid) NOT IN ('', '0', '-1')
),
watch_filtered AS (
    -- 观看事实先在独立 CTE 完成日期、端和有效观看过滤，再与赛事主播日关联。
    SELECT
        dt,
        cast(gameid AS varchar) AS gameid,
        cast(ayyuid AS varchar) AS luid,
        ukey
    FROM bp.yyzc_dws_with_user_by_gameid_ayyuid_ukey_day
    WHERE dt BETWEEN '{{START_DATE}}' AND '{{END_DATE}}'
      AND is_app = 1
      AND is_watch > 0
      AND is_black = 0
      AND ukey IS NOT NULL
),
category_event_user_day AS (
    -- 去掉一个用户在同品类同一天观看多个赛事主播造成的重复，用于计算赛事关联 DAU。
    SELECT DISTINCT w.dt, w.gameid, w.ukey
    FROM watch_filtered w
    INNER JOIN anchor_day a
        ON w.dt = a.dt
       AND w.gameid = a.gameid
       AND w.luid = a.luid
),
category_event_daily AS (
    SELECT dt, gameid, count(*) AS event_dau
    FROM category_event_user_day
    GROUP BY dt, gameid
),
ranked AS (
    SELECT
        dt,
        gameid,
        event_dau,
        count(*) OVER (PARTITION BY gameid) AS event_day_count,
        row_number() OVER (
            PARTITION BY gameid
            ORDER BY event_dau DESC, dt ASC
        ) AS rn
    FROM category_event_daily
)
SELECT
    dt,
    gameid,
    event_dau,
    event_day_count,
    rn
FROM ranked
WHERE rn <= cast(ceiling(event_day_count * 0.10) AS integer)
ORDER BY gameid, rn;

-- 验收要求：
-- 1. 先核对版权表快照分区、业务日覆盖和观看事实最新分区。
-- 2. 核对 category_event_daily 的 dt × gameid 唯一，category_event_user_day 的 dt × gameid × ukey 唯一。
-- 3. 抽查至少 5 个品类：输出行数必须等于 ceil(event_day_count × 10%)，且事件日按 event_dau 降序。
-- 4. 用 EXISTS 半连接独立复算至少 5 个事件日的 event_dau，不得复用被验证 CTE。
-- 5. 版权表未覆盖的品类必须标为“赛事覆盖未知”，不得推断为非赛事品类。
