with match_info as (
    select 
        substr(a.date,1,10) as match_dt,
        a.match_name,
        a.match_id, 
        b.game_full_name, 
        a.uid, -- luid
        c.nick
    from gamelive.dwd_huya_dim_game_copyright_info_d_a a --赛事版权表
    left join (
        select gid, game_full_name 
        from gamelive.to_main_games_day --游戏信息底表
        where dt = '2026-05-11' 
    ) b on a.game_id = b.gid
    left join (
        select nick, yyid, uid  -- nick昵称和uid的对应关系表
        from gamelive.dim_huya_ayyuid_info -- 虎牙主播表
        where dt = '2026-05-11'
    ) c on a.uid = c.uid
    where a.dt='2026-05-11'
    and substr(date,1,10)>='2024-01-01'
    -- and substr(date,1,10)<='2024-07-08'
    and a.live_type like '%直播%' --只计算直播
    and a.room_type = '独立直播间' --官方直播间 
    -- and a.game_id = '1' -- 英雄联盟
    -- and a.match_id in (9029201) -- LPL春季赛第一赛段
    group by 
        1,2,3,4,5,6
)


, zhubo_info as (
    select
        a.dt,
        a.luid,
        a.nickname,
        case 
            when a.acu >= 2000 then '头部主播'
            when a.acu >= 100 and acu <= 2000 then '腰部主播'
            when a.acu < 100 then '尾部主播'
            else '未知'
        end as zhubo_level,
        sum(a.live_mins) as total_live_mins
    from (    
        select 
            dt, 
            ayyuid as luid, 
            nickname,
            coalesce(avg(acu),0) as acu, 
            sum(live_mins) as live_mins
        from gamelive.dm_huya_ayyuid_detail_day t1 
        -- left join (select nick, yyid, uid from gamelive.dim_huya_ayyuid_info where dt = '2025-07-03') t2 on t1.ayyuid = t2.uid
        where dt between '2025-11-29' and '2025-12-07' --英锦赛期间开播的主播
        and gameid not in (2356) ---剔除体育主播
        group by 1,2,3
    ) a
    left join match_info b
    on a.luid = b.uid 
    where b.uid is null -- 剔除赛事主播
    group by 1,2,3,4
)


, laxin_user_info as ( ---拉新用户
    select 
        a.luid,
        a.nickname,
        a.zhubo_level,
        coalesce(a.total_live_mins, 0) as total_live_mins,
        b.user_ukey as user_ukey
    from zhubo_info a
    inner join (
        select dt, luid, user_ukey 
        from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 -- 宽口径内容拉新表
        where dt between '2025-11-29' and '2025-12-07' --英锦赛期间拉新的用户
            and user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
    ) b
    on a.dt = b.dt and a.luid = b.luid
    group by 1,2,3,4,5
)


, dashang_agg as (
    select 
        a.ukey as user_ukey,
        sum(a.consume_amt) as total_consume_amt
    from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
    inner join laxin_user_info b
        on a.ukey = b.user_ukey
    where a.dt between '2025-12-08' and '2026-06-06' --英锦赛结束180天后
    group by 1
)

,detail_info as (
    select 
        '2025.12.08 - 2026.06.06' as time_label,
        a.zhubo_level,  -- 主播等级
        a.luid,  -- 主播uid
        a.nickname,
        round(sum(a.total_live_mins),2) as total_live_mins,  -- 直播总时长
        count(distinct a.user_ukey) as total_laxin_users,  -- 拉新总人数
        round(sum(b.total_consume_amt), 2) as total_consume_amt,      -- 180天后总打赏金额
        count(distinct case when b.total_consume_amt > 0 then a.user_ukey end) as total_rewarded_users,  -- 180天后打赏人数
        count(distinct case when b.total_consume_amt > 0 then a.user_ukey end) * 1.0 / count(distinct a.user_ukey) as reward_rate  -- 180天后打赏率
    from laxin_user_info a
    left join dashang_agg b
    on a.user_ukey = b.user_ukey
    -- where a.zhubo_level in ('头部主播')
    group by 1,2,3,4
    -- order by 9 desc
)


select distinct
  time_label,
  zhubo_level,  -- 主播等级
  avg(reward_rate) over (partition by zhubo_level) as avg_reward_rate, 
  avg(total_laxin_users) over (partition by zhubo_level) as avg_laxin_users_num,
  avg(total_rewarded_users) over (partition by zhubo_level) as avg_rewarded_users_num,
  avg(total_consume_amt) over (partition by zhubo_level) as avg_consume_amt
from detail_info
order by 3 desc