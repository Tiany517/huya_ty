-- 参数化：运行前把 {{TARGET_STREAMER_LUID}} 替换为获准的 BIGINT 主播 ID。
-- 粒度：输入为日×用户归因底表，输出为月；月值为日归因 DAU 的算术平均。
with belongs_user as (
    select
        dt,
        count(distinct ukey) as belongs_user_cnt
    from zhgametemp.cwq_huya_ukey_shichang_luid_gameid_guishu_day_v1
    where dt >= '2025-01-01'
      and dt <= '2026-04-30'
      and luid = cast('{{TARGET_STREAMER_LUID}}' as bigint)
    group by dt
),

mth_avg as (
    select
        date_trunc('month', cast(dt as date)) as mth,
        sum(belongs_user_cnt) * 1.0 / count(distinct dt) as avg_belongs_user_cnt,
        count(distinct dt) as observed_days
    from belongs_user
    group by 1
)

select
    mth,
    avg_belongs_user_cnt,
    observed_days,
    avg(avg_belongs_user_cnt) over (
        order by mth
        rows between 5 preceding and current row
    ) as six_mth_avg,
    avg(avg_belongs_user_cnt) over (
        order by mth
        rows between 11 preceding and current row
    ) as twelve_mth_avg
from mth_avg
order by mth;
