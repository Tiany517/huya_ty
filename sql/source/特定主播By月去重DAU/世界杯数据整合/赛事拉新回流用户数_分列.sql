with copyright_info as (
  select distinct
    substr(a.date,1,10) as dt,
    a.game_id,
    b.game_name,
    b.game_label,
    a.match_name,
    a.uid as luid
  from gamelive.dwd_huya_dim_game_copyright_info_d_a a
  left join (
    select
      game_id,
      game_name,
      max(game_label) as game_label
    from gamelive.dim_huya_game_d_a 
    where 
      dt >= '2024-01-01'
    group by 
      game_id,
      game_name
  ) b 
  on a.game_id = b.game_id
  where a.dt='2026-07-12'
    and substr(a.date,1,10) >= '2026-06-12'
    and substr(a.date,1,10) <= '2026-07-15'
    and a.live_type like '%直播%'
)

, laxin_huiliu_user as (
    select distinct
        dt as new_dt,
        luid,
        luid_name,
        user_ukey,
        game_id,
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
        game_id,
        '回流' as label
    from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1
    where dt between '2026-06-12' and '2026-07-15'
      and user_ukey is not null
)



select
  a.game_name,
  a.match_name,
  count(distinct case when b.label = '拉新' then b.user_ukey end) as laxin_user_cnt,
  count(distinct case when b.label = '回流' then b.user_ukey end) as huiliu_user_cnt,
  count(distinct b.user_ukey) as total_user_cnt
from copyright_info a
left join laxin_huiliu_user b
on 
  a.luid = b.luid
  and a.dt = b.new_dt
  and a.game_id = b.game_id
group by 
  a.game_name,
  a.match_name
