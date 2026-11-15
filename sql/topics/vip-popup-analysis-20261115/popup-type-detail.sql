-- 粒度：配置ID；用户跨配置可重复，类型UV和曝光份额不可直接相加为整体用户。
select
  popup_type,
  material_id,
  count(*) as config_user_row_cnt,
  count(distinct uid) as popup_user_cnt,
  sum(exposure_cnt) as exposure_cnt,
  round(1.0 * sum(exposure_cnt) / nullif(count(distinct uid), 0), 2)
    as exposure_per_user
from zhgametemp.zty_vip_popup_type_user_d_i_v1
where dt between '2026-11-01' and '2026-11-12'
group by popup_type, material_id
order by exposure_cnt desc, material_id;

-- End of query.

