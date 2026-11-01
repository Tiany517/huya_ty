-- 目的：基于现有派生表口径，生成互相可复用的“主播日表”和“用户活动明细表”。
-- 重要：不要把两张表强行合并成一张用户级宽表，否则主播日 watch_min 会随用户数重复。
-- 主播日口径：完全沿用 zhgametemp.yty_jingpin_anchor_vaild_dau，不重算品类、不重新选主品类。
-- 用户活动口径：按天、平台、主播、用户、行为源品类汇总；gift_source_category 来自打赏源表，danmu_source_category 来自弹幕源表。
-- 平台：douyu、bilibili、douyin；pcode 原样保留，避免改变现成派生表口径。
-- 调度：Spark，tdate 日分区覆盖，支持幂等重跑和逐日回刷。

CREATE TABLE IF NOT EXISTS zhgametemp.yty_jingpin_external_anchor_day_di (
  pcode STRING COMMENT '平台，沿用派生表原值',
  r_category STRING COMMENT '品类，完全沿用派生表原值',
  anchor_uid STRING COMMENT '主播ID，取派生表r_lid',
  anchor_name STRING COMMENT '主播名称',
  vaild_acu DOUBLE COMMENT '有效ACU，沿用派生表',
  live_mins DOUBLE COMMENT '直播分钟数，沿用派生表',
  watch_min DOUBLE COMMENT '观时分钟数，沿用派生表',
  mall_watch_min DOUBLE COMMENT '品类大盘观时分钟数，沿用派生表',
  cate_vaild_dau DOUBLE COMMENT '品类有效DAU，沿用派生表',
  anchor_vaild_dau DOUBLE COMMENT '主播有效DAU，沿用派生表'
)
PARTITIONED BY (dt STRING COMMENT '日期分区')
STORED AS ORC;

CREATE TABLE IF NOT EXISTS zhgametemp.yty_jingpin_external_anchor_user_activity_di (
  pcode STRING COMMENT '平台',
  anchor_uid STRING COMMENT '平台内主播ID',
  anchor_name STRING COMMENT '主播名称',
  danmu_user_id STRING COMMENT '弹幕用户ID；该用户在该源品类下未发弹幕为空',
  gift_user_id STRING COMMENT '打赏用户ID；该用户在该源品类下未打赏为空',
  danmu_source_category STRING COMMENT '弹幕源表原始品类',
  gift_source_category STRING COMMENT '打赏源表原始品类',
  danmu_cnt BIGINT COMMENT '该用户在该主播直播间、该弹幕源品类下的普通弹幕次数',
  gift_cnt BIGINT COMMENT '该用户在该主播直播间、该打赏源品类下的打赏记录数',
  gift_value DOUBLE COMMENT '该用户在该主播直播间、该打赏源品类下的打赏金额',
  gift_user_type STRING COMMENT '按该用户当天在同一主播下跨源品类打赏总额计算的分层'
)
PARTITIONED BY (dt STRING COMMENT '日期分区')
STORED AS ORC;


WITH anchor_day_source AS (
  -- 原样取现成派生表，确保按 pcode + r_category 聚合后与参考 SQL 完全一致。
  SELECT
    CAST(dt AS STRING) AS dt,
    LOWER(CAST(pcode AS STRING)) AS pcode,
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
    AND LOWER(CAST(pcode AS STRING)) IN ('douyu', 'bilibili', 'douyin', 'douyin_web')
)

INSERT OVERWRITE TABLE zhgametemp.yty_jingpin_external_anchor_day_di
PARTITION (dt='${tdate?string('yyyy-MM-dd')}')

SELECT
  pcode,
  r_category,
  anchor_uid,
  anchor_name,
  vaild_acu,
  live_mins,
  watch_min,
  mall_watch_min,
  cate_vaild_dau,
  anchor_vaild_dau
FROM anchor_day_source;


WITH anchor_day_source AS (
  SELECT
    CAST(dt AS STRING) AS dt,
    LOWER(CAST(pcode AS STRING)) AS pcode,
    CAST(r_lid AS STRING) AS anchor_uid,
    MAX(CAST(r_owner AS STRING)) AS anchor_name
  FROM zhgametemp.yty_jingpin_anchor_vaild_dau
  WHERE dt = '${tdate?string('yyyy-MM-dd')}'
    AND LOWER(CAST(pcode AS STRING)) IN ('douyu', 'bilibili', 'douyin', 'douyin_web')
  GROUP BY
    CAST(dt AS STRING),
    LOWER(CAST(pcode AS STRING)),
    CAST(r_lid AS STRING)
),

anchor_key AS (
  SELECT DISTINCT dt, pcode, anchor_uid
  FROM anchor_day_source
),

gift_user_raw AS (
  -- 斗鱼、B站打赏，保留源品类。
  SELECT
    CAST(dt AS STRING) AS dt,
    LOWER(CAST(pcode AS STRING)) AS pcode,
    CAST(anchor_uid AS STRING) AS anchor_uid,
    CAST(anchor_name AS STRING) AS anchor_name,
    CAST(r_game_name AS STRING) AS source_category,
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
    CAST(anchor_name AS STRING),
    CAST(r_game_name AS STRING),
    CAST(sender_id AS STRING)

  UNION ALL

  -- 抖音打赏，保留源品类。
  SELECT
    CAST(dt AS STRING) AS dt,
    'douyin' AS pcode,
    CAST(uid AS STRING) AS anchor_uid,
    CAST(r_owner AS STRING) AS anchor_name,
    CAST(r_category AS STRING) AS source_category,
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
    CAST(r_owner AS STRING),
    CAST(r_category AS STRING),
    CAST(sender_id AS STRING)
),

gift_user_category_day AS (
  SELECT
    dt,
    pcode,
    anchor_uid,
    user_id,
    source_category,
    MAX(anchor_name) AS gift_anchor_name,
    SUM(gift_value) AS gift_value,
    SUM(gift_cnt) AS gift_cnt
  FROM gift_user_raw
  GROUP BY
    dt,
    pcode,
    anchor_uid,
    user_id,
    source_category
  HAVING SUM(gift_value) > 0
),

gift_user_day_total AS (
  -- 打赏类型仍按用户当天在同一个主播下的跨品类总金额计算。
  SELECT
    dt,
    pcode,
    anchor_uid,
    user_id,
    SUM(gift_value) AS gift_value
  FROM gift_user_category_day
  GROUP BY dt, pcode, anchor_uid, user_id
),

danmu_user_category_day AS (
  -- 弹幕保留源品类；这里只统计普通文字弹幕，同用户同主播同源品类聚合。
  SELECT
    CAST(dt AS STRING) AS dt,
    LOWER(CAST(pcode AS STRING)) AS pcode,
    CAST(uid AS STRING) AS anchor_uid,
    CAST(sender AS STRING) AS user_id,
    CAST(r_category AS STRING) AS source_category,
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
    LOWER(CAST(pcode AS STRING)),
    CAST(uid AS STRING),
    CAST(sender AS STRING),
    CAST(r_category AS STRING)
),

user_category_day AS (
  SELECT dt, pcode, anchor_uid, user_id, gift_source_category AS source_category
  FROM gift_user_category_day

  UNION

  SELECT dt, pcode, anchor_uid, user_id, danmu_source_category AS source_category
  FROM (
    SELECT dt, pcode, anchor_uid, user_id, source_category AS danmu_source_category
    FROM danmu_user_category_day
  ) x
)

INSERT OVERWRITE TABLE zhgametemp.yty_jingpin_external_anchor_user_activity_di
PARTITION (dt='${tdate?string('yyyy-MM-dd')}')

SELECT
  u.pcode,
  u.anchor_uid,
  COALESCE(a.anchor_name, g.gift_anchor_name, d.danmu_anchor_name) AS anchor_name,
  IF(d.user_id IS NOT NULL, u.user_id, NULL) AS danmu_user_id,
  IF(g.user_id IS NOT NULL, u.user_id, NULL) AS gift_user_id,
  d.source_category AS danmu_source_category,
  g.source_category AS gift_source_category,
  COALESCE(d.danmu_cnt, 0) AS danmu_cnt,
  COALESCE(g.gift_cnt, 0) AS gift_cnt,
  COALESCE(g.gift_value, 0) AS gift_value,
  CASE
    WHEN g.user_id IS NULL THEN '未打赏'
    WHEN t.gift_value >= 100000 THEN '特大R'
    WHEN t.gift_value >= 10000 THEN '大R'
    WHEN t.gift_value > 100 THEN '中R'
    ELSE '小R'
  END AS gift_user_type
FROM user_category_day u
INNER JOIN anchor_key k
  ON u.dt = k.dt
 AND u.pcode = k.pcode
 AND u.anchor_uid = k.anchor_uid
LEFT JOIN anchor_day_source a
  ON u.dt = a.dt
 AND u.pcode = a.pcode
 AND u.anchor_uid = a.anchor_uid
LEFT JOIN gift_user_category_day g
  ON u.dt = g.dt
 AND u.pcode = g.pcode
 AND u.anchor_uid = g.anchor_uid
 AND u.user_id = g.user_id
 AND u.source_category = g.source_category
LEFT JOIN danmu_user_category_day d
  ON u.dt = d.dt
 AND u.pcode = d.pcode
 AND u.anchor_uid = d.anchor_uid
 AND u.user_id = d.user_id
 AND u.source_category = d.source_category
LEFT JOIN gift_user_day_total t
  ON u.dt = t.dt
 AND u.pcode = t.pcode
 AND u.anchor_uid = t.anchor_uid
 AND u.user_id = t.user_id;
