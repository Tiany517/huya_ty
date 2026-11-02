with user_info as (
    select distinct
      user_ukey,
      case
        when product in ('huya_android', 'huya_pad') then 'Android'
        when product in ('huya_ios', 'huya_ipad') then 'IOS'
        when product in ('hmos_kiwi') then 'Harmony'
        else 'else'
      end as device_os
    from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
    where dt between '2026-02-17' and '2026-02-22' -- 赛事期间
    and product in (
      'huya_andriod',
      'huya_ipad',
      'huya_pad',
      'huya_ios',
      'hmos_kiwi'
  )
)



, user_watch_info as (
  select
    c.dt,
    c.device_os,
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

    c.game_id,
    c.game_name,

    sum(c.watch_duration) as watch_duration
  from (
    select
        a.dt,
        a.user_ukey,
        b.device_os,
        a.game_label,
        a.game_id,
        a.game_name,
        sum(a.watch_duration) as watch_duration
    from gamelive.dws_huya_user_behavior_d_i a
    inner join user_info b 
      on a.user_ukey = b.user_ukey
    where 
      a.dt between '2026-02-01' and '2026-05-28' 
    group by
      a.dt,
      a.user_ukey,
      b.device_os,
      a.game_label,
      a.game_id,
      a.game_name
  ) c
  group by
    c.dt,
    c.device_os,
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
    end,
    c.game_id,
    c.game_name
)

select
    dt,
    device_os,
    is_match,
    match_name,
    game_label,
    game_id,
    game_name,
    watch_duration
from user_watch_info
