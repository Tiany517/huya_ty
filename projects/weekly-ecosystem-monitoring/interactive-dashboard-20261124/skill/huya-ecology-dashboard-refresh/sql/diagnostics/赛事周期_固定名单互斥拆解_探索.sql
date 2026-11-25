-- 状态：探索/待正式全量验收。仅供复盘，不创建或覆盖生产表。
WITH cohort AS (
 SELECT DISTINCT cast(game_id AS varchar) gameid,cast(uid AS varchar) luid
 FROM zhgametemp.hss_huya_dim_game_copyright_info_d_a
 WHERE dt='2026-11-24' AND live_type LIKE '%直播%'
 AND ((cast(game_id AS varchar)='1' AND cast(match_id AS varchar)='9029206')
 OR (cast(game_id AS varchar)='2336' AND cast(match_id AS varchar)='9029419')
 OR (cast(game_id AS varchar)='862' AND cast(match_id AS varchar)='9029512'))
 AND substr(cast(day AS varchar),1,10) BETWEEN '2026-01-01' AND '2026-11-24'
 AND uid IS NOT NULL AND trim(cast(uid AS varchar)) NOT IN ('','0','-1')
), watch_base AS (
 SELECT dt,cast(gameid AS varchar) gameid,cast(ayyuid AS varchar) luid,ukey
 FROM bp.yyzc_dws_with_user_by_gameid_ayyuid_ukey_day
 WHERE dt BETWEEN '2026-11-09' AND '2026-11-22' AND gameid IN (1,2336,862)
 AND is_app=1 AND is_watch>0 AND is_black=0 AND ukey IS NOT NULL AND trim(cast(ukey AS varchar)) NOT IN ('','0','-1')
), user_day AS (
 SELECT w.dt,w.gameid,w.ukey,max(CASE WHEN c.luid IS NOT NULL THEN 1 ELSE 0 END) fixed_watch,
 max(CASE WHEN c.luid IS NULL THEN 1 ELSE 0 END) other_watch
 FROM watch_base w LEFT JOIN cohort c ON w.gameid=c.gameid AND w.luid=c.luid GROUP BY 1,2,3
)
SELECT dt,gameid,count(*) app_dau,sum(fixed_watch) fixed_cohort_dau,
sum(CASE WHEN fixed_watch=1 AND other_watch=0 THEN 1 ELSE 0 END) fixed_only,
sum(CASE WHEN fixed_watch=0 AND other_watch=1 THEN 1 ELSE 0 END) other_only,
sum(CASE WHEN fixed_watch=1 AND other_watch=1 THEN 1 ELSE 0 END) overlap
FROM user_day GROUP BY 1,2 ORDER BY 1,2
