-- 游戏支付用户赛事属性（优化版）：在 90 天观时聚合前先用支付用户做 semi join，降低 shuffle 数据量。
-- 口径保持不变：支付日前 90 天，赛事主播日期观时 / 同游戏总观时 >= 70% 为赛事用户。
with copyright_match_anchor_day as (
    select distinct
        substr(cast(src.day as string), 1, 10) as dt,
        cast(src.game_id as string) as game_id,
        cast(src.uid as string) as luid
    from zhgametemp.hss_huya_dim_game_copyright_info_d_a src
    where src.dt = '2026-11-23'
      and substr(cast(src.day as string), 1, 10) between '2026-07-14' and '2026-11-21'
      and src.live_type like '%直播%'
      and src.game_id is not null
      and src.uid is not null
      and trim(cast(src.uid as string)) not in ('', '0', '-1')
),
match_anchor_user_day as (
    select dt, game_id, luid
    from copyright_match_anchor_day
    group by dt, game_id, luid
),
revenue_detail as (
    select
        dt,
        cast(ext['ukey'] as string) as user_ukey,
        cast(game_id as string) as game_id,
        case
            when creator_uid is null or trim(cast(creator_uid as string)) in ('', '0', '-1') then '未知主播'
            else cast(creator_uid as string)
        end as anchor_uid,
        sum(cast(user_consume_amount as double)) as consume_amt
    from zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i
    where dt between '2026-10-12' and '2026-11-22'
      and cast(user_consume_amount as double) > 0
      and coalesce(is_free_item, 0) = 0
      and ext['ukey'] is not null
      and trim(cast(ext['ukey'] as string)) not in ('', '0', '-1')
      and cast(game_label as string) = '游戏'
    group by 1, 2, 3, 4
),
revenue_user_game_day as (
    select dt, user_ukey, game_id
    from revenue_detail
    group by dt, user_ukey, game_id
),
user_anchor_game_day_watch as (
    -- 先限定到支付用户，再按日/用户/游戏/主播聚合，避免对全量观看用户做大 shuffle。
    select
        s.dt,
        cast(s.user_ukey as string) as user_ukey,
        cast(s.igameid as string) as game_id,
        cast(s.luid as string) as luid,
        sum(cast(s.user_duration as double)) as watch_ms
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user s
    left semi join revenue_user_game_day p
      on cast(s.user_ukey as string) = p.user_ukey
    where s.dt between '2026-07-14' and '2026-11-21'
      and s.tag = 'gameid'
      and s.htime = 'session'
      and s.user_ukey is not null
      and trim(cast(s.user_ukey as string)) not in ('', '0', '-1')
      and s.igameid is not null
      and s.luid is not null
      and trim(cast(s.luid as string)) not in ('', '0', '-1')
      and cast(s.user_duration as double) > 0
    group by s.dt, cast(s.user_ukey as string), cast(s.igameid as string), cast(s.luid as string)
),
user_game_event_watch as (
    select
        t.dt,
        t.user_ukey,
        t.game_id,
        sum(w.watch_ms) as total_watch_ms,
        sum(case when m.luid is not null then w.watch_ms else 0 end) as event_watch_ms
    from revenue_user_game_day t
    inner join user_anchor_game_day_watch w
      on t.user_ukey = w.user_ukey
     and t.game_id = w.game_id
     and cast(w.dt as date) between date_add(cast(t.dt as date), -90) and date_add(cast(t.dt as date), -1)
    left join match_anchor_user_day m
      on w.dt = m.dt
     and w.game_id = m.game_id
     and w.luid = m.luid
    group by t.dt, t.user_ukey, t.game_id
),
user_game_event_type as (
    select
        dt,
        user_ukey,
        game_id,
        case
            when total_watch_ms > 0 and event_watch_ms * 1.0 / total_watch_ms >= 0.7 then '赛事用户'
            else '非赛事用户'
        end as user_event_type
    from user_game_event_watch
),
anchor_day_info as (
    select
        dt,
        cast(ayyuid as string) as luid,
        max(nullif(trim(cast(nickname as string)), '')) as nickname,
        max(nullif(trim(cast(cname as string)), '')) as cname
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2026-10-12' and '2026-11-22'
      and ayyuid is not null
      and trim(cast(ayyuid as string)) not in ('', '0', '-1')
    group by dt, cast(ayyuid as string)
),
game_dim as (
    select
        cast(game_id as string) as gameid,
        max(game_name) as game_name,
        max(game_label) as game_label
    from gamelive.dim_huya_game_d_a
    where dt = '2026-11-23'
    group by cast(game_id as string)
)
select
    r.dt,
    date_format(date_trunc('week', cast(r.dt as date)), 'yyyy-MM-dd') as week_start,
    r.game_id as gameid,
    coalesce(g.game_name, r.game_id) as game_name,
    '游戏' as content_group,
    coalesce(nullif(a.cname, ''), '无公会') as guild_name,
    r.anchor_uid as luid,
    coalesce(nullif(a.nickname, ''), '未知主播') as snick,
    coalesce(u.user_event_type, '非赛事用户') as user_event_type,
    round(sum(r.consume_amt), 2) as revenue,
    count(distinct r.user_ukey) as pay_user_cnt
from revenue_detail r
left join user_game_event_type u
  on r.dt = u.dt and r.user_ukey = u.user_ukey and r.game_id = u.game_id
left join anchor_day_info a
  on r.dt = a.dt and r.anchor_uid = a.luid
left join game_dim g
  on r.game_id = g.gameid
group by
    r.dt,
    date_format(date_trunc('week', cast(r.dt as date)), 'yyyy-MM-dd'),
    r.game_id,
    coalesce(g.game_name, r.game_id),
    coalesce(nullif(a.cname, ''), '无公会'),
    r.anchor_uid,
    coalesce(nullif(a.nickname, ''), '未知主播'),
    coalesce(u.user_event_type, '非赛事用户')
order by r.dt, r.game_id, guild_name, luid, user_event_type;
