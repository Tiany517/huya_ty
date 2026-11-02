with match_info as (
  select
    day as dt,
    uid as luid
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where 
    dt = '2026-05-26'
    and day >= '2026-02-17' 
    and day <= '2026-02-22' -- 25球员锦标赛
)

, sinuoke_laxin_user_info as (
  select distinct
    b.user_ukey
  from match_info a
  inner join (
      select dt, luid, user_ukey
      from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 -- 宽口径拉新表
      where dt between '2026-02-17' and '2026-02-22' -- 赛事期间
          and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
  ) b 
  on a.dt = b.dt and a.luid = b.luid
)

-- 在首次付费
, pay_info as (
    select
      a.user_uid,
      b.ukey as user_ukey,
      min(a.dt) as first_pay_dt
    from gamelive.dws_huya_revenue_detail_d_i a 
    left join (
        select 
          a.yyuid,
          a.ukey
        from gamelive.dwt_huya_session_level a
        inner join sinuoke_laxin_user_info b
          on a.ukey = b.user_ukey
        where a.dt between '2026-02-17' and '2026-05-25' -- 球员锦标赛开始至昨日
          and a.tag = 'product' 
    ) b
    on a.user_uid = b.yyuid
    inner join sinuoke_laxin_user_info c 
      on b.ukey = c.user_ukey
    where 
      a.dt between '2026-02-17' and '2026-05-25' -- 球员锦标赛开始至昨日
      and a.game_label in ('游戏', '游戏专区')
    group by 
      a.user_uid,
      b.ukey
)



, user_watch_info as (
  select
    c.dt,
    case
      when c.dt between '2025-05-21' and '2025-06-01' then '赛事期间'
      when c.dt between '2025-06-30' and '2025-07-23' then '赛事期间'
      when c.dt between '2025-07-28' and '2025-08-03' then '赛事期间'
      when c.dt between '2025-08-08' and '2025-08-16' then '赛事期间'
      when c.dt between '2025-08-24' and '2025-08-30' then '赛事期间'
      when c.dt between '2025-09-15' and '2025-09-21' then '赛事期间'
      when c.dt between '2025-09-22' and '2025-09-28' then '赛事期间'
      when c.dt between '2025-10-07' and '2025-10-13' then '赛事期间'
      when c.dt between '2025-10-19' and '2025-10-26' then '赛事期间'
      when c.dt between '2025-11-02' and '2025-11-09' then '赛事期间'
      when c.dt between '2025-11-10' and '2025-11-16' then '赛事期间'
      when c.dt between '2025-11-29' and '2025-12-07' then '赛事期间'
      when c.dt between '2025-12-10' and '2025-12-13' then '赛事期间'
      when c.dt between '2025-12-15' and '2025-12-21' then '赛事期间'
      when c.dt between '2026-01-11' and '2026-01-18' then '赛事期间'
      when c.dt between '2026-01-26' and '2026-02-01' then '赛事期间'
      when c.dt between '2026-02-03' and '2026-02-08' then '赛事期间'
      when c.dt between '2026-02-17' and '2026-02-22' then '赛事期间' -- 球员锦标赛
      when c.dt between '2026-02-23' and '2026-03-01' then '赛事期间'
      when c.dt between '2026-03-16' and '2026-03-22' then '赛事期间'
      when c.dt between '2026-03-30' and '2026-04-05' then '赛事期间'
      when c.dt between '2026-04-18' and '2026-05-04' then '赛事期间'
      else '非赛事'
    end as is_match, 

    case
      when c.dt between '2025-05-21' and '2025-06-01' then 'Q School'
      when c.dt between '2025-06-30' and '2025-07-23' then '冠军联赛(排名赛)'
      when c.dt between '2025-07-28' and '2025-08-03' then '上海大师赛(邀请赛)'
      when c.dt between '2025-08-08' and '2025-08-16' then '沙特大师赛'
      when c.dt between '2025-08-24' and '2025-08-30' then '武汉公开赛'
      when c.dt between '2025-09-15' and '2025-09-21' then '英格兰公开赛'
      when c.dt between '2025-09-22' and '2025-09-28' then '英国公开赛'
      when c.dt between '2025-10-07' and '2025-10-13' then '西安大奖赛'
      when c.dt between '2025-10-19' and '2025-10-26' then '北爱尔兰公开赛'
      when c.dt between '2025-11-02' and '2025-11-09' then '国际锦标赛'
      when c.dt between '2025-11-10' and '2025-11-16' then '冠中冠(邀请赛)'
      when c.dt between '2025-11-29' and '2025-12-07' then '英锦赛'
      when c.dt between '2025-12-10' and '2025-12-13' then '单局限时赛'
      when c.dt between '2025-12-15' and '2025-12-21' then '苏格兰公开赛'
      when c.dt between '2026-01-11' and '2026-01-18' then '大师赛(邀请赛)'
      when c.dt between '2026-01-26' and '2026-02-01' then '德国大师赛'
      when c.dt between '2026-02-03' and '2026-02-08' then '世界大奖赛'
      when c.dt between '2026-02-17' and '2026-02-22' then '球员锦标赛'
      when c.dt between '2026-02-23' and '2026-03-01' then '威尔士公开赛'
      when c.dt between '2026-03-16' and '2026-03-22' then '世界公开赛'
      when c.dt between '2026-03-30' and '2026-04-05' then '巡回锦标赛'
      when c.dt between '2026-04-18' and '2026-05-04' then '世锦赛'
      else '非赛事'
    end as match_name,

    case
      when c.game_label in ('娱乐', '娱乐专区') then '娱乐'
      when c.game_label in ('游戏', '游戏专区') then '游戏'
      else '其他' 
    end as game_label,

    sum(c.watch_duration) as watch_duration
  from (
    select
        a.dt,
        a.user_ukey,
        a.game_label,
        sum(a.watch_duration) as watch_duration
    from gamelive.dws_huya_user_behavior_d_i a
    inner join sinuoke_laxin_user_info b -- 斯诺克的拉新用户
      on a.user_ukey = b.user_ukey
    inner join pay_info p -- 有过付费记录
      on a.user_ukey = p.user_ukey
    where 
      a.dt between '2026-02-17' and '2026-05-25' -- 球员锦标赛开始至昨日 
      and a.dt < P.first_pay_dt -- 要在游戏之前
    group by
      a.dt,
      a.user_ukey,
      a.game_label
  ) c
  group by
    c.dt,
    case
      when c.dt between '2025-05-21' and '2025-06-01' then '赛事期间'
      when c.dt between '2025-06-30' and '2025-07-23' then '赛事期间'
      when c.dt between '2025-07-28' and '2025-08-03' then '赛事期间'
      when c.dt between '2025-08-08' and '2025-08-16' then '赛事期间'
      when c.dt between '2025-08-24' and '2025-08-30' then '赛事期间'
      when c.dt between '2025-09-15' and '2025-09-21' then '赛事期间'
      when c.dt between '2025-09-22' and '2025-09-28' then '赛事期间'
      when c.dt between '2025-10-07' and '2025-10-13' then '赛事期间'
      when c.dt between '2025-10-19' and '2025-10-26' then '赛事期间'
      when c.dt between '2025-11-02' and '2025-11-09' then '赛事期间'
      when c.dt between '2025-11-10' and '2025-11-16' then '赛事期间'
      when c.dt between '2025-11-29' and '2025-12-07' then '赛事期间'
      when c.dt between '2025-12-10' and '2025-12-13' then '赛事期间'
      when c.dt between '2025-12-15' and '2025-12-21' then '赛事期间'
      when c.dt between '2026-01-11' and '2026-01-18' then '赛事期间'
      when c.dt between '2026-01-26' and '2026-02-01' then '赛事期间'
      when c.dt between '2026-02-03' and '2026-02-08' then '赛事期间'
      when c.dt between '2026-02-17' and '2026-02-22' then '赛事期间'
      when c.dt between '2026-02-23' and '2026-03-01' then '赛事期间'
      when c.dt between '2026-03-16' and '2026-03-22' then '赛事期间'
      when c.dt between '2026-03-30' and '2026-04-05' then '赛事期间'
      when c.dt between '2026-04-18' and '2026-05-04' then '赛事期间'
      else '非赛事'
    end,
    case
      when c.dt between '2025-05-21' and '2025-06-01' then 'Q School'
      when c.dt between '2025-06-30' and '2025-07-23' then '冠军联赛(排名赛)'
      when c.dt between '2025-07-28' and '2025-08-03' then '上海大师赛(邀请赛)'
      when c.dt between '2025-08-08' and '2025-08-16' then '沙特大师赛'
      when c.dt between '2025-08-24' and '2025-08-30' then '武汉公开赛'
      when c.dt between '2025-09-15' and '2025-09-21' then '英格兰公开赛'
      when c.dt between '2025-09-22' and '2025-09-28' then '英国公开赛'
      when c.dt between '2025-10-07' and '2025-10-13' then '西安大奖赛'
      when c.dt between '2025-10-19' and '2025-10-26' then '北爱尔兰公开赛'
      when c.dt between '2025-11-02' and '2025-11-09' then '国际锦标赛'
      when c.dt between '2025-11-10' and '2025-11-16' then '冠中冠(邀请赛)'
      when c.dt between '2025-11-29' and '2025-12-07' then '英锦赛'
      when c.dt between '2025-12-10' and '2025-12-13' then '单局限时赛'
      when c.dt between '2025-12-15' and '2025-12-21' then '苏格兰公开赛'
      when c.dt between '2026-01-11' and '2026-01-18' then '大师赛(邀请赛)'
      when c.dt between '2026-01-26' and '2026-02-01' then '德国大师赛'
      when c.dt between '2026-02-03' and '2026-02-08' then '世界大奖赛'
      when c.dt between '2026-02-17' and '2026-02-22' then '球员锦标赛'
      when c.dt between '2026-02-23' and '2026-03-01' then '威尔士公开赛'
      when c.dt between '2026-03-16' and '2026-03-22' then '世界公开赛'
      when c.dt between '2026-03-30' and '2026-04-05' then '巡回锦标赛'
      when c.dt between '2026-04-18' and '2026-05-04' then '世锦赛'
      else '非赛事'
    end,
    case
      when c.game_label in ('娱乐', '娱乐专区') then '娱乐'
      when c.game_label in ('游戏', '游戏专区') then '游戏'
      else '其他'
    end
)

select
    '游戏付费用户' as user_type,
    dt,
    is_match,
    match_name,
    game_label,
    watch_duration
from user_watch_info
