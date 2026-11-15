-- 粒度：被拍脸的VIP用户；统计跨类型数量分布。
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

popup_user as (
  select
    cast(uid as varchar) as uid,
    count(distinct popup_type) as popup_type_cnt
  from zhgametemp.zty_vip_popup_type_user_d_i_v1
  where dt between '2026-11-01' and '2026-11-12'
  group by cast(uid as varchar)
)

select
  p.popup_type_cnt,
  count(*) as vip_user_cnt,
  round(100.0 * count(*) / nullif(sum(count(*)) over (), 0), 2) as pct_within_popup_vip
from popup_user p
inner join paid_member m on p.uid = m.uid
group by p.popup_type_cnt
order by p.popup_type_cnt;

-- End of query.

