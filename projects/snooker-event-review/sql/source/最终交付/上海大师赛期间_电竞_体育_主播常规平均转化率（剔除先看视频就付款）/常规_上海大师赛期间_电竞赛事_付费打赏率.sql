-- ========================================
-- LOL_LPL春季赛第三赛段
-- 拉新用户赛事结束后180天打赏追踪
-- ========================================

with match_info as (
    select 
        substr(a.date,1,10) as match_dt,
        a.uid as luid
    from gamelive.dwd_huya_dim_game_copyright_info_d_a a --赛事版权表
    where a.dt='2026-05-17'
    and substr(date,1,10) between '2025-07-28' and '2025-08-03'
    and a.live_type like '%直播%' --只计算直播
    and a.room_type = '独立直播间' --官方直播间 
    and a.content_type in ('游戏赛事')
    -- and a.game_id = '1' -- 英雄联盟
    -- and a.match_id in (9024707) -- 2025LPL第三赛段
    group by 1,2
)

, laxin_user as (
    select 
        a.dt, 
        a.user_ukey as user_ukey
    from zhgametemp.cxm_xinzeng_0413 a  -- 拉新用户表
    inner join match_info b 
        on a.dt = b.match_dt              -- 日期关联
        and trim(a.luid) = trim(b.luid) -- 主播关联
    where a.dt between '2025-07-28' and '2025-08-03'         -- 拉新时间限制
    group by 1,2
)

-- , first_time_video as (
--     select
--         user_ukey,
--         min(dt) as first_video_time
--     from gamelive.dws_huya_user_behavior_d_i
--     where dt between '2025-08-04' and '2026-02-10'
--         and data_type = 'video_session'
--         and live_content_type = '视频'
--         and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
--         and game_id <> 2356
--         and game_name not in ('体育','台球')
--         and is_black_ukey = 0
--         and watch_cnt > 0
--     group by user_ukey
-- )

, dashang_agg as (
    select 
        a.ukey as user_ukey,
        sum(a.consume_amt) as total_consume_amt
    from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
    -- inner join first_time_video c 
    --     on a.ukey = b.user_ukey
    --     and a.dt >= c.first_video_time -- 打赏时间在首次观看视频之后
    inner join laxin_user b
        on a.ukey = b.user_ukey
    where a.dt between '2025-08-04' and '2026-02-10' --赛季结束后的180天
    group by 1
)

select 
    '电竞赛事整体' as match_name,
    count(distinct a.user_ukey) as total_laxin_user_cnt,           -- 拉新总人数
    round(sum(b.total_consume_amt), 2) as total_dashang_amt,    -- 打赏总金额
    count(distinct b.user_ukey) as dashang_user_cnt,               -- 打赏人数（去重）
    count(distinct b.user_ukey) / count(distinct a.user_ukey) as retention_rate,
    sum(b.total_consume_amt) / count(distinct b.user_ukey) as arppu
from laxin_user a
left join dashang_agg b
    on a.user_ukey = b.user_ukey