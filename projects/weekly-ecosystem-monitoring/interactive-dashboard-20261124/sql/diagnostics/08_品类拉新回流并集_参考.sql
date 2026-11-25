-- 参考执行版本；日期为本次快照，不得直接用于其他周期。验收状态见METRIC_UPGRADE.md。
WITH raw AS (
 -- 原口径：拉新排除mailiang，回流不额外套买量条件；保留用户键用于并集去重。
 SELECT dt,cast(game_id AS varchar) gameid,cast(user_ukey AS varchar) user_ukey,1 is_new,0 is_return
 FROM zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
 WHERE dt BETWEEN '2026-10-01' AND '2026-11-24' AND guiyin_tag <> 'mailiang'
 AND user_ukey IS NOT NULL AND trim(cast(user_ukey AS varchar))<>''
 UNION ALL
 SELECT dt,cast(game_id AS varchar) gameid,cast(user_ukey AS varchar) user_ukey,0 is_new,1 is_return
 FROM zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1
 WHERE dt BETWEEN '2026-10-01' AND '2026-11-24'
 AND user_ukey IS NOT NULL AND trim(cast(user_ukey AS varchar))<>''
), user_day AS (
 -- 输出唯一键dt/gameid/user_ukey；两类标记合并，不能直接相加。
 SELECT dt,gameid,user_ukey,max(is_new) is_new,max(is_return) is_return FROM raw GROUP BY 1,2,3
)
SELECT dt,gameid,sum(is_new) newUsers,sum(is_return) returnUsers,count(*) newReturnUsers,
sum(CASE WHEN is_new=1 AND is_return=1 THEN 1 ELSE 0 END) intersectionUsers
FROM user_day GROUP BY 1,2 ORDER BY 1,2
