with watch_user_day as (
  -- 大盘观看用户：APP 直播观看，日粒度用户去重
  select
    dt,
    substr(dt, 1, 7) as month,
    user_ukey,

    max(1) as is_platform_watch,
    max(case
      when game_label in ('游戏', '游戏专区') then 1
      else 0
    end) as is_game_watch,
    max(case
      when game_label in ('娱乐', '娱乐专区')
       and game_id not in (2165, 1663, 2356) then 1
      else 0
    end) as is_ent_watch

  from gamelive.dws_huya_user_behavior_d_i
  where dt between '2025-01-01' and '2025-12-31'
    and product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
    and data_type = 'live_watch_session'
    and live_content_type = '直播'
    and is_black_ukey = 0
    and watch_cnt > 0
    and watch_duration > 0
    and user_ukey is not null
  group by
    dt,
    substr(dt, 1, 7),
    user_ukey
),

watch_day_stat as (
  -- 每日整体/游戏/娱乐观看人数
  select
    dt,
    month,
    count(distinct user_ukey) as platform_watch_user_cnt,
    count(distinct case when is_game_watch = 1 then user_ukey end) as game_watch_user_cnt,
    count(distinct case when is_ent_watch = 1 then user_ukey end) as ent_watch_user_cnt
  from watch_user_day
  group by
    dt,
    month
),

pay_user_day as (
  -- 大盘打赏用户：剔除刷单后的收入明细，日粒度用户去重
  select
    dt,
    substr(dt, 1, 7) as month,
    ext['ukey'] as user_ukey,

    max(1) as is_platform_pay,
    max(case
      when game_label in ('游戏', '游戏专区') then 1
      else 0
    end) as is_game_pay,
    max(case
      when game_label in ('娱乐', '娱乐专区')
       and game_id not in (2165, 1663, 2356) then 1
      else 0
    end) as is_ent_pay

  from zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i
  where dt between '2025-01-01' and '2025-12-31'
    and user_consume_amount > 0
    and ext['ukey'] is not null
  group by
    dt,
    substr(dt, 1, 7),
    ext['ukey']
),

pay_day_stat as (
  -- 每日整体/游戏/娱乐打赏人数
  select
    dt,
    month,
    count(distinct user_ukey) as platform_pay_user_cnt,
    count(distinct case when is_game_pay = 1 then user_ukey end) as game_pay_user_cnt,
    count(distinct case when is_ent_pay = 1 then user_ukey end) as ent_pay_user_cnt
  from pay_user_day
  group by
    dt,
    month
),

daily_rate as (
  -- 日打赏率：当天打赏用户数 / 当天观看用户数
  select
    w.dt,
    w.month,

    w.platform_watch_user_cnt,
    w.game_watch_user_cnt,
    w.ent_watch_user_cnt,

    coalesce(p.platform_pay_user_cnt, 0) as platform_pay_user_cnt,
    coalesce(p.game_pay_user_cnt, 0) as game_pay_user_cnt,
    coalesce(p.ent_pay_user_cnt, 0) as ent_pay_user_cnt,

    coalesce(p.platform_pay_user_cnt, 0) * 1.0000
      / nullif(w.platform_watch_user_cnt, 0) as platform_pay_rate,
    coalesce(p.game_pay_user_cnt, 0) * 1.0000
      / nullif(w.game_watch_user_cnt, 0) as game_pay_rate,
    coalesce(p.ent_pay_user_cnt, 0) * 1.0000
      / nullif(w.ent_watch_user_cnt, 0) as ent_pay_rate

  from watch_day_stat w
  left join pay_day_stat p
    on w.dt = p.dt
)

select
  month as `月份`,
  count(distinct dt) as `有观看行为天数`,

  avg(platform_watch_user_cnt) as `日均整体观看人数`,
  avg(platform_pay_user_cnt) as `日均整体打赏人数`,
  avg(platform_pay_rate) as `整体打赏率_月日均`,

  avg(game_watch_user_cnt) as `日均游戏观看人数`,
  avg(game_pay_user_cnt) as `日均游戏打赏人数`,
  avg(game_pay_rate) as `游戏打赏率_月日均`,

  avg(ent_watch_user_cnt) as `日均娱乐观看人数`,
  avg(ent_pay_user_cnt) as `日均娱乐打赏人数`,
  avg(ent_pay_rate) as `娱乐打赏率_月日均`

from daily_rate
group by
  month
order by
  `月份`;
