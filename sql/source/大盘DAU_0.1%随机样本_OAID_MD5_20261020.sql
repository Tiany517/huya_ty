-- 目的：从 2026 年 10 月全产品大盘 DAU 用户中抽取 0.1% 的 OAID 名单，并输出 OAID 的 32 位小写 MD5。
-- 数据源：gamelive.dws_huya_active_userid_d_i。
-- 时间范围：dt >= '2026-10-01' 且 dt < '2026-11-01'；当前最新可用分区为 2026-10-20。
-- 用户粒度：按 user_ukey 做整月去重；product 不限制，包含该表的全产品大盘。
-- 样本分母：10 月至少有一个非空 OAID 的月度去重 DAU 用户。
-- OAID 取值：同一 user_ukey 取 10 月最新日期、最新服务器时间对应的 OAID。
-- 抽样方式：按 random() 随机排序，抽取 ceil(用户数 × 0.1%) 条；每次执行样本会不同。
-- 输出口径：仅输出一列 oaid_md5，小写 32 位十六进制。

WITH monthly_dau_oaid_user AS (
    SELECT
        trim(user_ukey) AS user_ukey,
        max_by(
            trim(oaid),
            concat(dt, '|', coalesce(last_stime, ''))
        ) AS oaid
    FROM gamelive.dws_huya_active_userid_d_i
    WHERE dt >= '2026-10-01'
      AND dt < '2026-11-01'
      AND user_ukey IS NOT NULL
      AND trim(user_ukey) <> ''
      AND oaid IS NOT NULL
      AND trim(oaid) <> ''
    GROUP BY trim(user_ukey)
),

ranked_user AS (
    SELECT
        user_ukey,
        oaid,
        row_number() OVER (
            ORDER BY random()
        ) AS rn,
        count(*) OVER () AS user_cnt
    FROM monthly_dau_oaid_user
)

SELECT
    lower(to_hex(md5(to_utf8(oaid)))) AS oaid_md5
FROM ranked_user
WHERE rn <= ceil(user_cnt * 0.001)
ORDER BY rn;
