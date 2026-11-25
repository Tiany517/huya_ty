-- Presto研究模板；不写入生产表。须先确认最新快照与业务日覆盖。
-- 契约：版权输入可多对多；清洗后映射dt/gameid/luid唯一；用户日去重dt/gameid/ukey唯一。
-- 赛事DAU为APP四端，不含鸿蒙；不能把不同赛事UV相加当作品类并集。
WITH copyright_raw AS (
 SELECT substr(cast(day AS varchar),1,10) dt,
 CASE WHEN cast(game_id AS varchar)='无畏契约' THEN '5937'
      WHEN cast(game_id AS varchar)='王者万象棋' THEN '8127'
      ELSE cast(game_id AS varchar) END gameid,
 cast(uid AS varchar) luid,cast(match_id AS varchar) match_id
 FROM zhgametemp.hss_huya_dim_game_copyright_info_d_a
 WHERE dt='{{SNAPSHOT_DATE}}'
 AND substr(cast(day AS varchar),1,10) BETWEEN '{{START_DATE}}' AND '{{END_DATE}}'
 AND live_type LIKE '%直播%' AND uid IS NOT NULL AND match_id IS NOT NULL
), anchor_day AS (
 -- 每个品类主播日只保留一条，避免同主播多赛事导致观看行放大。
 SELECT DISTINCT dt,gameid,luid FROM copyright_raw
 WHERE trim(luid) NOT IN ('','0','-1')
), watch_filtered AS (
 -- 明细事实先过滤；join只保留业务键。Harmony不在本表is_app=1口径内。
 SELECT dt,cast(gameid AS varchar) gameid,cast(ayyuid AS varchar) luid,ukey
 FROM bp.yyzc_dws_with_user_by_gameid_ayyuid_ukey_day
 WHERE dt BETWEEN '{{START_DATE}}' AND '{{END_DATE}}'
 AND is_app=1 AND is_watch>0 AND is_black=0 AND ukey IS NOT NULL
), category_user_day AS (
 SELECT DISTINCT w.dt,w.gameid,w.ukey FROM watch_filtered w
 INNER JOIN anchor_day a ON w.dt=a.dt AND w.gameid=a.gameid AND w.luid=a.luid
), category_event_daily AS (
 SELECT dt,gameid,count(*) event_dau FROM category_user_day GROUP BY 1,2
), positive_distribution AS (
 -- 阈值样本为有正观看的登记赛日；日历零值与源缺失必须另核查，不能混淆。
 SELECT gameid,count(*) positive_days,approx_percentile(event_dau,.5) p50,
 approx_percentile(event_dau,.75) p75,approx_percentile(event_dau,.9) p90,
 max(event_dau) peak_dau FROM category_event_daily GROUP BY 1
)
SELECT d.dt,d.gameid,d.event_dau,p.positive_days,p.p50,p.p75,p.p90,p.peak_dau,
 CASE WHEN d.event_dau>=p.p90 THEN 1 ELSE 0 END p90_candidate
FROM category_event_daily d INNER JOIN positive_distribution p ON d.gameid=p.gameid
ORDER BY d.gameid,d.dt
-- P90仅候选，不是“大赛事”最终标签。另输出单赛事排期与强度，再核对官方赛程。
