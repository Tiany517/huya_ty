-- 口径说明：
-- 1. 样本：2026-07-01 至 2026-07-15 观看过王者荣耀直播/视频的用户，粒度为 user_ukey。
-- 2. cohort_date：用户在观察期内首次观看王者荣耀的日期。
-- 3. 7日窗口：cohort_date 至 cohort_date + 6 天。
-- 4. 7日留存：cohort_date + 6 天在 APP 端活跃，且 is_black_ukey = 0。
-- 5. 打赏金额：cohort_date 至 cohort_date + 6 天内 user_consume_amount > 0 的消费金额。
-- 6. 王者荣耀打赏金额：7日窗口内打赏对象 game_id 属于王者荣耀的消费金额。
-- 7. 使用前请确认王者荣耀 game_id 是否需改为固定 ID；当前按游戏名从维表识别。

with
-- ============================================================
-- 王者荣耀游戏ID
-- 粒度：game_id
-- 用途：识别观看和打赏对应的王者荣耀内容
-- ============================================================
honour_game as (
  select distinct
    cast(gid as varchar) as game_id
  from gamelive.to_main_games_day
  where dt between '2026-07-01' and '2026-07-21'
    and (
      game_full_name like '%王者荣耀%'
      or game_short_name like '%王者荣耀%'
    )
),

-- ============================================================
-- 观察期内观看王者荣耀的用户
-- 粒度：dt + user_ukey
-- 样本窗口：2026-07-01 至 2026-07-15
-- 过滤：APP端、有效观看、直播/视频
-- ============================================================
honour_watch_user_day as (
  select
    w.dt,
    w.user_ukey,
    sum(w.watch_duration) as honour_watch_duration
  from gamelive.dws_huya_user_behavior_d_i w
  inner join honour_game g
    on cast(w.game_id as varchar) = g.game_id
  where w.dt between '2026-07-01' and '2026-07-15'
    and w.product in ('huya_andriod', 'huya_ios', 'hmos_kiwi')
    and w.data_type in ('live_watch_session', 'video_session')
    and w.live_content_type in ('直播', '视频')
    and w.watch_cnt > 0
    and w.watch_duration > 0
    and (
      w.data_type = 'live_watch_session'
      or (
        w.data_type = 'video_session'
        and w.content_id <> 0
        and w.vid_can_play = 1
      )
    )
  group by
    w.dt,
    w.user_ukey
),

-- ============================================================
-- 用户首个王者荣耀观看日
-- 粒度：user_ukey
-- 用途：作为7日留存和7日打赏的起点
-- ============================================================
watch_user_base as (
  select
    user_ukey,
    min(dt) as cohort_date,
    sum(honour_watch_duration) as observe_period_honour_watch_duration
  from honour_watch_user_day
  group by user_ukey
),

-- ============================================================
-- 7日活跃与D7留存
-- 粒度：user_ukey
-- 活跃窗口：2026-07-01 至 2026-07-21，覆盖观察期最后一天 + 6 天
-- D7留存：首观看日 + 6 天当天活跃
-- ============================================================
active_7d as (
  select
    a.user_ukey,
    count(distinct b.dt) as active_days_7d,
    max(
      case
        when b.dt = date_format(
          date_add('day', 6, date_parse(a.cohort_date, '%Y-%m-%d')),
          '%Y-%m-%d'
        )
        then 1
        else 0
      end
    ) as is_d7_retain
  from watch_user_base a
  left join (
    select distinct
      dt,
      user_ukey
    from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
    where dt between '2026-07-01' and '2026-07-21'
      and product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
      and is_black_ukey = 0
  ) b
    on a.user_ukey = b.user_ukey
   and b.dt between a.cohort_date
                and date_format(
                  date_add('day', 6, date_parse(a.cohort_date, '%Y-%m-%d')),
                  '%Y-%m-%d'
                )
  group by a.user_ukey
),

-- ============================================================
-- 首观看日起7日内打赏
-- 粒度：user_ukey
-- 消费窗口：2026-07-01 至 2026-07-21，覆盖观察期最后一天 + 6 天
-- ============================================================
pay_7d as (
  select
    a.user_ukey,
    sum(p.user_consume_amount) as total_consume_amt_7d,
    sum(
      case
        when g.game_id is not null then p.user_consume_amount
        else 0
      end
    ) as honour_consume_amt_7d,
    count(distinct case when p.user_consume_amount > 0 then p.dt end) as pay_days_7d
  from watch_user_base a
  left join gamelive.dws_huya_revenue_detail_d_i p
    on a.user_ukey = p.ext['ukey']
   and p.dt between a.cohort_date
                and date_format(
                  date_add('day', 6, date_parse(a.cohort_date, '%Y-%m-%d')),
                  '%Y-%m-%d'
                )
   and p.dt between '2026-07-01' and '2026-07-21'
   and p.user_consume_amount > 0
  left join honour_game g
    on cast(p.game_id as varchar) = g.game_id
  group by a.user_ukey
),

-- ============================================================
-- 用户明细
-- 粒度：user_ukey
-- 用途：保留可复盘明细，再做最终聚合
-- ============================================================
user_detail as (
  select
    a.cohort_date,
    a.user_ukey,
    a.observe_period_honour_watch_duration,
    coalesce(b.active_days_7d, 0) as active_days_7d,
    coalesce(b.is_d7_retain, 0) as is_d7_retain,
    coalesce(c.total_consume_amt_7d, 0) as total_consume_amt_7d,
    coalesce(c.honour_consume_amt_7d, 0) as honour_consume_amt_7d,
    coalesce(c.pay_days_7d, 0) as pay_days_7d
  from watch_user_base a
  left join active_7d b
    on a.user_ukey = b.user_ukey
  left join pay_7d c
    on a.user_ukey = c.user_ukey
)

-- ============================================================
-- 最终汇总：按首观看日输出
-- ============================================================
select
  cohort_date,
  count(distinct user_ukey) as watch_user_cnt,
  sum(observe_period_honour_watch_duration) as observe_period_honour_watch_duration,

  count(distinct case when is_d7_retain = 1 then user_ukey end) as d7_retain_user_cnt,
  count(distinct case when is_d7_retain = 1 then user_ukey end) * 1.0000
    / nullif(count(distinct user_ukey), 0) as d7_retention_rate,

  sum(active_days_7d) as active_days_7d,
  sum(active_days_7d) * 1.0000
    / nullif(count(distinct user_ukey), 0) as avg_active_days_7d,

  count(distinct case when total_consume_amt_7d > 0 then user_ukey end) as pay_user_cnt_7d,
  count(distinct case when total_consume_amt_7d > 0 then user_ukey end) * 1.0000
    / nullif(count(distinct user_ukey), 0) as pay_rate_7d,
  sum(total_consume_amt_7d) as total_consume_amt_7d,
  sum(total_consume_amt_7d) * 1.0000
    / nullif(count(distinct user_ukey), 0) as arpu_7d,
  sum(total_consume_amt_7d) * 1.0000
    / nullif(count(distinct case when total_consume_amt_7d > 0 then user_ukey end), 0) as arppu_7d,

  count(distinct case when honour_consume_amt_7d > 0 then user_ukey end) as honour_pay_user_cnt_7d,
  sum(honour_consume_amt_7d) as honour_consume_amt_7d,
  sum(honour_consume_amt_7d) * 1.0000
    / nullif(count(distinct user_ukey), 0) as honour_arpu_7d
from user_detail
group by cohort_date
order by cohort_date;
