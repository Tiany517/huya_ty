-- 目的：计算 2026-01-01 至 2026-10-20 标题包含“反炸鱼”的直播间分钟acu和主播日acu，并剔除大比赛窗口。
-- sql 关键词统一使用小写。
-- 数据粒度：dt + luid + live_id。
-- 当前三张主数据表最新可用分区均为 2026-10-20。

with t1 as (
    select
        dt,
        sgamename as game_name,
        luid,
        lliveid as live_id,
        min(start_time) as start_time,
        max(end_time) as end_time,
        max(snick) as snick,
        max(slivedesc) as live_title
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where dt between '2026-01-01' and '2026-10-20'
      and tag = 'gameid'
      and htime = 'session'
      and igameid = 5937
      and slivedesc like '%反炸鱼%'
    group by
        dt,
        sgamename,
        luid,
        lliveid
),

-- 主播分钟级 acu，粒度：dt + 主播 + 直播间 + 分钟。
minute_acu as (
    select
        dt,
        ayyuid as luid,
        tkey1 as live_id,
        time_value as acu_minute,
        max(all_users) as minute_acu
    from gamelive.dw_huya_online_users
    where dt between '2026-01-01' and '2026-10-20'
      and tag = 'server_ayyuid_gameid_session'
      and gameid = '5937'
      and time_type = 'minute'
    group by
        dt,
        ayyuid,
        tkey1,
        time_value
),

-- 先将分钟 acu 聚合到直播间，避免与主播日数据形成一对多关联。
session_minute_acu as (
    select
        s.dt,
        s.luid,
        s.live_id,
        avg(m.minute_acu) as minute_acu
    from t1 s
    left join minute_acu m
      on s.dt = m.dt
     and s.luid = m.luid
     and s.live_id = m.live_id
     and cast(m.acu_minute as timestamp)
         between cast(s.start_time as timestamp)
             and cast(s.end_time as timestamp)
    group by
        s.dt,
        s.luid,
        s.live_id
),

-- 主播日表粒度：dt + ayyuid + gameid。
anchor_day_acu as (
    select
        dt,
        ayyuid as luid,
        max(acu) as day_acu
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2026-01-01' and '2026-10-20'
      and gameid = '5937'
    group by
        dt,
        ayyuid
),

match_anchor_info as (
    select distinct
        substr(date, 1, 10) as dt,
        match_name,
        uid as luid
    from gamelive.dwd_huya_dim_game_copyright_info_d_a
    where dt = '2026-10-20'
      and substr(date, 1, 10) between '2026-01-01' and '2026-12-31'
      and live_type like '%直播%'
      and game_id = 5937
),

match_info as (
    select
        match_name,
        min(dt) as min_dt,
        max(dt) as max_dt
    from match_anchor_info
    group by match_name
),

-- 大比赛日 dau，沿用原口径：比赛主播当天全内容 app 去重观看用户。
big_match_daily as (
    select
        a.dt,
        m.match_name,
        count(distinct a.user_ukey) as user_cnt
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
    inner join match_anchor_info m
      on a.dt = m.dt
     and a.luid = m.luid
    where a.dt between '2026-01-01' and '2026-10-20'
      and a.tag = 'gameid'
      and a.htime = 'session'
      and a.user_product in (
          'huya_andriod',
          'huya_ipad',
          'huya_pad',
          'huya_ios'
      )
      -- 若只统计无畏契约观看 dau，取消下一行注释。
      -- and a.igameid = 5937
    group by
        a.dt,
        m.match_name
),

big_match as (
    select
        d.match_name,
        i.min_dt,
        i.max_dt,
        date_diff(
            'day',
            cast(i.min_dt as date),
            cast(i.max_dt as date)
        ) + 1 as match_day_cnt,
        avg(d.user_cnt) as dau
    from big_match_daily d
    inner join match_info i
      on d.match_name = i.match_name
    group by
        d.match_name,
        i.min_dt,
        i.max_dt
    having avg(d.user_cnt) >= 50000
),

big_match_window as (
    select distinct
        min_dt,
        max_dt
    from big_match
)

select
    t1.dt,
    t1.game_name,
    t1.luid,
    t1.snick,
    t1.live_id,
    t1.live_title,
    t1.start_time,
    t1.end_time,
    sma.minute_acu,
    ada.day_acu
from t1
left join session_minute_acu sma
  on t1.dt = sma.dt
 and t1.luid = sma.luid
 and t1.live_id = sma.live_id
left join anchor_day_acu ada
  on t1.dt = ada.dt
 and t1.luid = ada.luid
where not exists (
    select 1
    from big_match_window b
    where t1.dt between b.min_dt and b.max_dt
)
order by
    t1.dt,
    t1.luid,
    t1.live_id;
