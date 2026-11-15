-- 粒度：dt；描述拍脸表每日去重用户和曝光上报次数。
select
  dt,
  count(*) as config_user_row_cnt,
  count(distinct uid) as popup_user_cnt,
  sum(exposure_cnt) as exposure_cnt,
  round(1.0 * sum(exposure_cnt) / nullif(count(distinct uid), 0), 2)
    as exposure_per_user
from zhgametemp.zty_vip_popup_type_user_d_i_v1
where dt between '2026-11-01' and '2026-11-12'
group by dt
order by dt;

-- End of query.

