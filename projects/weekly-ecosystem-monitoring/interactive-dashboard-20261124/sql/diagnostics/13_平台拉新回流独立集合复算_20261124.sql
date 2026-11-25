-- 独立验证：两侧平台用户日集合FULL OUTER JOIN，不复用union标记路径。输出dt唯一，5天，身份与买量规则同原契约。
WITH n AS (
 SELECT DISTINCT dt,cast(user_ukey AS varchar) ukey FROM zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
 WHERE dt IN ('2026-11-24','2026-11-17','2026-11-10','2026-11-03','2026-10-27')
 AND guiyin_tag<>'mailiang' AND user_ukey IS NOT NULL AND trim(cast(user_ukey AS varchar))<>''
), r AS (
 SELECT DISTINCT dt,cast(user_ukey AS varchar) ukey FROM zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1
 WHERE dt IN ('2026-11-24','2026-11-17','2026-11-10','2026-11-03','2026-10-27')
 AND user_ukey IS NOT NULL AND trim(cast(user_ukey AS varchar))<>''
)
SELECT coalesce(n.dt,r.dt) dt,count(n.ukey) newUsers,count(r.ukey) returnUsers,count(*) newReturnUsers,
sum(CASE WHEN n.ukey IS NOT NULL AND r.ukey IS NOT NULL THEN 1 ELSE 0 END) intersectionUsers
FROM n FULL OUTER JOIN r ON n.dt=r.dt AND n.ukey=r.ukey GROUP BY 1 ORDER BY 1
