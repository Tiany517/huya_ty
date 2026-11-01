-- 目的：计算站外四平台中直播过反炸鱼内容的主播，前 7/14/30 日、反炸鱼直播期间、后 7/14/30 日的日均 acu、弹幕数和互动人数。
-- 数据源：gamelive.dm_mkt_rowner_day。
-- 平台：douyin_web、douyu、bilibili、kuaishou。
-- 品类：r_category = '无畏契约'。
-- 反炸鱼识别：online_max_r_name like '%反炸鱼%'。
-- 事件日：每个 pcode + r_lid 在 2026-01-01 至 2026-10-20 首次出现反炸鱼内容直播间名称的日期。
-- acu：max(coalesce(try_cast(ext['vaild_acu'] as double), 0))；按有效记录日计算平均值。
-- 弹幕数：danmu_cnt；互动人数：com_ucnt。
-- 弹幕数和互动人数按窗口内主播日求和；互动人数是各日互动人数之和，不是跨日去重人数。
-- 大比赛日：沿用原口径，使用赛事版权表和站内 app 端 dau 阈值为 5 万的赛事窗口，窗口内全部日期剔除。
-- 当前数据最新可用分区为 2026-10-20。
-- sql 关键词统一使用小写。

with anchor_day as (
    select
        cast(dt as varchar) as dt,
        cast(pcode as varchar) as pcode,
        cast(r_lid as varchar) as r_lid,
        max(r_owner) as r_owner,
        max(
            coalesce(
                try_cast(ext['vaild_acu'] as double),
                0
            )
        ) as valid_acu,
        max(danmu_cnt) as danmu_cnt,
        max(com_ucnt) as com_ucnt,
        max(
            case
                when online_max_r_name like '%反炸鱼%' then 1
                else 0
            end
        ) as is_anti_fraud
    from gamelive.dm_mkt_rowner_day
    where dt between '2026-01-01' and '2026-10-20'
      and pcode in ('douyin_web', 'douyu', 'bilibili', 'kuaishou')
      and r_category = '无畏契约'
    group by
        cast(dt as varchar),
        cast(pcode as varchar),
        cast(r_lid as varchar)
),

anti_fraud_day as (
    select
        dt,
        pcode,
        r_lid,
        r_owner,
        valid_acu,
        danmu_cnt,
        com_ucnt
    from anchor_day
    where is_anti_fraud = 1
),

-- 每个主播取首次反炸鱼直播日作为前、后窗口的事件日。
anchor_event as (
    select
        pcode,
        r_lid,
        event_dt,
        r_owner
    from (
        select
            pcode,
            r_lid,
            dt as event_dt,
            r_owner,
            row_number() over (
                partition by pcode, r_lid
                order by dt, r_owner
            ) as rn
        from anti_fraud_day
    ) a
    where rn = 1
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

-- 大比赛日 dau，沿用原口径：站内比赛主播当天 app 端全内容去重观看用户。
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

anchor_day_valid as (
    select
        d.*
    from anchor_day d
    where not exists (
        select 1
        from big_match_window b
        where d.dt between b.min_dt and b.max_dt
    )
),

anti_fraud_day_valid as (
    select
        d.*
    from anti_fraud_day d
    where not exists (
        select 1
        from big_match_window b
        where d.dt between b.min_dt and b.max_dt
    )
),

-- 将前、后和反炸鱼期间分别展开到统一窗口表；只输出窗口内实际有记录的日期。
window_day as (
    select
        e.pcode,
        e.r_lid,
        e.r_owner,
        e.event_dt,
        'pre7' as window_name,
        d.dt,
        d.valid_acu,
        d.danmu_cnt,
        d.com_ucnt
    from anchor_event e
    inner join anchor_day_valid d
      on e.pcode = d.pcode
     and e.r_lid = d.r_lid
     and cast(d.dt as date)
         between date_add('day', -7, cast(e.event_dt as date))
             and date_add('day', -1, cast(e.event_dt as date))

    union all

    select
        e.pcode,
        e.r_lid,
        e.r_owner,
        e.event_dt,
        'pre14' as window_name,
        d.dt,
        d.valid_acu,
        d.danmu_cnt,
        d.com_ucnt
    from anchor_event e
    inner join anchor_day_valid d
      on e.pcode = d.pcode
     and e.r_lid = d.r_lid
     and cast(d.dt as date)
         between date_add('day', -14, cast(e.event_dt as date))
             and date_add('day', -1, cast(e.event_dt as date))

    union all

    select
        e.pcode,
        e.r_lid,
        e.r_owner,
        e.event_dt,
        'pre30' as window_name,
        d.dt,
        d.valid_acu,
        d.danmu_cnt,
        d.com_ucnt
    from anchor_event e
    inner join anchor_day_valid d
      on e.pcode = d.pcode
     and e.r_lid = d.r_lid
     and cast(d.dt as date)
         between date_add('day', -30, cast(e.event_dt as date))
             and date_add('day', -1, cast(e.event_dt as date))

    union all

    select
        e.pcode,
        e.r_lid,
        e.r_owner,
        e.event_dt,
        'anti_fraud' as window_name,
        d.dt,
        d.valid_acu,
        d.danmu_cnt,
        d.com_ucnt
    from anchor_event e
    inner join anti_fraud_day_valid d
      on e.pcode = d.pcode
     and e.r_lid = d.r_lid

    union all

    select
        e.pcode,
        e.r_lid,
        e.r_owner,
        e.event_dt,
        'post7' as window_name,
        d.dt,
        d.valid_acu,
        d.danmu_cnt,
        d.com_ucnt
    from anchor_event e
    inner join anchor_day_valid d
      on e.pcode = d.pcode
     and e.r_lid = d.r_lid
     and cast(d.dt as date)
         between date_add('day', 1, cast(e.event_dt as date))
             and date_add('day', 7, cast(e.event_dt as date))

    union all

    select
        e.pcode,
        e.r_lid,
        e.r_owner,
        e.event_dt,
        'post14' as window_name,
        d.dt,
        d.valid_acu,
        d.danmu_cnt,
        d.com_ucnt
    from anchor_event e
    inner join anchor_day_valid d
      on e.pcode = d.pcode
     and e.r_lid = d.r_lid
     and cast(d.dt as date)
         between date_add('day', 1, cast(e.event_dt as date))
             and date_add('day', 14, cast(e.event_dt as date))

    union all

    select
        e.pcode,
        e.r_lid,
        e.r_owner,
        e.event_dt,
        'post30' as window_name,
        d.dt,
        d.valid_acu,
        d.danmu_cnt,
        d.com_ucnt
    from anchor_event e
    inner join anchor_day_valid d
      on e.pcode = d.pcode
     and e.r_lid = d.r_lid
     and cast(d.dt as date)
         between date_add('day', 1, cast(e.event_dt as date))
             and date_add('day', 30, cast(e.event_dt as date))
),

window_metric as (
    select
        pcode,
        r_lid,
        r_owner,
        event_dt,
        window_name,
        count(valid_acu) as valid_days,
        avg(valid_acu) as avg_acu,
        sum(danmu_cnt) as danmu_cnt,
        sum(com_ucnt) as com_ucnt
    from window_day
    group by
        pcode,
        r_lid,
        r_owner,
        event_dt,
        window_name
)

select
    pcode,
    r_lid,
    r_owner,
    event_dt as first_anti_fraud_dt,
    window_name,
    valid_days,
    avg_acu,
    danmu_cnt,
    com_ucnt
from window_metric
order by
    pcode,
    r_lid,
    case window_name
        when 'pre7' then 1
        when 'pre14' then 2
        when 'pre30' then 3
        when 'anti_fraud' then 4
        when 'post7' then 5
        when 'post14' then 6
        when 'post30' then 7
    end;
