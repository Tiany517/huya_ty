-- 斯诺克各赛事抖音内容赛中热度：赛事期间发布视频的赛中最高点赞
-- 口径：
--   1. 视频归属：发布时间 pubdate 落在赛事起止日期内 -> 算作本场赛事期间发布的视频。
--   2. 快照过滤：仅保留快照日期 dt 处于赛事举办区间的记录，赛后快照全部丢弃。
--   3. video_match_period_max_like：单条视频在赛事进行时段内观测到的最高点赞。
--   4. match_period_total_like：赛事期间发布视频的“单视频赛中最高点赞”求和。
--   5. top_video_title / top_video_like：赛事期间发布视频里，赛中最高点赞最高的视频标题和对应点赞量。

with match_calendar as (
    select 1 as match_seq, '2024上海大师赛' as match_name, '2024-07-15' as start_dt, '2024-07-21' as end_dt union all
    select 2, '2024英国公开赛', '2024-08-30', '2024-09-07' union all
    select 3, '2024武汉公开赛', '2024-09-16', '2024-09-22' union all
    select 4, '2024国际锦标赛', '2024-09-23', '2024-09-29' union all
    select 5, '2024北爱尔兰公开赛', '2024-10-06', '2024-10-12' union all
    select 6, '2024英格兰公开赛', '2024-10-20', '2024-10-27' union all
    select 7, '2024冠中冠', '2024-11-03', '2024-11-10' union all
    select 8, '2024英锦赛', '2024-11-23', '2024-12-01' union all
    select 9, '2024苏格兰公开赛', '2024-12-04', '2024-12-07' union all
    select 10, '2025伦敦大师赛', '2025-01-12', '2025-01-19' union all
    select 11, '2025德国大师赛', '2025-01-27', '2025-02-02' union all
    select 12, '2025威尔士公开赛', '2025-02-10', '2025-02-16' union all
    select 13, '2025球员锦标赛', '2025-02-24', '2025-03-02' union all
    select 14, '2025巡回锦标赛', '2025-03-17', '2025-03-23' union all
    select 15, '2025世锦赛资格赛', '2025-03-31', '2025-04-06' union all
    select 16, '2025斯诺克世锦赛正赛', '2025-04-19', '2025-05-05' union all
    select 17, '2025上海大师赛', '2025-07-28', '2025-08-03' union all
    select 18, '2025欧洲大师赛', '2025-08-24', '2025-08-30' union all
    select 19, '2025英国公开赛', '2025-09-15', '2025-09-21' union all
    select 20, '2025武汉公开赛', '2025-09-22', '2025-09-28' union all
    select 21, '2025北爱尔兰公开赛', '2025-10-07', '2025-10-13' union all
    select 22, '2025英格兰公开赛', '2025-10-19', '2025-10-26' union all
    select 23, '2025冠中冠', '2025-11-02', '2025-11-09' union all
    select 24, '2025英锦赛', '2025-11-29', '2025-12-07' union all
    select 25, '2025苏格兰公开赛', '2025-12-10', '2025-12-13' union all
    select 26, '2025大奖赛', '2025-12-15', '2025-12-21' union all
    select 27, '2026伦敦大师赛', '2026-01-11', '2026-01-18' union all
    select 28, '2026德国大师赛', '2026-01-26', '2026-02-01' union all
    select 29, '2026威尔士公开赛', '2026-02-03', '2026-02-08' union all
    select 30, '2026球员锦标赛', '2026-02-17', '2026-02-22' union all
    select 31, '2026大奖赛', '2026-02-23', '2026-03-01' union all
    select 32, '2026巡回锦标赛', '2026-03-16', '2026-03-22' union all
    select 33, '2026世锦赛资格赛', '2026-03-30', '2026-04-05' union all
    select 34, '2026斯诺克世锦赛正赛', '2026-04-18', '2026-05-06' union all
    select 35, '2026上海大师赛', '2026-07-27', '2026-08-02'
),

douyin_snapshot as (
    select
        dt as snapshot_dt,
        substr(pubdate, 1, 10) as pub_dt,
        videoid,
        max(title) as title,
        platform,
        max(trim(huya_uid)) as huya_uid,
        max(cast(likecount as bigint)) as likecount
    from zhgametemp.yty_video_total_v2
    where dt between '2024-07-15' and '2026-08-02'
      and substr(pubdate, 1, 10) between '2024-07-15' and '2026-08-02'
      and videoid is not null
      and (
          lower(coalesce(title, '')) like '%斯诺克%'

          -- 赛事名称
          or lower(coalesce(title, '')) like '%上海大师赛%'
          or lower(coalesce(title, '')) like '%斯诺克上海大师赛%'
          or lower(coalesce(title, '')) like '%斯诺克世锦赛%'
          or lower(coalesce(title, '')) like '%世锦赛%'
          or lower(coalesce(title, '')) like '%英锦赛%'
          or lower(coalesce(title, '')) like '%斯诺克英锦赛%'
          or lower(coalesce(title, '')) like '%大师赛%'
          or lower(coalesce(title, '')) like '%斯诺克大师赛%'
          or lower(coalesce(title, '')) like '%英国公开赛%'
          or lower(coalesce(title, '')) like '%北爱尔兰公开赛%'
          or lower(coalesce(title, '')) like '%威尔士公开赛%'
          or lower(coalesce(title, '')) like '%苏格兰公开赛%'
          or lower(coalesce(title, '')) like '%欧洲大师赛%'
          or lower(coalesce(title, '')) like '%德国大师赛%'
          or lower(coalesce(title, '')) like '%爱尔兰公开赛%'
          or lower(coalesce(title, '')) like '%世界大奖赛%'
          or lower(coalesce(title, '')) like '%大奖赛%'
          or lower(coalesce(title, '')) like '%球员锦标赛%'
          or lower(coalesce(title, '')) like '%巡回锦标赛%'
          or lower(coalesce(title, '')) like '%冠中冠%'
          or lower(coalesce(title, '')) like '%斯诺克冠中冠%'
          or lower(coalesce(title, '')) like '%武汉公开赛%'
          or lower(coalesce(title, '')) like '%斯诺克武汉公开赛%'
          or lower(coalesce(title, '')) like '%西安大奖赛%'
          or lower(coalesce(title, '')) like '%斯诺克西安大奖赛%'
          or lower(coalesce(title, '')) like '%国际锦标赛%'
          or lower(coalesce(title, '')) like '%斯诺克国锦赛%'
          or lower(coalesce(title, '')) like '%中国公开赛%'
          or lower(coalesce(title, '')) like '%斯诺克中国公开赛%'
          or lower(coalesce(title, '')) like '%香港大师赛%'
          or lower(coalesce(title, '')) like '%斯诺克香港大师赛%'

          -- 知名选手名称
          or lower(coalesce(title, '')) like '%罗尼奥沙利文%'
          or lower(coalesce(title, '')) like '%奥沙利文%'
          or lower(coalesce(title, '')) like '%约翰希金斯%'
          or lower(coalesce(title, '')) like '%希金斯%'
          or lower(coalesce(title, '')) like '%马克塞尔比%'
          or lower(coalesce(title, '')) like '%塞尔比%'
          or lower(coalesce(title, '')) like '%贾德特鲁姆普%'
          or lower(coalesce(title, '')) like '%特鲁姆普%'
          or lower(coalesce(title, '')) like '%马克威廉姆斯%'
          or lower(coalesce(title, '')) like '%威廉姆斯%'
          or lower(coalesce(title, '')) like '%尼尔罗伯逊%'
          or lower(coalesce(title, '')) like '%罗伯逊%'
          or lower(coalesce(title, '')) like '%凯伦威尔逊%'
          or lower(coalesce(title, '')) like '%威尔逊%'
          or lower(coalesce(title, '')) like '%马克艾伦%'
          or lower(coalesce(title, '')) like '%艾伦%'
          or lower(coalesce(title, '')) like '%肖恩墨菲%'
          or lower(coalesce(title, '')) like '%墨菲%'
          or lower(coalesce(title, '')) like '%巴里霍金斯%'
          or lower(coalesce(title, '')) like '%霍金斯%'
          or lower(coalesce(title, '')) like '%里奇沃顿%'
          or lower(coalesce(title, '')) like '%沃顿%'
          or lower(coalesce(title, '')) like '%斯图尔特宾汉姆%'
          or lower(coalesce(title, '')) like '%宾汉姆%'
          or lower(coalesce(title, '')) like '%马克塞尔特%'
          or lower(coalesce(title, '')) like '%塞尔特%'
          or lower(coalesce(title, '')) like '%加里威尔逊%'
          or lower(coalesce(title, '')) like '%阿里卡特%'
          or lower(coalesce(title, '')) like '%卡特%'
          or lower(coalesce(title, '')) like '%周跃龙%'
          or lower(coalesce(title, '')) like '%丁俊晖%'
          or lower(coalesce(title, '')) like '%赵心童%'
          or lower(coalesce(title, '')) like '%吴宜泽%'
          or lower(coalesce(title, '')) like '%斯佳辉%'
          or lower(coalesce(title, '')) like '%肖国栋%'
          or lower(coalesce(title, '')) like '%张安达%'
          or lower(coalesce(title, '')) like '%庞俊旭%'
          or lower(coalesce(title, '')) like '%范争一%'
          or lower(coalesce(title, '')) like '%曹宇鹏%'
          or lower(coalesce(title, '')) like '%袁思俊%'
      )
    group by
        dt,
        substr(pubdate, 1, 10),
        videoid,
        platform
),

-- 赛事期间发布，且只看赛事期间快照
event_period_publish_snapshot as (
    select
        m.match_seq,
        m.match_name,
        m.start_dt,
        m.end_dt,
        s.platform,
        s.videoid,
        s.title,
        s.huya_uid,
        s.pub_dt,
        s.snapshot_dt,
        s.likecount
    from match_calendar m
    inner join douyin_snapshot s
        on s.pub_dt between m.start_dt and m.end_dt
       and s.snapshot_dt between m.start_dt and m.end_dt
),

event_video_snapshot_rank as (
    select
        match_seq,
        match_name,
        start_dt,
        end_dt,
        platform,
        videoid,
        title,
        huya_uid,
        pub_dt,
        snapshot_dt,
        likecount,
        row_number() over (
            partition by match_seq, platform, videoid
            order by likecount desc, snapshot_dt desc
        ) as rn
    from event_period_publish_snapshot
),

event_video_stat as (
    select
        match_seq,
        platform,
        videoid,
        max(huya_uid) as huya_uid,
        min(pub_dt) as pub_dt,
        min(snapshot_dt) as first_match_snapshot_dt,
        max(snapshot_dt) as last_match_snapshot_dt,
        count(distinct snapshot_dt) as match_snapshot_day_cnt,
        max(likecount) as video_match_period_max_like
    from event_period_publish_snapshot
    group by
        match_seq,
        platform,
        videoid
),

-- 每条赛事期内发布的视频，在赛事期内观测到的最高点赞
event_video_max_like as (
    select
        r.match_seq,
        r.match_name,
        r.start_dt,
        r.end_dt,
        r.platform,
        r.videoid,
        r.title,
        s.huya_uid,
        s.pub_dt,
        s.first_match_snapshot_dt,
        s.last_match_snapshot_dt,
        s.match_snapshot_day_cnt,
        s.video_match_period_max_like
    from event_video_snapshot_rank r
    inner join event_video_stat s
        on r.match_seq = s.match_seq
       and r.platform = s.platform
       and r.videoid = s.videoid
    where r.rn = 1
),

event_video_rank as (
    select
        *,
        row_number() over (
            partition by match_seq
            order by video_match_period_max_like desc, videoid
        ) as rn
    from event_video_max_like
),

event_summary as (
    select
        match_seq,
        match_name,
        start_dt,
        end_dt,
        count(distinct concat(coalesce(platform, ''), '_', cast(videoid as string))) as publish_video_cnt,
        sum(video_match_period_max_like) as match_period_total_like,
        avg(video_match_period_max_like) as avg_video_match_period_max_like,
        max(video_match_period_max_like) as top_video_like,
        count(distinct huya_uid) as huya_uid_cnt
    from event_video_max_like
    group by
        match_seq,
        match_name,
        start_dt,
        end_dt
)

-- 赛事级汇总：包含视频最高点赞量总和，以及该赛事最高点赞视频 title 和点赞量
select
    s.match_seq,
    s.match_name,
    s.start_dt,
    s.end_dt,
    s.publish_video_cnt,
    s.match_period_total_like,
    s.avg_video_match_period_max_like,
    s.top_video_like,
    r.title as top_video_title,
    r.platform as top_video_platform,
    r.videoid as top_videoid,
    r.pub_dt as top_video_pub_dt,
    r.first_match_snapshot_dt as top_video_first_match_snapshot_dt,
    r.last_match_snapshot_dt as top_video_last_match_snapshot_dt,
    s.huya_uid_cnt
from event_summary s
left join event_video_rank r
    on s.match_seq = r.match_seq
   and r.rn = 1
order by
    s.match_seq;

-- 如果要看视频明细，执行下面这段：
-- select
--     match_seq,
--     match_name,
--     start_dt,
--     end_dt,
--     platform,
--     videoid,
--     title,
--     huya_uid,
--     pub_dt,
--     first_match_snapshot_dt,
--     last_match_snapshot_dt,
--     match_snapshot_day_cnt,
--     video_match_period_max_like
-- from event_video_max_like
-- order by
--     match_seq,
--     video_match_period_max_like desc;
