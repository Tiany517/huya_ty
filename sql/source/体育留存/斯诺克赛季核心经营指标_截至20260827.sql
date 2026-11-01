-- 斯诺克赛季核心经营指标
-- 口径：沿用用户提供的赛季窗口和斯诺克版权直播间名单。
-- 1. 全年日均APP DAU：斯诺克赛事每日 APP 观看用户之和 / 赛季自然日数。
-- 2. 赛事日日均APP DAU：斯诺克赛事每日 APP 观看用户之和 / 实际产生观看 session 的赛事天数。
-- 3. 全端总观看时长 / APP总观看时长：斯诺克版权直播间 session 的 user_duration，单位小时；原始单位为毫秒。
-- 4. APP新增用户：现有内容直播拉新表中，归因到斯诺克直播间且当天发生 APP 观看的去重用户。
-- 5. 礼物流水：按用户提供的去刷单 APP 打赏明细口径汇总；单位沿用 user_consume_amount。

with season_info as (
    select
        '截至8月27日' as version,
        '24/25赛季' as season,
        '2024-03-06' as start_dt,
        '2024-08-27' as end_dt
    union all
    select 
        '截至8月27日', 
        '25/26赛季', 
        '2025-03-06', 
        '2025-08-27'
    union all
    select 
        '截至8月27日', 
        '26/27赛季', 
        '2026-03-06', 
        '2026-08-27'
    union all
    select 
        '完整赛季', 
        '24/25赛季', 
        '2024-03-06', 
        '2025-03-05'
    union all
    select 
        '完整赛季', 
        '25/26赛季', 
        '2025-03-06', 
        '2026-03-05'
),

match_info as (
    select distinct
        substr(day, 1, 10) as dt,
        uid as luid
    from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
    where dt = '2026-08-27'
      and substr(day, 1, 10) between '2024-03-06' and '2026-08-27'
      and copyright_name like '%斯诺克%'
),

match_timetable_summary as (
    select
        s.version,
        season_name,
        sum(
            case
                when t.start_dt >= cast(s.start_dt as date)
                 and t.end_dt <= cast(s.end_dt as date)
                    then t.match_dcnt
                else datediff(
                    least(t.end_dt, cast(s.end_dt as date)),
                    greatest(t.start_dt, cast(s.start_dt as date))
                ) + 1
            end
        ) as match_days
    from season_info s
    inner join zhgametemp.zty_snooker_match_timetable_0902_v1 t
      on s.season = t.season_name
     and t.end_dt >= cast(s.start_dt as date)
     and t.start_dt <= cast(s.end_dt as date)
    group by s.version, season_name
),

season_days as (
    select
        s.version,
        s.season,
        s.start_dt,
        s.end_dt,
        count(distinct m.dt) as calendar_days,
        coalesce(max(t.match_days), 0) as event_days
    from season_info s
    left join match_info m
      on m.dt between s.start_dt and s.end_dt
    left join match_timetable_summary t
      on s.version = t.version
     and s.season = t.season_name
    group by s.version, s.season, s.start_dt, s.end_dt
),

watch_detail as (
    select
        dt,
        luid,
        user_ukey,
        user_product,
        user_duration
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where dt between '2024-03-06' and '2026-08-27'
      and tag = 'gameid'
      and htime = 'session'
      and user_ukey is not null
      and user_duration > 0
),

snooker_watch_daily as (
    select
        m.dt,
        count(distinct case when w.user_product in (
            'huya_andriod',
            'huya_ipad',
            'huya_pad',
            'huya_ios'
        ) then w.user_ukey end) as event_app_dau,
        sum(w.user_duration) / 3600000.0 as all_watch_hours,
        sum(case when w.user_product in (
            'huya_andriod',
            'huya_ipad',
            'huya_pad',
            'huya_ios'
        ) then w.user_duration else 0 end) / 3600000.0 as app_watch_hours
    from match_info m
    inner join watch_detail w
      on m.dt = w.dt
     and m.luid = w.luid
    group by m.dt
),

event_watch_summary as (
    select
        s.version,
        s.season,
        sum(coalesce(w.event_app_dau, 0)) * 1.0000
            / nullif(max(d.calendar_days), 0) as annual_avg_app_dau,
        sum(coalesce(w.event_app_dau, 0)) * 1.0000 / nullif(max(d.event_days), 0) as event_avg_app_dau,
        sum(coalesce(w.all_watch_hours, 0)) as all_watch_hours,
        sum(coalesce(w.app_watch_hours, 0)) as app_watch_hours
    from season_info s
    inner join season_days d
      on s.version = d.version
     and s.season = d.season
    left join snooker_watch_daily w
      on w.dt between s.start_dt and s.end_dt
    group by s.version, s.season
),

app_new_user_detail as (
    select distinct
        a.dt,
        a.luid,
        a.user_ukey
    from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a
    inner join match_info m
      on a.dt = m.dt
     and a.luid = m.luid
    where a.dt between '2024-03-06' and '2026-08-27'
      and a.guiyin_tag <> 'mailiang'
),

new_user_summary as (
    select
        s.version,
        s.season,
        count(distinct n.user_ukey) as app_new_user_cnt
    from season_info s
    left join app_new_user_detail n
      on n.dt between s.start_dt and s.end_dt
    group by s.version, s.season
),

revenue_detail as (
    select
        dt,
        creator_uid as luid,
        user_consume_amount
    from zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i
    where dt between '2024-03-06' and '2026-08-27'
      and user_consume_amount > 0
      and ext['ukey'] is not null
      and product in (
          'huya_andriod',
          'huya_ipad',
          'huya_pad',
          'huya_ios'
      )
),

gift_daily as (
    select
        r.dt,
        sum(r.user_consume_amount) as gift_revenue
    from revenue_detail r
    inner join match_info m
      on r.dt = m.dt
     and r.luid = m.luid
    group by r.dt
),

gift_summary as (
    select
        s.version,
        s.season,
        sum(coalesce(g.gift_revenue, 0)) as gift_revenue
    from season_info s
    left join gift_daily g
      on g.dt between s.start_dt and s.end_dt
    group by s.version, s.season
)

select
    s.season as `赛季`,
    s.version as `版本`,
    s.start_dt as `开始日期`,
    s.end_dt as `截止日期`,
    d.calendar_days as `自然日数`,
    d.event_days as `赛事日数`,
    w.annual_avg_app_dau as `全年日均APPDAU`,
    w.event_avg_app_dau as `赛事日日均APPDAU`,
    w.all_watch_hours as `全端总观看时长_小时`,
    w.app_watch_hours as `APP总观看时长_小时`,
    w.app_watch_hours / nullif(d.calendar_days, 0) as `APP日均观看时长_小时`,
    n.app_new_user_cnt as `APP新增用户`,
    g.gift_revenue as `礼物流水`
from season_info s
left join season_days d
  on s.version = d.version
 and s.season = d.season
left join event_watch_summary w
  on s.version = w.version
 and s.season = w.season
left join new_user_summary n
  on s.version = n.version
 and s.season = n.season
left join gift_summary g
  on s.version = g.version
 and s.season = g.season
order by
    case s.version
        when '截至8月27日' then 1
        when '完整赛季' then 2
        else 3
    end,
    case s.season
        when '24/25赛季' then 1
        when '25/26赛季' then 2
        when '26/27赛季' then 3
        else 4
    end;
