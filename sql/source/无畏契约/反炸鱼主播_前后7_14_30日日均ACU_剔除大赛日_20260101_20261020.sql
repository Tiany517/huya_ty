-- 目的：计算直播过反炸鱼内容的主播，在前 7/14/30 日、反炸鱼直播期间、后 7/14/30 日的日均 acu。
-- 事件日：每个主播 2026-01-01 至 2026-10-20 首次直播反炸鱼的日期。
-- 日均口径：主播有效开播日的 acu 平均值；分母为剔除大比赛日后实际有 acu 记录的开播天数。
-- 大比赛日：比赛主播 app 端日均 dau 大于等于 5 万的赛事窗口，窗口内全部日期剔除。
-- 当前相关数据表最新可用分区均为 2026-10-20。
-- sql 关键词统一使用小写。

with anti_fraud_session as (
    select
        dt,
        cast(luid as varchar) as luid,
        cast(lliveid as varchar) as live_id,
        max(snick) as snick
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where dt between '2026-01-01' and '2026-10-20'
      and tag = 'gameid'
      and htime = 'session'
      and igameid = 5937
      and slivedesc like '%反炸鱼%'
    group by
        dt,
        cast(luid as varchar),
        cast(lliveid as varchar)
),

-- 主播反炸鱼直播日，粒度为 dt + luid。
anti_fraud_day as (
    select
        dt,
        luid,
        max(snick) as snick
    from anti_fraud_session
    group by
        dt,
        luid
),

-- 每个主播取首次反炸鱼直播日作为前、后窗口的事件日。
anchor_event as (
    select
        luid,
        min(dt) as event_dt,
        max_by(snick, dt) as snick
    from anti_fraud_day
    group by luid
),

match_anchor_info as (
    select distinct
        substr(date, 1, 10) as dt,
        match_name,
        cast(uid as varchar) as luid
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
),

-- 主播日 acu，仅保留当天真实开播的有效 acu 记录。
anchor_day_base as (
    select
        cast(dt as varchar) as dt,
        cast(ayyuid as varchar) as luid,
        max(acu) as day_acu
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2026-01-01' and '2026-10-20'
      and gameid = '5937'
      and live_hours_only_live > 0
    group by
        cast(dt as varchar),
        cast(ayyuid as varchar)
),

-- 剔除大比赛日后的主播日 acu。
anchor_day_valid as (
    select
        d.dt,
        d.luid,
        d.day_acu
    from anchor_day_base d
    where not exists (
        select 1
        from big_match_window b
        where d.dt between b.min_dt and b.max_dt
    )
),

-- 反炸鱼直播日 acu，同时剔除落在大比赛窗口内的反炸鱼日期。
anti_fraud_day_acu as (
    select
        af.luid,
        af.dt,
        d.day_acu
    from anti_fraud_day af
    left join anchor_day_base d
      on af.dt = d.dt
     and af.luid = d.luid
    where not exists (
        select 1
        from big_match_window b
        where af.dt between b.min_dt and b.max_dt
    )
),

-- 将前、后和反炸鱼期间三个口径分别展开到统一窗口表。
window_day as (
    select
        e.luid,
        'pre7' as window_name,
        d.dt,
        d.day_acu
    from anchor_event e
    inner join anchor_day_valid d
      on e.luid = d.luid
     and cast(d.dt as date)
         between date_add('day', -7, cast(e.event_dt as date))
             and date_add('day', -1, cast(e.event_dt as date))

    union all

    select
        e.luid,
        'pre14' as window_name,
        d.dt,
        d.day_acu
    from anchor_event e
    inner join anchor_day_valid d
      on e.luid = d.luid
     and cast(d.dt as date)
         between date_add('day', -14, cast(e.event_dt as date))
             and date_add('day', -1, cast(e.event_dt as date))

    union all

    select
        e.luid,
        'pre30' as window_name,
        d.dt,
        d.day_acu
    from anchor_event e
    inner join anchor_day_valid d
      on e.luid = d.luid
     and cast(d.dt as date)
         between date_add('day', -30, cast(e.event_dt as date))
             and date_add('day', -1, cast(e.event_dt as date))

    union all

    select
        af.luid,
        'anti_fraud' as window_name,
        af.dt,
        af.day_acu
    from anti_fraud_day_acu af

    union all

    select
        e.luid,
        'post7' as window_name,
        d.dt,
        d.day_acu
    from anchor_event e
    inner join anchor_day_valid d
      on e.luid = d.luid
     and cast(d.dt as date)
         between date_add('day', 1, cast(e.event_dt as date))
             and date_add('day', 7, cast(e.event_dt as date))

    union all

    select
        e.luid,
        'post14' as window_name,
        d.dt,
        d.day_acu
    from anchor_event e
    inner join anchor_day_valid d
      on e.luid = d.luid
     and cast(d.dt as date)
         between date_add('day', 1, cast(e.event_dt as date))
             and date_add('day', 14, cast(e.event_dt as date))

    union all

    select
        e.luid,
        'post30' as window_name,
        d.dt,
        d.day_acu
    from anchor_event e
    inner join anchor_day_valid d
      on e.luid = d.luid
     and cast(d.dt as date)
         between date_add('day', 1, cast(e.event_dt as date))
             and date_add('day', 30, cast(e.event_dt as date))
),

window_metric as (
    select
        luid,
        count_if(window_name = 'anti_fraud' and day_acu is not null) as anti_fraud_valid_days,
        avg(case when window_name = 'anti_fraud' then day_acu end) as anti_fraud_avg_acu,

        count_if(window_name = 'pre7' and day_acu is not null) as pre7_valid_days,
        avg(case when window_name = 'pre7' then day_acu end) as pre7_avg_acu_raw,

        count_if(window_name = 'pre14' and day_acu is not null) as pre14_valid_days,
        avg(case when window_name = 'pre14' then day_acu end) as pre14_avg_acu_raw,

        count_if(window_name = 'pre30' and day_acu is not null) as pre30_valid_days,
        avg(case when window_name = 'pre30' then day_acu end) as pre30_avg_acu_raw,

        count_if(window_name = 'post7' and day_acu is not null) as post7_valid_days,
        avg(case when window_name = 'post7' then day_acu end) as post7_avg_acu_raw,

        count_if(window_name = 'post14' and day_acu is not null) as post14_valid_days,
        avg(case when window_name = 'post14' then day_acu end) as post14_avg_acu_raw,

        count_if(window_name = 'post30' and day_acu is not null) as post30_valid_days,
        avg(case when window_name = 'post30' then day_acu end) as post30_avg_acu_raw
    from window_day
    group by luid
)

select
    e.luid,
    e.snick,
    e.event_dt as first_anti_fraud_dt,
    wm.anti_fraud_valid_days,
    wm.anti_fraud_avg_acu,

    wm.pre7_valid_days,
    case
        when date_diff('day', cast('2026-01-01' as date), cast(e.event_dt as date)) >= 7
        then wm.pre7_avg_acu_raw
    end as pre7_avg_acu,

    wm.pre14_valid_days,
    case
        when date_diff('day', cast('2026-01-01' as date), cast(e.event_dt as date)) >= 14
        then wm.pre14_avg_acu_raw
    end as pre14_avg_acu,

    wm.pre30_valid_days,
    case
        when date_diff('day', cast('2026-01-01' as date), cast(e.event_dt as date)) >= 30
        then wm.pre30_avg_acu_raw
    end as pre30_avg_acu,

    wm.post7_valid_days,
    case
        when date_diff('day', cast(e.event_dt as date), cast('2026-10-20' as date)) >= 7
        then wm.post7_avg_acu_raw
    end as post7_avg_acu,

    wm.post14_valid_days,
    case
        when date_diff('day', cast(e.event_dt as date), cast('2026-10-20' as date)) >= 14
        then wm.post14_avg_acu_raw
    end as post14_avg_acu,

    wm.post30_valid_days,
    case
        when date_diff('day', cast(e.event_dt as date), cast('2026-10-20' as date)) >= 30
        then wm.post30_avg_acu_raw
    end as post30_avg_acu
from anchor_event e
left join window_metric wm
  on e.luid = wm.luid
order by
    e.event_dt,
    e.luid;
