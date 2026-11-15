-- 粒度：dt+配置；用于识别不同类型的投放日峰谷。
select
  dt,
  popup_type,
  material_id,
  count(distinct uid) as popup_user_cnt,
  sum(exposure_cnt) as exposure_cnt
from zhgametemp.zty_vip_popup_type_user_d_i_v1
where dt between '2026-11-01' and '2026-11-12'
group by dt, popup_type, material_id
order by dt, exposure_cnt desc;

-- End of query.

