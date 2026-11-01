-- 用途：为 7 万多个正常 FPS 主播昵称解析真实 luid，并计算 2026 年日均 ACU、ACU 分层和逐月开播天数。
-- 时间：2026-01-01 至 2026-10-20。
-- 说明：不要把 7 万多个昵称拼进 snick in (...)。先下载全量昵称候选映射，再在本地精确匹配。
-- 多候选：同一昵称按历史上最后一次出现的 luid 识别；同一天仍出现多个 luid 时，取最大 luid 作为确定性兜底。
-- 未命中：再用 dim_huya_ayyuid_info 最新快照补查；仍无法唯一匹配的保留在审计表。

-- 1. 历史昵称候选映射。
-- 昵称先 base64，避免逗号、引号、换行破坏 CSV；下载后在本地解码并按“昵称最近出现日期”选择 luid。
select
    to_base64(to_utf8(trim(cast(nickname as varchar)))) as snick_b64,
    cast(ayyuid as varchar) as luid,
    max(cast(dt as varchar)) as latest_dt
from gamelive.dm_huya_ayyuid_detail_day
where dt between '2026-01-01' and '2026-10-20'
  and nickname is not null
  and trim(cast(nickname as varchar)) <> ''
group by
    to_base64(to_utf8(trim(cast(nickname as varchar)))),
    cast(ayyuid as varchar)

-- 2. 当前主播信息快照，用于补查历史明细中未命中的昵称。
select
    cast(uid as varchar) as luid,
    to_base64(to_utf8(trim(cast(nick as varchar)))) as snick_b64,
    cast(roomid as varchar) as roomid,
    cast(create_time as varchar) as create_time
from gamelive.dim_huya_ayyuid_info
where dt = '2026-10-22'
  and nick is not null
  and trim(cast(nick as varchar)) <> ''

-- 3. 主播年度实际开播日的日均 ACU。
-- 先在“主播 x 日”汇总，避免一个主播一天多个品类行重复计权；live_mins 原表单位为小时。
with anchor_day as (
    select
        cast(dt as varchar) as dt,
        cast(ayyuid as varchar) as luid,
        coalesce(avg(acu), 0) as acu,
        coalesce(sum(live_mins), 0) as live_mins
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2026-01-01' and '2026-10-20'
    group by
        cast(dt as varchar),
        cast(ayyuid as varchar)
)
select
    luid,
    count(distinct dt) as live_day_cnt,
    avg(acu) as avg_daily_acu,
    sum(live_mins) as total_live_hours
from anchor_day
where live_mins > 0
group by luid

-- 4. 主播逐月开播天数和开播时长。
with anchor_day as (
    select
        cast(dt as varchar) as dt,
        cast(ayyuid as varchar) as luid,
        coalesce(avg(acu), 0) as acu,
        coalesce(sum(live_mins), 0) as live_mins
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2026-01-01' and '2026-10-20'
    group by
        cast(dt as varchar),
        cast(ayyuid as varchar)
)
select
    substr(dt, 1, 7) as mth,
    luid,
    count(distinct dt) as live_day_cnt,
    sum(live_mins) as live_hours
from anchor_day
where live_mins > 0
group by
    substr(dt, 1, 7),
    luid
