with laxin_info as (
  select distinct 
    a.dt,
    a.luid,
    a.user_ukey,
    'laxin' as tag
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a
  where a.dt between '2026-06-12' and '2026-06-21'
    and a.guiyin_tag <> 'mailiang'

  union all

  select distinct 
    a.dt,
    a.luid,
    a.user_ukey,
    'huiliu' as tag
  from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1 a
  where a.dt between '2026-06-12' and '2026-06-21'
)



select
    a.copyright_name,
    a.match_name,
    count(distinct dt) as activity_duration,
    count(distinct b.user_ukey) as user_cnt,
    count(distinct b.user_ukey)/count(distinct dt) as avg_user_cnt
from (
    select
        copyright_name,
        match_name,
        dt
    from (
        select
            day as dt,
            copyright_name,
            concat(substr(day, 1, 4), match_name) as match_name
        from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
        where dt = '2026-06-25'
            and day >= '2024-01-01' 
        group by day, copyright_name, match_name, uid
    )
    group by 1,2
)
inner join laxin_info b 
on a.dt = b.dt and a.luid = b.luid
group by a.copyright_name, a.match_name
