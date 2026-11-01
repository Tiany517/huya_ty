create table if not exists zhgametemp.zty_huya_xingxiu_subcategory_monthly_retention_dau_v1 (
  mth string,
  pcode string,
  game_name string,
  sub_category string,
  monthly_avg_dau double,
  daily_watch_mins double,
  total_gift_cnt bigint,
  total_gift_value double,
  total_danmu_cnt bigint,
  avg_daily_danmu_user_cnt double,
  avg_daily_pay_user_cnt double,
  cohort_days bigint,
  danmu_base_user_cnt bigint,
  danmu_7d_retain_user_cnt bigint,
  danmu_7d_retained_rate double,
  danmu_14d_retain_user_cnt bigint,
  danmu_14d_retained_rate double,
  danmu_30d_retain_user_cnt bigint,
  danmu_30d_retained_rate double,
  gift_base_user_cnt bigint,
  gift_7d_retain_user_cnt bigint,
  gift_7d_retained_rate double,
  gift_14d_retain_user_cnt bigint,
  gift_14d_retained_rate double,
  gift_30d_retain_user_cnt bigint,
  gift_30d_retained_rate double
)
stored as orc;

with
-- 主播日子类标签：同一主播日只保留一行；同时命中多个子类时单独归为“星秀-多标签”。
tag_anchor_day as (
  select
    x.dt,
    x.anchor_uid,
    case
      when size(x.sub_category_list) = 1 then x.sub_category_list[0]
      else '星秀-多标签'
    end as sub_category
  from (
    select
      a.dt,
      cast(a.uid as string) as anchor_uid,
      collect_set(
        case
          when b.name like '星秀-好声音%' then '星秀-好声音'
          when b.name like '星秀-舞蹈%' then '星秀-舞蹈'
          when b.name like '星秀-女团%' then '星秀-女团'
          when b.name like '星秀-脱口秀%' then '星秀-脱口秀'
        end
      ) as sub_category_list
    from gamelive.ods_huya_profile_tag_admin a
    inner join gamelive.ods_huya_tag_info_admin b
      on a.dt = b.dt
     and cast(a.tid as string) = b.id
    where a.dt between '2025-01-01' and '2026-10-29'
      and a.status = 1
      and b.status = '1'
      and b.name like '星秀%'
    group by a.dt, cast(a.uid as string)
  ) x
  where size(x.sub_category_list) > 0
),

category_dim as (
  select
    gid,
    max(game_full_name) as game_name
  from gamelive.to_main_games_day
  where dt = '2026-10-29'
    and game_full_name = '星秀'
  group by gid
),

-- 弹幕先聚合到主播日用户粒度；事件品类用 live_gameid 映射，不复制到多个子类。
danmu_anchor_user_day as (
  select
    d.dt,
    'huya' as pcode,
    c.game_name,
    cast(d.lpid as string) as anchor_uid,
    cast(d.luid as string) as user_id,
    count(1) as danmu_cnt
  from gamelive.gamelive_huya_danmu_log d
  inner join category_dim c
    on d.live_gameid = c.gid
  where d.dt between '2025-01-01' and '2026-10-29'
    and d.passed = '0'
    and d.lpid is not null
    and d.luid is not null
    and trim(cast(d.lpid as string)) <> ''
    and trim(cast(d.luid as string)) <> ''
  group by
    d.dt,
    c.game_name,
    cast(d.lpid as string),
    cast(d.luid as string)
),

-- 打赏先聚合到主播日用户粒度；跨订单、跨来源子类汇总，不保留来源子类行。
gift_anchor_user_day as (
  select
    dt,
    'huya' as pcode,
    game_name,
    cast(creator_uid as string) as anchor_uid,
    cast(user_uid as string) as user_id,
    count(1) as gift_cnt,
    sum(cast(user_consume_amount as double)) as gift_value
  from gamelive.dws_huya_revenue_detail_d_i
  where dt between '2025-01-01' and '2026-10-29'
    and live_platform = '虎牙'
    and consume_order_type = '礼物'
    and is_free_item = 0
    and user_consume_amount > 0
    and game_name = '星秀'
    and creator_uid is not null
    and user_uid is not null
    and trim(cast(creator_uid as string)) <> ''
    and trim(cast(user_uid as string)) <> ''
  group by
    dt,
    game_name,
    cast(creator_uid as string),
    cast(user_uid as string)
),

user_anchor_day as (
  select
    coalesce(d.dt, g.dt) as dt,
    coalesce(d.pcode, g.pcode) as pcode,
    coalesce(d.game_name, g.game_name) as game_name,
    coalesce(d.anchor_uid, g.anchor_uid) as anchor_uid,
    coalesce(d.user_id, g.user_id) as user_id,
    coalesce(d.danmu_cnt, 0) as danmu_cnt,
    coalesce(g.gift_cnt, 0) as gift_cnt,
    coalesce(g.gift_value, 0) as gift_value
  from danmu_anchor_user_day d
  full outer join gift_anchor_user_day g
    on d.dt = g.dt
   and d.pcode = g.pcode
   and d.game_name = g.game_name
   and d.anchor_uid = g.anchor_uid
   and d.user_id = g.user_id
),

-- 一层是星秀整体；另一层按主播日子类标签展开。整体与子类分别独立聚合，互不复制。
user_category_day as (
  select
    dt,
    pcode,
    game_name,
    '星秀-整体' as sub_category,
    user_id,
    sum(danmu_cnt) as danmu_cnt,
    sum(gift_cnt) as gift_cnt,
    sum(gift_value) as gift_value
  from user_anchor_day
  group by dt, pcode, game_name, user_id

  union all

  select
    u.dt,
    u.pcode,
    u.game_name,
    t.sub_category,
    u.user_id,
    sum(u.danmu_cnt) as danmu_cnt,
    sum(u.gift_cnt) as gift_cnt,
    sum(u.gift_value) as gift_value
  from user_anchor_day u
  inner join tag_anchor_day t
    on u.dt = t.dt
   and u.anchor_uid = t.anchor_uid
  group by u.dt, u.pcode, u.game_name, t.sub_category, u.user_id
),

daily_flow as (
  select
    dt,
    substr(dt, 1, 7) as mth,
    pcode,
    game_name,
    sub_category,
    sum(danmu_cnt) as danmu_cnt,
    sum(gift_cnt) as gift_cnt,
    sum(gift_value) as gift_value,
    count(distinct if(danmu_cnt > 0, user_id, null)) as danmu_user_cnt,
    count(distinct if(gift_cnt > 0 and gift_value > 0, user_id, null)) as pay_user_cnt
  from user_category_day
  group by dt, substr(dt, 1, 7), pcode, game_name, sub_category
),

monthly_flow as (
  select
    mth,
    pcode,
    game_name,
    sub_category,
    sum(gift_cnt) as total_gift_cnt,
    sum(gift_value) as total_gift_value,
    sum(danmu_cnt) as total_danmu_cnt,
    avg(cast(danmu_user_cnt as double)) as avg_daily_danmu_user_cnt,
    avg(cast(pay_user_cnt as double)) as avg_daily_pay_user_cnt
  from daily_flow
  group by mth, pcode, game_name, sub_category
),

retention_base as (
  select
    dt,
    pcode,
    game_name,
    sub_category,
    user_id,
    if(danmu_cnt > 0, 1, 0) as is_danmu,
    if(gift_cnt > 0 and gift_value > 0, 1, 0) as is_gift
  from user_category_day
  where dt between '2025-01-01' and '2026-09-30'
),

retention_candidate as (
  select
    dt as base_dt,
    date_format(date_add(to_date(dt, 'yyyy-MM-dd'), 6), 'yyyy-MM-dd') as target_dt,
    pcode,
    game_name,
    sub_category,
    user_id,
    7 as retention_day,
    is_danmu,
    is_gift
  from retention_base

  union all

  select
    dt as base_dt,
    date_format(date_add(to_date(dt, 'yyyy-MM-dd'), 13), 'yyyy-MM-dd') as target_dt,
    pcode,
    game_name,
    sub_category,
    user_id,
    14 as retention_day,
    is_danmu,
    is_gift
  from retention_base

  union all

  select
    dt as base_dt,
    date_format(date_add(to_date(dt, 'yyyy-MM-dd'), 29), 'yyyy-MM-dd') as target_dt,
    pcode,
    game_name,
    sub_category,
    user_id,
    30 as retention_day,
    is_danmu,
    is_gift
  from retention_base
),

retention_matched as (
  select
    c.base_dt,
    c.pcode,
    c.game_name,
    c.sub_category,
    c.user_id,
    c.retention_day,
    c.is_danmu,
    c.is_gift,
    coalesce(r.is_danmu, 0) as target_is_danmu,
    coalesce(r.is_gift, 0) as target_is_gift
  from retention_candidate c
  left join retention_base r
    on r.dt = c.target_dt
   and r.pcode = c.pcode
   and r.game_name = c.game_name
   and r.sub_category = c.sub_category
   and r.user_id = c.user_id
),

retention_monthly as (
  select
    substr(base_dt, 1, 7) as mth,
    pcode,
    game_name,
    sub_category,
    count(distinct base_dt) as cohort_days,
    sum(is_danmu) as danmu_base_user_cnt,
    sum(if(retention_day = 7 and is_danmu = 1 and target_is_danmu = 1, 1, 0)) as danmu_7d_retain_user_cnt,
    sum(if(retention_day = 14 and is_danmu = 1 and target_is_danmu = 1, 1, 0)) as danmu_14d_retain_user_cnt,
    sum(if(retention_day = 30 and is_danmu = 1 and target_is_danmu = 1, 1, 0)) as danmu_30d_retain_user_cnt,
    sum(is_gift) as gift_base_user_cnt,
    sum(if(retention_day = 7 and is_gift = 1 and target_is_gift = 1, 1, 0)) as gift_7d_retain_user_cnt,
    sum(if(retention_day = 14 and is_gift = 1 and target_is_gift = 1, 1, 0)) as gift_14d_retain_user_cnt,
    sum(if(retention_day = 30 and is_gift = 1 and target_is_gift = 1, 1, 0)) as gift_30d_retain_user_cnt
  from retention_matched
  group by substr(base_dt, 1, 7), pcode, game_name, sub_category
),

watch_day_all as (
  select
    dt,
    'huya' as pcode,
    '星秀' as game_name,
    '星秀-整体' as sub_category,
    sum(cast(view_mins_only_live as double)) * 60 as watch_mins
  from gamelive.dm_huya_ayyuid_detail_day
  where dt between '2025-01-01' and '2026-10-29'
    and game_name = '星秀'
  group by dt
),

watch_day_sub as (
  select
    w.dt,
    'huya' as pcode,
    '星秀' as game_name,
    t.sub_category,
    sum(cast(w.view_mins_only_live as double)) * 60 as watch_mins
  from gamelive.dm_huya_ayyuid_detail_day w
  inner join tag_anchor_day t
    on w.dt = t.dt
   and cast(w.ayyuid as string) = t.anchor_uid
  where w.dt between '2025-01-01' and '2026-10-29'
    and w.game_name = '星秀'
  group by w.dt, t.sub_category
),

watch_day_out as (
  select dt, pcode, game_name, sub_category, watch_mins from watch_day_all
  union all
  select dt, pcode, game_name, sub_category, watch_mins from watch_day_sub
),

watch_month_days as (
  select
    substr(dt, 1, 7) as mth,
    count(distinct dt) as watch_days
  from gamelive.dm_huya_ayyuid_detail_day
  where dt between '2025-01-01' and '2026-10-29'
  group by substr(dt, 1, 7)
),

monthly_watch as (
  select
    substr(w.dt, 1, 7) as mth,
    w.pcode,
    w.game_name,
    w.sub_category,
    sum(w.watch_mins) / nullif(max(m.watch_days), 0) as daily_watch_mins
  from watch_day_out w
  inner join watch_month_days m
    on substr(w.dt, 1, 7) = m.mth
  group by substr(w.dt, 1, 7), w.pcode, w.game_name, w.sub_category
),

dau_day_all as (
  select
    dt,
    'huya' as pcode,
    '星秀' as game_name,
    '星秀-整体' as sub_category,
    count(distinct ukey) as dau
  from zhgametemp.cwq_huya_ayyuid_session_from_server_with_user_heichan_pachong_v1
  where dt between '2025-01-01' and '2026-10-29'
    and user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios')
    and heichan_lable = 'not_heichan'
    and pachong_lable = 'not_pachong'
    and game_name = '星秀'
  group by dt
),

dau_day_sub as (
  select
    d.dt,
    'huya' as pcode,
    '星秀' as game_name,
    t.sub_category,
    count(distinct d.ukey) as dau
  from zhgametemp.cwq_huya_ayyuid_session_from_server_with_user_heichan_pachong_v1 d
  inner join tag_anchor_day t
    on d.dt = t.dt
   and cast(d.luid as string) = t.anchor_uid
  where d.dt between '2025-01-01' and '2026-10-29'
    and d.user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios')
    and d.heichan_lable = 'not_heichan'
    and d.pachong_lable = 'not_pachong'
    and d.game_name = '星秀'
  group by d.dt, t.sub_category
),

dau_day_out as (
  select dt, pcode, game_name, sub_category, dau from dau_day_all
  union all
  select dt, pcode, game_name, sub_category, dau from dau_day_sub
),

monthly_dau as (
  select
    substr(d.dt, 1, 7) as mth,
    d.pcode,
    d.game_name,
    d.sub_category,
    sum(d.dau) / nullif(max(m.watch_days), 0) as monthly_avg_dau
  from dau_day_out d
  inner join watch_month_days m
    on substr(d.dt, 1, 7) = m.mth
  group by substr(d.dt, 1, 7), d.pcode, d.game_name, d.sub_category
)

insert overwrite table zhgametemp.zty_huya_xingxiu_subcategory_monthly_retention_dau_v1
select
  k.mth,
  k.pcode,
  k.game_name,
  k.sub_category,
  d.monthly_avg_dau,
  w.daily_watch_mins,
  coalesce(f.total_gift_cnt, 0) as total_gift_cnt,
  coalesce(f.total_gift_value, 0) as total_gift_value,
  coalesce(f.total_danmu_cnt, 0) as total_danmu_cnt,
  coalesce(f.avg_daily_danmu_user_cnt, 0) as avg_daily_danmu_user_cnt,
  coalesce(f.avg_daily_pay_user_cnt, 0) as avg_daily_pay_user_cnt,
  coalesce(r.cohort_days, 0) as cohort_days,
  coalesce(r.danmu_base_user_cnt, 0) as danmu_base_user_cnt,
  coalesce(r.danmu_7d_retain_user_cnt, 0) as danmu_7d_retain_user_cnt,
  cast(r.danmu_7d_retain_user_cnt as double) / nullif(r.danmu_base_user_cnt, 0) as danmu_7d_retained_rate,
  coalesce(r.danmu_14d_retain_user_cnt, 0) as danmu_14d_retain_user_cnt,
  cast(r.danmu_14d_retain_user_cnt as double) / nullif(r.danmu_base_user_cnt, 0) as danmu_14d_retained_rate,
  coalesce(r.danmu_30d_retain_user_cnt, 0) as danmu_30d_retain_user_cnt,
  cast(r.danmu_30d_retain_user_cnt as double) / nullif(r.danmu_base_user_cnt, 0) as danmu_30d_retained_rate,
  coalesce(r.gift_base_user_cnt, 0) as gift_base_user_cnt,
  coalesce(r.gift_7d_retain_user_cnt, 0) as gift_7d_retain_user_cnt,
  cast(r.gift_7d_retain_user_cnt as double) / nullif(r.gift_base_user_cnt, 0) as gift_7d_retained_rate,
  coalesce(r.gift_14d_retain_user_cnt, 0) as gift_14d_retain_user_cnt,
  cast(r.gift_14d_retain_user_cnt as double) / nullif(r.gift_base_user_cnt, 0) as gift_14d_retained_rate,
  coalesce(r.gift_30d_retain_user_cnt, 0) as gift_30d_retain_user_cnt,
  cast(r.gift_30d_retain_user_cnt as double) / nullif(r.gift_base_user_cnt, 0) as gift_30d_retained_rate
from (
  select mth, pcode, game_name, sub_category from monthly_flow
  union
  select mth, pcode, game_name, sub_category from monthly_watch
  union
  select mth, pcode, game_name, sub_category from monthly_dau
  union
  select mth, pcode, game_name, sub_category from retention_monthly
) k
left join monthly_flow f
  on k.mth = f.mth
 and k.pcode = f.pcode
 and k.game_name = f.game_name
 and k.sub_category = f.sub_category
left join monthly_watch w
  on k.mth = w.mth
 and k.pcode = w.pcode
 and k.game_name = w.game_name
 and k.sub_category = w.sub_category
left join monthly_dau d
  on k.mth = d.mth
 and k.pcode = d.pcode
 and k.game_name = d.game_name
 and k.sub_category = d.sub_category
left join retention_monthly r
  on k.mth = r.mth
 and k.pcode = r.pcode
 and k.game_name = r.game_name
 and k.sub_category = r.sub_category;
