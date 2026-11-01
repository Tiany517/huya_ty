with new_user as (
    select
        dt as new_dt,
        luid,
        luid_name,
        user_ukey
    from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1
    where dt between '2026-06-01' and '2026-06-30'
    group by dt, luid, luid_name, user_ukey
),
user_days as (
    select
        nu.luid,
        nu.luid_name,
        nu.user_ukey,
        count(distinct b.dt) as active_days_7d,
        case when count(distinct b.dt) > 0 then 1 else 0 end as is_retain
    from new_user nu
    left join (
        select distinct dt, user_ukey
        from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
        where dt between '2026-06-01' and '2026-07-06'
          and is_black_ukey = 0
    ) b
        on nu.user_ukey = b.user_ukey
        and b.dt between nu.new_dt and date_add(nu.new_dt, 6)
    group by nu.luid, nu.luid_name, nu.user_ukey
)
select
    luid,
    luid_name,
    count(distinct user_ukey) as total_new,
    sum(is_retain) as retain_7d_cnt,
    sum(is_retain) / count(distinct user_ukey) as retain_7d_rate,
    sum(active_days_7d) as sum_all_active_days,
    sum(active_days_7d) / count(distinct user_ukey) as avg_7d_active_day
from user_days
group by luid, luid_name