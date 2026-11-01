with new_user as (
  select a.dt, a.user_ukey, a.luid
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a
  where a.dt between '2026-06-12' and '2026-07-01'
    and a.guiyin_tag <> 'mailiang'
),

user_days as (
    select
        nu.luid,
        nu.luid_name,
        nu.user_ukey,
        count(distinct case when b.dt between nu.new_dt and date_add(nu.new_dt, 6) then b.dt end) as active_days_7d,
        count(distinct case when b.dt between nu.new_dt and date_add(nu.new_dt, 13) then b.dt end) as active_days_14d,
        max(case when b.dt = date_add(nu.new_dt, 6) then 1 else 0 end) as is_retain_7,
        max(case when b.dt = date_add(nu.new_dt, 13) then 1 else 0 end) as is_retain_14
    from new_user nu
    left join (
        select distinct dt, user_ukey
        from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
        where dt between '2026-06-01' and '2026-07-12'
          and is_black_ukey = 0
    ) b
        on nu.user_ukey = b.user_ukey
        and b.dt between nu.new_dt and date_add(nu.new_dt, 13)
    group by nu.luid, nu.luid_name, nu.user_ukey
)

select
    luid,
    luid_name,
    count(distinct user_ukey) as total_new,
    sum(is_retain_7) as retain_7d_cnt,
    sum(is_retain_7) * 1.0 / count(distinct user_ukey) as retain_7d_rate,
    sum(active_days_7d) as sum_all_active_days_7d,
    sum(active_days_7d) * 1.0 / count(distinct user_ukey) as avg_7d_active_day,
    sum(is_retain_14) as retain_14d_cnt,
    sum(is_retain_14) * 1.0 / count(distinct user_ukey) as retain_14d_rate,
    sum(active_days_14d) as sum_all_active_days_14d,
    sum(active_days_14d) * 1.0 / count(distinct user_ukey) as avg_14d_active_day
from user_days
group by luid, luid_name
