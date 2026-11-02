-- ========================================
-- LOL_LPL春季赛第一赛段
-- ========================================
with match_info_lpl as (
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
    and a.game_id = '1' -- 英雄联盟
    and a.match_id in (9029201) -- LPL春季赛第一赛段
    group by 
        1,2,3,4,5,6
)
, lpl_spring_laxin_user as (
    select 
        a.dt, 
        b.game_full_name,
        b.match_id,
        b.match_name,
        a.user_ukey as user_ukey
    from zhgametemp.cxm_xinzeng_0413 a  -- 拉新用户表
    inner join 
        match_info_lpl b 
    on 
        a.dt = b.match_dt              -- 日期关联
        and trim(a.luid) = trim(b.uid) -- 主播关联
    where a.dt >= '2024-09-01'         -- 拉新时间限制
    group by 1,2,3,4,5
)
, dashang_agg_lpl as (
    select 
        a.ukey as user_ukey,
        sum(a.consume_amt) as total_consume_amt
    from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
    inner join lpl_spring_laxin_user b
        on a.ukey = b.user_ukey
    where a.dt between '2026-01-14' and '2026-03-08' -- LPL春季赛第一赛段日期
    group by 1
)


-- ========================================
-- LOL_LPL春季赛第二赛段
-- ========================================

,match_info_lpl_2 as (
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
    and a.game_id = '1' -- 英雄联盟
    and a.match_id in (9029203) -- LPL春季赛第二赛段
    group by 
        1,2,3,4,5,6
)
, lpl_spring_2_laxin_user as (
    select 
        a.dt, 
        b.game_full_name,
        b.match_id,
        b.match_name,
        a.user_ukey as user_ukey
    from zhgametemp.cxm_xinzeng_0413 a  -- 拉新用户表
    inner join 
        match_info_lpl_2 b 
    on 
        a.dt = b.match_dt              -- 日期关联
        and trim(a.luid) = trim(b.uid) -- 主播关联
    where a.dt >= '2024-09-01'         -- 拉新时间限制
    group by 1,2,3,4,5
)
, dashang_agg_lpl_2 as (
    select 
        a.ukey as user_ukey,
        sum(a.consume_amt) as total_consume_amt
    from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
    inner join lpl_spring_2_laxin_user b
        on a.ukey = b.user_ukey
    where a.dt between '2026-04-04' and '2026-05-10' -- LPL春季赛第二赛段日期
    group by 1
)



-- ========================================
-- LOL_全球先锋赛
-- ========================================
, match_info_xianfeng as (
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
    and a.game_id = '1' -- 英雄联盟
    and a.match_id in (9029202) -- 2026全球先锋赛
    group by 
        1,2,3,4,5,6
)
, xianfeng_spring_laxin_user as (
    select 
        a.dt, 
        b.game_full_name,
        b.match_id,
        b.match_name,
        a.user_ukey as user_ukey
    from zhgametemp.cxm_xinzeng_0413 a  -- 拉新用户表
    inner join 
        match_info_xianfeng b 
    on 
        a.dt = b.match_dt              -- 日期关联
        and trim(a.luid) = trim(b.uid) -- 主播关联
    where a.dt >= '2024-09-01'         -- 拉新时间限制
    group by 1,2,3,4,5
)
, dashang_agg_xianfeng as (
    select 
        a.ukey as user_ukey,
        sum(a.consume_amt) as total_consume_amt
    from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
    inner join xianfeng_spring_laxin_user b
        on a.ukey = b.user_ukey
    where a.dt between '2026-03-16' and '2026-03-22' -- 全球先锋赛日期
    group by 1
)


-- ========================================
-- 王者_2026KPL春季赛
-- ========================================
,match_info_kpl_spring as (
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
    and a.game_id = '2336' -- 王者荣耀
    and a.match_id in (9029401) -- 王者2026KPL春季赛
    group by 
        1,2,3,4,5,6
)
, kpl_spring_laxin_user as (
    select 
        a.dt, 
        b.game_full_name,
        b.match_id,
        b.match_name,
        a.user_ukey as user_ukey
    from zhgametemp.cxm_xinzeng_0413 a  -- 拉新用户表
    inner join 
        match_info_kpl_spring b 
    on 
        a.dt = b.match_dt              -- 日期关联
        and trim(a.luid) = trim(b.uid) -- 主播关联
    where a.dt >= '2024-09-01'         -- 拉新时间限制
    group by 1,2,3,4,5
)
, dashang_agg_kpl as (
    select 
        a.ukey as user_ukey,
        sum(a.consume_amt) as total_consume_amt
    from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
    inner join kpl_spring_laxin_user b
        on a.ukey = b.user_ukey
    where a.dt between '2026-01-14' and '2026-04-11' -- KPL春季赛日期
    group by 1
)


-- ========================================
-- 斯诺克_2026斯诺克世界锦标赛
-- ========================================
, match_info_snooker as (
  select day as dt, uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a --体育运动直播表
  where dt = '2026-05-11'
    and day >= '2026-04-18'
    and day <= '2026-05-04'
)

, snooker_laxin_user as (
    select 
        b.user_ukey
    from match_info_snooker a
    inner join (
        select dt, luid, user_ukey, game_id, game_name
        from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1
        where dt between '2026-04-18' and '2026-05-04'  -- 修正空格
            and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
    ) b on a.dt = b.dt and a.luid = b.luid
    group by 1
)

, dashang_agg_snooker as (
  select 
    a.ukey as user_ukey,             
    sum(a.consume_amt) as total_consume_amt
  from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2 a
  inner join snooker_laxin_user b        
    on a.ukey = b.user_ukey 
  where a.dt between '2026-04-18' and '2026-05-04'
    and a.consume_amt > 0
  group by a.ukey
)




-- ========================================
-- 总计算
-- ========================================

select 
    'LOL' as game_name,
    'LPL_1' as league_type,
    '2026.01.14 - 2026.03.08' as time_label,
    match_name,
    match_id,
    count(distinct a.user_ukey) as total_laxin_users,  -- 拉新总人数
    round(sum(b.total_consume_amt), 2) as total_consume_amt,      -- 赛事期间打赏总金额
    count(distinct case when b.total_consume_amt > 0 then b.user_ukey end) as total_rewarded_users,  -- 赛事期间打赏人数
    count(distinct case when b.total_consume_amt > 0 then b.user_ukey end) * 1.0 / count(distinct a.user_ukey) as reward_rate  -- 赛事期间打赏率
from lpl_spring_laxin_user a
left join dashang_agg_lpl b
on a.user_ukey = b.user_ukey
group by  1,2,3,4,5


union all


select 
    'LOL' as game_name,
    'LPL_2' as league_type,
    '2026.04.04 - 2026.05.10' as time_label,
    match_name,
    match_id,
    count(distinct a.user_ukey) as total_laxin_users,  -- 拉新总人数
    round(sum(b.total_consume_amt), 2) as total_consume_amt,      -- 赛事期间打赏总金额
    count(distinct case when b.total_consume_amt > 0 then b.user_ukey end) as total_rewarded_users,  -- 赛事期间打赏人数
    count(distinct case when b.total_consume_amt > 0 then b.user_ukey end) * 1.0 / count(distinct a.user_ukey) as reward_rate  -- 赛事期间打赏率
from lpl_spring_2_laxin_user a
left join dashang_agg_lpl_2 b
on a.user_ukey = b.user_ukey
group by  1,2,3,4,5

union all

select 
    'LOL' as game_name,
    '全球先锋赛' as league_type,
    '2026.03.16 - 2026.03.22' as time_label,
    match_name,
    match_id,
    count(distinct a.user_ukey) as total_laxin_users,  -- 拉新总人数
    round(sum(b.total_consume_amt), 2) as total_consume_amt,      -- 赛事期间打赏总金额
    count(distinct case when b.total_consume_amt > 0 then b.user_ukey end) as total_rewarded_users,  -- 赛事期间打赏人数
    count(distinct case when b.total_consume_amt > 0 then b.user_ukey end) * 1.0 / count(distinct a.user_ukey) as reward_rate  -- 赛事期间打赏率
from xianfeng_spring_laxin_user a
left join dashang_agg_xianfeng b
on a.user_ukey = b.user_ukey
group by 1,2,3,4,5

union all

select 
    '王者荣耀' as game_name,
    '2026KPL春季赛' as league_type,
    '2026.01.14 - 2026.04.11' as time_label,
    match_name,
    match_id,
    count(distinct a.user_ukey) as total_laxin_users,  -- 拉新总人数
    round(sum(b.total_consume_amt), 2) as total_consume_amt,      -- 赛事期间打赏总金额
    count(distinct case when b.total_consume_amt > 0 then b.user_ukey end) as total_rewarded_users,  -- 赛事期间打赏人数
    count(distinct case when b.total_consume_amt > 0 then b.user_ukey end) * 1.0 / count(distinct a.user_ukey) as reward_rate  -- 赛事期间打赏率
from kpl_spring_laxin_user a
left join dashang_agg_kpl b
on a.user_ukey = b.user_ukey
group by  1,2,3,4,5


union all

select 
    '斯诺克' as game_name,
    '2026斯诺克世界锦标赛' as league_type,
    '2026.04.18 - 2026.05.04' as time_label,
    '2026斯诺克世界锦标赛' as match_name, 
    'snooker_2026' as match_id,  
    count(distinct a.user_ukey) as total_laxin_users,  -- 拉新总人数
    round(sum(b.total_consume_amt), 2) as total_consume_amt,      -- 赛事期间打赏总金额
    count(distinct case when b.total_consume_amt > 0 then b.user_ukey end) as total_rewarded_users,  -- 赛事期间打赏人数
    count(distinct case when b.total_consume_amt > 0 then b.user_ukey end) * 1.0 / count(distinct a.user_ukey) as reward_rate  -- 赛事期间打赏率
from snooker_laxin_user a
left join dashang_agg_snooker b
on a.user_ukey = b.user_ukey
group by 1,2,3,4,5