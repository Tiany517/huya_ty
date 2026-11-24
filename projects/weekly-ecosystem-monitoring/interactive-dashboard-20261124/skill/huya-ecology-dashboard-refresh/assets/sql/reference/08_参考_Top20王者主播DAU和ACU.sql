with t1 as (
    select
        a.dt,
        case
            when a.dt between '2026-08-31' and '2026-09-06'
                then 'W36'
            when a.dt between '2026-09-07' and '2026-09-13'
                then 'W37'
        end as week_period,
        a.luid,
        a.snick,
        a.avg_acu,
        a.dau,
        a.attribution_user_cnt,
        a.interest_user_cnt
    from zhgametemp.zty_category_ecology_health_daily_d_i_0827_v1 a
    where a.dt between '2026-08-31' and '2026-09-13'
      and a.gameid = 2336
)


select
    week_period,
    luid,
    snick,
    count(distinct dt) as observed_days,
    avg(avg_acu) as avg_acu,
    avg(dau) as dau,
    avg(attribution_user_cnt) as attribution_user_cnt,
    avg(interest_user_cnt) as interest_user_cnt
from t1
group by
    week_period,
    luid,
    snick
having avg(avg_acu) >= 50