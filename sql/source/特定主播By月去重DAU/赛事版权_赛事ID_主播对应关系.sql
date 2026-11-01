select 
    substr(a.date,1,10) as match_dt,
    a.match_name,
    a.match_id, 
    b.game_full_name, 
    a.game_id
    -- a.uid, -- luid
    -- c.nick
from gamelive.dwd_huya_dim_game_copyright_info_d_a a --赛事版权表
left join (
    select gid, game_full_name 
    from gamelive.to_main_games_day --游戏信息底表
    where dt >= '2026-04-01' and dt <= '2026-05-31'
) b on a.game_id = b.gid
left join (
    select nick, yyid, uid  -- nick昵称和uid的对应关系表
    from gamelive.dim_huya_ayyuid_info -- 虎牙主播表
    where dt >= '2026-04-01' and dt <= '2026-05-31'
) c on a.uid = c.uid
where a.dt='2026-05-11'
and substr(date,1,10) >= '2026-04-01' and substr(date,1,10) <= '2026-05-31'
-- and substr(date,1,10)<='2024-07-08'
and a.live_type like '%直播%' --只计算直播
and a.room_type = '独立直播间' --官方直播间 
and b.game_full_name like '%英雄联盟%'
-- and a.game_id = '1' -- 英雄联盟
-- and a.match_id in (9029201) -- LPL春季赛第一赛段
group by 
    1,2,3,4,5
