-- 粒度：VIP快照用户 + 拍脸类型；VIP总UV与各类型UV分别去重。
with paid_member as (
  select cast(uid as varchar) as uid
  from gamelive.dwd_huya_pay_platform_vip_detail_d_a
  where dt = '2026-11-12'
    and status = '200'
    and try_cast(amount as double) > 0
    and coalesce(lower(trim(cast(uid as varchar))), '')
        not in ('0','',' ','null','other','-','-1')
  group by cast(uid as varchar)
),

popup_type_user as (
  select
    popup_type,
    material_id,
    cast(uid as varchar) as uid,
    sum(exposure_cnt) as exposure_cnt
  from zhgametemp.zty_vip_popup_type_user_d_i_v1
  where dt between '2026-11-01' and '2026-11-12'
  group by popup_type, material_id, cast(uid as varchar)
),

vip_type as (
  select
    p.popup_type,
    p.material_id,
    count(distinct p.uid) as vip_popup_user_cnt,
    sum(p.exposure_cnt) as vip_exposure_cnt
  from popup_type_user p
  inner join paid_member m on p.uid = m.uid
  group by p.popup_type, p.material_id
),

vip_total as (
  select count(distinct uid) as vip_user_cnt from paid_member
)

select
  v.popup_type,
  v.material_id,
  v.vip_popup_user_cnt,
  v.vip_exposure_cnt,
  round(100.0 * v.vip_popup_user_cnt / nullif(t.vip_user_cnt, 0), 2)
    as vip_coverage_pct
from vip_type v
cross join vip_total t
order by v.vip_popup_user_cnt desc, v.material_id;

-- End of query.

