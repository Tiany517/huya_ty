with wx_anchor_day as (
  select
      a.dt,
      substr(a.dt, 1, 7) as month,
      b.creator_uid as luid,
      a.userid,
      sum(cast(a.audiencecnt as bigint)) as dau
  from gamelive.dwd_spider_wxmcn_anchor_livedata_list_d_i a
  left join (
      select
          pid as creator_uid,
          vx_vedio_id
      from gamelive.ods_live_huya_vedio_stream_push_conf_1760614652931321858
      where dt = date_format(
          date_add('day', -1, current_date),
          '%Y-%m-%d'
      )
      group by
          pid,
          vx_vedio_id
  ) b
      on a.userid = b.vx_vedio_id
  where a.dt >= '2026-06-01'
    and a.dt <= '2026-08-18'
    and cast(a.onlinetimeduration as double) > 0
    and b.creator_uid is not null
  group by
      a.dt,
      substr(a.dt, 1, 7),
      b.creator_uid,
      a.userid
),

huya_anchor_day as (
  select
      dt,
      luid,
      sum(
          cast(online_duration as double) / 1000 / 3600
      ) as online_duration_huya
  from gamelive.dwt_huya_ayyuid_session_from_server_no_user
  where dt >= '2026-06-01'
    and dt <= '2026-08-18'
    and length(dt) = 10
    and tag = 'gameid'
    and htime = 'session'
  group by
      dt,
      luid
),

-- 按视频号实际有数据的日期，统计每月有效天数
month_days as (
  select
    month,
    count(distinct dt) as observed_days
  from wx_anchor_day
  group by
      month
)

select
  a.month,
  case
      when coalesce(c.online_duration_huya, 0) > 0
          then '双播'
      else '单播'
  end as luid_type,
  a.luid,
  b.nick,
  b.game_id as belong_game_id,
  b.game_name as belong_game_name,
  sum(a.dau) * 1.0000 / max(m.observed_days) as dau,
  sum(a.dau) * 1.0000
      / max(m.observed_days)
      * 0.26 as dau_youxiao,
  count(distinct a.dt) as live_days,
  max(m.observed_days) as observed_days
from wx_anchor_day a
left join (
    select
        luid,
        nick,
        igameid as game_id,
        game_name
    from (
        select
            luid,
            nick,
            igameid,
            game_name,
            dt,
            row_number() over (
                partition by luid
                order by dt desc
            ) as rn
        from zhgametemp.cwq_huya_ukey_shichang_luid_gameid_guishu_day_v1
        where dt >= '2025-01-01'
    ) t
    where rn = 1
) b
    on a.luid = b.luid

left join huya_anchor_day c
    on a.dt = c.dt
   and a.luid = c.luid

inner join month_days m
    on a.month = m.month

group by
    a.month,
    case
        when coalesce(c.online_duration_huya, 0) > 0
            then '双播'
        else '单播'
    end,
    a.luid,
    b.nick,
    b.game_id,
    b.game_name

order by
    a.month,
    luid_type,
    a.luid;