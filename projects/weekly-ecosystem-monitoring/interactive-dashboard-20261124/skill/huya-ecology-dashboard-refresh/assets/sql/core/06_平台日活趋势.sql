-- 平台 DAU 日趋势：用于异动日报的官方平台总盘。
-- 输出粒度：dt；唯一键：dt。
-- 日期区间由调用方替换 <start>、<end>，必须覆盖日报日期和至少 4 个相同星期基线。
-- 不按品类汇总，避免用户跨品类重叠导致平台 DAU 被放大。
SELECT
    dt,
    count(DISTINCT user_ukey) AS platform_dau
FROM gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
WHERE dt BETWEEN '<start>' AND '<end>'
  AND product IN (
      'huya_andriod',
      'huya_ipad',
      'huya_pad',
      'huya_ios',
      'hmos_kiwi'
  )
  AND is_black_ukey = 0
GROUP BY dt
ORDER BY dt;
