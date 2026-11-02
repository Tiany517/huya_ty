select 
  substr(a.date,1,10) as match_dt,
  a.match_id,
  a.match_name
  -- a.match_id, 
  -- b.game_full_name,
  -- a.uid  ### uid=luid ###
  -- nick 
from gamelive.dwd_huya_dim_game_copyright_info_d_a a --赛事版权表格
left join (
  select gid, game_full_name 
  from gamelive.to_main_games_day -- 赛事明细底表
  where dt = '2026-05-10' 
) b on a.game_id = b.gid
left join (
  select nick, yyid, uid 
  from gamelive.dim_huya_ayyuid_info 
  where dt = '2026-05-10'
) c on a.uid = c.uid
where a.dt='2026-05-10'
and substr(date,1,10)>='2024-01-01'
-- and substr(date,1,10)<='2024-07-08'
and live_type like '%直播%' --只计算直播
and room_type = '独立直播间' --官方直播间 
and a.game_id = '1' -- 英雄联盟
group by 
  1,2,3
order by 1 asc