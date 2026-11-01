-- 目的：统计指定主播在无畏契约（gameid=5937）下，2026-01-01 至 2026-10-26 的直播表现。
-- 样本：用户提供的 13 个主播 UID。
-- 粒度：主播一行。
-- 口径：
--   1. DAU：观看表按主播 x 日对 user_ukey 去重；过滤 tag='gameid'、htime='session'、igameid=5937。
--   2. 直播时长：主播日表 live_hours_only_live > 0；单位小时，输出换算为分钟。
--   3. 2026年日均DAU：各观看日 DAU 之和 / 有观看记录天数。
--   4. 单日DAU超20万开播日：当日 DAU > 200000 且当日有效开播时长 > 0。
--   5. “单日DAU超20万开播日日均直播时长”：上述达标日的直播时长之和 / 达标天数。
-- 实际最新可用分区：主播日表和观看会话表均取至 2026-10-26。

with

target_uid as (
    select uid
    from (
        values
            ('1279518938631'),
            ('1860008570'),
            ('1014447803'),
            ('1199627305549'),
            ('1319533338733'),
            ('1843949176'),
            ('1259517233171'),
            ('1642544888'),
            ('1199556643949'),
            ('1199548593898'),
            ('1279540786939'),
            ('1506689257'),
            ('1279543300040')
    ) t(uid)
),

-- 主播 x 日有效开播：只统计无畏契约，时长字段单位为小时
live_day as (
    select
        cast(dt as varchar) as dt,
        cast(ayyuid as varchar) as uid,
        max(nickname) as nickname,
        sum(live_hours_only_live) as live_hours
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2026-01-01' and '2026-10-26'
      and cast(gameid as varchar) = '5937'
      and live_hours_only_live > 0
      and cast(ayyuid as varchar) in (
          '1279518938631', '1860008570', '1014447803', '1199627305549',
          '1319533338733', '1843949176', '1259517233171', '1642544888',
          '1199556643949', '1199548593898', '1279540786939', '1506689257',
          '1279543300040'
      )
    group by cast(dt as varchar), cast(ayyuid as varchar)
),

-- 主播 x 日观看DAU：按当天 user_ukey 去重
view_day as (
    select
        cast(dt as varchar) as dt,
        cast(luid as varchar) as uid,
        count(distinct user_ukey) as day_dau
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where dt between '2026-01-01' and '2026-10-26'
      and tag = 'gameid'
      and htime = 'session'
      and igameid = 5937
      and cast(luid as varchar) in (
          '1279518938631', '1860008570', '1014447803', '1199627305549',
          '1319533338733', '1843949176', '1259517233171', '1642544888',
          '1199556643949', '1199548593898', '1279540786939', '1506689257',
          '1279543300040'
      )
    group by cast(dt as varchar), cast(luid as varchar)
),

-- 补齐主播 x 日网格，避免漏掉只有开播记录或只有观看记录的日期
uid_day as (
    select uid, dt from live_day
    union
    select uid, dt from view_day
),

joined_day as (
    select
        d.uid,
        l.nickname,
        d.dt,
        v.day_dau,
        l.live_hours
    from uid_day d
    left join live_day l
      on d.uid = l.uid
     and d.dt = l.dt
    left join view_day v
      on d.uid = v.uid
     and d.dt = v.dt
),

summary as (
    select
        uid,
        max(nickname) as nickname,
        count(distinct case when live_hours > 0 then dt end) as live_days,
        sum(case when live_hours > 0 then live_hours else 0 end)
          / nullif(count(distinct case when live_hours > 0 then dt end), 0)
          as avg_daily_live_hours_all,
        count(distinct case when day_dau is not null then dt end) as watch_days,
        sum(coalesce(day_dau, 0))
          / nullif(count(distinct case when day_dau is not null then dt end), 0)
          as avg_daily_dau_all,
        count(distinct case when live_hours > 0 and day_dau > 200000 then dt end)
          as high_dau_live_days,
        sum(case when live_hours > 0 and day_dau > 200000 then live_hours else 0 end)
          / nullif(count(distinct case when live_hours > 0 and day_dau > 200000 then dt end), 0)
          as avg_daily_live_hours_dau_gt_200k,
        max(day_dau) as max_daily_dau,
        min(case when day_dau > 200000 then dt end) as first_day_dau_gt_200k,
        max(case when day_dau > 200000 then dt end) as last_day_dau_gt_200k
    from joined_day
    group by uid
)

select
    uid as "主播UID",
    nickname as "主播昵称",
    live_days as "有效开播天数",
    round(avg_daily_dau_all, 0) as "2026年日均DAU",
    round(avg_daily_live_hours_all * 60.0, 1) as "2026年有效开播日日均直播时长_分钟",
    high_dau_live_days as "单日DAU超20万且开播天数",
    round(avg_daily_live_hours_dau_gt_200k * 60.0, 1)
      as "单日DAU超20万开播日日均直播时长_分钟",
    max_daily_dau as "单日最高DAU",
    first_day_dau_gt_200k as "首次单日DAU超20万",
    last_day_dau_gt_200k as "最近单日DAU超20万"
from summary
order by
    case when avg_daily_dau_all >= 200000 then 0 else 1 end,
    avg_daily_dau_all desc,
    uid;
