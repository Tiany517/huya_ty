with
watch_world_cup_info as (
  select dt, user_ukey
  from (
    select dt, user_ukey, implicit_tags,
      row_number() over (partition by dt, user_ukey order by watch_duration desc) as rnk
    from (
      select dt, user_ukey, implicit_tags, sum(watch_duration) as watch_duration
      from gamelive.dws_huya_user_behavior_d_i
      where dt between '2026-06-12' and '2026-07-01'
        and product in ('huya_andriod', 'huya_ios', 'hmos_kiwi')
        and data_type in ('video_session', 'live_watch_session')
        and live_content_type in ('视频', '直播')
        and content_id <> 0 and vid_can_play = 1 and watch_cnt > 0
      group by dt, user_ukey, implicit_tags
    ) t1
  ) t2
  where rnk = 1
    and (implicit_tags like '%美加墨世界杯%' or implicit_tags like '%世界杯%')
),


video_preference as (
  select v.dt, v.user_ukey
  from (
    select dt, user_ukey, sum(watch_duration) as video_watch_duration
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '2026-06-12' and '2026-07-01'
      and product in ('huya_andriod', 'huya_ios', 'hmos_kiwi')
      and data_type = 'video_session' and live_content_type = '视频'
      and content_id <> 0 and vid_can_play = 1 and watch_cnt > 0
      and (implicit_tags like '%美加墨世界杯%' or implicit_tags like '%世界杯%')
    group by dt, user_ukey
  ) v
  left join (
    select dt, user_ukey, sum(watch_duration) as live_watch_duration
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '2026-06-12' and '2026-07-01'
      and product in ('huya_andriod', 'huya_ios', 'hmos_kiwi')
      and data_type = 'live_watch_session' and live_content_type = '直播'
      and watch_cnt > 0
    group by dt, user_ukey
  ) l on v.dt = l.dt and v.user_ukey = l.user_ukey
  where v.video_watch_duration > coalesce(l.live_watch_duration, 0)
),


new_user_pool as (
  select a.dt, a.user_ukey, a.luid
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a
  where a.dt between '2026-06-12' and '2026-07-01'
    and a.guiyin_tag <> 'mailiang'
),

-- ============================================================
-- 直播拉新原始（未关联搜索）
-- ============================================================
live_new_raw as (
  select dt, user_ukey
  from new_user_pool
  where luid in ('1239543466013','1239543466014','1531433300','1259527226795','585199800')

  union all

  select dt, user_ukey
  from new_user_pool
  where dt between '2026-06-16' and '2026-06-17'
    and luid = '1199568157971'
),

-- ============================================================
-- 视频拉新原始（未关联搜索）
-- ============================================================
video_new_raw as (
  select n.dt, n.user_ukey
  from new_user_pool n
  inner join video_preference p
    on n.dt = p.dt and n.user_ukey = p.user_ukey
),

-- ============================================================
-- 搜索拉新基表：live + video inner join 搜索表
-- ============================================================
search_new_base as (
  select a.dt, a.user_ukey, b.source
  from (
    select dt, user_ukey from live_new_raw
    union all
    select dt, user_ukey from video_new_raw
  ) a
  inner join zhgametemp.zty_huya_world_cup_actual_new_user_v4 b
    on a.user_ukey = b.ukey and a.dt = b.dt
),

-- ============================================================
-- 有效搜索拉新 = 主动搜索 + 被动搜索（含 watch_world_cup_info）
-- ============================================================
valid_search_new_user as (
  -- 主动搜索
  select distinct dt, user_ukey
  from search_new_base
  where source in ('用户手动输入', '自发搜索')

  union

  -- 被动搜索
  select distinct a.dt, a.user_ukey
  from search_new_base a
  inner join watch_world_cup_info c
    on a.dt = c.dt and a.user_ukey = c.user_ukey
  where a.source not in ('用户手动输入', '自发搜索')
),

-- ============================================================
-- 竞猜拉新（裂变 iinvedtype = 2）
-- ============================================================
bet_new_user as (
  select
    from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd') as dt,
    concat('mobile/', t.shuyadeviceid) as user_ukey
  from gamelive.dwd_huya_t_friendinvinfo_d_a t
  where t.dt = '2026-07-01'
    and from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd') between '2026-06-12' and '2026-07-01'
    and t.iscenetype1 = 0
    and t.iscenetype2 = 7
    and t.iinvedtype = 2
  group by from_unixtime(cast(t.ltime as bigint), 'yyyy-MM-dd'), t.shuyadeviceid
),

-- ============================================================
-- 拉新用户统一口径
-- ============================================================
all_user_union as (
  select dt as new_dt, user_ukey from valid_search_new_user
  union all
  select dt as new_dt, user_ukey from bet_new_user
),

-- ============================================================
-- 7日活跃 / 留存
-- ============================================================
user_days as (
  select
    a.new_dt,
    a.user_ukey,
    count(distinct b.dt) as active_days_7d,
    max(case when b.dt = date_add(a.new_dt, 6) then 1 else 0 end) as is_retain
  from all_user_union a
  left join (
    select distinct dt, user_ukey
    from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
    where dt between '2026-06-12' and '2026-07-08'
      and is_black_ukey = 0
  ) b
    on a.user_ukey = b.user_ukey
   and b.dt between a.new_dt and date_add(a.new_dt, 6)
  group by a.new_dt, a.user_ukey
),

-- ============================================================
-- 7日观看明细（按品类）
-- ============================================================
user_watch_7d as (
  select
    a.new_dt,
    a.user_ukey,
    case
      when w.game_label in ('娱乐', '娱乐专区') and w.game_id = 2356 then '体育'
      when w.game_label in ('娱乐', '娱乐专区') then '娱乐'
      when w.game_label in ('游戏', '游戏专区') then '游戏'
      else '其他'
    end as game_label,
    sum(w.watch_duration) as watch_duration
  from all_user_union a
  inner join gamelive.dws_huya_user_behavior_d_i w
    on a.user_ukey = w.user_ukey
   and w.dt between '2026-06-12' and '2026-07-08'
  where
    w.product in ('huya_andriod', 'huya_ios', 'hmos_kiwi')
    and w.data_type = 'live_watch_session'
    and w.live_content_type = '直播'
  group by
    a.new_dt,
    a.user_ukey,
    case
      when w.game_label in ('娱乐', '娱乐专区') and w.game_id = 2356 then '体育'
      when w.game_label in ('娱乐', '娱乐专区') then '娱乐'
      when w.game_label in ('游戏', '游戏专区') then '游戏'
      else '其他'
    end
),

-- ============================================================
-- 7日打赏明细（按品类）
-- ============================================================
user_payment_7d as (
  select
    a.new_dt,
    a.user_ukey,
    case
      when p.game_label in ('娱乐', '娱乐专区') and p.game_id = 2356 then '体育'
      when p.game_label in ('娱乐', '娱乐专区') then '娱乐'
      when p.game_label in ('游戏', '游戏专区') then '游戏'
      else '其他'
    end as game_label,
    sum(p.user_consume_amount) as total_consume_amt
  from all_user_union a
  inner join gamelive.dws_huya_revenue_detail_d_i p
    on a.user_ukey = p.ext['ukey']
    and p.dt between '2026-06-12' and '2026-07-08'
  where
    p.user_consume_amount > 0
  group by
    a.new_dt,
    a.user_ukey,
    case
      when p.game_label in ('娱乐', '娱乐专区') and p.game_id = 2356 then '体育'
      when p.game_label in ('娱乐', '娱乐专区') then '娱乐'
      when p.game_label in ('游戏', '游戏专区') then '游戏'
      else '其他'
    end
),

user_info as (
    select b.ukey, a.gender,cast((2025-cast(substr(a.birthday,1,4) as int)) as string) as age 
    from gamelive.dwd_huya_user_real_name_info_d_a a 
    left join (
      select yyuid,ukey,end_time ,rn 
      from(
        select yyuid,ukey,end_time 
          ,row_number()over(partition by yyuid order by end_time desc) rn
        from gamelive.dwt_huya_session_level 
        where dt between '2026-01-01' and '2026-07-08'
          and length(dt)=10  
          and tag = 'product' 
      )t 
      where rn=1 
    ) b 
    on a.uid = b.yyuid 
    where a.dt='2025-11-23' 
    group by b.ukey, a.gender,cast((2025-cast(substr(a.birthday,1,4) as int)) as string)
)



-- ============================================================
-- 最终输出：你可以按需改成插表/汇总
-- ============================================================
select distinct
  a.new_dt,
  a.user_ukey,
  u.age,
  u.gender,
  d.active_days_7d,
  d.is_retain,
  w.game_label as watch_game_label,
  w.watch_duration,
  p.game_label as pay_game_label,
  p.total_consume_amt
from all_user_union a
left join user_days d
  on a.new_dt = d.new_dt and a.user_ukey = d.user_ukey
left join user_watch_7d w
  on a.new_dt = w.new_dt and a.user_ukey = w.user_ukey
left join user_payment_7d p
  on a.new_dt = p.new_dt and a.user_ukey = p.user_ukey
left join user_info u
  on a.user_ukey = u.ukey