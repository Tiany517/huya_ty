-- 状态：探索/待正式全量验收。仅供复盘，不创建或覆盖生产表。
WITH match_day AS (
 -- 品类赛事日覆盖：同一主播多赛事先压到日期/品类/主播，避免多赛重复。
 SELECT DISTINCT substr(cast(day AS varchar),1,10) dt,
 CASE WHEN cast(game_id AS varchar)='无畏契约' THEN '5937' WHEN cast(game_id AS varchar)='王者万象棋' THEN '8127' ELSE cast(game_id AS varchar) END gameid,
 cast(uid AS varchar) luid
 FROM zhgametemp.hss_huya_dim_game_copyright_info_d_a
 WHERE dt='2026-11-24' AND substr(cast(day AS varchar),1,10) BETWEEN '2026-05-29' AND '2026-11-24'
 AND live_type LIKE '%直播%' AND uid IS NOT NULL AND trim(cast(uid AS varchar)) NOT IN ('','0','-1') AND match_id IS NOT NULL
), watch_base AS (
 SELECT dt,cast(gameid AS varchar) gameid,cast(ayyuid AS varchar) luid,ukey
 FROM bp.yyzc_dws_with_user_by_gameid_ayyuid_ukey_day
 WHERE dt BETWEEN '2026-05-29' AND '2026-11-24' AND is_app=1 AND is_watch>0 AND is_black=0
 AND ukey IS NOT NULL AND trim(cast(ukey AS varchar)) NOT IN ('','0','-1')
), category_event_daily AS (
 SELECT w.dt,w.gameid,count(DISTINCT w.ukey) event_dau
 FROM watch_base w INNER JOIN match_day m ON w.dt=m.dt AND w.gameid=m.gameid AND w.luid=m.luid GROUP BY 1,2
)
SELECT gameid,count(*) positive_calendar_days,approx_percentile(event_dau,0.5) p50,
approx_percentile(event_dau,0.75) p75,approx_percentile(event_dau,0.9) p90,approx_percentile(event_dau,0.95) p95,
max(event_dau) peak_dau,min(dt) first_observed_day,max(dt) last_observed_day
FROM category_event_daily GROUP BY gameid ORDER BY gameid
