with livestream_user_info as (
  select
      dt,
      user_ukey,
      sum(watch_duration) as live_watch_duration
  from gamelive.dws_huya_user_behavior_d_i
  where 
      product in ('huya_andriod','huya_ios','hmos_kiwi')
      and data_type = 'live_watch_session'
      and live_content_type = '直播'
      and watch_cnt > 0
      and (
          (
              creator_uid in (1239543466013, 1239543466014, 1531433300, 1259527226795, 585199800)
              and dt = '2026-06-14'
          )
          or
          (
              creator_uid in (1199568157971) --童锦程
              and dt between '2026-06-16' and '2026-06-17' --固定：童锦程世界杯期间直播日期
          )
      )
  group by 
      dt, user_ukey
),

video_user_info as (
  select
      dt,
      user_ukey,
      sum(watch_duration) as video_watch_duration
  from gamelive.dws_huya_user_behavior_d_i
  where 
      dt = '2026-06-14'
      and product in ('huya_andriod','huya_ios','hmos_kiwi')
      and data_type = 'video_session'
      and live_content_type = '视频'
      and content_id <> 0
      and vid_can_play = 1
      and watch_cnt > 0
      and (implicit_tags like '%美加墨世界杯%' or implicit_tags like '%世界杯%')
  group by 
      dt, user_ukey
),

-- 3.1 投注原始数据
betting_user_info as (
  select
    dt,
    uid,
    sum(cast(cnt as double)) as uid_bet_cnt,
    sum(1) as uid_bet_pv
  from gamelive.dwd_huya_predicting_game_pay_option_detail_d_i
  where cnt > 0
    and dt = '2026-06-14'
    and bet_pid in ('10748220','2367547387','1199630339535','1199652774074','294636272','1575250000','2272316519','1199568157971','1867489698','1279518938631','1014447803','1860008570','1531433300','1199526826004','1486343265','500066171','1661091641','1589657344','1509413742','2381472418','1191588902','1199656029798','1677942333','1279515529757','1271256459','1182498550','1199585096447','1636999467','1852594244','1279513816099','1607888466','1259517233171','1199659485620','9284975','20852986','1784500555','1199599175963','1199548593898','103291603','1062203607','1199661106293','1199641333987','1199602377745','1199655480461','1199610004865','1558173124','1279542841394','1259527226795','1199590843647','1199657592299','1199642042189','1199614292524','1199628311699','1199657141334','1279527609081','2373515260','585199800','1239543466013','1239543466014','1001276654')
  group by dt, uid
),

-- 3.2 投注按dt聚合
betting_by_dt as (
  select
    dt,
    count(distinct uid) as bet_uid_uv,
    sum(uid_bet_cnt) as bet_cnt,
    sum(uid_bet_pv) as bet_pv
  from betting_user_info 
  group by dt
),

-- 3.3 投注用户关联的UKEY（用于计算投注DAU）
bet_user_ukey as (
  select distinct
    a.dt,
    b.ukey as user_ukey
  from betting_user_info a
  left join (
    select yyuid, ukey
    from (
      select
        yyuid,
        ukey,
        row_number() over(partition by yyuid order by end_time desc) as rn
      from gamelive.dwt_huya_session_level
      where dt >= '2026-01-01'
        and length(dt) = 10
        and tag = 'product'
    ) t
    where rn = 1
  ) b
    on a.uid = b.yyuid
  where b.ukey is not null
),

-- 4.1 直播DAU和观看时长
live_by_dt as (
  select
    dt,
    count(distinct user_ukey) as live_user_cnt,
    sum(live_watch_duration) as live_watch_duration
  from livestream_user_info
  group by dt
),

-- 4.2 视频DAU和观看时长
video_by_dt as (
  select
    dt,
    count(distinct user_ukey) as video_user_cnt,
    sum(video_watch_duration) as video_watch_duration
  from video_user_info
  group by dt
),

-- 4.3 投注DAU（UKEY去重）
bet_dau_by_dt as (
  select
    dt,
    count(distinct user_ukey) as bet_user_cnt
  from bet_user_ukey
  group by dt
),

-- 4.4 总DAU（直播 + 视频 + 投注 三个渠道UKEY去重）
total_dau as (
  select
    dt,
    count(distinct user_ukey) as total_user_cnt
  from (
    select dt, user_ukey from livestream_user_info
    union
    select dt, user_ukey from video_user_info
    union
    select dt, user_ukey from bet_user_ukey
  )
  group by dt
)


select
  a.dt,
  -- DAU指标
  b.live_user_cnt,
  a.video_user_cnt,
  d.bet_user_cnt,
  c.total_user_cnt,
  -- 观看时长
  b.live_watch_duration,
  a.video_watch_duration,
  -- 投注指标（UID粒度）
  e.bet_uid_uv,
  e.bet_cnt as user_bet_cnt,
  e.bet_pv as user_bet_pv
from video_by_dt a
left join live_by_dt b 
  on a.dt = b.dt
left join total_dau c 
  on a.dt = c.dt
left join bet_dau_by_dt d 
  on a.dt = d.dt
left join betting_by_dt e 
  on a.dt = e.dt