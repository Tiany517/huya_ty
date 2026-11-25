-- 参考执行版本；日期为本次快照，不得直接用于其他周期。验收状态见METRIC_UPGRADE.md。
WITH anchor_day AS (
 -- 互动分子：日/品类/主播先压唯一键；原指标来自dm明细，跨主播合计不是品类去重互动UV。
 SELECT dt,cast(gameid AS varchar) gameid,cast(ayyuid AS varchar) luid,
 max(coalesce(com_ucnt,0)) interaction_users,max(coalesce(com_cnt,0)) interaction_cnt
 FROM gamelive.dm_huya_ayyuid_detail_day
 WHERE dt BETWEEN '2026-10-01' AND '2026-11-24' AND ayyuid IS NOT NULL AND trim(cast(ayyuid AS varchar)) NOT IN ('','0','-1')
 GROUP BY 1,2,3
), watch_anchor_day AS (
 -- 同粒度的主播观看DAU作为互动率分母，避免用跨主播互动合计除以品类去重DAU。
 SELECT dt,cast(gameid AS varchar) gameid,cast(luid AS varchar) luid,max(dau) anchor_dau
 FROM zhgametemp.zty_category_ecology_health_daily_d_i_0827_v1
 WHERE dt BETWEEN '2026-10-01' AND '2026-11-24' AND category='主播明细'
 AND luid IS NOT NULL AND trim(cast(luid AS varchar)) NOT IN ('','0','-1')
 GROUP BY 1,2,3
)
SELECT w.dt,w.gameid,sum(a.interaction_users) interactionUsers,sum(w.anchor_dau) interactionDenominator,
sum(a.interaction_cnt) interactionCnt,count(*) anchorKeys,count(a.luid) matchedAnchorKeys,
sum(CASE WHEN a.interaction_users>w.anchor_dau THEN 1 ELSE 0 END) numeratorAboveDenominatorKeys
FROM watch_anchor_day w LEFT JOIN anchor_day a ON w.dt=a.dt AND w.gameid=a.gameid AND w.luid=a.luid
GROUP BY 1,2 ORDER BY 1,2
