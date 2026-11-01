with laxin_huiliu_user as (
    select distinct
        dt as new_dt,
        luid,
        luid_name,
        user_ukey,
        '拉新' as label
    from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
    where dt between '2026-06-12' and '2026-07-15'
      and user_ukey is not null

    union all

    select distinct
        dt as new_dt,
        luid,
        luid_name,
        user_ukey,
        '回流' as label
    from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1
    where dt between '2026-06-12' and '2026-07-15'
      and user_ukey is not null
)

select
    luid,
    luid_name,
    count(distinct case when label = '拉新' then user_ukey end) as laxin_user_cnt,
    count(distinct case when label = '回流' then user_ukey end) as huiliu_user_cnt,
    count(distinct user_ukey) as total_user_cnt
from laxin_huiliu_user
group by
    luid,
    luid_name