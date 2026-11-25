-- 状态：探索/待正式全量验收。仅供复盘，不创建或覆盖生产表。
WITH match_anchor_day AS (
 -- 输入版权快照；输出dt/gameid/luid/match_id唯一。同主播多赛可展开，赛事内用户必须再次去重。
 SELECT DISTINCT substr(cast(day AS varchar),1,10) dt,cast(game_id AS varchar) gameid,cast(uid AS varchar) luid,cast(match_id AS varchar) match_id
 FROM zhgametemp.hss_huya_dim_game_copyright_info_d_a
 WHERE dt='2026-11-24' AND substr(cast(day AS varchar),1,10) BETWEEN '2026-05-29' AND '2026-11-24'
 AND live_type LIKE '%直播%' AND uid IS NOT NULL AND trim(cast(uid AS varchar)) NOT IN ('','0','-1')
 AND match_id IS NOT NULL
), names AS (
 SELECT cast(game_id AS varchar) gameid,cast(match_id AS varchar) match_id,max(match_name) match_name
 FROM zhgametemp.hss_huya_dim_game_copyright_info_d_a
 WHERE dt='2026-11-24' AND substr(cast(day AS varchar),1,10) BETWEEN '2026-05-29' AND '2026-11-24'
 AND live_type LIKE '%直播%' GROUP BY 1,2
), watch_base AS (
 -- 明细先过滤；原用户SQL APP口径，不含鸿蒙；同赛事同日跨主播去重。
 SELECT dt,cast(gameid AS varchar) gameid,cast(ayyuid AS varchar) luid,ukey
 FROM bp.yyzc_dws_with_user_by_gameid_ayyuid_ukey_day
 WHERE dt BETWEEN '2026-05-29' AND '2026-11-24' AND is_app=1 AND is_watch>0 AND is_black=0
 AND ukey IS NOT NULL AND trim(cast(ukey AS varchar)) NOT IN ('','0','-1')
), event_daily AS (
 SELECT m.dt,m.gameid,m.match_id,count(DISTINCT w.ukey) event_dau
 FROM watch_base w INNER JOIN match_anchor_day m ON m.dt=w.dt AND m.gameid=w.gameid AND m.luid=w.luid
 GROUP BY 1,2,3
), category_threshold AS (
 -- 阈值样本为单场赛事的有观看赛事日；不是各赛事DAU之和，也不是所有自然日P90。
 SELECT gameid,count(*) positive_event_days,count(DISTINCT dt) positive_calendar_days,count(DISTINCT match_id) event_count,
 approx_percentile(event_dau,0.5) p50,approx_percentile(event_dau,0.75) p75,
 approx_percentile(event_dau,0.9) p90,approx_percentile(event_dau,0.95) p95
 FROM event_daily WHERE event_dau>0 GROUP BY gameid
), event_summary AS (
 SELECT gameid,match_id,min(dt) mapped_start,max(dt) mapped_end,count(*) mapped_days,
 count_if(event_dau>0) observed_days,avg(event_dau) mean_event_dau,
 approx_percentile(event_dau,0.5) median_event_dau,max(event_dau) peak_event_dau,
 max_by(dt,event_dau) peak_date
 FROM event_daily GROUP BY gameid,match_id
)
SELECT e.*,n.match_name,c.positive_event_days,c.positive_calendar_days,c.event_count,c.p50,c.p75,c.p90,c.p95
FROM event_summary e LEFT JOIN names n ON e.gameid=n.gameid AND e.match_id=n.match_id
LEFT JOIN category_threshold c ON e.gameid=c.gameid ORDER BY e.gameid,e.peak_event_dau DESC
