-- 目的：生成站外主播-日-用户活动日志明细。
-- 粒度：dt + pcode + anchor_uid + 用户ID，一行对应用户当天在一个主播直播间下的弹幕/打赏信息。
-- 平台：斗鱼、B站、抖音；抖音 douyin_web 统一映射为 douyin；不含虎牙。
-- 品类：保留全部品类，包括娱乐品类。r_category 为标准品类，platform_category 为平台原始品类。
-- 用户合并：弹幕用户与打赏用户取并集；同一用户当天同时有弹幕和打赏时合并为一行。
-- 时长：抖音等平台 live_mins 字段为 0，直播时长使用 hour_cnt * 60；其他平台使用 live_mins。
-- 调度：Spark，按 dt 分区覆盖，支持同一 tdate 幂等重跑，也支持历史日期逐日回刷。
-- 依赖变量：tdate，示例为 ${tdate?string('yyyy-MM-dd')}。

CREATE TABLE IF NOT EXISTS zhgametemp.yty_jingpin_external_anchor_user_activity_di (
  pcode STRING COMMENT '平台；抖音统一为douyin',
  r_category STRING COMMENT '主播当天标准品类',
  platform_category STRING COMMENT '主播当天平台原始品类',
  anchor_uid STRING COMMENT '平台内主播ID',
  anchor_name STRING COMMENT '主播名称',
  danmu_user_id STRING COMMENT '当天发送普通弹幕的用户ID；未发弹幕为空',
  gift_user_id STRING COMMENT '当天发生打赏的用户ID；未打赏为空',
  danmu_cnt BIGINT COMMENT '当天在该主播直播间发送普通弹幕次数',
  gift_cnt BIGINT COMMENT '当天在该主播直播间打赏记录数',
  gift_value DOUBLE COMMENT '当天在该主播直播间打赏金额合计',
  gift_user_type STRING COMMENT '当天打赏金额分层',
  live_mins DOUBLE COMMENT '主播当天直播分钟数',
  watch_min DOUBLE COMMENT '主播当天直播分钟数乘有效ACU，用于后续观时加权'
)
PARTITIONED BY (dt STRING COMMENT '日期分区')
STORED AS ORC;

WITH anchor_day_agg AS (
  -- 主播日主数据：保留全部品类，不剔除娱乐；抖音开播时长取 hour_cnt * 60。
  SELECT
    CAST(dt AS STRING) AS dt,
    CASE
      WHEN LOWER(CAST(pcode AS STRING)) = 'douyin_web' THEN 'douyin'
      ELSE LOWER(CAST(pcode AS STRING))
    END AS pcode,
    COALESCE(cate1, r_category) AS r_category,
    CAST(r_category AS STRING) AS platform_category,
    CAST(r_lid AS STRING) AS anchor_uid,
    MAX(CAST(r_owner AS STRING)) AS anchor_name,
    SUM(
      IF(
        LOWER(CAST(pcode AS STRING)) IN ('douyin_web', 'douyin', 'kuaishou'),
        COALESCE(CAST(hour_cnt AS BIGINT), 0) * 60,
        COALESCE(CAST(live_mins AS BIGINT), 0)
      )
    ) AS live_mins,
    SUM(
      IF(
        LOWER(CAST(pcode AS STRING)) IN ('douyin_web', 'douyin', 'kuaishou'),
        COALESCE(CAST(hour_cnt AS BIGINT), 0) * 60,
        COALESCE(CAST(live_mins AS BIGINT), 0)
      ) * COALESCE(CAST(ext['vaild_acu'] AS DOUBLE), 0)
    ) AS watch_min
  FROM gamelive.dm_mkt_rowner_day
  WHERE dt = '${tdate?string('yyyy-MM-dd')}'
    AND LOWER(CAST(pcode AS STRING)) IN ('douyu', 'bilibili', 'douyin_web')
  GROUP BY
    CAST(dt AS STRING),
    CASE
      WHEN LOWER(CAST(pcode AS STRING)) = 'douyin_web' THEN 'douyin'
      ELSE LOWER(CAST(pcode AS STRING))
    END,
    COALESCE(cate1, r_category),
    CAST(r_category AS STRING),
    CAST(r_lid AS STRING)
),

anchor_day AS (
  -- 同一主播当天若映射出多个品类，保留有效直播分钟最长的一条作为主播主品类；
  -- 完整互动日志仍挂在主播上，不因品类映射拆成多行。
  SELECT
    dt,
    pcode,
    r_category,
    platform_category,
    anchor_uid,
    anchor_name,
    live_mins,
    watch_min
  FROM (
    SELECT
      a.*,
      ROW_NUMBER() OVER (
        PARTITION BY a.dt, a.pcode, a.anchor_uid
        ORDER BY a.live_mins DESC, a.watch_min DESC, a.r_category, a.platform_category
      ) AS rn
    FROM anchor_day_agg a
  ) x
  WHERE rn = 1
),

gift_user_raw AS (
  -- 斗鱼、B站打赏明细，先压缩到天-平台-主播-用户-原始品类粒度。
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

  -- 抖音打赏明细。
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

gift_user_day AS (
  -- 一个用户当天在同一主播下可能跨多个原始品类打赏，这里合并为该主播下的日打赏金额。
  SELECT
    dt,
    pcode,
    anchor_uid,
    user_id,
    MAX(anchor_name) AS gift_anchor_name,
    MAX(source_category) AS gift_source_category,
    SUM(gift_value) AS gift_value,
    SUM(gift_cnt) AS gift_cnt
  FROM gift_user_raw
  GROUP BY
    dt,
    pcode,
    anchor_uid,
    user_id
  HAVING SUM(gift_value) > 0
),

danmu_user_day AS (
  -- 普通文字弹幕明细；msgtype=0，按天-平台-主播-用户去重聚合。
  SELECT
    CAST(dt AS STRING) AS dt,
    CASE
      WHEN LOWER(CAST(pcode AS STRING)) = 'douyin_web' THEN 'douyin'
      ELSE LOWER(CAST(pcode AS STRING))
    END AS pcode,
    CAST(uid AS STRING) AS anchor_uid,
    CAST(sender AS STRING) AS user_id,
    MAX(CAST(r_owner AS STRING)) AS danmu_anchor_name,
    MAX(CAST(r_category AS STRING)) AS danmu_source_category,
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
  -- 弹幕用户与打赏用户取并集，避免只保留既发弹幕又打赏的用户。
  SELECT dt, pcode, anchor_uid, user_id FROM gift_user_day
  UNION
  SELECT dt, pcode, anchor_uid, user_id FROM danmu_user_day
)

INSERT OVERWRITE TABLE zhgametemp.yty_jingpin_external_anchor_user_activity_di
PARTITION (dt='${tdate?string('yyyy-MM-dd')}')

SELECT
  u.pcode,
  COALESCE(a.r_category, d.danmu_source_category, g.gift_source_category) AS r_category,
  COALESCE(a.platform_category, d.danmu_source_category, g.gift_source_category) AS platform_category,
  u.anchor_uid,
  COALESCE(a.anchor_name, d.danmu_anchor_name, g.gift_anchor_name) AS anchor_name,
  IF(d.user_id IS NOT NULL, u.user_id, NULL) AS danmu_user_id,
  IF(g.user_id IS NOT NULL, u.user_id, NULL) AS gift_user_id,
  COALESCE(d.danmu_cnt, 0) AS danmu_cnt,
  COALESCE(g.gift_cnt, 0) AS gift_cnt,
  COALESCE(g.gift_value, 0) AS gift_value,
  CASE
    WHEN g.user_id IS NULL THEN '未打赏'
    WHEN g.gift_value >= 100000 THEN '特大R'
    WHEN g.gift_value >= 10000 THEN '大R'
    WHEN g.gift_value > 100 THEN '中R'
    ELSE '小R'
  END AS gift_user_type,
  a.live_mins,
  a.watch_min
FROM user_day u
LEFT JOIN anchor_day a
  ON u.dt = a.dt
 AND u.pcode = a.pcode
 AND u.anchor_uid = a.anchor_uid
LEFT JOIN danmu_user_day d
  ON u.dt = d.dt
 AND u.pcode = d.pcode
 AND u.anchor_uid = d.anchor_uid
 AND u.user_id = d.user_id
LEFT JOIN gift_user_day g
  ON u.dt = g.dt
 AND u.pcode = g.pcode
 AND u.anchor_uid = g.anchor_uid
 AND u.user_id = g.user_id;
