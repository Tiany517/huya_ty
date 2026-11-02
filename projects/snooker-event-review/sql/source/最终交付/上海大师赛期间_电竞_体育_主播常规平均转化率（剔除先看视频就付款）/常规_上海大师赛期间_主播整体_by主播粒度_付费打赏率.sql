with match_info as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a -- 体育赛事主播
  where dt = '2026-05-17' 
    and day >= '2025-07-28'
    and day <= '2025-08-03' -- 2025年上海大师赛期间
)

, copyright_match_info as (
    select 
        substr(a.date,1,10) as match_dt,
        a.uid as luid
    from gamelive.dwd_huya_dim_game_copyright_info_d_a a --赛事版权表 -- 版权赛事主播
    where a.dt='2026-05-17'
    and substr(date,1,10) between '2025-07-28' and '2025-08-03'
    and a.live_type like '%直播%' --只计算直播
    and a.room_type = '独立直播间' --官方直播间 
    -- and a.game_id = '2336' -- 王者荣耀
    -- and a.match_id in (9025409) -- 2025KPL夏季赛
    group by 1,2
)

, zhubo_info as (
    select
        a.dt,
        a.luid,
        a.nickname
        -- case 
        --     when a.acu >= 2000 then '头部主播'
        --     when a.acu >= 100 and acu <= 2000 then '腰部主播'
        --     when a.acu < 100 then '尾部主播'
        --     else '未知'
        -- end as zhubo_level,
        -- sum(a.live_mins) as total_live_mins
    from (    
        select 
            dt, 
            ayyuid as luid, 
            nickname
            -- coalesce(avg(acu),0) as acu
            -- sum(live_mins) as live_mins
        from gamelive.dm_huya_ayyuid_detail_day t1  -- 主播直播明细表
        -- left join (select nick, yyid, uid from gamelive.dim_huya_ayyuid_info where dt = '2025-07-03') t2 on t1.ayyuid = t2.uid
        where dt between '2025-07-28' and '2025-08-03' --英锦赛期间开播的主播
        and 
            -- 1663 星秀，2165 户外， 2356 体育
            gameid not in (1663, 2165, 2356) ---剔除体育主播
        group by 1,2,3
    ) a
    left join match_info b
    on a.luid = b.luid
    -- and a.dt = b.dt
    left join  copyright_match_info c
    on a.luid = c.luid
    -- and a.dt = c.match_dt
    where 
      b.luid is null -- 剔除体育赛事主播
      and c.luid is null -- 剔除游戏赛事主播
    group by 1,2,3
)


, laxin_user_info as ( ---拉新用户
    select 
        a.luid,
        a.nickname,
        -- a.zhubo_level,
        -- coalesce(a.total_live_mins, 0) as total_live_mins,
        b.user_ukey as user_ukey
    from zhubo_info a
    inner join (
        select dt, luid, user_ukey 
        from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 -- 宽口径内容拉新表
        where dt between '2025-07-28' and '2025-08-03' --英锦赛期间拉新的用户
            and user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
    ) b
    on a.dt = b.dt and a.luid = b.luid
    group by 1,2,3
)

-- , first_time_video as(
--   select
--       user_ukey, 
--       min(dt) as first_live_dt
--   from gamelive.dws_huya_user_behavior_d_i
--   where dt between '2025-08-04' and '2026-02-10'
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
        a.luid,
        a.nickname,
        a.user_ukey,
        sum(b.consume_amt) as total_consume_amt
    from laxin_user_info a
    left join zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 b
    on a.user_ukey = b.ukey
        and b.dt between '2025-08-04' and '2026-02-10'  -- ✅ 放在 ON 条件里，先过滤把需要的的打赏数据过滤出来，在join，而不是等连接完再过滤，这样留存数据都1
    group by 1,2,3
)

select 
    '主播整体' as match_name,
    b.luid,
    b.nickname,
    count(distinct a.user_ukey) as total_laxin_users,  -- 拉新总人数
    round(sum(b.total_consume_amt), 2) as total_dashang_amt,      -- 180天后总打赏金额
    count(distinct case when b.total_consume_amt > 0 then b.user_ukey end) as dashang_user_cnt,  -- 180天后打赏人数
    count(distinct case when b.total_consume_amt > 0 then b.user_ukey end) / count(distinct a.user_ukey) as retention_rate,  -- 180天后打赏率
    sum(b.total_consume_amt) / count(distinct case when b.total_consume_amt > 0 then b.user_ukey end) as arppu
from laxin_user_info a
left join dashang_agg b
on a.user_ukey = b.user_ukey
-- where a.zhubo_level in ('头部主播')
group by 1,2,3
order by 4 desc, 7 desc