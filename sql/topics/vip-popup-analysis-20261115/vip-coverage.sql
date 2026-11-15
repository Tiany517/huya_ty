-- 粒度：VIP快照用户；匹配键为字符串UID。
-- VIP口径：2026-11-12快照中成功且正金额订单去重用户，首次订单取全历史最早成功时间。
-- 拍脸口径：ztz表11月1日至12日任意配置、任意一天曝光，用户去重。
with paid_member as (
  select
    cast(uid as varchar) as uid,
    min(try_cast(create_time as timestamp)) as first_order_ts
  from gamelive.dwd_huya_pay_platform_vip_detail_d_a
  where dt = '2026-11-12'
    and status = '200'
    and try_cast(amount as double) > 0
    and coalesce(lower(trim(cast(uid as varchar))), '')
        not in ('0','',' ','null','other','-','-1')
  group by cast(uid as varchar)
),

popup_user as (
  select distinct cast(uid as varchar) as uid
  from zhgametemp.zty_vip_popup_type_user_d_i_v1
  where dt between '2026-11-01' and '2026-11-12'
),

member_flag as (
  select
    m.uid,
    m.first_order_ts,
    case when p.uid is not null then 1 else 0 end as is_popup,
    case when m.first_order_ts >= timestamp '2026-08-31 00:00:00'
              and m.first_order_ts < timestamp '2026-11-13 00:00:00'
         then 1 else 0 end as is_activity_period_new_vip
  from paid_member m
  left join popup_user p on m.uid = p.uid
)

select
  '全部成功付费会员' as vip_group,
  count(*) as vip_user_cnt,
  sum(is_popup) as popup_user_cnt,
  count(*) - sum(is_popup) as no_popup_user_cnt,
  round(100.0 * sum(is_popup) / nullif(count(*), 0), 2) as popup_rate_pct,
  round(100.0 * (count(*) - sum(is_popup)) / nullif(count(*), 0), 2) as no_popup_rate_pct
from member_flag

union all

select
  '2026-08-31至11-12新增VIP' as vip_group,
  count(*) as vip_user_cnt,
  sum(is_popup) as popup_user_cnt,
  count(*) - sum(is_popup) as no_popup_user_cnt,
  round(100.0 * sum(is_popup) / nullif(count(*), 0), 2) as popup_rate_pct,
  round(100.0 * (count(*) - sum(is_popup)) / nullif(count(*), 0), 2) as no_popup_rate_pct
from member_flag
where is_activity_period_new_vip = 1;

-- End of query.

