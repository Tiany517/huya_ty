with watch_behavior_base as (
  -- 观看明细统一使用 behavior 表；watch_duration 单位为毫秒
  select
    dt,
    user_ukey,
    creator_uid,
    game_id,
    game_label,
    sum(watch_duration) as watch_duration
  from gamelive.dws_huya_user_behavior_d_i
  where dt between '2026-05-01' and '2026-08-05'
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
  group by
    dt,
    user_ukey,
    creator_uid,
    game_id,
    game_label
),

july_user_anchor_watch as (
  -- 2026-07 全月按主播聚合观看时长，用于判断 2026-08-04 的“上个月归属”
  select
    user_ukey,
    creator_uid as belong_luid,
    sum(watch_duration) as month_watch_duration
  from watch_behavior_base
  where dt between '2026-07-01' and '2026-07-31'
  group by
    user_ukey,
    creator_uid
),

july_user_belong as (
  -- 每个用户只保留 2026-07 观看时长最长的归属主播
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
    from july_user_anchor_watch
  ) t
  where rn = 1
),

watch_tong_0804_user as (
  -- 2026-08-04 当天观看过童锦程直播间的用户
  select distinct
    user_ukey
  from watch_behavior_base
  where dt = '2026-08-04'
    and creator_uid = 1199568157971
),

target_user as (
  -- 固定样本：2026-07 归属姿态，且 2026-08-04 看过童锦程直播间
  select
    t.user_ukey
  from watch_tong_0804_user t
  inner join july_user_belong b
    on t.user_ukey = b.user_ukey
   and b.belong_luid = 2367547387
),

daily_calendar as (
  -- 输出 2026-05-01 至 2026-08-05 的每日数据
  select distinct
    dt
  from watch_behavior_base
),

target_user_cnt as (
  select
    count(distinct user_ukey) as target_user_cnt
  from target_user
),

daily_watch_stat as (
  -- 固定样本每日全平台、童锦程、姿态观看表现
  select
    w.dt,

    count(distinct w.user_ukey) as all_platform_watch_user_cnt,
    sum(coalesce(w.watch_duration, 0)) as all_platform_watch_duration,

    count(distinct case
      when w.creator_uid = 1199568157971 and w.watch_duration > 0 then w.user_ukey
    end) as watch_tong_user_cnt,
    sum(case
      when w.creator_uid = 1199568157971 then coalesce(w.watch_duration, 0)
      else 0
    end) as watch_tong_duration,

    count(distinct case
      when w.creator_uid = 2367547387 and w.watch_duration > 0 then w.user_ukey
    end) as watch_zitai_user_cnt,
    sum(case
      when w.creator_uid = 2367547387 then coalesce(w.watch_duration, 0)
      else 0
    end) as watch_zitai_duration

  from target_user u
  inner join watch_behavior_base w
    on u.user_ukey = w.user_ukey
  group by
    w.dt
),

daily_ent_watch_stat as (
  -- 固定样本每日观看娱乐品类表现
  -- 娱乐口径：game_label in ('娱乐','娱乐专区')，且排除户外(2165)、星秀(1663)、体育(2356)
  select
    w.dt,
    count(distinct w.user_ukey) as ent_watch_user_cnt,
    sum(coalesce(w.watch_duration, 0)) as ent_watch_duration,
    count(distinct w.creator_uid) as ent_watch_anchor_cnt
  from target_user u
  inner join watch_behavior_base w
    on u.user_ukey = w.user_ukey
  where w.game_label in ('娱乐', '娱乐专区')
    and w.game_id not in (2165, 1663, 2356)
  group by
    w.dt
),

daily_pay_stat as (
  -- 固定样本每日全站打赏、童锦程打赏、姿态打赏
  select
    p.dt,
    count(distinct case
      when p.user_consume_amount > 0 then u.user_ukey
    end) as pay_user_cnt,
    sum(coalesce(p.user_consume_amount, 0)) as consume_amt,

    count(distinct case
      when p.creator_uid = 1199568157971 and p.user_consume_amount > 0 then u.user_ukey
    end) as pay_tong_user_cnt,
    sum(case
      when p.creator_uid = 1199568157971 then coalesce(p.user_consume_amount, 0)
      else 0
    end) as consume_amt_to_tong,

    count(distinct case
      when p.creator_uid = 2367547387 and p.user_consume_amount > 0 then u.user_ukey
    end) as pay_zitai_user_cnt,
    sum(case
      when p.creator_uid = 2367547387 then coalesce(p.user_consume_amount, 0)
      else 0
    end) as consume_amt_to_zitai

  from target_user u
  inner join gamelive.dws_huya_revenue_detail_d_i p
    on u.user_ukey = p.ext['ukey']
  where p.dt between '2026-05-01' and '2026-08-05'
    and p.user_consume_amount > 0
    and p.ext['ukey'] is not null
  group by
    p.dt
),

daily_ent_pay_stat as (
  -- 固定样本每日娱乐品类打赏；ukey 取 ext['ukey']
  -- 娱乐口径：game_label in ('娱乐','娱乐专区')，且排除户外(2165)、星秀(1663)、体育(2356)
  select
    p.dt,
    count(distinct case
      when p.user_consume_amount > 0 then u.user_ukey
    end) as ent_pay_user_cnt,
    sum(coalesce(p.user_consume_amount, 0)) as ent_consume_amt
  from target_user u
  inner join zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i p
    on u.user_ukey = p.ext['ukey']
  where p.dt between '2026-05-01' and '2026-08-05'
    and p.user_consume_amount > 0
    and p.ext['ukey'] is not null
    and p.game_label in ('娱乐', '娱乐专区')
    and p.game_id not in (2165, 1663, 2356)
  group by
    p.dt
)

select
  d.dt as `日期`,
  (select target_user_cnt from target_user_cnt) as `固定样本用户数_7月归属姿态且0804看童锦程`,

  coalesce(w.all_platform_watch_user_cnt, 0) as `固定样本当天全平台观看人数`,
  coalesce(w.all_platform_watch_duration, 0) / 1000.0 / 60
    / nullif(w.all_platform_watch_user_cnt, 0) as `固定样本当天全平台观看人均观时_分钟`,

  coalesce(w.watch_tong_user_cnt, 0) as `固定样本当天观看童锦程人数`,
  coalesce(w.watch_tong_duration, 0) / 1000.0 / 60
    / nullif(w.watch_tong_user_cnt, 0) as `固定样本当天观看童锦程人均观时_分钟`,

  coalesce(w.watch_zitai_user_cnt, 0) as `固定样本当天观看姿态人数`,
  coalesce(w.watch_zitai_duration, 0) / 1000.0 / 60
    / nullif(w.watch_zitai_user_cnt, 0) as `固定样本当天观看姿态人均观时_分钟`,

  coalesce(ew.ent_watch_user_cnt, 0) as `固定样本当天观看娱乐品类人数`,
  coalesce(ew.ent_watch_duration, 0) / 1000.0 / 60
    / nullif(ew.ent_watch_user_cnt, 0) as `固定样本当天观看娱乐品类人均观时_分钟`,
  coalesce(ew.ent_watch_anchor_cnt, 0) as `固定样本当天观看娱乐品类主播数`,

  coalesce(p.pay_user_cnt, 0) as `固定样本当天打赏人数`,
  case
    when (select target_user_cnt from target_user_cnt) > 0
    then coalesce(p.pay_user_cnt, 0) * 1.0000 / (select target_user_cnt from target_user_cnt)
  end as `固定样本当天打赏率`,
  coalesce(p.consume_amt, 0) as `固定样本当天打赏金额`,
  case
    when p.pay_user_cnt > 0
    then coalesce(p.consume_amt, 0) * 1.0000 / p.pay_user_cnt
  end as `固定样本当天人均打赏金额`,

  coalesce(ep.ent_pay_user_cnt, 0) as `固定样本当天打赏娱乐品类人数`,
  case
    when (select target_user_cnt from target_user_cnt) > 0
    then coalesce(ep.ent_pay_user_cnt, 0) * 1.0000 / (select target_user_cnt from target_user_cnt)
  end as `固定样本当天打赏娱乐品类打赏率`,
  coalesce(ep.ent_consume_amt, 0) as `固定样本当天打赏娱乐品类金额`,
  case
    when ep.ent_pay_user_cnt > 0
    then coalesce(ep.ent_consume_amt, 0) * 1.0000 / ep.ent_pay_user_cnt
  end as `固定样本当天打赏娱乐品类人均金额`,

  coalesce(p.pay_tong_user_cnt, 0) as `固定样本当天打赏童锦程人数`,
  coalesce(p.consume_amt_to_tong, 0) as `固定样本当天打赏童锦程金额`,
  case
    when p.pay_tong_user_cnt > 0
    then coalesce(p.consume_amt_to_tong, 0) * 1.0000 / p.pay_tong_user_cnt
  end as `固定样本当天打赏童锦程人均金额`,

  coalesce(p.pay_zitai_user_cnt, 0) as `固定样本当天打赏姿态人数`,
  coalesce(p.consume_amt_to_zitai, 0) as `固定样本当天打赏姿态金额`,
  case
    when p.pay_zitai_user_cnt > 0
    then coalesce(p.consume_amt_to_zitai, 0) * 1.0000 / p.pay_zitai_user_cnt
  end as `固定样本当天打赏姿态人均金额`

from daily_calendar d
left join daily_watch_stat w
  on d.dt = w.dt
left join daily_ent_watch_stat ew
  on d.dt = ew.dt
left join daily_pay_stat p
  on d.dt = p.dt
left join daily_ent_pay_stat ep
  on d.dt = ep.dt
order by
  `日期`;
