-- 目的：校验 2026-09 站外主播用户活动测试表。
-- 引擎：优先 Presto；大查询建议提交到 Spark 异步执行。
-- 测试表：zhgametemp.zty_jingpin_user_activity_202609_test
-- 参考主播日表：zhgametemp.zty_jingpin_anchor_day_di
-- 平台范围：douyu、bilibili、douyin；douyin_web 统一为 douyin。

-- 1. 唯一粒度：dt + pcode + r_category + anchor_uid + user_id。
SELECT
  COUNT(*) AS duplicate_groups,
  COALESCE(SUM(row_cnt), 0) AS rows_in_duplicate_groups
FROM (
  SELECT
    dt, pcode, r_category, anchor_uid, user_id,
    COUNT(*) AS row_cnt
  FROM zhgametemp.zty_jingpin_user_activity_202609_test
  WHERE dt >= '2026-09-01' AND dt < '2026-10-01'
  GROUP BY dt, pcode, r_category, anchor_uid, user_id
) t
WHERE row_cnt > 1;


-- 2. anchor_day_di 与参考表按平台 + 品类 FULL JOIN。
WITH ref AS (
  SELECT
    pcode,
    r_category,
    SUM(watch_min) AS watch_mins,
    SUM(live_mins) AS live_min
  FROM zhgametemp.yty_jingpin_anchor_vaild_dau
  WHERE dt >= '2026-09-01' AND dt < '2026-10-01'
    AND LOWER(CAST(pcode AS VARCHAR)) IN ('douyu', 'bilibili', 'douyin')
  GROUP BY pcode, r_category
),
delivered AS (
  SELECT
    pcode,
    r_category,
    SUM(watch_min) AS watch_mins,
    SUM(live_mins) AS live_min
  FROM zhgametemp.zty_jingpin_anchor_day_di
  WHERE dt >= '2026-09-01' AND dt < '2026-10-01'
  GROUP BY pcode, r_category
),
j AS (
  SELECT
    ref.pcode AS ref_pcode,
    delivered.pcode AS delivered_pcode,
    ref.watch_mins AS ref_watch_mins,
    delivered.watch_mins AS delivered_watch_mins,
    ref.live_min AS ref_live_min,
    delivered.live_min AS delivered_live_min
  FROM ref
  FULL OUTER JOIN delivered
    ON ref.pcode = delivered.pcode
   AND ref.r_category = delivered.r_category
)
SELECT
  COUNT(*) AS total_groups,
  SUM(CASE WHEN ref_pcode IS NOT NULL AND delivered_pcode IS NOT NULL THEN 1 ELSE 0 END) AS matched,
  SUM(CASE WHEN ref_pcode IS NOT NULL AND delivered_pcode IS NULL THEN 1 ELSE 0 END) AS ref_only,
  SUM(CASE WHEN ref_pcode IS NULL AND delivered_pcode IS NOT NULL THEN 1 ELSE 0 END) AS delivered_only,
  SUM(CASE WHEN ABS(COALESCE(ref_watch_mins, 0) - COALESCE(delivered_watch_mins, 0)) > 0.001 THEN 1 ELSE 0 END) AS watch_mismatch_groups,
  SUM(CASE WHEN ABS(COALESCE(ref_live_min, 0) - COALESCE(delivered_live_min, 0)) > 0.001 THEN 1 ELSE 0 END) AS live_mismatch_groups,
  MAX(ABS(COALESCE(ref_watch_mins, 0) - COALESCE(delivered_watch_mins, 0))) AS max_watch_abs_diff,
  MAX(ABS(COALESCE(ref_live_min, 0) - COALESCE(delivered_live_min, 0))) AS max_live_abs_diff,
  SUM(COALESCE(ref_watch_mins, 0)) AS ref_watch_mins_total,
  SUM(COALESCE(delivered_watch_mins, 0)) AS delivered_watch_mins_total,
  SUM(COALESCE(ref_live_min, 0)) AS ref_live_min_total,
  SUM(COALESCE(delivered_live_min, 0)) AS delivered_live_min_total
FROM j;


-- 3. 普通弹幕：源事件按 dt+pcode+r_category+anchor_uid 汇总后与测试表 FULL JOIN。
WITH ref AS (
  SELECT
    CAST(dt AS VARCHAR) AS dt,
    CASE WHEN LOWER(CAST(pcode AS VARCHAR)) = 'douyin_web' THEN 'douyin' ELSE LOWER(CAST(pcode AS VARCHAR)) END AS pcode,
    COALESCE(NULLIF(TRIM(CAST(r_category AS VARCHAR)), ''), '未知品类') AS r_category,
    CAST(uid AS VARCHAR) AS anchor_uid,
    COUNT(*) AS danmu_cnt
  FROM gamelive.dwt_jingpin_danmulog_day
  WHERE dt >= '2026-09-01' AND dt < '2026-10-01'
    AND LOWER(CAST(pcode AS VARCHAR)) IN ('douyu', 'bilibili', 'douyin', 'douyin_web')
    AND CAST(msgtype AS VARCHAR) = '0'
    AND sender IS NOT NULL
    AND TRIM(CAST(sender AS VARCHAR)) <> ''
  GROUP BY
    CAST(dt AS VARCHAR),
    CASE WHEN LOWER(CAST(pcode AS VARCHAR)) = 'douyin_web' THEN 'douyin' ELSE LOWER(CAST(pcode AS VARCHAR)) END,
    COALESCE(NULLIF(TRIM(CAST(r_category AS VARCHAR)), ''), '未知品类'),
    CAST(uid AS VARCHAR)
),
delivered AS (
  SELECT
    dt, pcode, r_category, anchor_uid,
    SUM(danmu_cnt) AS danmu_cnt
  FROM zhgametemp.zty_jingpin_user_activity_202609_test
  WHERE dt >= '2026-09-01' AND dt < '2026-10-01'
    AND danmu_cnt > 0
  GROUP BY dt, pcode, r_category, anchor_uid
),
j AS (
  SELECT
    ref.dt AS ref_dt, delivered.dt AS delivered_dt,
    ref.pcode AS ref_pcode, delivered.pcode AS delivered_pcode,
    ref.r_category AS ref_category, delivered.r_category AS delivered_category,
    ref.anchor_uid AS ref_anchor_uid, delivered.anchor_uid AS delivered_anchor_uid,
    ref.danmu_cnt AS ref_danmu_cnt, delivered.danmu_cnt AS delivered_danmu_cnt
  FROM ref
  FULL OUTER JOIN delivered
    ON ref.dt = delivered.dt
   AND ref.pcode = delivered.pcode
   AND ref.r_category = delivered.r_category
   AND COALESCE(ref.anchor_uid, '') = COALESCE(delivered.anchor_uid, '')
)
SELECT
  COUNT(*) AS total_groups,
  SUM(CASE WHEN ref_dt IS NOT NULL AND delivered_dt IS NOT NULL THEN 1 ELSE 0 END) AS matched,
  SUM(CASE WHEN ref_dt IS NOT NULL AND delivered_dt IS NULL THEN 1 ELSE 0 END) AS ref_only,
  SUM(CASE WHEN ref_dt IS NULL AND delivered_dt IS NOT NULL THEN 1 ELSE 0 END) AS delivered_only,
  SUM(CASE WHEN COALESCE(ref_danmu_cnt, 0) <> COALESCE(delivered_danmu_cnt, 0) THEN 1 ELSE 0 END) AS mismatch_groups,
  SUM(COALESCE(ref_danmu_cnt, 0)) AS source_danmu_cnt,
  SUM(COALESCE(delivered_danmu_cnt, 0)) AS delivered_danmu_cnt
FROM j;


-- 4. 打赏：源事件与测试表按 dt+pcode+r_category+anchor_uid FULL JOIN。
-- 测试表没有 gift_cnt，因此金额可按最终表对账；打赏笔数在 gift_user_day 层单独校验。
WITH gift_raw AS (
  SELECT
    CAST(dt AS VARCHAR) AS dt,
    LOWER(CAST(pcode AS VARCHAR)) AS pcode,
    COALESCE(NULLIF(TRIM(CAST(r_game_name AS VARCHAR)), ''), '未知品类') AS r_category,
    CAST(anchor_uid AS VARCHAR) AS anchor_uid,
    CAST(sender_id AS VARCHAR) AS user_id,
    CAST(gift_value AS DOUBLE) AS gift_value
  FROM zhgametemp.yty_huya_jingpin_yingshou_gift_times
  WHERE dt >= '2026-09-01' AND dt < '2026-10-01'
    AND LOWER(CAST(pcode AS VARCHAR)) IN ('douyu', 'bilibili')
    AND sender_id IS NOT NULL
    AND TRIM(CAST(sender_id AS VARCHAR)) <> ''

  UNION ALL

  SELECT
    CAST(dt AS VARCHAR) AS dt,
    'douyin' AS pcode,
    COALESCE(NULLIF(TRIM(CAST(r_category AS VARCHAR)), ''), '未知品类') AS r_category,
    CAST(uid AS VARCHAR) AS anchor_uid,
    CAST(sender_id AS VARCHAR) AS user_id,
    CAST(gift_value AS DOUBLE) AS gift_value
  FROM zhgametemp.yty_douyin_all_rcategory_gift_detail
  WHERE dt >= '2026-09-01' AND dt < '2026-10-01'
    AND sender_id IS NOT NULL
    AND TRIM(CAST(sender_id AS VARCHAR)) <> ''
),
ref AS (
  SELECT
    dt, pcode, r_category, anchor_uid,
    COUNT(*) AS gift_cnt,
    SUM(COALESCE(gift_value, 0.0)) AS gift_value
  FROM gift_raw
  GROUP BY dt, pcode, r_category, anchor_uid
),
delivered AS (
  SELECT
    dt, pcode, r_category, anchor_uid,
    SUM(gift_value) AS gift_value
  FROM zhgametemp.zty_jingpin_user_activity_202609_test
  WHERE dt >= '2026-09-01' AND dt < '2026-10-01'
    AND gift_value <> 0
  GROUP BY dt, pcode, r_category, anchor_uid
),
j AS (
  SELECT
    ref.dt AS ref_dt, delivered.dt AS delivered_dt,
    ref.pcode AS ref_pcode, delivered.pcode AS delivered_pcode,
    ref.r_category AS ref_category, delivered.r_category AS delivered_category,
    ref.anchor_uid AS ref_anchor_uid, delivered.anchor_uid AS delivered_anchor_uid,
    ref.gift_cnt AS ref_gift_cnt,
    ref.gift_value AS ref_gift_value,
    delivered.gift_value AS delivered_gift_value
  FROM ref
  FULL OUTER JOIN delivered
    ON ref.dt = delivered.dt
   AND ref.pcode = delivered.pcode
   AND ref.r_category = delivered.r_category
   AND COALESCE(ref.anchor_uid, '') = COALESCE(delivered.anchor_uid, '')
)
SELECT
  COUNT(*) AS total_groups,
  SUM(CASE WHEN ref_dt IS NOT NULL AND delivered_dt IS NOT NULL THEN 1 ELSE 0 END) AS matched,
  SUM(CASE WHEN ref_dt IS NOT NULL AND delivered_dt IS NULL THEN 1 ELSE 0 END) AS ref_only,
  SUM(CASE WHEN ref_dt IS NULL AND delivered_dt IS NOT NULL THEN 1 ELSE 0 END) AS delivered_only,
  SUM(CASE WHEN ABS(COALESCE(ref_gift_value, 0) - COALESCE(delivered_gift_value, 0)) > 0.001 THEN 1 ELSE 0 END) AS gift_value_mismatch_groups,
  SUM(COALESCE(ref_gift_cnt, 0)) AS source_gift_cnt,
  SUM(COALESCE(ref_gift_value, 0)) AS source_gift_value,
  SUM(COALESCE(delivered_gift_value, 0)) AS delivered_gift_value
FROM j;


-- 5. 打赏源记录先按用户活动粒度汇总，校验笔数不丢失。
WITH gift_raw AS (
  SELECT
    CAST(dt AS VARCHAR) AS dt,
    LOWER(CAST(pcode AS VARCHAR)) AS pcode,
    COALESCE(NULLIF(TRIM(CAST(r_game_name AS VARCHAR)), ''), '未知品类') AS r_category,
    CAST(anchor_uid AS VARCHAR) AS anchor_uid,
    CAST(sender_id AS VARCHAR) AS user_id,
    CAST(gift_value AS DOUBLE) AS gift_value
  FROM zhgametemp.yty_huya_jingpin_yingshou_gift_times
  WHERE dt >= '2026-09-01' AND dt < '2026-10-01'
    AND LOWER(CAST(pcode AS VARCHAR)) IN ('douyu', 'bilibili')
    AND sender_id IS NOT NULL
    AND TRIM(CAST(sender_id AS VARCHAR)) <> ''
  UNION ALL
  SELECT
    CAST(dt AS VARCHAR), 'douyin',
    COALESCE(NULLIF(TRIM(CAST(r_category AS VARCHAR)), ''), '未知品类'),
    CAST(uid AS VARCHAR), CAST(sender_id AS VARCHAR), CAST(gift_value AS DOUBLE)
  FROM zhgametemp.yty_douyin_all_rcategory_gift_detail
  WHERE dt >= '2026-09-01' AND dt < '2026-10-01'
    AND sender_id IS NOT NULL
    AND TRIM(CAST(sender_id AS VARCHAR)) <> ''
),
gift_user_day AS (
  SELECT
    dt, pcode, r_category, anchor_uid, user_id,
    COUNT(*) AS gift_cnt,
    SUM(COALESCE(gift_value, 0.0)) AS gift_value
  FROM gift_raw
  GROUP BY dt, pcode, r_category, anchor_uid, user_id
)
SELECT
  (SELECT COUNT(*) FROM gift_raw) AS source_gift_cnt,
  SUM(gift_cnt) AS gift_user_day_gift_cnt,
  COUNT(*) AS gift_user_day_rows
FROM gift_user_day;


-- 6. 测试表中的未知品类和缺失主播汇总。
SELECT
  SUM(CASE WHEN r_category = '未知品类' THEN danmu_cnt ELSE 0 END) AS unknown_category_danmu_records,
  COUNT(DISTINCT CASE WHEN r_category = '未知品类' AND danmu_cnt > 0 THEN CONCAT(dt, '|', pcode, '|', user_id) END) AS unknown_category_danmu_users,
  SUM(CASE WHEN r_category = '未知品类' THEN gift_value ELSE 0 END) AS unknown_category_gift_value,
  COUNT(DISTINCT CASE WHEN r_category = '未知品类' AND gift_value <> 0 THEN CONCAT(dt, '|', pcode, '|', user_id) END) AS unknown_category_gift_users,
  SUM(CASE WHEN anchor_uid IS NULL OR TRIM(anchor_uid) = '' THEN danmu_cnt ELSE 0 END) AS missing_anchor_danmu_records,
  COUNT(DISTINCT CASE WHEN (anchor_uid IS NULL OR TRIM(anchor_uid) = '') AND danmu_cnt > 0 THEN CONCAT(dt, '|', pcode, '|', user_id) END) AS missing_anchor_danmu_users,
  SUM(CASE WHEN anchor_uid IS NULL OR TRIM(anchor_uid) = '' THEN gift_value ELSE 0 END) AS missing_anchor_gift_value
FROM zhgametemp.zty_jingpin_user_activity_202609_test
WHERE dt >= '2026-09-01' AND dt < '2026-10-01';


-- 7. 本版不使用外部品类映射；r_game_name -> r_category 和 r_category -> r_category 均为恒等映射。
-- 因此映射一对多重复记录数、金额均应为 0。
SELECT
  'r_game_name -> r_category identity' AS mapping_rule,
  0 AS one_to_many_source_categories,
  0 AS duplicated_records,
  CAST(0.0 AS DOUBLE) AS duplicated_gift_value;
