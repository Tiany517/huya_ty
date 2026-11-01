with minute_online as (
    select
        dt,
        time_value,
        sum(all_users) as online_users
    from gamelive.dw_huya_online_users -- 主播每分钟的观看人数
    where dt between '2026-09-02' and '2026-09-09'
      and tag = 'server_ayyuid_gameid_session'
      and ayyuid = '1509413742'
    group by
        dt,
        time_value
),

daily_acu as (
    -- 当日分钟级在线人数均值，与日表 acu 口径一致
    select
        dt,
        avg(online_users) as daily_acu
    from minute_online
    group by
        dt
),

hourly_online as (
    select
        dt,
        concat(
            substr(time_value, 12, 2),
            ':00-',
            substr(time_value, 12, 2),
            ':59'
        ) as hour_period,
        count(*) as online_minute_cnt,
        avg(online_users) as acu,
        max(online_users) as pcu
    from minute_online
    group by
        dt,
        concat(
            substr(time_value, 12, 2),
            ':00-',
            substr(time_value, 12, 2),
            ':59'
        )
)

select
    h.dt as "日期",
    h.hour_period as "小时段",
    h.online_minute_cnt as "有在线记录分钟数",
    round(h.acu, 2) as "acu",
    h.pcu as "pcu",
    round(d.daily_acu, 2) as "当日acu"
from hourly_online h
left join daily_acu d
    on h.dt = d.dt
order by
    h.dt,
    h.hour_period;
