with anchor_list as (
  -- 目标归属主播：2026-06 全平台观看时长最长的主播
  select '姿态' as anchor_name, '英雄联盟' as anchor_game_name, cast(2367547387 as bigint) as luid
  union all select '明凯', '王者荣耀', cast(1705516953 as bigint)
),

june_user_anchor_watch as (
  -- 2026-06 全平台按主播聚合观看时长，用于判断用户 6 月归属主播
  select
    user_ukey,
    creator_uid as belong_luid,
    sum(watch_duration) as month_watch_duration
  from gamelive.dws_huya_user_behavior_d_i
  where dt between '2026-06-01' and '2026-06-30'
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

june_user_belong as (
  -- 每个用户只保留 2026-06 全平台观看时长最长的归属主播
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
    from june_user_anchor_watch
  ) t
  where rn = 1
),

watched_event_room_user as (
  -- 2026-07-09 至 2026-07-16 累计观看指定直播间超过 5 分钟的用户；按主播/直播间 creator_uid=1199517808234 识别
  select
    user_ukey
  from gamelive.dws_huya_user_behavior_d_i
  where dt between '2026-07-09' and '2026-07-16'
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
    and creator_uid = 1199517808234
  group by
    user_ukey
  having sum(watch_duration) > 5 * 60 * 1000
),

target_user_by_anchor as (
  -- 固定样本：2026-06 归属到姿态/明凯，且 2026-07-09 至 2026-07-16 累计观看指定直播间超过 5 分钟
  select
    a.anchor_name,
    a.anchor_game_name,
    a.luid as belong_luid,
    b.user_ukey
  from june_user_belong b
  inner join anchor_list a
    on b.belong_luid = a.luid
  inner join watched_event_room_user r
    on b.user_ukey = r.user_ukey
),

target_user_group as (
  -- 同时输出归属主播分组和整体去重
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

watch_user_day as (
  -- 日粒度用户观看打标，保留平台/游戏/娱乐指标和游戏娱乐重叠关系
  select
    g.group_type,
    g.group_name,
    g.anchor_game_name,
    g.belong_luid,
    w.dt,
    g.user_ukey,

    sum(w.watch_duration) as platform_watch_duration,
    count(distinct w.creator_uid) as platform_watch_anchor_cnt,

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
  where w.dt between '2026-01-01' and '2026-08-05'
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

    count(distinct user_ukey) as platform_watch_user_cnt,
    sum(platform_watch_duration) as platform_watch_duration,
    sum(platform_watch_anchor_cnt) as platform_watch_anchor_cnt,

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

    sum(cast(p.user_consume_amount as double)) as platform_consume_amt,

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
  where p.dt between '2026-01-01' and '2026-08-05'
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
    count(distinct case when platform_consume_amt > 0 then user_ukey end) as platform_pay_user_cnt,
    sum(platform_consume_amt) as platform_consume_amt,
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
)

select
  w.dt as `日期`,
  w.group_type as `分组类型`,
  w.group_name as `分组名称`,
  w.anchor_game_name as `主播品类`,
  w.belong_luid as `归属主播luid`,
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

  coalesce(p.platform_pay_user_cnt, 0) * 1.0000
    / nullif(w.platform_watch_user_cnt, 0) as `平台打赏率`,
  coalesce(p.game_pay_user_cnt, 0) * 1.0000
    / nullif(w.game_watch_user_cnt, 0) as `游戏打赏率`,
  coalesce(p.ent_pay_user_cnt, 0) * 1.0000
    / nullif(w.ent_watch_user_cnt, 0) as `娱乐打赏率`,

  coalesce(p.platform_consume_amt, 0) * 1.0000
    / nullif(p.platform_pay_user_cnt, 0) as `人均平台打赏金额`,
  coalesce(p.game_consume_amt, 0) * 1.0000
    / nullif(p.game_pay_user_cnt, 0) as `人均游戏打赏金额`,
  coalesce(p.ent_consume_amt, 0) * 1.0000
    / nullif(p.ent_pay_user_cnt, 0) as `人均娱乐打赏金额`

from watch_daily_stat w
inner join group_user_cnt u
  on w.group_type = u.group_type
 and w.group_name = u.group_name
 and w.anchor_game_name = u.anchor_game_name
 and coalesce(w.belong_luid, -1) = coalesce(u.belong_luid, -1)
left join pay_daily_stat p
  on w.group_type = p.group_type
 and w.group_name = p.group_name
 and w.anchor_game_name = p.anchor_game_name
 and coalesce(w.belong_luid, -1) = coalesce(p.belong_luid, -1)
 and w.dt = p.dt
order by
  `日期`,
  `分组类型`,
  `分组名称`;
