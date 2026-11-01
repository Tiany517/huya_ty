with daily_target_watch_user as (
  -- 2026年5月以来，童锦程和姿态每日观看用户明细
  select
    dt,
    creator_uid as luid,
    user_ukey,
    sum(watch_duration) as user_duration
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
    and creator_uid in (1199568157971, 2367547387)
  group by dt, creator_uid, user_ukey
),

need_user_month as (
  select distinct
    user_ukey,
    date_format(
      add_months(trunc(to_date(dt), 'MM'), -1),
      'yyyy-MM'
    ) as prev_month
  from daily_target_watch_user
),

prev_month_user_luid_watch as (
  -- 用户在上一个自然月内按主播聚合观看时长，单位毫秒
  select
    m.prev_month,
    w.user_ukey,
    w.creator_uid as belong_luid,
    sum(w.watch_duration) as month_user_duration
  from gamelive.dws_huya_user_behavior_d_i w
  inner join need_user_month m
    on w.user_ukey = m.user_ukey
   and substr(w.dt, 1, 7) = m.prev_month
  where w.dt between '2026-04-01' and '2026-07-31'
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
  group by m.prev_month, w.user_ukey, w.creator_uid
),

prev_month_user_belong as (
  -- 每个用户每个上月，只保留观看时长最长的归属主播
  select
    prev_month,
    user_ukey,
    belong_luid
  from (
    select
      prev_month,
      user_ukey,
      belong_luid,
      month_user_duration,
      row_number() over (
        partition by prev_month, user_ukey
        order by month_user_duration desc, belong_luid
      ) as rn
    from prev_month_user_luid_watch
  ) t
  where rn = 1
),

daily_anchor_watch as (
  -- 两个主播每日观看人数、人均观时，以及归属交叉观看指标
  select
    w.dt,
    w.luid,
    count(distinct w.user_ukey) as watch_user_cnt,
    sum(w.user_duration) / 1000.0 / 60 / count(distinct w.user_ukey) as avg_watch_duration_min,

    count(distinct case
      when w.luid = 1199568157971
       and b.belong_luid = 2367547387
      then w.user_ukey
    end) as tong_from_prev_month_zitai_belong_user_cnt,

    sum(case
      when w.luid = 1199568157971
       and b.belong_luid = 2367547387
      then w.user_duration
      else 0
    end) as tong_from_prev_month_zitai_belong_user_duration,

    count(distinct case
      when w.luid = 2367547387
       and b.belong_luid = 1199568157971
      then w.user_ukey
    end) as zitai_from_prev_month_tong_belong_user_cnt

  from daily_target_watch_user w
  left join prev_month_user_belong b
    on w.user_ukey = b.user_ukey
   and date_format(
         add_months(trunc(to_date(w.dt), 'MM'), -1),
         'yyyy-MM'
       ) = b.prev_month
  group by w.dt, w.luid
),

daily_prev_month as (
  -- 每个观察日对应的上一个自然月，用于等值关联归属用户池，避免 cross join
  select distinct
    dt,
    date_format(
      add_months(trunc(to_date(dt), 'MM'), -1),
      'yyyy-MM'
    ) as prev_month
  from daily_target_watch_user
),

daily_zitai_belong_user as (
  -- 每天对应“上个月归属姿态”的用户池
  select
    d.dt,
    b.user_ukey
  from daily_prev_month d
  inner join prev_month_user_belong b
    on d.prev_month = b.prev_month
   and b.belong_luid = 2367547387
),

daily_zitai_belong_user_watch as (
  -- 姿态归属用户每日全平台观时，以及在姿态本身的观时
  select
    u.dt,
    count(distinct case
      when w.watch_duration > 0 then u.user_ukey
    end) as zitai_belong_all_platform_watch_user_cnt,
    sum(coalesce(w.watch_duration, 0)) as zitai_belong_all_platform_user_duration,

    count(distinct case
      when w.creator_uid = 2367547387 and w.watch_duration > 0 then u.user_ukey
    end) as zitai_belong_watch_zitai_user_cnt,
    sum(case
      when w.creator_uid = 2367547387 then coalesce(w.watch_duration, 0)
      else 0
    end) as zitai_belong_watch_zitai_user_duration

  from daily_zitai_belong_user u
  left join gamelive.dws_huya_user_behavior_d_i w
    on u.user_ukey = w.user_ukey
   and u.dt = w.dt
   and w.dt between '2026-05-01' and '2026-08-05'
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
  group by u.dt
),

daily_zitai_belong_user_pay as (
  -- 姿态归属用户每日打赏：全站、童锦程、姿态
  select
    u.dt,
    count(distinct u.user_ukey) as zitai_belong_user_cnt,
    count(distinct case when p.user_consume_amount > 0 then u.user_ukey end) as zitai_belong_pay_user_cnt,
    sum(coalesce(p.user_consume_amount, 0)) as zitai_belong_consume_amt,

    count(distinct case
      when p.creator_uid = 1199568157971 and p.user_consume_amount > 0
      then u.user_ukey
    end) as zitai_belong_pay_tong_user_cnt,
    sum(case
      when p.creator_uid = 1199568157971 then coalesce(p.user_consume_amount, 0)
      else 0
    end) as zitai_belong_consume_amt_to_tong,

    count(distinct case
      when p.creator_uid = 2367547387 and p.user_consume_amount > 0
      then u.user_ukey
    end) as zitai_belong_pay_zitai_user_cnt,
    sum(case
      when p.creator_uid = 2367547387 then coalesce(p.user_consume_amount, 0)
      else 0
    end) as zitai_belong_consume_amt_to_zitai

  from daily_zitai_belong_user u
  left join gamelive.dws_huya_revenue_detail_d_i p
    on u.user_ukey = p.ext['ukey']
   and u.dt = p.dt
   and p.dt between '2026-05-01' and '2026-08-05'
   and p.user_consume_amount > 0
  group by u.dt
),

daily_zitai_belong_ent_watch as (
  -- 姿态归属用户每日观看娱乐品类：
  -- 娱乐口径按内容分类：game_label in ('娱乐','娱乐专区')，且排除户外(2165)、星秀(1663)、体育(2356)
  select
    u.dt,
    count(distinct case
      when w.watch_duration > 0 then u.user_ukey
    end) as zitai_belong_ent_watch_user_cnt,
    sum(coalesce(w.watch_duration, 0)) as zitai_belong_ent_watch_duration,
    count(distinct w.creator_uid) as zitai_belong_ent_watch_anchor_cnt
  from daily_zitai_belong_user u
  left join gamelive.dws_huya_user_behavior_d_i w
    on u.user_ukey = w.user_ukey
   and u.dt = w.dt
   and w.dt between '2026-05-01' and '2026-08-05'
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
   and w.game_label in ('娱乐', '娱乐专区')
   and w.game_id not in (2165, 1663, 2356)
  group by u.dt
),

daily_zitai_belong_ent_pay as (
  -- 姿态归属用户每日打赏娱乐品类：
  -- ukey 取 zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i 的 ext['ukey']
  -- 娱乐口径按内容分类：game_label in ('娱乐','娱乐专区')，且排除户外(2165)、星秀(1663)、体育(2356)
  select
    u.dt,
    count(distinct case
      when p.user_consume_amount > 0 then u.user_ukey
    end) as zitai_belong_ent_pay_user_cnt,
    sum(coalesce(p.user_consume_amount, 0)) as zitai_belong_ent_consume_amt
  from daily_zitai_belong_user u
  left join zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i p
    on u.user_ukey = p.ext['ukey']
   and u.dt = p.dt
   and p.dt between '2026-05-01' and '2026-08-05'
   and p.user_consume_amount > 0
   and p.game_label in ('娱乐', '娱乐专区')
   and p.game_id not in (2165, 1663, 2356)
  group by u.dt
)

select
  a.dt as `日期`,

  max(case when a.luid = 1199568157971 then a.watch_user_cnt end) as `童锦程每日观看人数`,
  max(case when a.luid = 1199568157971 then a.avg_watch_duration_min end) as `童锦程每日人均观看时长_分钟`,

  max(case when a.luid = 2367547387 then a.watch_user_cnt end) as `姿态每日观看人数`,
  max(case when a.luid = 2367547387 then a.avg_watch_duration_min end) as `姿态每日人均观看时长_分钟`,

  max(case
    when a.luid = 1199568157971
    then a.tong_from_prev_month_zitai_belong_user_cnt
  end) as `童锦程观看人数中上月归属姿态用户数`,

  max(case
    when a.luid = 1199568157971
    then a.tong_from_prev_month_zitai_belong_user_duration
  end) / 1000.0 / 60
    / nullif(
        max(case
          when a.luid = 1199568157971
          then a.tong_from_prev_month_zitai_belong_user_cnt
        end),
        0
      ) as `上月归属姿态用户当天观看童锦程人均时长_分钟`,

  max(case
    when a.luid = 2367547387
    then a.zitai_from_prev_month_tong_belong_user_cnt
  end) as `姿态观看人数中上月归属童锦程用户数`,

  coalesce(p.zitai_belong_user_cnt, 0) as `上月归属姿态用户数`,

  coalesce(w.zitai_belong_all_platform_watch_user_cnt, 0) as `上月归属姿态用户当天全平台观看用户数`,
  coalesce(w.zitai_belong_all_platform_user_duration, 0) / 1000.0 / 60
    / nullif(p.zitai_belong_user_cnt, 0) as `上月归属姿态用户当天全平台人均观时_分钟`,

  coalesce(w.zitai_belong_watch_zitai_user_cnt, 0) as `上月归属姿态用户当天观看姿态用户数`,
  coalesce(w.zitai_belong_watch_zitai_user_duration, 0) / 1000.0 / 60
    / nullif(w.zitai_belong_watch_zitai_user_cnt, 0) as `上月归属姿态用户当天观看姿态人均观时_分钟`,

  coalesce(ent_w.zitai_belong_ent_watch_user_cnt, 0) as `上月归属姿态用户当天观看娱乐品类人数`,
  coalesce(ent_w.zitai_belong_ent_watch_duration, 0) / 1000.0 / 60
    / nullif(ent_w.zitai_belong_ent_watch_user_cnt, 0) as `上月归属姿态用户当天观看娱乐品类人均观时_分钟`,
  coalesce(ent_w.zitai_belong_ent_watch_anchor_cnt, 0) as `上月归属姿态用户当天观看娱乐品类主播数`,

  coalesce(p.zitai_belong_pay_user_cnt, 0) as `上月归属姿态且当天打赏用户数`,
  case
    when p.zitai_belong_user_cnt > 0
    then p.zitai_belong_pay_user_cnt * 1.0000 / p.zitai_belong_user_cnt
  end as `上月归属姿态用户当天打赏率`,

  coalesce(p.zitai_belong_consume_amt, 0) as `上月归属姿态用户当天全站打赏金额`,
  case
    when p.zitai_belong_pay_user_cnt > 0
    then coalesce(p.zitai_belong_consume_amt, 0) * 1.0000 / p.zitai_belong_pay_user_cnt
  end as `上月归属姿态用户当天全站人均打赏金额`,

  coalesce(ent_p.zitai_belong_ent_pay_user_cnt, 0) as `上月归属姿态且当天打赏娱乐品类人数`,
  case
    when p.zitai_belong_user_cnt > 0
    then coalesce(ent_p.zitai_belong_ent_pay_user_cnt, 0) * 1.0000 / p.zitai_belong_user_cnt
  end as `上月归属姿态用户当天打赏娱乐品类打赏率`,
  coalesce(ent_p.zitai_belong_ent_consume_amt, 0) as `上月归属姿态用户当天打赏娱乐品类金额`,
  case
    when ent_p.zitai_belong_ent_pay_user_cnt > 0
    then coalesce(ent_p.zitai_belong_ent_consume_amt, 0) * 1.0000 / ent_p.zitai_belong_ent_pay_user_cnt
  end as `上月归属姿态用户当天打赏娱乐品类人均金额`,

  coalesce(p.zitai_belong_pay_tong_user_cnt, 0) as `上月归属姿态且当天打赏童锦程用户数`,
  coalesce(p.zitai_belong_consume_amt_to_tong, 0) as `上月归属姿态用户当天打赏童锦程金额`,
  case
    when p.zitai_belong_pay_tong_user_cnt > 0
    then coalesce(p.zitai_belong_consume_amt_to_tong, 0) * 1.0000 / p.zitai_belong_pay_tong_user_cnt
  end as `上月归属姿态用户当天打赏童锦程人均金额`,

  coalesce(p.zitai_belong_pay_zitai_user_cnt, 0) as `上月归属姿态且当天打赏姿态用户数`,
  coalesce(p.zitai_belong_consume_amt_to_zitai, 0) as `上月归属姿态用户当天打赏姿态金额`,
  case
    when p.zitai_belong_pay_zitai_user_cnt > 0
    then coalesce(p.zitai_belong_consume_amt_to_zitai, 0) * 1.0000 / p.zitai_belong_pay_zitai_user_cnt
  end as `上月归属姿态用户当天打赏姿态人均金额`

from daily_anchor_watch a
left join daily_zitai_belong_user_pay p
  on a.dt = p.dt
left join daily_zitai_belong_user_watch w
  on a.dt = w.dt
left join daily_zitai_belong_ent_watch ent_w
  on a.dt = ent_w.dt
left join daily_zitai_belong_ent_pay ent_p
  on a.dt = ent_p.dt
group by
  a.dt,
  p.zitai_belong_user_cnt,
  p.zitai_belong_pay_user_cnt,
  p.zitai_belong_consume_amt,
  p.zitai_belong_pay_tong_user_cnt,
  p.zitai_belong_consume_amt_to_tong,
  p.zitai_belong_pay_zitai_user_cnt,
  p.zitai_belong_consume_amt_to_zitai,
  w.zitai_belong_all_platform_watch_user_cnt,
  w.zitai_belong_all_platform_user_duration,
  w.zitai_belong_watch_zitai_user_cnt,
  w.zitai_belong_watch_zitai_user_duration,
  ent_w.zitai_belong_ent_watch_user_cnt,
  ent_w.zitai_belong_ent_watch_duration,
  ent_w.zitai_belong_ent_watch_anchor_cnt,
  ent_p.zitai_belong_ent_pay_user_cnt,
  ent_p.zitai_belong_ent_consume_amt
order by `日期`;
