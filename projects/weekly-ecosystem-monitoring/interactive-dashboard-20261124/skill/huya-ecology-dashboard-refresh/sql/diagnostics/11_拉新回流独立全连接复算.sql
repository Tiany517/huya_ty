-- 独立验证：不用union标记聚合路径，改用两侧用户集合full join；5品类/报告日抽查。
WITH n AS (
 SELECT DISTINCT dt,cast(game_id AS varchar) gameid,cast(user_ukey AS varchar) ukey
 FROM zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
 WHERE dt='2026-11-24' AND cast(game_id AS varchar) IN ('1','2336','2165','5937','3203')
 AND guiyin_tag<>'mailiang' AND user_ukey IS NOT NULL AND trim(cast(user_ukey AS varchar))<>''
), r AS (
 SELECT DISTINCT dt,cast(game_id AS varchar) gameid,cast(user_ukey AS varchar) ukey
 FROM zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1
 WHERE dt='2026-11-24' AND cast(game_id AS varchar) IN ('1','2336','2165','5937','3203')
 AND user_ukey IS NOT NULL AND trim(cast(user_ukey AS varchar))<>''
)
SELECT coalesce(n.dt,r.dt) dt,coalesce(n.gameid,r.gameid) gameid,
count(n.ukey) newUsers,count(r.ukey) returnUsers,count(*) newReturnUsers,
sum(CASE WHEN n.ukey IS NOT NULL AND r.ukey IS NOT NULL THEN 1 ELSE 0 END) intersectionUsers
FROM n FULL OUTER JOIN r ON n.dt=r.dt AND n.gameid=r.gameid AND n.ukey=r.ukey
GROUP BY 1,2 ORDER BY 1,2
