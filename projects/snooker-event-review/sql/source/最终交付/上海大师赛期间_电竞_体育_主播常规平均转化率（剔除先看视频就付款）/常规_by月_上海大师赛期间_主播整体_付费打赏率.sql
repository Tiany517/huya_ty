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
    and substr(date,1,10)>='2024-01-01'
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
        and gameid not in (2356) ---剔除体育主播
        group by 1,2,3
    ) a
    left join match_info b
    on a.luid = b.luid
    left join  copyright_match_info c
    on a.luid = c.luid
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


, dashang_agg as (
    select 
      substr(a.dt,1,7) as yearmonth,
      a.ukey as user_ukey,
      sum(a.consume_amt) as total_consume_amt
    from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
    where a.dt between '2025-08-04' and '2026-02-10' --英锦赛结束180天后
    group by 1,2
)

select 
    '主播整体' as match_name,
    b.yearmonth,
    (select count(distinct user_ukey) from laxin_user_info) as total_laxin_users,  -- 拉新总人数
    sum(b.total_consume_amt)  as total_dashang_amt,      -- 180天后总打赏金额
    count(distinct case when b.total_consume_amt > 0 then a.user_ukey end) as dashang_user_cnt,  -- 180天后打赏人数
    count(distinct case when b.total_consume_amt > 0 then a.user_ukey end) / (select count(distinct user_ukey) from laxin_user_info) as retention_rate,  -- 180天后打赏率
    sum(b.total_consume_amt) / count(distinct case when b.total_consume_amt > 0 then a.user_ukey end) as arppu
from laxin_user_info a
left join dashang_agg b
on a.user_ukey = b.user_ukey
group by 2
order by 2 asc