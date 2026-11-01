with anchor_info as (
  select 
    ayyuid as luid,
    max(nickname) as nickname
  from gamelive.dm_huya_ayyuid_detail_day
  where 
    dt >= '2023-01-01' and dt <= '2023-12-31'
    and ayyuid in (1259515661837,900821317)
  group by ayyuid
),


user_month_anchor_base as (
  select
      substr(a.dt, 1, 7) as mth,
      a.user_ukey as ukey,
      a.luid,
      sum(a.all_dur) as month_duration
  from zhgametemp.cwq_huya_gameid_heichan_ukey_detail_v2 a
  where 
      a.dt between '2023-01-01' and '2026-06-30'
      and heichan_lable = 'not_heichan' --去黑产
      and app_ukey is not null --APP
      and a.all_dur > 0
  group by
      substr(a.dt, 1, 7),
      a.user_ukey,
      a.luid
),

user_month_belong as (
    select
        mth,
        ukey,
        luid
    from (
        select
            mth,
            ukey,
            luid,
            row_number() over (
                partition by mth, ukey
                order by month_duration desc, luid
            ) as rn
        from user_month_anchor_base
    ) t
    where rn = 1
)


select
    a.mth,
    a.luid,
    b.nickname as luid_name,
    count(distinct a.ukey) as belong_user_cnt
from user_month_belong a 
left join anchor_info b 
  on a.luid = b.luid
where a.luid in (1259515661837, 900821317)
group by
    a.mth,
    a.luid,
    b.nickname