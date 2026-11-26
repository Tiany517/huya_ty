-- Presto研究模板：按单赛事周期统计赛事关联主播覆盖DAU。
-- 必须替换 {{SNAPSHOT_DATE}}、{{START_DATE}}、{{END_DATE}}。
-- APP口径沿用原赛事SQL：is_app=1、is_watch>0、is_black=0，不含鸿蒙。
WITH match_anchor_day AS (
    -- 每个主播每天、每个游戏只保留一条赛事关联记录，避免同一主播多赛放大观看用户。
    SELECT DISTINCT substr(cast(day AS varchar), 1, 10) AS dt,
           CASE WHEN cast(game_id AS varchar) = '无畏契约' THEN '5937'
                WHEN cast(game_id AS varchar) = '王者万象棋' THEN '8127'
                ELSE cast(game_id AS varchar) END AS gameid,
           cast(uid AS varchar) AS luid,
           cast(match_id AS varchar) AS match_id
    FROM zhgametemp.hss_huya_dim_game_copyright_info_d_a
    WHERE dt = '{{SNAPSHOT_DATE}}'
      AND substr(cast(day AS varchar), 1, 10) BETWEEN '{{START_DATE}}' AND '{{END_DATE}}'
      AND live_type LIKE '%直播%'
      AND uid IS NOT NULL
      AND trim(cast(uid AS varchar)) NOT IN ('', '0', '-1')
      AND match_id IS NOT NULL
), names AS (
    SELECT CASE WHEN cast(game_id AS varchar) = '无畏契约' THEN '5937'
                WHEN cast(game_id AS varchar) = '王者万象棋' THEN '8127'
                ELSE cast(game_id AS varchar) END AS gameid,
           cast(match_id AS varchar) AS match_id,
           max(match_name) AS match_name
    FROM zhgametemp.hss_huya_dim_game_copyright_info_d_a
    WHERE dt = '{{SNAPSHOT_DATE}}'
      AND substr(cast(day AS varchar), 1, 10) BETWEEN '{{START_DATE}}' AND '{{END_DATE}}'
      AND live_type LIKE '%直播%'
    GROUP BY 1, 2
), watch_filtered AS (
    -- 事实表先独立过滤，后续join只保留业务键；不含鸿蒙。
    SELECT dt,
           cast(gameid AS varchar) AS gameid,
           cast(ayyuid AS varchar) AS luid,
           ukey
    FROM bp.yyzc_dws_with_user_by_gameid_ayyuid_ukey_day
    WHERE dt BETWEEN '{{START_DATE}}' AND '{{END_DATE}}'
      AND is_app = 1
      AND is_watch > 0
      AND is_black = 0
      AND ukey IS NOT NULL
      AND trim(cast(ukey AS varchar)) NOT IN ('', '0', '-1')
), event_daily AS (
    -- 粒度：dt × gameid × match_id；人数按ukey去重。
    SELECT m.dt, m.gameid, m.match_id, count(DISTINCT w.ukey) AS event_dau
    FROM watch_filtered w
    INNER JOIN match_anchor_day m
      ON m.dt = w.dt AND m.gameid = w.gameid AND m.luid = w.luid
    GROUP BY 1, 2, 3
), event_summary AS (
    SELECT gameid, match_id, min(dt) AS mapped_start, max(dt) AS mapped_end,
           count(*) AS mapped_days, count_if(event_dau > 0) AS observed_days,
           avg(event_dau) AS mean_event_dau,
           approx_percentile(event_dau, 0.5) AS median_event_dau,
           max(event_dau) AS peak_event_dau,
           max_by(dt, event_dau) AS peak_date
    FROM event_daily
    GROUP BY 1, 2
)
SELECT e.*, n.match_name
FROM event_summary e
LEFT JOIN names n ON e.gameid = n.gameid AND e.match_id = n.match_id
ORDER BY e.gameid, e.mean_event_dau DESC
