-- Presto研究模板：输出版权登记赛日，供脚本按“单赛事周期”筛选大赛事。
-- 必须替换 {{SNAPSHOT_DATE}}、{{START_DATE}}、{{END_DATE}} 后执行。
-- 输出唯一键 dt × gameid × match_id；同一主播/赛事重复记录先压重。
WITH copyright_raw AS (
    SELECT substr(cast(day AS varchar), 1, 10) AS dt,
           CASE WHEN cast(game_id AS varchar) = '无畏契约' THEN '5937'
                WHEN cast(game_id AS varchar) = '王者万象棋' THEN '8127'
                ELSE cast(game_id AS varchar) END AS gameid,
           cast(match_id AS varchar) AS match_id,
           max(match_name) AS match_name
    FROM zhgametemp.hss_huya_dim_game_copyright_info_d_a
    WHERE dt = '{{SNAPSHOT_DATE}}'
      AND substr(cast(day AS varchar), 1, 10) BETWEEN '{{START_DATE}}' AND '{{END_DATE}}'
      AND live_type LIKE '%直播%'
      AND match_id IS NOT NULL
    GROUP BY 1, 2, 3
)
SELECT dt, gameid, match_id, match_name
FROM copyright_raw
ORDER BY gameid, match_id, dt
