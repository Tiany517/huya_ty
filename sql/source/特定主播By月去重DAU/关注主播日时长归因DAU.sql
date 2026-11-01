with target_zhubo as (
  select distinct
    nick,
    uid
  from gamelive.dim_huya_ayyuid_info
  where 
    dt >= '2024-01-01' 
    and nick in (
      '韩涵-TuT',
      '小予神【从不滚刀】',
      '华创-明凯【巅峰第二】'
    )
)

select distinct
    a.dt,
    b.nick,
    count(a.ukey) as dau
from zhgametemp.cwq_huya_ukey_shichang_luid_gameid_guishu_day_v1 a 
left join target_zhubo b 
on a.luid = b.uid
where a.dt >= '2026-04-01' and a.dt <= '2026-06-07'
group by 1,2