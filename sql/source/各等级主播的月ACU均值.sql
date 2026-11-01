with zhubo_info as (
    select distinct 
        a.dt,
        substr(a.dt, 1, 7) as month,
        a.luid,
        a.nickname,
        case
            when a.acu >= 2000 then '头部主播'
            when a.acu >= 100 and a.acu <= 2000 then '腰部主播'
            when a.acu < 100 then '尾部主播'
            else '未知'
        end as zhubo_level,
        a.acu as acu,
        a.live_mins as live_hours
    from (
        select
            dt,
            ayyuid as luid,
            nickname,
            coalesce(avg(acu), 0) as acu,
            sum(live_mins) as live_mins
        from gamelive.dm_huya_ayyuid_detail_day t1
        where dt between '2026-05-01' and '2026-07-31'
          and gameid = 2336 --王者荣耀
        group by 1, 2, 3
    ) a
)

select
    month,
    zhubo_level,
    avg(acu) as "月日均acu均值",
    avg(live_hours) as "月日均开播时长",
    count(distinct luid) as "主播数"
from zhubo_info
group by month, zhubo_level
order by month,
    case zhubo_level
        when '头部主播' then 1
        when '腰部主播' then 2
        when '尾部主播' then 3
        else 4
    end;