-- 无畏契约（gameid=5937）全体主播年日均核心指标
-- 数据范围：2026-01-01 至 2026-10-22（实际最新可用分区）
-- 粒度：主播一行；先聚合到主播×日，再计算主播全期均值
-- 有效开播日：live_hours_only_live > 0
-- 单位：live_hours_only_live、view_mins_only_live 在源表中均为小时，输出时转换为分钟
-- 月日均开播天数：实际开播天数 / 10 个日历月，未开播月份按 0 天参与

with anchor_day as (
    select
        cast(dt as varchar) as dt,
        cast(ayyuid as varchar) as luid,
        -- 展示层清理昵称中的引号、逗号和换行，避免异常昵称破坏 CSV 结构；仅影响昵称展示，不影响主播ID及指标
        max(
            substr(
                regexp_replace(
                    coalesce(cast(nickname as varchar), ''),
                    '[",\r\n\t]+',
                    ' '
                ),
                1,
                100
            )
        ) as nickname,
        coalesce(avg(acu), 0) as day_acu,
        coalesce(sum(live_hours_only_live), 0) as day_live_hours,
        coalesce(sum(view_mins_only_live), 0) as day_view_hours
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2026-01-01' and '2026-10-22'
      and cast(gameid as varchar) = '5937'
      and live_hours_only_live > 0
    group by
        cast(dt as varchar),
        cast(ayyuid as varchar)
)

select
    luid,
    max(nickname) as nickname,
    count(distinct dt) as live_day_cnt,
    avg(day_acu) as avg_daily_acu,
    avg(day_live_hours * 60.0) as avg_daily_live_minutes,
    count(distinct dt) / 10.0 as avg_monthly_live_days,
    avg(day_view_hours * 60.0) as avg_daily_view_minutes
from anchor_day
group by luid
order by avg_daily_acu desc;
