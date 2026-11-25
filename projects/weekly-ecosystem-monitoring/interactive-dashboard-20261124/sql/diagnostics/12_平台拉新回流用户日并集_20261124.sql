-- V1.2结果契约：源归因表明细→dt/ukey唯一→dt；不加总品类UV；不含鸿蒙；拉新保留买量排除规则。
-- 分区已核查10/01—11/24各55天；独立验证另走两集合full join，输出不能仅凭执行成功标为正式通过。
WITH new_filtered AS (
 SELECT dt,cast(user_ukey AS varchar) ukey FROM zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
 WHERE dt BETWEEN '2026-10-01' AND '2026-11-24' AND guiyin_tag<>'mailiang'
 AND user_ukey IS NOT NULL AND trim(cast(user_ukey AS varchar))<>''
), return_filtered AS (
 SELECT dt,cast(user_ukey AS varchar) ukey FROM zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1
 WHERE dt BETWEEN '2026-10-01' AND '2026-11-24'
 AND user_ukey IS NOT NULL AND trim(cast(user_ukey AS varchar))<>''
), users AS (
 SELECT dt,ukey,1 is_new,0 is_return FROM new_filtered
 UNION ALL SELECT dt,ukey,0,1 FROM return_filtered
), user_day AS (
 SELECT dt,ukey,max(is_new) is_new,max(is_return) is_return FROM users GROUP BY 1,2
)
SELECT dt,sum(is_new) newUsers,sum(is_return) returnUsers,count(*) newReturnUsers,
sum(CASE WHEN is_new=1 AND is_return=1 THEN 1 ELSE 0 END) intersectionUsers
FROM user_day GROUP BY 1 ORDER BY 1
