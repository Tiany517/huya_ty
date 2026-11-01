-- 目的：识别2026年内首次跨播到无畏契约、且此前主品类不是无畏契约的主播
-- 时间范围：2026-01-01 至 2026-10-20
-- 端范围：虎牙移动端（Android/iPad/Pad/iOS）
-- 主品类：统计期全量观看时长，按 game_id 汇总后取最大；
--         并列时取 game_id 较小者
-- 跨播日：2026年内首次出现无畏契约观看记录的自然日
-- DAU：主播×日，按全品类去重 user_ukey；同时输出当天无畏契约单独 DAU
-- 涨幅：跨播日全品类 DAU 相对该主播上一个实际开播日的全品类 DAU

with session_game_day as (
    select
        cast(dt as varchar) as dt,
        cast(luid as varchar) as luid,
        cast(igameid as bigint) as game_id,
        max(cast(sgamename as varchar)) as game_name,
        max(cast(snick as varchar)) as snick,
        sum(cast(user_duration as double)) as watch_duration_ms,
        count(distinct user_ukey) as game_dau
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where dt between '2026-01-01' and '2026-10-20'
      and tag = 'gameid'
      and htime = 'session'
      and user_product in (
          'huya_andriod',
          'huya_ipad',
          'huya_pad',
          'huya_ios'
      )
      and luid is not null
      and igameid is not null
      and user_ukey is not null
      and cast(user_duration as double) > 0
    group by
        cast(dt as varchar),
        cast(luid as varchar),
        cast(igameid as bigint)
),

first_valorant as (
    -- 2026年内该主播首次出现无畏契约观看记录的日期
    select
        luid,
        min(dt) as cross_dt
    from session_game_day
    where game_id = 5937
    group by luid
),

main_game_score as (
    -- 使用统计期全量观看时长判断主播主品类
    select
        s.luid,
        s.game_id,
        max(s.game_name) as game_name,
        sum(s.watch_duration_ms) as total_watch_duration_ms
    from session_game_day s
    group by
        s.luid,
        s.game_id
),

main_game as (
    select
        luid,
        game_id,
        game_name,
        total_watch_duration_ms
    from (
        select
            luid,
            game_id,
            game_name,
            total_watch_duration_ms,
            row_number() over (
                partition by luid
                order by total_watch_duration_ms desc, game_id
            ) as rnk
        from main_game_score
    ) t
    where rnk = 1
      and game_id <> 5937
),

candidate as (
    select
        f.luid,
        f.cross_dt
    from first_valorant f
    inner join main_game p
        on f.luid = p.luid
),

cross_day_valorant as (
    select
        s.luid,
        s.dt,
        s.snick,
        s.game_dau as cross_day_valorant_dau
    from session_game_day s
    inner join candidate c
        on s.luid = c.luid
       and s.dt = c.cross_dt
    where s.game_id = 5937
),

anchor_day as (
    -- 候选主播的全品类主播×日 DAU；用于计算跨播日总 DAU 和上一开播日
    select
        cast(a.dt as varchar) as dt,
        cast(a.luid as varchar) as luid,
        max(cast(a.snick as varchar)) as snick,
        count(distinct a.user_ukey) as total_dau
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
    inner join candidate c
        on cast(a.luid as varchar) = c.luid
    where a.dt between '2026-01-01' and '2026-10-20'
      and a.tag = 'gameid'
      and a.htime = 'session'
      and a.user_product in (
          'huya_andriod',
          'huya_ipad',
          'huya_pad',
          'huya_ios'
      )
      and a.user_ukey is not null
      and cast(a.user_duration as double) > 0
    group by
        cast(a.dt as varchar),
        cast(a.luid as varchar)
),

anchor_day_with_prev as (
    select
        luid,
        dt,
        snick,
        total_dau,
        lag(dt) over (
            partition by luid
            order by dt
        ) as prev_live_dt,
        lag(total_dau) over (
            partition by luid
            order by dt
        ) as prev_live_dau
    from anchor_day
)

select
    d.dt as cross_dt,
    d.luid,
    d.snick,
    p.game_id as belong_game_id,
    p.game_name as belong_game_name,
    v.cross_day_valorant_dau,
    d.total_dau as cross_day_total_dau,
    d.prev_live_dt,
    d.prev_live_dau,
    d.total_dau - d.prev_live_dau as dau_change,
    round(
        100.0 * (d.total_dau - d.prev_live_dau)
        / nullif(d.prev_live_dau, 0),
        2
    ) as dau_growth_pct
from anchor_day_with_prev d
inner join candidate c
    on d.luid = c.luid
   and d.dt = c.cross_dt
inner join main_game p
    on d.luid = p.luid
inner join cross_day_valorant v
    on d.luid = v.luid
   and d.dt = v.dt
order by
    d.total_dau desc,
    d.dt,
    d.luid;
