-- Presto目标表检查：每日用户、曝光、唯一键和异常字段。
select dt, count(*) as row_cnt, count(distinct uid) as uid_cnt,
  sum(exposure_cnt) as exposure_cnt,
  count(*) - count(distinct row(material_id, uid)) as duplicate_keys,
  sum(case when popup_type is null or material_id is null or uid is null
    or exposure_cnt is null or exposure_cnt <= 0 then 1 else 0 end) as invalid_rows
from zhgametemp.zty_vip_popup_type_user_d_i_v1
where dt between '2026-11-01' and '2026-11-12'
group by dt order by dt
