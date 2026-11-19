-- 王者荣耀陪玩主播月内跳动
-- 引擎：Spark SQL
-- 样本：2026-07-01 至 2026-11-18，game_id=2336，端类型不限。
-- 主播日粒度：dt + luid。主播当日任意一场直播标题命中陪玩关键词，即该日为陪玩日；否则为非陪玩日。
-- 主播月粒度：mth + luid。月内同时存在陪玩日和非陪玩日，即定义为发生跳动。
-- 方向：按主播当月首次开播日与最后一次开播日的状态判断；首末状态相同但月内曾跳动的，计入“往返后回到原状态”。
with anchor_day as (
    -- 粒度：dt + luid；每个主播每天只保留一条日级状态。
    select
        dt,
        substr(dt, 1, 7) as mth,
        cast(luid as string) as luid,
        max(
            case
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
                    then 1
                else 0
            end
        ) as is_peiwan_day
    from gamelive.dwt_huya_ayyuid_session_from_server_no_user
    where dt between '2026-07-01' and '2026-11-18'
      and length(dt) = 10
      and tag = 'gameid'
      and htime = 'session'
      and cast(igameid as string) = '2336'
      and luid is not null
      and trim(cast(luid as string)) not in ('', '0', '-1')
    group by
        dt,
        substr(dt, 1, 7),
        cast(luid as string)
),
anchor_day_window as (
    -- 为基础日记录标记首次开播日和最后开播日，用于判断月初至月末的净方向。
    select
        dt,
        mth,
        luid,
        is_peiwan_day,
        row_number() over (
            partition by mth, luid
            order by dt asc
        ) as first_day_rn,
        row_number() over (
            partition by mth, luid
            order by dt desc
        ) as last_day_rn
    from anchor_day
),
anchor_month_state as (
    -- 粒度：mth + luid；汇总当月两种日级状态及首末状态。
    select
        mth,
        luid,
        count(*) as active_day_cnt,
        max(is_peiwan_day) as has_peiwan_day,
        max(case when is_peiwan_day = 0 then 1 else 0 end) as has_non_peiwan_day,
        max(case when first_day_rn = 1 then is_peiwan_day else 0 end) as first_day_status,
        max(case when last_day_rn = 1 then is_peiwan_day else 0 end) as last_day_status
    from anchor_day_window
    group by
        mth,
        luid
),
anchor_month_jump as (
    -- 粒度仍为 mth + luid；is_jump=1 表示月内同时出现陪玩日和非陪玩日。
    select
        mth,
        luid,
        active_day_cnt,
        has_peiwan_day,
        has_non_peiwan_day,
        first_day_status,
        last_day_status,
        case
            when has_peiwan_day = 1 and has_non_peiwan_day = 1 then 1
            else 0
        end as is_jump
    from anchor_month_state
)
select
    mth as month,
    count(*) as active_anchor_cnt,
    sum(is_jump) as jump_anchor_cnt,
    sum(is_jump) * 1.0 / nullif(count(*), 0) as jump_anchor_ratio,
    sum(
        case
            when is_jump = 1 and first_day_status = 1 and last_day_status = 0 then 1
            else 0
        end
    ) as peiwan_to_non_anchor_cnt,
    sum(
        case
            when is_jump = 1 and first_day_status = 0 and last_day_status = 1 then 1
            else 0
        end
    ) as non_to_peiwan_anchor_cnt,
    sum(
        case
            when is_jump = 1 and first_day_status = last_day_status then 1
            else 0
        end
    ) as round_trip_same_anchor_cnt
from anchor_month_jump
group by
    mth
order by
    mth
