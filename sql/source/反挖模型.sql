select distinct 
  *
from zhgametemp.cys_huya_jingpin_fanwa_result
where 
  pcode in ('douyu') 
  and r_category in ('CS2')
  and dt >= '2026-01-01'
  and r_owner like ('%玩机器%')
order by dt