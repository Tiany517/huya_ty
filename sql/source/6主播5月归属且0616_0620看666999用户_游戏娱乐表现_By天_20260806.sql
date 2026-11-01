with anchor_list as (
  -- 目标主播名单
  select '狂魔哥解说' as anchor_name, '王者荣耀' as anchor_game_name, 1567578875 as luid
  union all select '明凯' as anchor_name, '王者荣耀' as anchor_game_name, 1705516953 as luid
  union all select '魔创-雅一儿【许仙】' as anchor_name, '主机游戏' as anchor_game_name, 1784500555 as luid
  union all select '药水哥' as anchor_name, '英雄联盟' as anchor_game_name, 2319419933 as luid
  union all select '东星耀扬【单枪匹马】' as anchor_name, '王者荣耀' as anchor_game_name, 1279521053571 as luid
  union all select 'XLX金木' as anchor_name, '王者荣耀' as anchor_game_name, 1199610004865 as luid
),

watch_behavior_base as (
  -- 观看明细统一使用 behavior 表；watch_duration 单位为毫秒
  select
    dt,
    user_ukey,
    creator_uid,
    game_id,
    game_label,
    sum(watch_duration) as watch_duration
  from gamelive.dws_huya_user_behavior_d_i
  where dt between '2025-01-01' and '2026-08-05'
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
    dt,
    user_ukey,
    creator_uid,
    game_id,
    game_label
),

may_user_anchor_watch as (
  -- 2025-05 全平台按主播聚合观看时长，用于判断用户 5 月归属主播
  select
    user_ukey,
    creator_uid as belong_luid,
    sum(watch_duration) as month_watch_duration
  from watch_behavior_base
  where dt between '2025-05-01' and '2025-05-31'
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
  -- 2025-06-16 至 2025-06-20 看过 roomid=666999 的用户；behavior 表按主播 creator_uid=1099531740247 识别
  select distinct
    user_ukey
  from watch_behavior_base
  where dt between '2025-06-16' and '2025-06-20'
    and creator_uid = 1099531740247
),

target_user_by_anchor as (
  -- 固定样本：2025-05 归属到目标主播，且 2025-06-16 至 2025-06-20 看过 roomid=666999
  select
    a.anchor_name,
    a.anchor_game_name,
    a.luid as belong_luid,
    b.user_ukey
  from may_user_belong b
  inner join anchor_list a
    on b.belong_luid = a.luid
  inner join watched_room_0616_0620_user r
    on b.user_ukey = r.user_ukey
),

target_user_group as (
  -- 同时输出每位主播分组，以及整体去重用户组
  select
    '主播' as group_type,
    anchor_name as group_name,
    anchor_game_name,
    belong_luid,
    user_ukey
  from target_user_by_anchor
  union all
  select
    '整体去重' as group_type,
    '整体去重' as group_name,
    '整体去重' as anchor_game_name,
    cast(null as bigint) as belong_luid,
    user_ukey
  from (
    select distinct
      user_ukey
    from target_user_by_anchor
  ) t
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

user_daily_watch as (
  -- 固定样本用户每日观看表现；游戏/娱乐按内容大类拆分
  select
    g.group_type,
    g.group_name,
    g.anchor_game_name,
    g.belong_luid,
    w.dt,
    g.user_ukey,

    sum(w.watch_duration) as platform_watch_duration,
    count(distinct w.creator_uid) as platform_watch_anchor_cnt,

    sum(case
      when w.game_label in ('游戏', '游戏专区') then w.watch_duration
      else 0
    end) as game_watch_duration,
    count(distinct case
      when w.game_label in ('游戏', '游戏专区') then w.creator_uid
    end) as game_watch_anchor_cnt,

    sum(case
      when w.game_label in ('娱乐', '娱乐专区')
       and w.game_id not in (2165, 1663, 2356) then w.watch_duration
      else 0
    end) as ent_watch_duration,
    count(distinct case
      when w.game_label in ('娱乐', '娱乐专区')
       and w.game_id not in (2165, 1663, 2356) then w.creator_uid
    end) as ent_watch_anchor_cnt

  from target_user_group g
  inner join watch_behavior_base w
    on g.user_ukey = w.user_ukey
  group by
    g.group_type,
    g.group_name,
    g.anchor_game_name,
    g.belong_luid,
    w.dt,
    g.user_ukey
),

daily_watch_stat as (
  select
    group_type,
    group_name,
    anchor_game_name,
    belong_luid,
    dt,

    count(distinct user_ukey) as platform_watch_user_cnt,
    count(distinct case when game_watch_duration > 0 then user_ukey end) as game_watch_user_cnt,
    count(distinct case when ent_watch_duration > 0 then user_ukey end) as ent_watch_user_cnt,

    sum(platform_watch_duration) as platform_watch_duration,
    sum(game_watch_duration) as game_watch_duration,
    sum(ent_watch_duration) as ent_watch_duration,

    sum(platform_watch_anchor_cnt) as platform_watch_anchor_cnt,
    sum(case when game_watch_duration > 0 then game_watch_anchor_cnt else 0 end) as game_watch_anchor_cnt,
    sum(case when ent_watch_duration > 0 then ent_watch_anchor_cnt else 0 end) as ent_watch_anchor_cnt

  from user_daily_watch
  group by
    group_type,
    group_name,
    anchor_game_name,
    belong_luid,
    dt
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
  where dt between '2025-01-01' and '2026-08-05'
    and user_consume_amount > 0
    and ext['ukey'] is not null
  group by
    dt,
    ext['ukey'],
    creator_uid,
    game_id,
    game_label
),

user_daily_pay as (
  -- 固定样本用户每日打赏表现；游戏/娱乐按内容大类拆分
  select
    g.group_type,
    g.group_name,
    g.anchor_game_name,
    g.belong_luid,
    p.dt,
    g.user_ukey,

    sum(p.consume_amt) as platform_consume_amt,
    sum(case
      when p.game_label in ('游戏', '游戏专区') then p.consume_amt
      else 0
    end) as game_consume_amt,
    sum(case
      when p.game_label in ('娱乐', '娱乐专区')
       and p.game_id not in (2165, 1663, 2356) then p.consume_amt
      else 0
    end) as ent_consume_amt

  from target_user_group g
  inner join revenue_base p
    on g.user_ukey = p.user_ukey
  group by
    g.group_type,
    g.group_name,
    g.anchor_game_name,
    g.belong_luid,
    p.dt,
    g.user_ukey
),

daily_pay_stat as (
  select
    group_type,
    group_name,
    anchor_game_name,
    belong_luid,
    dt,

    count(distinct case when platform_consume_amt > 0 then user_ukey end) as platform_pay_user_cnt,
    count(distinct case when game_consume_amt > 0 then user_ukey end) as game_pay_user_cnt,
    count(distinct case when ent_consume_amt > 0 then user_ukey end) as ent_pay_user_cnt,

    sum(platform_consume_amt) as platform_consume_amt,
    sum(game_consume_amt) as game_consume_amt,
    sum(ent_consume_amt) as ent_consume_amt

  from user_daily_pay
  group by
    group_type,
    group_name,
    anchor_game_name,
    belong_luid,
    dt
),

group_day_key as (
  -- 不做日期与分组的笛卡尔积：只保留观看或打赏任一侧有行为的分组日期
  select group_type, group_name, anchor_game_name, belong_luid, dt
  from daily_watch_stat
  union
  select group_type, group_name, anchor_game_name, belong_luid, dt
  from daily_pay_stat
)

select
  k.dt as `日期`,
  k.group_type as `分组类型`,
  k.group_name as `分组名称`,
  k.anchor_game_name as `主播品类`,
  k.belong_luid as `归属主播luid`,
  u.fixed_user_cnt as `固定样本用户数`,

  coalesce(w.platform_watch_user_cnt, 0) as `平台观看人数`,
  coalesce(w.game_watch_user_cnt, 0) as `游戏观看人数`,
  coalesce(w.ent_watch_user_cnt, 0) as `娱乐观看人数`,

  coalesce(w.platform_watch_duration, 0) / 1000.0 / 60
    / nullif(w.platform_watch_user_cnt, 0) as `人均平台观看时长_分钟`,
  coalesce(w.game_watch_duration, 0) / 1000.0 / 60
    / nullif(w.game_watch_user_cnt, 0) as `人均游戏观看时长_分钟`,
  coalesce(w.ent_watch_duration, 0) / 1000.0 / 60
    / nullif(w.ent_watch_user_cnt, 0) as `人均娱乐观看时长_分钟`,

  coalesce(w.game_watch_anchor_cnt, 0) * 1.0000
    / nullif(w.game_watch_user_cnt, 0) as `人均游戏观看主播数`,
  coalesce(w.ent_watch_anchor_cnt, 0) * 1.0000
    / nullif(w.ent_watch_user_cnt, 0) as `人均娱乐观看主播数`,
  coalesce(w.platform_watch_anchor_cnt, 0) * 1.0000
    / nullif(w.platform_watch_user_cnt, 0) as `人均平台观看主播数`,

  coalesce(p.platform_pay_user_cnt, 0) as `平台打赏人数`,
  coalesce(p.game_pay_user_cnt, 0) as `游戏打赏人数`,
  coalesce(p.ent_pay_user_cnt, 0) as `娱乐打赏人数`,

  coalesce(p.platform_consume_amt, 0) * 1.0000
    / nullif(p.platform_pay_user_cnt, 0) as `人均平台打赏金额`,
  coalesce(p.game_consume_amt, 0) * 1.0000
    / nullif(p.game_pay_user_cnt, 0) as `人均游戏打赏金额`,
  coalesce(p.ent_consume_amt, 0) * 1.0000
    / nullif(p.ent_pay_user_cnt, 0) as `人均娱乐打赏金额`

from group_day_key k
inner join group_user_cnt u
  on k.group_type = u.group_type
 and k.group_name = u.group_name
 and k.anchor_game_name = u.anchor_game_name
 and coalesce(k.belong_luid, -1) = coalesce(u.belong_luid, -1)
left join daily_watch_stat w
  on k.group_type = w.group_type
 and k.group_name = w.group_name
 and k.anchor_game_name = w.anchor_game_name
 and coalesce(k.belong_luid, -1) = coalesce(w.belong_luid, -1)
 and k.dt = w.dt
left join daily_pay_stat p
  on k.group_type = p.group_type
 and k.group_name = p.group_name
 and k.anchor_game_name = p.anchor_game_name
 and coalesce(k.belong_luid, -1) = coalesce(p.belong_luid, -1)
 and k.dt = p.dt
order by
  `日期`,
  `分组类型`,
  `分组名称`;
