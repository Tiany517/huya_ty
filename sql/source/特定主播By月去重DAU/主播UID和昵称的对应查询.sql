select 
    nick, 
    yyid, 
    uid  -- nick昵称和uid的对应关系表
from gamelive.dim_huya_ayyuid_info -- 虎牙主播表
where dt = '2026-05-11'
