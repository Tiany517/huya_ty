with match_info as (
    select substr(a.date,1,10) as match_dt, a.uid as luid
    from gamelive.dwd_huya_dim_game_copyright_info_d_a a
    where a.dt='2026-05-18'
    and substr(date,1,10) between '2025-07-28' and '2025-08-03'
    and a.live_type like '%直播%'
    and a.room_type = '独立直播间'
    and a.content_type in ('游戏赛事')
    group by 1,2
)

, laxin_user as (
    select a.dt, a.user_ukey
    from zhgametemp.cxm_xinzeng_0413 a
    inner join match_info b on a.dt = b.match_dt and trim(a.luid) = trim(b.luid)
    where a.dt between '2025-07-28' and '2025-08-03'
    group by 1,2
)

, user_monthly_dashang as (
    select 
        substr(b.dt,1,7) as yearmonth,
        b.ukey as user_ukey,
        sum(b.consume_amt) as monthly_amt
    from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 b
    where b.dt between '2025-08-04' and '2026-02-10'
    group by 1,2
)

select 
    '电竞赛事整体' as match_name,
    b.yearmonth,
    
    -- 分母：所有拉新用户（每月都一样）
    (select count(distinct user_ukey) from laxin_user) as total_laxin_user_cnt,
    
    round(sum(b.monthly_amt), 2) as total_dashang_amt,
    
    -- 分子：该月有打赏的用户
    count(distinct case when b.monthly_amt > 0 then a.user_ukey end) as dashang_user_cnt,
    
    -- 留存率 = 该月打赏人数 / 总拉新人数
    count(distinct case when b.monthly_amt > 0 then a.user_ukey end)/ 
        (select count(distinct user_ukey) from laxin_user) as retention_rate,
    
    sum(b.monthly_amt) / nullif(count(distinct case when b.monthly_amt > 0 then a.user_ukey end), 0) as arppu

from laxin_user a
left join user_monthly_dashang b 
on a.user_ukey = b.user_ukey
group by 2
order by 2 asc