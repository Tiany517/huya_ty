select distinct
  game_name,
  game_id,
  game_type_name
from gamelive.dim_huya_game_d_a
where 
  dt >= '2024-01-01'
  and (game_type_name in ('暴雪', 'DOTA2', '炉石传说')) or (game_name like ('暴雪', 'DOTA2', '炉石传说'))