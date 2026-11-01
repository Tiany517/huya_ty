  select distinct
    from_unixtime(unix_timestamp(a.dt,'yyyyMMdd'),'yyyy-MM-dd') as dt,
    a.pid as ayyuid,
    a.uid as fan_uid,
    case
        when a.score >= 24000000 then 40
        when a.score >= 17000000 then 39
        when a.score >= 12000000 then 38
        when a.score >= 8000000 then 37
        when a.score >= 5000000 then 36
        when a.score >= 3900000 then 35
        when a.score >= 3000000 then 34
        when a.score >= 2250000 then 33
        when a.score >= 1700000 then 32
        when a.score >= 1300000 then 31
        when a.score >= 1000000 then 30
        when a.score >= 760000 then 29
        when a.score >= 588000 then 28
        when a.score >= 454000 then 27
        when a.score >= 345000 then 26
        when a.score >= 268000 then 25
        when a.score >= 215000 then 24
        when a.score >= 175000 then 23
        when a.score >= 140000 then 22
        when a.score >= 110000 then 21
        when a.score >= 83400 then 20
        when a.score >= 65400 then 19
        when a.score >= 52580 then 18
        when a.score >= 42700 then 17
        when a.score >= 34500 then 16
        when a.score >= 27340 then 15
        when a.score >= 20840 then 14
        when a.score >= 14840 then 13
        when a.score >= 9840 then 12
        when a.score >= 6690 then 11
        when a.score >= 4290 then 10
        when a.score >= 2715 then 9
        when a.score >= 1665 then 8
        when a.score >= 1040 then 7
        when a.score >= 640 then 6
        when a.score >= 385 then 5
        when a.score >= 190 then 4
        when a.score >= 70 then 3
        when a.score >= 30 then 2
        when a.score >= 10 then 1
        else null
    end as level
from gamelive.gamelive_reducedbadgeinfo a
inner join zhubo_info b
    on a.pid = b.ayyuid
   and from_unixtime(unix_timestamp(a.dt,'yyyyMMdd'),'yyyy-MM-dd') = b.dt
    where a.dt >= '20260101' and a.dt <= '20260531'