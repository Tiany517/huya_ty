-- 微信视频号流量下钻
-- 对比窗口：上周 2026-10-26 至 2026-11-01；本周 2026-11-02 至 2026-11-08。
-- 数据口径：仅纳入开播时长大于 0 的主播自然日记录。
-- 输出粒度：userid + usernickname；指标按主播汇总两周日均值及环比差异。

with t1 as (
    select
        dt,
        case
            when dt between '2026-10-26' and '2026-11-01' then '上周'
            when dt between '2026-11-02' and '2026-11-08' then '本周'
        end as week,
        userid,
        usernickname,
        sum(cast(audiencecnt as bigint)) as dau,
        sum(cast(onlinetimeduration as double)) as online_duration
    from gamelive.dwd_spider_wxmcn_anchor_livedata_list_d_i a
    where dt >= '2026-10-26'
      and dt <= '2026-11-08'
      and cast(onlinetimeduration as double) > 0
    group by
        dt,
        week,
        userid,
        usernickname
)

select
    userid,
    usernickname,

    sum(case when week = '上周' then dau end) as "上周DAU",
    sum(case when week = '本周' then dau end) as "本周DAU",
    sum(case when week = '本周' then dau end)
        / nullif(sum(case when week = '上周' then dau end), 0) - 1 as "DAU差异",

    sum(case when week = '上周' then live_day_cnt end) as "上周开播天数",
    sum(case when week = '本周' then live_day_cnt end) as "本周开播天数",
    cast(sum(case when week = '本周' then live_day_cnt end) as double)
        / nullif(sum(case when week = '上周' then live_day_cnt end), 0) - 1
        as "开播天数差异",

    sum(case when week = '上周' then avg_live_duration end) as "上周日均开播时长",
    sum(case when week = '本周' then avg_live_duration end) as "本周日均开播时长",
    sum(case when week = '本周' then avg_live_duration end)
        / nullif(sum(case when week = '上周' then avg_live_duration end), 0) - 1
        as "日均开播时长差异"
from (
    select
        week,
        userid,
        usernickname,
        avg(dau) as dau,
        count(distinct dt) as live_day_cnt,
        sum(online_duration) / count(distinct dt) as avg_live_duration
    from t1
    group by
        week,
        userid,
        usernickname
) t
group by
    userid,
    usernickname;
