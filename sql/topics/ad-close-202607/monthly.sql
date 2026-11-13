-- Spark；待执行验证。仅在7月31个源分区就绪、日任务均成功并对账后运行。
-- 描述指标；固定分母是7月分层用户，不是广告曝光用户。
with close_month as (
  -- 输入：dt+ukey；输出：ukey唯一。跨日同一用户只计一次关闭用户。
  select
    user_ukey,
    max(is_close_ad) as is_close_ad,
    sum(close_ad_cnt) as close_ad_cnt
  from zhgametemp.zty_huya_close_ad_user_day_202607_v2
  where dt between '2026-07-01' and '2026-07-31'
  group by user_ukey
)

-- 输入两侧ukey唯一；1:0/1关联不放大；输出每个观看分层一行。
select
  w.user_level,
  count(*) as `分层用户数`,
  sum(coalesce(c.is_close_ad, 0)) as `7月关闭广告用户数`,
  round(100.0 * sum(coalesce(c.is_close_ad, 0))
    / nullif(count(*), 0), 2) as `7月关闭广告用户占比(%)`,
  sum(coalesce(c.close_ad_cnt, 0)) as `7月关闭广告次数`
from zhgametemp.zty_huya_watch_user_level_202607_v1 w
left join close_month c
  on w.user_ukey = c.user_ukey
group by w.user_level;
