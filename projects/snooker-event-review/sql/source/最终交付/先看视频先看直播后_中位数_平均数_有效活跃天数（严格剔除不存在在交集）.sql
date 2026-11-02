    -- ========================================
    -- 简化版：两条路径 + 漏斗间有效活跃天数
    -- ========================================

    with match_info as (
    select day as dt, uid as luid
    from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
    where dt = '2026-05-17' 
        and day >= '2025-07-28'
        and day <= '2025-08-03'
    )

    , laxin_user_info as (
        select distinct b.user_ukey
        from match_info a
        inner join (
            select dt, luid, user_ukey
            from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
            where dt between '2025-07-28' and '2025-08-03'
                and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        ) b on a.dt = b.dt and a.luid = b.luid
    )

    -- ========================================
    -- 1. 赛事期间首次行为
    -- ========================================
    , first_video_time as (
        select user_ukey, min(dt) as first_video_dt
        from gamelive.dws_huya_user_behavior_d_i
        where dt between '2025-07-28' and '2025-08-03'
            and data_type = 'video_session'
            and live_content_type = '视频'
            and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
            and game_id <> 2356
            and game_name not in ('体育','台球')
            and is_black_ukey = 0
            and watch_cnt > 0
        group by user_ukey
    )

    , first_live_time as (
        select user_ukey, min(dt) as first_live_dt
        from gamelive.dws_huya_user_behavior_d_i
        where dt between '2025-07-28' and '2025-08-03'
            and data_type = 'live_watch_session'
            and live_content_type = '直播'
            and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
            and game_id <> 2356
            and game_name not in ('体育','台球')
            and is_black_ukey = 0
            and watch_cnt > 0
        group by user_ukey
    )

    -- ========================================
    -- 2. 用户路径分类
    -- ========================================
    , user_type as (
        select 
            a.user_ukey,
            case 
                when v.first_video_dt is not null and l.first_live_dt is not null 
                    and v.first_video_dt < l.first_live_dt then '先看视频'
                when v.first_video_dt is not null and l.first_live_dt is not null 
                    and l.first_live_dt < v.first_video_dt then '先看直播'
                else null
            end as first_behavior,
            v.first_video_dt,
            l.first_live_dt
        from laxin_user_info a
        left join first_video_time v on a.user_ukey = v.user_ukey
        left join first_live_time l on a.user_ukey = l.user_ukey
    )

    , video_first_users as (
        select user_ukey, first_video_dt, first_live_dt
        from user_type 
        where first_behavior = '先看视频'
    )

    , live_first_users as (
        select user_ukey, first_video_dt, first_live_dt
        from user_type 
        where first_behavior = '先看直播'
    )

    -- ========================================
    -- 3. 先看视频路径：视频 → 星秀 → 打赏
    -- ========================================

    -- 3.1 视频到星秀：计算首次看星秀前的活跃天数
    , video_xinxiu as (
        select 
            a.user_ukey,
            min(a.dt) as xinxiu_dt  -- 首次看星秀日期
        from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
        inner join video_first_users b on a.user_ukey = b.user_ukey
        where a.dt >= b.first_video_dt
            and a.dt between '2025-08-04' and '2026-01-31'
            and a.tag = 'gameid'
            and a.htime = 'session'
            and a.user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
            and a.igameid = 1663
            and a.user_duration > 0
        group by a.user_ukey
    )

    -- 3.2 【新增】视频 → 星秀 之间的有效活跃天数（在行为表内统计）
    , video_to_xinxiu_active_days as (
        select 
            b.user_ukey,
            -- 关键：统计首次看视频之后、首次看星秀之前，在行为表内的活跃天数（去重日期）
            count(distinct a.dt) as active_days
        from video_first_users b
        -- 关联行为表，取首次视频到首次星秀之间的行为
        inner join gamelive.dws_huya_user_behavior_d_i a
            on a.user_ukey = b.user_ukey
            -- 只看首次视频当天及之后
            and a.dt >= b.first_video_dt
            -- 只看首次星秀当天及之前（如果已到达星秀）
            and a.dt <= coalesce(
                (select min(x.xinxiu_dt) from video_xinxiu x where x.user_ukey = b.user_ukey),
                '2026-01-31'  -- 如果还没到星秀，取最大日期
            )
        where a.dt between '2025-07-28' and '2026-01-31'
            and a.product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
            and a.is_black_ukey = 0
        group by b.user_ukey
    )

    -- 3.3 星秀到打赏
    , video_dashang as (
        select 
            a.ukey as user_ukey,
            min(a.dt) as dashang_dt  -- 首次打赏日期
        from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
        inner join video_xinxiu b on a.ukey = b.user_ukey
        where a.dt >= b.xinxiu_dt
            and a.dt between '2025-08-04' and '2026-01-31'
            and a.consume_amt > 0
        group by a.ukey
    )

    -- 3.4 【新增】星秀 → 打赏 之间的有效活跃天数（在行为表内统计）
    , xinxiu_to_dashang_active_days as (
        select 
            b.user_ukey,
            -- 关键：统计首次看星秀之后、首次打赏之前，在行为表内的活跃天数（去重日期）
            count(distinct a.dt) as active_days
        from video_xinxiu b
        -- 关联行为表，取首次星秀到首次打赏之间的行为
        inner join gamelive.dws_huya_user_behavior_d_i a
            on a.user_ukey = b.user_ukey
            -- 只看首次星秀当天及之后
            and a.dt >= b.xinxiu_dt
            -- 只看首次打赏当天及之前（如果已打赏）
            and a.dt <= coalesce(
                (select min(d.dashang_dt) from video_dashang d where d.user_ukey = b.user_ukey),
                '2026-01-31'  -- 如果还没打赏，取最大日期
            )
        where a.dt between '2025-07-28' and '2026-01-31'
            and a.product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
            and a.is_black_ukey = 0
        group by b.user_ukey
    )

    -- ========================================
    -- 4. 先看直播路径：直播 → 星秀 → 打赏
    -- ========================================

    -- 4.1 直播到星秀
    , live_xinxiu as (
        select 
            a.user_ukey,
            min(a.dt) as xinxiu_dt
        from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
        inner join live_first_users b on a.user_ukey = b.user_ukey
        where a.dt >= b.first_live_dt
            and a.dt between '2025-08-04' and '2026-01-31'
            and a.tag = 'gameid'
            and a.htime = 'session'
            and a.user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
            and a.igameid = 1663
            and a.user_duration > 0
        group by a.user_ukey
    )

    -- 4.2 【新增】直播 → 星秀 之间的有效活跃天数
    , live_to_xinxiu_active_days as (
        select 
            b.user_ukey,
            count(distinct a.dt) as active_days
        from live_first_users b
        inner join gamelive.dws_huya_user_behavior_d_i a
            on a.user_ukey = b.user_ukey
            and a.dt >= b.first_live_dt
            and a.dt <= coalesce(
                (select min(x.xinxiu_dt) from live_xinxiu x where x.user_ukey = b.user_ukey),
                '2026-01-31'
            )
        where a.dt between '2025-07-28' and '2026-01-31'
            and a.product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
            and a.is_black_ukey = 0
        group by b.user_ukey
    )

    -- 4.3 星秀到打赏
    , live_dashang as (
        select 
            a.ukey as user_ukey,
            min(a.dt) as dashang_dt
        from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
        inner join live_xinxiu b on a.ukey = b.user_ukey
        where a.dt >= b.xinxiu_dt
            and a.dt between '2025-08-04' and '2026-01-31'
            and a.consume_amt > 0
        group by a.ukey
    )

    -- 4.4 【新增】星秀 → 打赏 之间的有效活跃天数
    , live_xinxiu_to_dashang_active_days as (
        select 
            b.user_ukey,
            count(distinct a.dt) as active_days
        from live_xinxiu b
        inner join gamelive.dws_huya_user_behavior_d_i a
            on a.user_ukey = b.user_ukey
            and a.dt >= b.xinxiu_dt
            and a.dt <= coalesce(
                (select min(d.dashang_dt) from live_dashang d where d.user_ukey = b.user_ukey),
                '2026-01-31'
            )
        where a.dt between '2025-07-28' and '2026-01-31'
            and a.product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
            and a.is_black_ukey = 0
        group by b.user_ukey
    )

    -- ========================================
    -- 5. 最终输出：有效活跃天数
    -- ========================================

    -- 先看视频路径
    select
        '先看视频' as user_group,
        -- 视频 → 星秀 之间的有效活跃天数（中位数）
        approx_percentile(vx.active_days, 0.5) as median_video_to_xinxiu_days,
        -- 星秀 → 打赏 之间的有效活跃天数（中位数）
        approx_percentile(xd.active_days, 0.5) as median_xinxiu_to_dashang_days,
        -- 视频 → 星秀 之间的有效活跃天数（平均数）
        avg(vx.active_days) as avg_video_to_xinxiu_days,
        -- 星秀 → 打赏 之间的有效活跃天数（平均数）
        avg(xd.active_days) as avg_xinxiu_to_dashang_days
    from video_first_users a
    left join video_to_xinxiu_active_days vx on a.user_ukey = vx.user_ukey
    left join xinxiu_to_dashang_active_days xd on a.user_ukey = xd.user_ukey
    where exists (select 1 from video_xinxiu x where x.user_ukey = a.user_ukey)

    union all

    -- 先看直播路径
    select
        '先看直播' as user_group,
        -- 直播 → 星秀 之间的有效活跃天数（中位数）
        approx_percentile(lx.active_days, 0.5) as median_video_to_xinxiu_days,
        -- 星秀 → 打赏 之间的有效活跃天数（中位数）
        approx_percentile(ld.active_days, 0.5) as median_xinxiu_to_dashang_days,
        -- 直播 → 星秀 之间的有效活跃天数（平均数）
        avg(lx.active_days) as avg_video_to_xinxiu_days,
        -- 星秀 → 打赏 之间的有效活跃天数（平均数）
        avg(ld.active_days) as avg_xinxiu_to_dashang_days
    from live_first_users a
    left join live_to_xinxiu_active_days lx on a.user_ukey = lx.user_ukey
    left join live_xinxiu_to_dashang_active_days ld on a.user_ukey = ld.user_ukey
    where exists (select 1 from live_xinxiu x where x.user_ukey = a.user_ukey); 