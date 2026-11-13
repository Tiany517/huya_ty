select count(*) as row_cnt, count(distinct uid) as uid_cnt, sum(exposure_cnt) as exposure_cnt,
 count(*) - count(distinct row(material_id, uid)) as duplicate_keys
from zhgametemp.zty_vip_popup_type_user_d_i_v1
where dt = '2026-11-09'
