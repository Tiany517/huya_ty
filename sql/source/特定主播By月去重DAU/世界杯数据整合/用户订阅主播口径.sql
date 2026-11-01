select ukey,ayyuid
from gamelive.dwd_huya_dy_user a 
join zhgametemp.lj_dim_ukey_yyuid b 
on a.yyuid  = b.yyuid 
where length(a.dt) = 10
and a.dt>='2025-03-01' and a.dt <= '2025-03-09'
and a.tag = 'huya'
group by ukey,ayyuid 