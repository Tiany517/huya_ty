-- 粒度：用户；先跨日期和配置合并，再统计曝光频率与跨配置类型数。
with user_popup as (
  select
    cast(uid as varchar) as uid,
    sum(exposure_cnt) as exposure_cnt,
    count(distinct popup_type) as popup_type_cnt,
    count(distinct material_id) as material_cnt,
    count(distinct dt) as active_day_cnt
  from zhgametemp.zty_vip_popup_type_user_d_i_v1
  where dt between '2026-11-01' and '2026-11-12'
  group by cast(uid as varchar)
)
select
  count(*) as popup_user_cnt,
  sum(exposure_cnt) as total_exposure_cnt,
  round(avg(cast(exposure_cnt as double)), 2) as avg_exposure_cnt,
  approx_percentile(exposure_cnt, 0.50) as exposure_p50,
  approx_percentile(exposure_cnt, 0.75) as exposure_p75,
  approx_percentile(exposure_cnt, 0.90) as exposure_p90,
  approx_percentile(exposure_cnt, 0.95) as exposure_p95,
  approx_percentile(exposure_cnt, 0.99) as exposure_p99,
  max(exposure_cnt) as exposure_max,
  round(avg(cast(popup_type_cnt as double)), 2) as avg_popup_type_cnt,
  sum(case when popup_type_cnt >= 2 then 1 else 0 end) as multi_type_user_cnt,
  round(100.0 * sum(case when popup_type_cnt >= 2 then 1 else 0 end)
    / nullif(count(*), 0), 2) as multi_type_user_rate_pct,
  round(avg(cast(active_day_cnt as double)), 2) as avg_active_day_cnt
from user_popup;

-- End of query.

