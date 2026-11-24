-- 主播专项日级追踪：W42-W47，健康日表主播日粒度补公会、roomid和互动指标。
with game_dim as (
    select cast(game_id as varchar) as gameid, max(game_label) as game_label
    from gamelive.dim_huya_game_d_a
    where dt='2026-11-23'
    group by cast(game_id as varchar)
),
anchor_day_info as (
    select dt,
           cast(gameid as varchar) as gameid,
           cast(ayyuid as varchar) as luid,
           max(nullif(trim(cast(nickname as varchar)),'')) as nickname,
           max(nullif(trim(cast(cname as varchar)),'')) as cname,
           max(nullif(trim(cast(roomid as varchar)),'')) as roomid,
           max(coalesce(com_cnt,0)) as interaction_cnt,
           max(coalesce(com_ucnt,0)) as interaction_user_cnt
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2026-10-12' and '2026-11-22'
      and ayyuid is not null
      and trim(cast(ayyuid as varchar)) not in ('','0','-1')
    group by dt,cast(gameid as varchar),cast(ayyuid as varchar)
)
select h.dt,
       h.gameid,
       case
           when g.game_label='游戏' then '游戏'
           when g.game_label='娱乐' and h.gameid in ('1663','2165','4079') then '娱乐（秀场）'
           when g.game_label='娱乐' then '娱乐（非秀场）'
           else '未匹配'
       end as content_group,
       coalesce(nullif(a.cname,''),'无公会') as guild_name,
       h.luid,
       coalesce(nullif(a.nickname,''),nullif(trim(h.snick),''),'未知主播') as snick,
       coalesce(nullif(a.roomid,''),'') as roomid,
       h.dau,
       h.daily_revenue,
       h.daily_pay_user_cnt,
       h.is_live,
       h.live_mins,
       h.avg_acu,
       h.avg_view_mins,
       h.attribution_user_cnt,
       coalesce(a.interaction_cnt,0) as interaction_cnt,
       coalesce(a.interaction_user_cnt,0) as interaction_user_cnt
from zhgametemp.zty_category_ecology_health_daily_d_i_0827_v1 h
left join game_dim g on h.gameid=g.gameid
left join anchor_day_info a
  on h.dt=a.dt and h.gameid=a.gameid and h.luid=a.luid
where h.dt between '2026-10-12' and '2026-11-22'
  and h.category='主播明细'
  and h.luid is not null
  and trim(h.luid) not in ('','0','-1')
  and coalesce(trim(h.snick),'') not like '#%'
  and coalesce(trim(h.snick),'') <> '未归属主播'
order by h.dt,h.gameid,h.luid;
