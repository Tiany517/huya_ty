-- 独立复算：不使用正式 SQL 的首次/末次窗口，直接统计每个主播当月有直播的自然日数及其中陪玩日数。
with anchor_month_day_cnt as (
    select
        substr(dt, 1, 7) as mth,
        cast(luid as string) as luid,
        count(distinct dt) as active_day_cnt,
        count(
            distinct case
                when slivedesc like '%车位%'
                  or slivedesc like '%带粉%'
                  or slivedesc like '%车%'
                  or slivedesc like '%位置%'
                  or slivedesc like '%等单%'
                  or slivedesc like '%发车%'
                  or slivedesc like '%有位%'
                  or slivedesc like '%甜妹%'
                  or slivedesc like '%接号%'
                  or slivedesc like '%秒上%'
                  or slivedesc like '%有缘人%'
                  or slivedesc like '%包天%'
                  or slivedesc like '%打号%'
                  or slivedesc like '%黑色%'
                  or slivedesc like '%带飞%'
                  or slivedesc like '%电一%'
                  or slivedesc like '%网一%'
                  or slivedesc like '%黑玫%'
                  or slivedesc like '%老板%'
                  or slivedesc like '%上分%'
                  or slivedesc like '%无单%'
                  or slivedesc like '%滴滴%'
                  or slivedesc like '%软萌%'
                  or slivedesc like '%甜御%'
                  or slivedesc like '%下三%'
                  or slivedesc like '%养号%'
                  or slivedesc like '%全包%'
                  or slivedesc like '%接所有%'
                    then dt
            end
        ) as peiwan_day_cnt
    from gamelive.dwt_huya_ayyuid_session_from_server_no_user
    where dt between '2026-07-01' and '2026-11-18'
      and length(dt) = 10
      and tag = 'gameid'
      and htime = 'session'
      and cast(igameid as string) = '2336'
      and luid is not null
      and trim(cast(luid as string)) not in ('', '0', '-1')
    group by
        substr(dt, 1, 7),
        cast(luid as string)
)
select
    mth as month,
    count(*) as active_anchor_cnt,
    sum(
        case
            when peiwan_day_cnt > 0 and peiwan_day_cnt < active_day_cnt then 1
            else 0
        end
    ) as jump_anchor_cnt,
    sum(
        case
            when peiwan_day_cnt > 0 and peiwan_day_cnt < active_day_cnt then 1
            else 0
        end
    ) * 1.0 / nullif(count(*), 0) as jump_anchor_ratio
from anchor_month_day_cnt
group by
    mth
order by
    mth
