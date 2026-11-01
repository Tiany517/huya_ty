with window_list as (
  -- 活动期：2025-09-09 至 2025-09-11；前后窗口不含活动期
  select '活动前90天' as window_name, '2025-06-11' as start_dt, '2025-09-08' as end_dt, 1 as window_order
  union all select '活动前30天', '2025-08-10', '2025-09-08', 2
  union all select '活动前14天', '2025-08-26', '2025-09-08', 3
  union all select '活动前7天', '2025-09-02', '2025-09-08', 4
  union all select '活动期', '2025-09-09', '2025-09-11', 5
  union all select '活动后7天', '2025-09-12', '2025-09-18', 6
  union all select '活动后14天', '2025-09-12', '2025-09-25', 7
  union all select '活动后30天', '2025-09-12', '2025-10-11', 8
  union all select '活动后90天', '2025-09-12', '2025-12-10', 9
),

august_user_anchor_watch as (
  -- 归属基础：2025-08 用户按主播聚合观看时长
  select
    user_ukey,
    creator_uid as belong_luid,
    sum(watch_duration) as month_watch_duration
  from gamelive.dws_huya_user_behavior_d_i
  where dt between '2025-08-01' and '2025-08-31'
    and product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
    and data_type = 'live_watch_session'
    and live_content_type = '直播'
    and is_black_ukey = 0
    and watch_cnt > 0
    and watch_duration > 0
    and user_ukey is not null
    and creator_uid is not null
  group by
    user_ukey,
    creator_uid
),

august_user_belong as (
  -- 2025-08 每个用户观看时长最长的主播
  select
    user_ukey,
    belong_luid
  from (
    select
      user_ukey,
      belong_luid,
      row_number() over (
        partition by user_ukey
        order by month_watch_duration desc, belong_luid
      ) as rn
    from august_user_anchor_watch
  ) t
  where rn = 1
),

target_user_group as (
  -- 固定样本：2025-08 归属 1199517808234，且 2025-09-09 至 2025-09-11 累计观看该直播间超过 5 分钟
  select
    '整体' as group_type,
    '1199517808234归属用户' as group_name,
    '未知' as anchor_game_name,
    cast(1199517808234 as bigint) as belong_luid,
    b.user_ukey
  from august_user_belong b
  inner join (
    select
      user_ukey
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '2025-09-09' and '2025-09-11'
      and product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
      and data_type = 'live_watch_session'
      and live_content_type = '直播'
      and is_black_ukey = 0
      and watch_cnt > 0
      and watch_duration > 0
      and user_ukey is not null
      and creator_uid = 1199517808234
    group by
      user_ukey
    having sum(watch_duration) > 5 * 60 * 1000
  ) r
    on b.user_ukey = r.user_ukey
  where b.belong_luid = 1199517808234
),

group_user_cnt as (
  select
    group_type,
    group_name,
    anchor_game_name,
    belong_luid,
    count(distinct user_ukey) as fixed_user_cnt
  from target_user_group
  group by
    group_type,
    group_name,
    anchor_game_name,
    belong_luid
),

watch_user_day as (
  -- 日粒度用户观看打标，保留游戏/娱乐重叠关系
  select
    g.group_type,
    g.group_name,
    g.anchor_game_name,
    g.belong_luid,
    w.dt,
    g.user_ukey,

    max(case
      when w.game_label in ('娱乐', '娱乐专区')
       and w.game_id not in (2165, 1663, 2356) then 1
      else 0
    end) as is_ent_watch,
    sum(case
      when w.game_label in ('娱乐', '娱乐专区')
       and w.game_id not in (2165, 1663, 2356) then w.watch_duration
      else 0
    end) as ent_watch_duration,
    count(distinct case
      when w.game_label in ('娱乐', '娱乐专区')
       and w.game_id not in (2165, 1663, 2356) then w.creator_uid
    end) as ent_watch_anchor_cnt,

    max(case
      when w.game_label in ('游戏', '游戏专区') then 1
      else 0
    end) as is_game_watch,
    sum(case
      when w.game_label in ('游戏', '游戏专区') then w.watch_duration
      else 0
    end) as game_watch_duration,
    count(distinct case
      when w.game_label in ('游戏', '游戏专区') then w.creator_uid
    end) as game_watch_anchor_cnt

  from target_user_group g
  inner join gamelive.dws_huya_user_behavior_d_i w
    on g.user_ukey = w.user_ukey
  where w.dt between '2025-06-11' and '2025-12-10'
    and w.product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
    and w.data_type = 'live_watch_session'
    and w.live_content_type = '直播'
    and w.is_black_ukey = 0
    and w.watch_cnt > 0
    and w.watch_duration > 0
    and w.user_ukey is not null
    and w.creator_uid is not null
  group by
    g.group_type,
    g.group_name,
    g.anchor_game_name,
    g.belong_luid,
    w.dt,
    g.user_ukey
),

watch_daily_stat as (
  select
    group_type,
    group_name,
    anchor_game_name,
    belong_luid,
    dt,

    count(distinct case when is_ent_watch = 1 then user_ukey end) as ent_watch_user_cnt,
    count(distinct case when is_game_watch = 1 then user_ukey end) as game_watch_user_cnt,
    count(distinct case when is_ent_watch = 1 or is_game_watch = 1 then user_ukey end) as game_or_ent_watch_user_cnt,
    count(distinct case when is_game_watch = 1 and is_ent_watch = 0 then user_ukey end) as game_only_watch_user_cnt,
    count(distinct case when is_game_watch = 1 and is_ent_watch = 1 then user_ukey end) as game_and_ent_watch_user_cnt,

    sum(ent_watch_duration) as ent_watch_duration,
    sum(case when is_ent_watch = 1 then ent_watch_anchor_cnt else 0 end) as ent_watch_anchor_cnt,

    sum(game_watch_duration) as game_watch_duration,
    sum(case when is_game_watch = 1 then game_watch_anchor_cnt else 0 end) as game_watch_anchor_cnt

  from watch_user_day
  group by
    group_type,
    group_name,
    anchor_game_name,
    belong_luid,
    dt
),

pay_user_day as (
  -- 日粒度用户打赏，用户键取 ext['ukey']
  select
    g.group_type,
    g.group_name,
    g.anchor_game_name,
    g.belong_luid,
    p.dt,
    g.user_ukey,

    sum(case
      when p.game_label in ('娱乐', '娱乐专区')
       and p.game_id not in (2165, 1663, 2356) then cast(p.user_consume_amount as double)
      else 0
    end) as ent_consume_amt,

    sum(case
      when p.game_label in ('游戏', '游戏专区') then cast(p.user_consume_amount as double)
      else 0
    end) as game_consume_amt

  from target_user_group g
  inner join zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i p
    on g.user_ukey = p.ext['ukey']
  where p.dt between '2025-06-11' and '2025-12-10'
    and p.user_consume_amount > 0
    and p.ext['ukey'] is not null
  group by
    g.group_type,
    g.group_name,
    g.anchor_game_name,
    g.belong_luid,
    p.dt,
    g.user_ukey
),

pay_daily_stat as (
  select
    group_type,
    group_name,
    anchor_game_name,
    belong_luid,
    dt,
    count(distinct case when ent_consume_amt > 0 then user_ukey end) as ent_pay_user_cnt,
    sum(ent_consume_amt) as ent_consume_amt,
    count(distinct case when game_consume_amt > 0 then user_ukey end) as game_pay_user_cnt,
    sum(game_consume_amt) as game_consume_amt
  from pay_user_day
  group by
    group_type,
    group_name,
    anchor_game_name,
    belong_luid,
    dt
),

daily_metric as (
  -- 一开始口径：先按天算指标，活动窗口层再 avg(日指标)
  select
    w.group_type,
    w.group_name,
    w.anchor_game_name,
    w.belong_luid,
    wl.window_name,
    wl.start_dt,
    wl.end_dt,
    wl.window_order,
    w.dt,
    u.fixed_user_cnt,

    coalesce(w.ent_watch_user_cnt, 0) as ent_watch_user_cnt,
    coalesce(w.game_watch_user_cnt, 0) as game_watch_user_cnt,
    coalesce(w.game_or_ent_watch_user_cnt, 0) as game_or_ent_watch_user_cnt,
    coalesce(w.game_only_watch_user_cnt, 0) as game_only_watch_user_cnt,
    coalesce(w.game_and_ent_watch_user_cnt, 0) as game_and_ent_watch_user_cnt,

    coalesce(w.ent_watch_user_cnt, 0) * 1.0000
      / nullif(w.game_or_ent_watch_user_cnt, 0) as ent_watch_user_share_game_ent_den,
    coalesce(w.game_watch_user_cnt, 0) * 1.0000
      / nullif(w.game_or_ent_watch_user_cnt, 0) as game_watch_user_share_game_ent_den,
    coalesce(w.ent_watch_user_cnt, 0) * 1.0000
      / nullif(u.fixed_user_cnt, 0) as ent_watch_user_share_fixed_den,

    coalesce(w.ent_watch_duration, 0) / 1000.0 / 60
      / nullif(w.ent_watch_user_cnt, 0) as ent_avg_watch_duration_min,
    coalesce(w.ent_watch_anchor_cnt, 0) * 1.0000
      / nullif(w.ent_watch_user_cnt, 0) as ent_avg_watch_anchor_cnt,
    coalesce(p.ent_pay_user_cnt, 0) * 1.0000
      / nullif(w.ent_watch_user_cnt, 0) as ent_pay_rate,
    coalesce(p.ent_consume_amt, 0) * 1.0000
      / nullif(p.ent_pay_user_cnt, 0) as ent_avg_pay_amt,

    coalesce(w.game_watch_duration, 0) / 1000.0 / 60
      / nullif(w.game_watch_user_cnt, 0) as game_avg_watch_duration_min,
    coalesce(w.game_watch_anchor_cnt, 0) * 1.0000
      / nullif(w.game_watch_user_cnt, 0) as game_avg_watch_anchor_cnt,
    coalesce(p.game_pay_user_cnt, 0) * 1.0000
      / nullif(w.game_watch_user_cnt, 0) as game_pay_rate,
    coalesce(p.game_consume_amt, 0) * 1.0000
      / nullif(p.game_pay_user_cnt, 0) as game_avg_pay_amt

  from watch_daily_stat w
  inner join window_list wl
    on w.dt between wl.start_dt and wl.end_dt
  inner join group_user_cnt u
    on w.group_type = u.group_type
   and w.group_name = u.group_name
   and w.anchor_game_name = u.anchor_game_name
   and w.belong_luid = u.belong_luid
  left join pay_daily_stat p
    on w.group_type = p.group_type
   and w.group_name = p.group_name
   and w.anchor_game_name = p.anchor_game_name
   and w.belong_luid = p.belong_luid
   and w.dt = p.dt
)

select
  window_name as `窗口`,
  min(start_dt) as `起始日期`,
  max(end_dt) as `结束日期`,
  datediff(to_date(max(end_dt)), to_date(min(start_dt))) + 1 as `窗口天数`,
  max(fixed_user_cnt) as `固定样本用户数`,
  count(distinct dt) as `有观看行为天数`,

  avg(ent_watch_user_cnt) as `日均娱乐观看人数`,
  avg(game_watch_user_cnt) as `日均游戏观看人数`,
  avg(game_or_ent_watch_user_cnt) as `日均游戏或娱乐去重观看人数`,
  avg(game_only_watch_user_cnt) as `日均只看游戏未看娱乐人数`,
  avg(game_and_ent_watch_user_cnt) as `日均游戏娱乐均观看人数`,

  avg(ent_watch_user_share_game_ent_den) as `娱乐观看人数占比_游戏娱乐去重分母`,
  avg(game_watch_user_share_game_ent_den) as `游戏观看人数占比_游戏娱乐去重分母`,
  avg(ent_watch_user_share_fixed_den) as `娱乐观看人数占比_固定样本分母`,

  avg(ent_avg_watch_duration_min) as `娱乐人均观看时长_分钟`,
  avg(ent_avg_watch_anchor_cnt) as `娱乐人均观看主播数`,
  avg(ent_pay_rate) as `娱乐平均打赏率`,
  avg(ent_avg_pay_amt) as `娱乐人均打赏金额`,

  avg(game_avg_watch_duration_min) as `游戏人均观看时长_分钟`,
  avg(game_avg_watch_anchor_cnt) as `游戏人均观看主播数`,
  avg(game_pay_rate) as `游戏平均打赏率`,
  avg(game_avg_pay_amt) as `游戏人均打赏金额`

from daily_metric
group by
  window_name,
  window_order
order by
  window_order;
