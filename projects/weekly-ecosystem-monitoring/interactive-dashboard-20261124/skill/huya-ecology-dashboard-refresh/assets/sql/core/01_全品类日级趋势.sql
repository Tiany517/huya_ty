-- 全品类日级趋势：健康日表“品类整体”粒度，按最新品类维表标记内容大类。
-- 同时补充：当天品类、内容大类和全平台有开播的主播数（按 luid 去重）。
with game_dim as (
    select
        cast(game_id as varchar) as gameid,
        max(game_label) as game_label,
        max(game_name) as dim_game_name
    from gamelive.dim_huya_game_d_a
    where dt = '2026-11-23'
    group by cast(game_id as varchar)
),
category_daily as (
    select
        h.dt,
        cast(h.gameid as varchar) as gameid,
        h.game_name,
        case
            when g.game_label = '游戏' then '游戏'
            when g.game_label = '娱乐' and cast(h.gameid as varchar) in ('1663', '2165', '4079') then '娱乐（秀场）'
            when g.game_label = '娱乐' then '娱乐（非秀场）'
            else '未匹配'
        end as content_group,
        h.dau,
        h.daily_revenue,
        h.daily_pay_user_cnt,
        h.arppu,
        h.avg_view_mins,
        h.attribution_user_cnt
    from zhgametemp.zty_category_ecology_health_daily_d_i_0827_v1 h
    left join game_dim g on cast(h.gameid as varchar) = g.gameid
    where h.dt between '2026-01-01' and '2026-11-23'
      and h.category = '品类整体'
),
active_anchor as (
    -- 粒度：dt x 品类 x 主播；先去重，再分别按品类、内容大类和平台汇总。
    select
        h.dt,
        cast(h.gameid as varchar) as gameid,
        cast(h.luid as varchar) as luid,
        case
            when g.game_label = '游戏' then '游戏'
            when g.game_label = '娱乐' and cast(h.gameid as varchar) in ('1663', '2165', '4079') then '娱乐（秀场）'
            when g.game_label = '娱乐' then '娱乐（非秀场）'
            else '未匹配'
        end as content_group
    from zhgametemp.zty_category_ecology_health_daily_d_i_0827_v1 h
    left join game_dim g on cast(h.gameid as varchar) = g.gameid
    where h.dt between '2026-01-01' and '2026-11-23'
      and h.category = '主播明细'
      and h.is_live = 1
      and h.luid is not null
      and trim(cast(h.luid as varchar)) not in ('', '0', '-1')
      and coalesce(trim(cast(h.snick as varchar)), '') not like '#%'
      and coalesce(trim(cast(h.snick as varchar)), '') <> '未归属主播'
    group by h.dt, cast(h.gameid as varchar), cast(h.luid as varchar), case
        when g.game_label = '游戏' then '游戏'
        when g.game_label = '娱乐' and cast(h.gameid as varchar) in ('1663', '2165', '4079') then '娱乐（秀场）'
        when g.game_label = '娱乐' then '娱乐（非秀场）'
        else '未匹配'
    end
),
category_live_counts as (
    select dt, gameid, count(distinct luid) as live_anchor_cnt
    from active_anchor
    group by dt, gameid
),
group_live_counts as (
    select dt, content_group, count(distinct luid) as group_live_anchor_cnt
    from active_anchor
    group by dt, content_group
),
total_live_counts as (
    select dt, count(distinct luid) as total_live_anchor_cnt
    from active_anchor
    group by dt
)
select
    c.dt,
    c.gameid,
    c.game_name,
    c.content_group,
    c.dau,
    c.daily_revenue,
    c.daily_pay_user_cnt,
    c.arppu,
    c.avg_view_mins,
    c.attribution_user_cnt,
    coalesce(cl.live_anchor_cnt, 0) as live_anchor_cnt,
    coalesce(gl.group_live_anchor_cnt, 0) as group_live_anchor_cnt,
    coalesce(tl.total_live_anchor_cnt, 0) as total_live_anchor_cnt
from category_daily c
left join category_live_counts cl on c.dt = cl.dt and c.gameid = cl.gameid
left join group_live_counts gl on c.dt = gl.dt and c.content_group = gl.content_group
left join total_live_counts tl on c.dt = tl.dt
order by c.dt, c.content_group, c.game_name;
