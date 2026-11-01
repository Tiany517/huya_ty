with anchor_list as (
  -- 剔除狂魔哥解说、魔创-雅一儿【许仙】后，保留的目标主播
  select '明凯' as anchor_name, '王者荣耀' as anchor_game_name, 1705516953 as luid
  union all select '药水哥' as anchor_name, '英雄联盟' as anchor_game_name, 2319419933 as luid
  union all select 'XLX金木' as anchor_name, '王者荣耀' as anchor_game_name, 1199610004865 as luid
),

window_list as (
  -- 需要对比的活动前后窗口
  select '活动前90天' as window_name, '2025-03-18' as start_dt, '2025-06-15' as end_dt, 1 as window_order
  union all select '活动前30天', '2025-05-17', '2025-06-15', 2
  union all select '活动前14天', '2025-06-02', '2025-06-15', 3
  union all select '活动期', '2025-06-16', '2025-06-20', 4
  union all select '活动后14天', '2025-06-21', '2025-07-04', 5
  union all select '活动后30天', '2025-06-21', '2025-07-20', 6
  union all select '活动后90天', '2025-06-21', '2025-09-18', 7
),

may_user_anchor_watch as (
  -- 2025-05 全平台按主播聚合观看时长，用于判断用户 5 月归属主播
  select
    user_ukey,
    creator_uid as belong_luid,
    sum(watch_duration) as month_watch_duration
  from gamelive.dws_huya_user_behavior_d_i
  where dt between '2025-05-01' and '2025-05-31'
    and product in (
      'huya_andriod',
      'huya_ipad',
      'huya_pad',
      'huya_ios',
      'hmos_kiwi'
    )
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

may_user_belong as (
  -- 每个用户只保留 2025-05 全平台观看时长最长的主播
  select
    user_ukey,
    belong_luid
  from (
    select
      user_ukey,
      belong_luid,
      month_watch_duration,
      row_number() over (
        partition by user_ukey
        order by month_watch_duration desc, belong_luid
      ) as rn
    from may_user_anchor_watch
  ) t
  where rn = 1
),

watched_room_0616_0620_user as (
  -- 2025-06-16 至 2025-06-20 看过 roomid=666999 的用户；按主播 creator_uid=1099531740247 识别
  select distinct
    user_ukey
  from gamelive.dws_huya_user_behavior_d_i
  where dt between '2025-06-16' and '2025-06-20'
    and product in (
      'huya_andriod',
      'huya_ipad',
      'huya_pad',
      'huya_ios',
      'hmos_kiwi'
    )
    and data_type = 'live_watch_session'
    and live_content_type = '直播'
    and is_black_ukey = 0
    and watch_cnt > 0
    and watch_duration > 0
    and user_ukey is not null
    and creator_uid = 1099531740247
),

target_user as (
  -- 固定样本：2025-05 归属到保留主播，且 2025-06-16 至 2025-06-20 看过 roomid=666999
  select
    b.user_ukey
  from may_user_belong b
  inner join anchor_list a
    on b.belong_luid = a.luid
  inner join watched_room_0616_0620_user r
    on b.user_ukey = r.user_ukey
  group by
    b.user_ukey
),

target_user_cnt as (
  select
    count(distinct user_ukey) as fixed_user_cnt
  from target_user
),

watch_user_window as (
  -- 窗口内按用户聚合游戏/娱乐观看，保留用户级是否看过游戏/娱乐，避免重叠用户被重复计入分母
  select
    wl.window_name,
    wl.start_dt,
    wl.end_dt,
    wl.window_order,
    u.user_ukey,

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

  from target_user u
  inner join gamelive.dws_huya_user_behavior_d_i w
    on u.user_ukey = w.user_ukey
  inner join window_list wl
    on w.dt between wl.start_dt and wl.end_dt
  where w.dt between '2025-03-18' and '2025-09-18'
    and w.product in (
      'huya_andriod',
      'huya_ipad',
      'huya_pad',
      'huya_ios',
      'hmos_kiwi'
    )
    and w.data_type = 'live_watch_session'
    and w.live_content_type = '直播'
    and w.is_black_ukey = 0
    and w.watch_cnt > 0
    and w.watch_duration > 0
    and w.user_ukey is not null
    and w.creator_uid is not null
  group by
    wl.window_name,
    wl.start_dt,
    wl.end_dt,
    wl.window_order,
    u.user_ukey
),

watch_window_stat as (
  select
    window_name,
    start_dt,
    end_dt,
    window_order,

    count(distinct case when is_ent_watch = 1 then user_ukey end) as ent_watch_user_cnt,
    count(distinct case when is_game_watch = 1 then user_ukey end) as game_watch_user_cnt,
    count(distinct case
      when is_ent_watch = 1 or is_game_watch = 1 then user_ukey
    end) as game_or_ent_watch_user_cnt,
    count(distinct case
      when is_game_watch = 1 and is_ent_watch = 0 then user_ukey
    end) as game_only_watch_user_cnt,
    count(distinct case
      when is_game_watch = 1 and is_ent_watch = 1 then user_ukey
    end) as game_and_ent_watch_user_cnt,

    sum(ent_watch_duration) as ent_watch_duration,
    sum(case when is_ent_watch = 1 then ent_watch_anchor_cnt else 0 end) as ent_watch_anchor_cnt,

    sum(game_watch_duration) as game_watch_duration,
    sum(case when is_game_watch = 1 then game_watch_anchor_cnt else 0 end) as game_watch_anchor_cnt

  from watch_user_window
  group by
    window_name,
    start_dt,
    end_dt,
    window_order
),

revenue_base as (
  -- 打赏明细使用剔刷单收入表；用户键取 ext['ukey']
  select
    dt,
    ext['ukey'] as user_ukey,
    creator_uid,
    game_id,
    game_label,
    sum(cast(user_consume_amount as double)) as consume_amt
  from zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i
  where dt between '2025-03-18' and '2025-09-18'
    and user_consume_amount > 0
    and ext['ukey'] is not null
  group by
    dt,
    ext['ukey'],
    creator_uid,
    game_id,
    game_label
),

pay_user_window as (
  -- 窗口内按用户聚合游戏/娱乐打赏
  select
    wl.window_name,
    wl.start_dt,
    wl.end_dt,
    wl.window_order,
    u.user_ukey,

    sum(case
      when p.game_label in ('娱乐', '娱乐专区')
       and p.game_id not in (2165, 1663, 2356) then p.consume_amt
      else 0
    end) as ent_consume_amt,

    sum(case
      when p.game_label in ('游戏', '游戏专区') then p.consume_amt
      else 0
    end) as game_consume_amt

  from target_user u
  inner join revenue_base p
    on u.user_ukey = p.user_ukey
  inner join window_list wl
    on p.dt between wl.start_dt and wl.end_dt
  group by
    wl.window_name,
    wl.start_dt,
    wl.end_dt,
    wl.window_order,
    u.user_ukey
),

pay_window_stat as (
  select
    window_name,
    start_dt,
    end_dt,
    window_order,

    count(distinct case when ent_consume_amt > 0 then user_ukey end) as ent_pay_user_cnt,
    sum(ent_consume_amt) as ent_consume_amt,

    count(distinct case when game_consume_amt > 0 then user_ukey end) as game_pay_user_cnt,
    sum(game_consume_amt) as game_consume_amt

  from pay_user_window
  group by
    window_name,
    start_dt,
    end_dt,
    window_order
)

select
  wl.window_name as `窗口`,
  wl.start_dt as `起始日期`,
  wl.end_dt as `结束日期`,
  datediff(to_date(wl.end_dt), to_date(wl.start_dt)) + 1 as `窗口天数`,
  (select fixed_user_cnt from target_user_cnt) as `固定样本用户数`,

  coalesce(w.ent_watch_user_cnt, 0) as `娱乐窗口去重观看人数`,
  coalesce(w.game_watch_user_cnt, 0) as `游戏窗口去重观看人数`,
  coalesce(w.game_or_ent_watch_user_cnt, 0) as `游戏或娱乐窗口去重观看人数`,
  coalesce(w.game_only_watch_user_cnt, 0) as `只看游戏未看娱乐人数`,
  coalesce(w.game_and_ent_watch_user_cnt, 0) as `游戏娱乐均观看人数`,

  coalesce(w.ent_watch_user_cnt, 0) * 1.0000
    / nullif(w.game_or_ent_watch_user_cnt, 0) as `娱乐观看人数占比_游戏娱乐去重分母`,
  coalesce(w.game_watch_user_cnt, 0) * 1.0000
    / nullif(w.game_or_ent_watch_user_cnt, 0) as `游戏观看人数占比_游戏娱乐去重分母`,
  coalesce(w.ent_watch_user_cnt, 0) * 1.0000
    / nullif((select fixed_user_cnt from target_user_cnt), 0) as `娱乐观看人数占比_固定样本分母`,

  coalesce(w.ent_watch_duration, 0) / 1000.0 / 60
    / nullif(w.ent_watch_user_cnt, 0) as `娱乐人均观看时长_分钟`,
  coalesce(w.ent_watch_anchor_cnt, 0) * 1.0000
    / nullif(w.ent_watch_user_cnt, 0) as `娱乐人均观看主播数`,
  coalesce(p.ent_pay_user_cnt, 0) * 1.0000
    / nullif(w.ent_watch_user_cnt, 0) as `娱乐平均打赏率`,
  coalesce(p.ent_consume_amt, 0) * 1.0000
    / nullif(p.ent_pay_user_cnt, 0) as `娱乐人均打赏金额`,

  coalesce(w.game_watch_duration, 0) / 1000.0 / 60
    / nullif(w.game_watch_user_cnt, 0) as `游戏人均观看时长_分钟`,
  coalesce(w.game_watch_anchor_cnt, 0) * 1.0000
    / nullif(w.game_watch_user_cnt, 0) as `游戏人均观看主播数`,
  coalesce(p.game_pay_user_cnt, 0) * 1.0000
    / nullif(w.game_watch_user_cnt, 0) as `游戏平均打赏率`,
  coalesce(p.game_consume_amt, 0) * 1.0000
    / nullif(p.game_pay_user_cnt, 0) as `游戏人均打赏金额`

from window_list wl
left join watch_window_stat w
  on wl.window_name = w.window_name
left join pay_window_stat p
  on wl.window_name = p.window_name
order by
  wl.window_order;
