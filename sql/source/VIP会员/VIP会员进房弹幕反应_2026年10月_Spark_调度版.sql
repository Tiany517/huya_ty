-- 调度说明：本文件按仓库既有 Spark 调度模板组织，包含建表和动态分区覆盖写入。
-- 不依赖宏变量；最终查询返回 dt='2026-10-31'，并显式启用动态分区 nonstrict 模式。
-- 最终输出不区分小时；粒度为用户组+整体/品类+ACU分层。
-- 目的：比较 2026 年 10 月 VIP 用户与普通用户进房前后各 3 分钟的直播间弹幕反应。
-- 引擎：Spark SQL
-- VIP 订单快照：gamelive.dwd_huya_pay_platform_vip_detail_d_a，dt='2026-11-08'。
-- 事件：只在观看表中取“进房”事件，事件时间使用 user_start_time。
-- 用户组：
--   1. VIP用户：10 月购买过 VIP，且本次进房发生在其 10 月首笔成功订单之后。
--   2. 普通用户：在本次进房发生时尚未购买过 VIP；因此 10 月未来购卡用户，
--      在其购卡前的进房事件计入普通用户。
--   3. 在观察期开始前已购买、但 10 月未再次购买的 VIP，不进入上述两组。
-- 场次：取至少有一位 VIP 用户购卡后进入过的直播场次，场次键为 dt+主播UID+live_id。
-- 弹幕：passed='0'，内容非空，排除主播本人；主指标排除触发进房用户本人。
-- 窗口：[event_ts-3分钟, event_ts) 与 [event_ts, event_ts+3分钟)。
-- 限制：不要求用户进房距离开播满 N 分钟；只统计目标直播场次内的用户进房事件。
-- 去重：进房事件按用户+场次+进房时间去重；弹幕按场次+发送用户+时间+内容去重。
-- 重叠：同一场次内事件窗口若与上一或下一事件相隔不足 180 秒，标记为重叠事件。

-- 调度平台若支持 Spark 会话参数，建议配置：
-- spark.sql.autoBroadcastJoinThreshold=-1
-- spark.sql.adaptive.enabled=true
-- spark.sql.adaptive.coalescePartitions.enabled=true

create table if not exists zhgametemp.zty_ads_huya_vip_entry_danmu_reaction_month_v1 (
    user_group                  string  comment '用户组：VIP用户/普通用户',
    breakdown_type              string  comment '分组类型：整体/用户类别',
    user_type                   string  comment '场景：整体/游戏/娱乐/品类未知',
    acu_bin                     string  comment '直播间ACU分层',
    event_cnt                   bigint  comment '进房事件数',
    event_user_cnt              bigint  comment '当前ACU层级内去重进房用户数',
    overlap_event_cnt           bigint  comment '前后3分钟窗口与相邻事件重叠的进房事件数',
    avg_danmu_before_3m         double  comment '进房前3分钟平均弹幕数',
    avg_danmu_after_3m          double  comment '进房后3分钟平均弹幕数',
    avg_danmu_change            double  comment '进房后减进房前3分钟平均弹幕变化',
    total_danmu_before_3m       bigint  comment '进房前3分钟弹幕总数',
    total_danmu_after_3m        bigint  comment '进房后3分钟弹幕总数',
    events_with_before_danmu    bigint  comment '进房前3分钟有弹幕的事件数',
    events_with_after_danmu     bigint  comment '进房后3分钟有弹幕的事件数',
    non_overlap_event_cnt       bigint  comment '无相邻事件窗口重叠的进房事件数',
    non_overlap_avg_before_3m   double  comment '无重叠事件进房前3分钟平均弹幕数',
    non_overlap_avg_after_3m    double  comment '无重叠事件进房后3分钟平均弹幕数',
    non_overlap_avg_change      double  comment '无重叠事件进房前后3分钟平均弹幕变化'
)
partitioned by (
    dt string comment '月度统计截止日，固定为2026-10-31'
)
stored as orc;

with vip_user_status as (
    -- 粒度：UID；一次扫描同时得到首次购卡和 10 月首次购卡时间。
    select
        cast(uid as string) as user_uid,
        min(case when to_timestamp(cast(create_time as string)) is not null
                 then to_timestamp(cast(create_time as string)) end) as first_vip_ts,
        min(case when to_timestamp(cast(create_time as string)) >= timestamp '2026-10-01 00:00:00'
                       and to_timestamp(cast(create_time as string)) < timestamp '2026-11-01 00:00:00'
                 then to_timestamp(cast(create_time as string)) end) as first_oct_vip_ts
    from gamelive.dwd_huya_pay_platform_vip_detail_d_a
    where dt = '2026-11-08'
      and substr(create_time, 1, 10) between '2026-08-31' and '2026-10-31'
      and status = '200'
      and cast(amount as double) > 0
      and uid is not null
      and lower(cast(uid as string)) not in ('', '0', 'other')
    group by cast(uid as string)
),

vip_target_entry as (
    -- 粒度：VIP 用户进房事件；只纳入 10 月首笔成功订单后的进房。
    select distinct
        cast(w.user_yyuid as string) as user_uid,
        cast(w.luid as string) as creator_uid,
        cast(w.lliveid as string) as live_id,
        w.dt as event_dt,
        to_timestamp(cast(w.user_start_time as string)) as event_ts
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user w
    inner join vip_user_status v
        on cast(w.user_yyuid as string) = v.user_uid
       and v.first_oct_vip_ts is not null
       and to_timestamp(cast(w.user_start_time as string)) >= v.first_oct_vip_ts
    where w.dt between '2026-10-01' and '2026-10-31'
      and w.tag = 'gameid'
      and w.htime = 'session'
      and w.user_yyuid is not null
      and w.luid is not null
      and w.lliveid is not null
      and w.user_start_time is not null
      and to_timestamp(cast(w.user_start_time as string)) >= timestamp '2026-10-01 00:00:00'
      and to_timestamp(cast(w.user_start_time as string)) < timestamp '2026-11-01 00:00:00'
),

target_room as (
    -- 粒度：日期+主播+live_id；两组都只统计这些目标直播场次。
    select distinct
        event_dt,
        creator_uid,
        live_id
    from vip_target_entry
),

watch_event_raw as (
    -- 粒度：原始用户进房事件；进房时间必须使用 user_start_time，不能使用 start_time。
    select distinct
        w.dt as event_dt,
        cast(w.user_yyuid as string) as user_uid,
        cast(w.luid as string) as creator_uid,
        cast(w.lliveid as string) as live_id,
        to_timestamp(cast(w.user_start_time as string)) as event_ts
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user w
    inner join target_room r
        on w.dt = r.event_dt
       and cast(w.luid as string) = r.creator_uid
       and cast(w.lliveid as string) = r.live_id
    where w.dt between '2026-10-01' and '2026-10-31'
      and w.tag = 'gameid'
      and w.htime = 'session'
      and w.user_yyuid is not null
      and w.luid is not null
      and w.lliveid is not null
      and w.user_start_time is not null
      and to_timestamp(cast(w.user_start_time as string)) >= timestamp '2026-10-01 00:00:00'
      and to_timestamp(cast(w.user_start_time as string)) < timestamp '2026-11-01 00:00:00'
),

watch_event as (
    -- 粒度：dt+用户+主播+live_id+进房时间；同一时刻不同用户必须分别保留。
    select
        event_dt,
        user_uid,
        creator_uid,
        live_id,
        event_ts,
        concat_ws(
            '|', '进房', event_dt, user_uid, creator_uid, live_id,
            cast(event_ts as string)
        ) as event_id
    from watch_event_raw
    where event_ts is not null
    group by event_dt, user_uid, creator_uid, live_id, event_ts
),

classified_watch_event as (
    -- 分组规则：购卡后算 VIP；购卡前或从未购卡算普通；其余既往 VIP 不计入两组。
    select
        case
            when s.first_oct_vip_ts is not null and e.event_ts >= s.first_oct_vip_ts
                then 'VIP用户'
            when coalesce(s.first_vip_ts, timestamp '9999-12-31 00:00:00') > e.event_ts
                then '普通用户'
        end as user_group,
        e.event_id,
        e.user_uid,
        e.creator_uid,
        e.live_id,
        e.event_dt,
        e.event_ts,
        cast(floor(unix_timestamp(e.event_ts)) as bigint) as event_sec
    from watch_event e
    left join vip_user_status s
        on e.user_uid = s.user_uid
    where (s.first_oct_vip_ts is not null and e.event_ts >= s.first_oct_vip_ts)
       or (coalesce(s.first_vip_ts, timestamp '9999-12-31 00:00:00') > e.event_ts)
),

event_keys as (
    select distinct event_dt, user_uid, creator_uid, live_id
    from classified_watch_event
),

category_key as (
    -- 粒度：事件日期+用户+主播+live_id；MIN/MAX 不同即多标签，归入品类未知。
    select
        b.dt as event_dt,
        cast(b.user_uid as string) as user_uid,
        cast(b.creator_uid as string) as creator_uid,
        cast(b.live_id as string) as live_id,
        min(b.game_label) as game_label_min,
        max(b.game_label) as game_label_max
    from gamelive.dws_huya_user_behavior_d_i b
    inner join event_keys e
        on b.dt = e.event_dt
       and cast(b.user_uid as string) = e.user_uid
       and cast(b.creator_uid as string) = e.creator_uid
       and cast(b.live_id as string) = e.live_id
    where b.dt between '2026-10-01' and '2026-10-31'
      and b.data_type = 'live_watch_session'
      and b.live_content_type = '直播'
    group by
        b.dt,
        cast(b.user_uid as string),
        cast(b.creator_uid as string),
        cast(b.live_id as string)
),

event_category as (
    select
        e.*,
        case
            when c.game_label_min = c.game_label_max and c.game_label_max = '游戏' then '游戏'
            when c.game_label_min = c.game_label_max and c.game_label_max = '娱乐' then '娱乐'
            else '品类未知'
        end as user_type
    from classified_watch_event e
    left join category_key c
        on e.event_dt = c.event_dt
       and e.user_uid = c.user_uid
       and e.creator_uid = c.creator_uid
       and e.live_id = c.live_id
),

minute_acu as (
    -- 粒度：日期+主播+live_id+分钟；先按目标场次过滤 ACU 表。
    select
        a.dt as event_dt,
        cast(a.ayyuid as string) as creator_uid,
        cast(a.tkey1 as string) as live_id,
        date_trunc('minute', to_timestamp(cast(a.time_value as string))) as acu_minute,
        max(cast(a.all_users as double)) as acu
    from gamelive.dw_huya_online_users a
    inner join target_room r
        on a.dt = r.event_dt
       and cast(a.ayyuid as string) = r.creator_uid
       and cast(a.tkey1 as string) = r.live_id
    where a.dt between '2026-10-01' and '2026-10-31'
      and a.tag = 'server_ayyuid_liveid_session'
      and a.time_type = 'minute'
      and a.time_value is not null
      and a.all_users is not null
    group by
        a.dt,
        cast(a.ayyuid as string),
        cast(a.tkey1 as string),
        date_trunc('minute', to_timestamp(cast(a.time_value as string)))
),

event_acu as (
    select
        e.*,
        a.acu,
        case
            when a.acu > 0 and a.acu <= 2 then '(0,2]'
            when a.acu > 2 and a.acu <= 5 then '(2,5]'
            when a.acu > 5 and a.acu <= 10 then '(5,10]'
            when a.acu > 10 and a.acu <= 20 then '(10,20]'
            when a.acu > 20 and a.acu <= 50 then '(20,50]'
            when a.acu > 50 and a.acu <= 100 then '(50,100]'
            when a.acu > 100 and a.acu <= 200 then '(100,200]'
            when a.acu > 200 and a.acu <= 500 then '(200,500]'
            when a.acu > 500 and a.acu <= 1000 then '(500,1000]'
            when a.acu > 1000 and a.acu <= 2000 then '(1000,2000]'
            when a.acu > 2000 and a.acu <= 5000 then '(2000,5000]'
            when a.acu > 5000 and a.acu <= 10000 then '(5000,10000]'
            when a.acu > 10000 and a.acu <= 20000 then '(10000,20000]'
            when a.acu > 20000 and a.acu <= 50000 then '(20000,50000]'
            when a.acu > 50000 and a.acu <= 100000 then '(50000,100000]'
            when a.acu > 100000 then '(100000,+]'
            else 'unknown'
        end as acu_bin,
        case
            when a.acu > 0 and a.acu <= 2 then 1
            when a.acu > 2 and a.acu <= 5 then 2
            when a.acu > 5 and a.acu <= 10 then 3
            when a.acu > 10 and a.acu <= 20 then 4
            when a.acu > 20 and a.acu <= 50 then 5
            when a.acu > 50 and a.acu <= 100 then 6
            when a.acu > 100 and a.acu <= 200 then 7
            when a.acu > 200 and a.acu <= 500 then 8
            when a.acu > 500 and a.acu <= 1000 then 9
            when a.acu > 1000 and a.acu <= 2000 then 10
            when a.acu > 2000 and a.acu <= 5000 then 11
            when a.acu > 5000 and a.acu <= 10000 then 12
            when a.acu > 10000 and a.acu <= 20000 then 13
            when a.acu > 20000 and a.acu <= 50000 then 14
            when a.acu > 50000 and a.acu <= 100000 then 15
            when a.acu > 100000 then 16
            else 99
        end as acu_bin_order,
        case
            when e.event_sec - lag(e.event_sec) over (
                partition by e.creator_uid, e.live_id order by e.event_sec
            ) < 180
            or lead(e.event_sec) over (
                partition by e.creator_uid, e.live_id order by e.event_sec
            ) - e.event_sec < 180
            then 1 else 0
        end as is_window_overlap
    from event_category e
    left join minute_acu a
        on e.event_dt = a.event_dt
       and e.creator_uid = a.creator_uid
       and e.live_id = a.live_id
       and date_trunc('minute', e.event_ts) = a.acu_minute
),

danmu_source as (
    -- 粒度：发送人+场次+秒+内容；有效弹幕要求内容非空。
    select distinct
        cast(d.lpid as string) as creator_uid,
        cast(d.luid as string) as sender_uid,
        cast(d.liveid as string) as live_id,
        to_timestamp(cast(d.time as string)) as danmu_ts,
        cast(unix_timestamp(to_timestamp(cast(d.time as string))) as bigint) as event_sec,
        coalesce(nullif(d.askscontent, ''), nullif(d.scontent, '')) as content
    from gamelive.gamelive_huya_danmu_log d
    inner join target_room r
        on cast(d.lpid as string) = r.creator_uid
       and cast(d.liveid as string) = r.live_id
    where d.dt between '2026-09-30' and '2026-11-01'
      and d.passed = '0'
      and d.lpid is not null
      and d.luid is not null
      and d.liveid is not null
      and d.time is not null
      and coalesce(nullif(d.askscontent, ''), nullif(d.scontent, '')) is not null
      and to_timestamp(cast(d.time as string)) >= timestamp '2026-09-30 23:57:00'
      and to_timestamp(cast(d.time as string)) < timestamp '2026-11-01 00:03:00'
),

room_danmu_sec as (
    -- 粒度：直播场次+秒；房间级弹幕先聚合，避免每个用户进房事件都进入同一窗口。
    select
        creator_uid,
        live_id,
        event_sec,
        count(*) as danmu_cnt
    from danmu_source
    where sender_uid <> creator_uid
    group by creator_uid, live_id, event_sec
),

user_danmu_sec as (
    -- 粒度：直播场次+发送用户+秒；只用于从窗口结果中扣除进房用户本人弹幕。
    select
        creator_uid,
        live_id,
        sender_uid,
        event_sec,
        count(*) as danmu_cnt
    from danmu_source
    where sender_uid <> creator_uid
    group by creator_uid, live_id, sender_uid, event_sec
),

event_time_grid as (
    -- 粒度：直播场次+进房秒；确保没有弹幕的进房时刻也落在房间时间轴上。
    select distinct creator_uid, live_id, event_sec
    from event_acu
),

room_timeline as (
    -- 粒度：直播场次+秒；每个秒只保留一条弹幕计数，事件秒补充零值。
    select
        creator_uid,
        live_id,
        event_sec,
        sum(danmu_cnt) as danmu_cnt
    from (
        select creator_uid, live_id, event_sec, danmu_cnt
        from room_danmu_sec
        union all
        select creator_uid, live_id, event_sec, cast(0 as bigint) as danmu_cnt
        from event_time_grid
    ) t
    group by creator_uid, live_id, event_sec
),

room_window as (
    -- 房间级前窗 [t-180s,t) 与后窗 [t,t+179s]。
    select
        creator_uid,
        live_id,
        event_sec,
        sum(danmu_cnt) over (
            partition by creator_uid, live_id
            order by event_sec
            range between 180 preceding and 1 preceding
        ) as before_cnt,
        sum(danmu_cnt) over (
            partition by creator_uid, live_id
            order by event_sec
            range between current row and 179 following
        ) as after_cnt
    from room_timeline
),

sender_room_keys as (
    -- 只对当月在该场次真正发过弹幕的用户构造个人时间轴，减少无效事件行。
    select distinct creator_uid, live_id, sender_uid
    from user_danmu_sec
),

event_sender_time_grid as (
    -- 粒度：直播场次+发送用户+进房秒；仅保留有个人弹幕的发送用户。
    select distinct
        e.creator_uid,
        e.live_id,
        e.user_uid as sender_uid,
        e.event_sec
    from event_acu e
    inner join sender_room_keys k
        on e.creator_uid = k.creator_uid
       and e.live_id = k.live_id
       and e.user_uid = k.sender_uid
),

sender_timeline as (
    -- 粒度：直播场次+发送用户+秒；用于精确扣除触发事件用户自己的前后窗弹幕。
    select
        creator_uid,
        live_id,
        sender_uid,
        event_sec,
        sum(danmu_cnt) as danmu_cnt
    from (
        select creator_uid, live_id, sender_uid, event_sec, danmu_cnt
        from user_danmu_sec
        union all
        select
            creator_uid,
            live_id,
            sender_uid,
            event_sec,
            cast(0 as bigint) as danmu_cnt
        from event_sender_time_grid
    ) t
    group by creator_uid, live_id, sender_uid, event_sec
),

sender_window as (
    -- 个人弹幕前窗 [t-180s,t) 与后窗 [t,t+179s]。
    select
        creator_uid,
        live_id,
        sender_uid,
        event_sec,
        coalesce(sum(danmu_cnt) over (
            partition by creator_uid, live_id, sender_uid
            order by event_sec
            range between 180 preceding and 1 preceding
        ), 0) as before_cnt,
        coalesce(sum(danmu_cnt) over (
            partition by creator_uid, live_id, sender_uid
            order by event_sec
            range between current row and 179 following
        ), 0) as after_cnt
    from sender_timeline
),

reaction_event as (
    -- 每个进房事件一行：房间窗口减该用户个人窗口，复现原口径的“排除触发者本人弹幕”。
    select
        e.event_id,
        e.user_uid as event_user_uid,
        e.user_group,
        e.user_type,
        e.acu_bin,
        e.acu_bin_order,
        e.is_window_overlap,
        greatest(
            coalesce(r.before_cnt, 0) - coalesce(s.before_cnt, 0),
            0
        ) as before_danmu_cnt,
        greatest(
            coalesce(r.after_cnt, 0) - coalesce(s.after_cnt, 0),
            0
        ) as after_danmu_cnt
    from event_acu e
    left join room_window r
        on e.creator_uid = r.creator_uid
       and e.live_id = r.live_id
       and e.event_sec = r.event_sec
    left join sender_window s
        on e.creator_uid = s.creator_uid
       and e.live_id = s.live_id
       and e.user_uid = s.sender_uid
       and e.event_sec = s.event_sec
),

summary as (
    select
        user_group,
        case when user_type is null then '整体' else '用户类别' end as breakdown_type,
        coalesce(user_type, '整体') as user_type,
        acu_bin,
        acu_bin_order,
        count(*) as event_cnt,
        count(distinct event_user_uid) as event_user_cnt,
        sum(case when is_window_overlap = 1 then 1 else 0 end) as overlap_event_cnt,
        avg(before_danmu_cnt) as avg_danmu_before_3m,
        avg(after_danmu_cnt) as avg_danmu_after_3m,
        avg(after_danmu_cnt - before_danmu_cnt) as avg_danmu_change,
        sum(before_danmu_cnt) as total_danmu_before_3m,
        sum(after_danmu_cnt) as total_danmu_after_3m,
        sum(case when before_danmu_cnt > 0 then 1 else 0 end) as events_with_before_danmu,
        sum(case when after_danmu_cnt > 0 then 1 else 0 end) as events_with_after_danmu,
        sum(case when is_window_overlap = 0 then 1 else 0 end) as non_overlap_event_cnt,
        avg(case when is_window_overlap = 0 then before_danmu_cnt end) as non_overlap_avg_before_3m,
        avg(case when is_window_overlap = 0 then after_danmu_cnt end) as non_overlap_avg_after_3m,
        avg(case when is_window_overlap = 0 then after_danmu_cnt - before_danmu_cnt end) as non_overlap_avg_change
    from reaction_event
    group by grouping sets (
        (user_group, acu_bin, acu_bin_order),
        (user_group, user_type, acu_bin, acu_bin_order)
    )
)

set hive.exec.dynamic.partition.mode=nonstrict;

insert overwrite table zhgametemp.zty_ads_huya_vip_entry_danmu_reaction_month_v1
partition (dt)

select
    user_group,
    breakdown_type,
    user_type,
    acu_bin,
    event_cnt,
    event_user_cnt,
    overlap_event_cnt,
    round(avg_danmu_before_3m, 4) as avg_danmu_before_3m,
    round(avg_danmu_after_3m, 4) as avg_danmu_after_3m,
    round(avg_danmu_change, 4) as avg_danmu_change,
    total_danmu_before_3m,
    total_danmu_after_3m,
    events_with_before_danmu,
    events_with_after_danmu,
    non_overlap_event_cnt,
    round(non_overlap_avg_before_3m, 4) as non_overlap_avg_before_3m,
    round(non_overlap_avg_after_3m, 4) as non_overlap_avg_after_3m,
    round(non_overlap_avg_change, 4) as non_overlap_avg_change,
    '2026-10-31' as dt
from summary;

-- 调度版结束
