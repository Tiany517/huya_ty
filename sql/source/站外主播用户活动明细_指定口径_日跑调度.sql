-- 目的：生成站外主播日表和站外主播用户活动明细表。
-- 主播日口径：原样承接 zhgametemp.yty_jingpin_anchor_vaild_dau，不重算、不改品类、不选主品类。
-- 用户活动粒度：dt + pcode + r_category + anchor_uid + coalesce(danmu_user_id, gift_user_id)。
-- 平台：douyu、bilibili、douyin。
-- 引擎：Spark。
-- 调度变量：tdate，例如 ${tdate?string('yyyy-MM-dd')}。

CREATE TABLE IF NOT EXISTS zhgametemp.zty_jingpin_anchor_day_di (
  pcode STRING COMMENT '平台',
  r_category STRING COMMENT '品类，原样承接',
  anchor_uid STRING COMMENT '主播ID，取自r_lid',
  anchor_name STRING COMMENT '主播名称',
  vaild_acu DOUBLE COMMENT '有效ACU，原样承接',
  live_mins DOUBLE COMMENT '直播分钟数，原样承接',
  watch_min DOUBLE COMMENT '观时分钟数，原样承接',
  mall_watch_min DOUBLE COMMENT '品类大盘观时分钟数，原样承接',
  cate_vaild_dau DOUBLE COMMENT '品类有效DAU，原样承接',
  anchor_vaild_dau DOUBLE COMMENT '主播有效DAU，原样承接'
)
PARTITIONED BY (dt STRING COMMENT '日期分区')
STORED AS ORC;

CREATE TABLE IF NOT EXISTS zhgametemp.zty_jingpin_anchor_user_activity_di (
  pcode STRING COMMENT '平台',
  r_category STRING COMMENT '主播当天品类，来自anchor_day_di',
  anchor_uid STRING COMMENT '平台内主播ID',
  anchor_name STRING COMMENT '主播名称',
  danmu_user_id STRING COMMENT '当天发送普通弹幕的用户ID；未发弹幕为空',
  gift_user_id STRING COMMENT '当天发生打赏的用户ID；未打赏为空',
  danmu_cnt BIGINT COMMENT '当天普通弹幕次数',
  gift_cnt BIGINT COMMENT '当天打赏记录数',
  gift_value DOUBLE COMMENT '当天跨打赏源品类汇总后的打赏金额',
  gift_user_type STRING COMMENT '按当天同一主播下打赏总额计算的用户类型'
)
PARTITIONED BY (dt STRING COMMENT '日期分区')
STORED AS ORC;


INSERT OVERWRITE TABLE zhgametemp.zty_jingpin_anchor_day_di
PARTITION (dt='${tdate?string('yyyy-MM-dd')}')
SELECT
  CAST(pcode AS STRING) AS pcode,
  CAST(r_category AS STRING) AS r_category,
  CAST(r_lid AS STRING) AS anchor_uid,
  CAST(r_owner AS STRING) AS anchor_name,
  CAST(vaild_acu AS DOUBLE) AS vaild_acu,
  CAST(live_mins AS DOUBLE) AS live_mins,
  CAST(watch_min AS DOUBLE) AS watch_min,
  CAST(mall_watch_min AS DOUBLE) AS mall_watch_min,
  CAST(cate_vaild_dau AS DOUBLE) AS cate_vaild_dau,
  CAST(anchor_vaild_dau AS DOUBLE) AS anchor_vaild_dau
FROM zhgametemp.yty_jingpin_anchor_vaild_dau
WHERE dt = '${tdate?string('yyyy-MM-dd')}'
  AND LOWER(CAST(pcode AS STRING)) IN ('douyu', 'bilibili', 'douyin');


INSERT OVERWRITE TABLE zhgametemp.zty_jingpin_anchor_user_activity_di
PARTITION (dt='${tdate?string('yyyy-MM-dd')}')

WITH anchor_day AS (
  -- 一个主播日在派生表中有多个品类时，保留多行；同一主播日多品类分别用于用户品类归属。
  SELECT
    CAST(dt AS STRING) AS dt,
    CAST(pcode AS STRING) AS pcode,
    CAST(r_category AS STRING) AS r_category,
    CAST(r_lid AS STRING) AS anchor_uid,
    MAX(CAST(r_owner AS STRING)) AS anchor_name
  FROM zhgametemp.yty_jingpin_anchor_vaild_dau
  WHERE dt = '${tdate?string('yyyy-MM-dd')}'
    AND LOWER(CAST(pcode AS STRING)) IN ('douyu', 'bilibili', 'douyin')
  GROUP BY
    CAST(dt AS STRING),
    CAST(pcode AS STRING),
    CAST(r_category AS STRING),
    CAST(r_lid AS STRING)
),

gift_user_raw AS (
  -- 斗鱼、B站打赏：先丢弃源品类，只保留到 天+平台+主播+用户。
  SELECT
    CAST(dt AS STRING) AS dt,
    LOWER(CAST(pcode AS STRING)) AS pcode,
    CAST(anchor_uid AS STRING) AS anchor_uid,
    MAX(CAST(anchor_name AS STRING)) AS anchor_name,
    CAST(sender_id AS STRING) AS user_id,
    SUM(COALESCE(CAST(gift_value AS DOUBLE), 0)) AS gift_value,
    COUNT(*) AS gift_cnt
  FROM zhgametemp.yty_huya_jingpin_yingshou_gift_times
  WHERE dt = '${tdate?string('yyyy-MM-dd')}'
    AND LOWER(CAST(pcode AS STRING)) IN ('douyu', 'bilibili')
    AND sender_id IS NOT NULL
    AND TRIM(CAST(sender_id AS STRING)) <> ''
  GROUP BY
    CAST(dt AS STRING),
    LOWER(CAST(pcode AS STRING)),
    CAST(anchor_uid AS STRING),
    CAST(sender_id AS STRING)

  UNION ALL

  -- 抖音打赏：先丢弃源品类，只保留到 天+平台+主播+用户。
  SELECT
    CAST(dt AS STRING) AS dt,
    'douyin' AS pcode,
    CAST(uid AS STRING) AS anchor_uid,
    MAX(CAST(r_owner AS STRING)) AS anchor_name,
    CAST(sender_id AS STRING) AS user_id,
    SUM(COALESCE(CAST(gift_value AS DOUBLE), 0)) AS gift_value,
    COUNT(*) AS gift_cnt
  FROM zhgametemp.yty_douyin_all_rcategory_gift_detail
  WHERE dt = '${tdate?string('yyyy-MM-dd')}'
    AND sender_id IS NOT NULL
    AND TRIM(CAST(sender_id AS STRING)) <> ''
  GROUP BY
    CAST(dt AS STRING),
    CAST(uid AS STRING),
    CAST(sender_id AS STRING)
),

gift_user_day AS (
  SELECT
    dt,
    pcode,
    anchor_uid,
    user_id,
    MAX(anchor_name) AS gift_anchor_name,
    SUM(gift_value) AS gift_value,
    SUM(gift_cnt) AS gift_cnt
  FROM gift_user_raw
  GROUP BY dt, pcode, anchor_uid, user_id
  HAVING SUM(gift_value) > 0
),

danmu_user_day AS (
  SELECT
    CAST(dt AS STRING) AS dt,
    CASE
      WHEN LOWER(CAST(pcode AS STRING)) = 'douyin_web' THEN 'douyin'
      ELSE LOWER(CAST(pcode AS STRING))
    END AS pcode,
    CAST(uid AS STRING) AS anchor_uid,
    CAST(sender AS STRING) AS user_id,
    MAX(CAST(r_owner AS STRING)) AS danmu_anchor_name,
    COUNT(*) AS danmu_cnt
  FROM gamelive.dwt_jingpin_danmulog_day
  WHERE dt = '${tdate?string('yyyy-MM-dd')}'
    AND LOWER(CAST(pcode AS STRING)) IN ('douyu', 'bilibili', 'douyin_web')
    AND CAST(msgtype AS STRING) = '0'
    AND sender IS NOT NULL
    AND TRIM(CAST(sender AS STRING)) <> ''
  GROUP BY
    CAST(dt AS STRING),
    CASE
      WHEN LOWER(CAST(pcode AS STRING)) = 'douyin_web' THEN 'douyin'
      ELSE LOWER(CAST(pcode AS STRING))
    END,
    CAST(uid AS STRING),
    CAST(sender AS STRING)
),

user_day AS (
  SELECT dt, pcode, anchor_uid, user_id FROM gift_user_day
  UNION
  SELECT dt, pcode, anchor_uid, user_id FROM danmu_user_day
)

SELECT
  a.pcode,
  a.r_category,
  a.anchor_uid,
  COALESCE(a.anchor_name, g.gift_anchor_name, d.danmu_anchor_name) AS anchor_name,
  IF(d.user_id IS NOT NULL, u.user_id, NULL) AS danmu_user_id,
  IF(g.user_id IS NOT NULL, u.user_id, NULL) AS gift_user_id,
  COALESCE(d.danmu_cnt, 0) AS danmu_cnt,
  COALESCE(g.gift_cnt, 0) AS gift_cnt,
  COALESCE(g.gift_value, 0.0) AS gift_value,
  CASE
    WHEN g.user_id IS NULL THEN '未打赏'
    WHEN g.gift_value >= 100000 THEN '特大R'
    WHEN g.gift_value >= 10000 THEN '大R'
    WHEN g.gift_value > 100 THEN '中R'
    WHEN g.gift_value > 0 THEN '小R'
    ELSE '未打赏'
  END AS gift_user_type
FROM user_day u
INNER JOIN anchor_day a
  ON u.dt = a.dt
 AND u.pcode = a.pcode
 AND u.anchor_uid = a.anchor_uid
LEFT JOIN gift_user_day g
  ON u.dt = g.dt
 AND u.pcode = g.pcode
 AND u.anchor_uid = g.anchor_uid
 AND u.user_id = g.user_id
LEFT JOIN danmu_user_day d
  ON u.dt = d.dt
 AND u.pcode = d.pcode
 AND u.anchor_uid = d.anchor_uid
 AND u.user_id = d.user_id;
