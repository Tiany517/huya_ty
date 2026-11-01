select distinct
    gid,
    game_full_name,
    game_short_name
from gamelive.to_main_games_day --游戏底表，包含game_label等
where 
  dt >= '2024-01-01'
 and lower(game_full_name) like '%apex%'
-- and gid in (100032) or gid in (10032)