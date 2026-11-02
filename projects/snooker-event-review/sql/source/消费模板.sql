-- ========================================
-- 2024/25赛季：上海大师赛拉新 → 世锦赛留存 → 消费分析
-- 维度：user_ukey + game_id + game_name
-- 规则：一个用户可能在多个game_id被拉新，消费金额只算一次，分配给第一个game_id
-- 
-- 2024年上海大师赛(邀请赛)比赛日期：2024.07.15-21
-- 2025年世锦赛比赛日期：2025.04.18-05.04
-- 消费观察期：2024.07.15 - 2025.05.04
-- ========================================

with match_info as ( -- 找出上海大师赛(邀请赛)的比赛信息，主要是为了找到播过斯诺克赛事的主播
  select distinct
    dt
    ,match_year
    ,live_type
    ,room_type
    ,game_id
    ,match_id
    ,match_name
    ,uid as luid
    ,day
  from zhgametemp.hss_huya_sport_movie_liveroom_register_info_d_a
  where dt='2026-05-07'  -- 用最新的日期分区
    and day>='2024-07-15'
    and day<='2024-07-21'  -- 上海大师赛(邀请赛)的比赛日期：2024.07.15-21
    and match_name like '%斯诺克%'
)
-- 要找到的是通过哪一位主播拉新的，所以要找到播过斯诺克赛事的主播，而不是直接将斯诺克赛事和拉新用户进行关联
, luid_info as( 
  select distinct
    a.dt
    ,b.luid
    ,a.ukey
  from zhgametemp.cwq_huya_ukey_shichang_luid_gameid_guishu_day_v1 a -- 日时长归因底表，找出用户单日观看最长时长的主播
  inner join match_info as b
  on 
    a.luid = b.luid
    and a.dt = b.day -- 如果是看赛事的话，记得把日期对上，才会归到赛事日上，主播关联的话，不代表赛事日的主播的用户，而是单纯的主播的用户
  where 
    a.dt between '2024-07-15' and '2024-07-21' -- 上海大师赛(邀请赛)的比赛日期：2024.07.15-21
    and a.nick like '%斯诺克%'
) 
-- ========================================
-- 拉新用户表（只保留user_ukey，和留存分析SQL一致）
-- ========================================
, acquisition_user_info as (
  select distinct
    a.user_ukey
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a -- 拉新用户表
  inner join match_info as b
    on a.dt = b.day
  and a.game_id = b.game_id
    -- 要增加关联的主播ID，参考之前
  inner join luid_info c
    on a.user_ukey = c.ukey
  where 
    a.dt between '2024-07-15' and '2024-07-21'  -- 上海大师赛(邀请赛)拉新日期：2024.07.15-21
)
-- ========================================
-- 拉新用户的game_id信息（单独获取，不用于过滤用户）
-- ========================================
, user_game_info as (
  select
    user_ukey,
    min(game_id) as first_game_id,
    min(game_name) as first_game_name
  from (
    select distinct a.user_ukey, a.game_id, a.game_name
    from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a
    inner join match_info as b on a.dt = b.day and a.game_id = b.game_id
    inner join luid_info c on a.user_ukey = c.ukey
    where a.dt between '2024-07-15' and '2024-07-21'
  ) t
  group by user_ukey
)
-- ========================================
-- 世锦赛留存判断（基于user_ukey，和留存分析SQL一致）
-- ========================================
, world_retention as (
  select distinct a.user_ukey, 1 as is_world_retained
  from acquisition_user_info a
  inner join gamelive.dws_huya_active_product_ukey_info_withsdk_d_i b -- 活跃用户表，找出拉新用户中在世锦赛活跃的用户
    on a.user_ukey = b.user_ukey 
  where b.dt between '2025-04-18' and '2025-05-04' -- 世锦赛的比赛日期：2025.04.18-05.04
)
-- ========================================
-- 留存用户消费（全周期：按user_ukey聚合，直接关联打赏表ukey）
-- ========================================
, user_consume as (
  select
    ukey as user_ukey,  -- 打赏表的ukey
    sum(consume_amt) as total_consume,
    count(distinct dt) as consume_days,
    count(*) as consume_records
  from zhgametemp.hy_user_anchor_dashang_byd_v0421_v2
  where dt >= '2024-07-15' -- 从上海大师赛拉新开始
    and dt <= '2025-05-04' -- 到世锦赛结束
  group by ukey
)

-- ========================================
-- 输出：game_id维度，消费金额只分配给第一个game_id
-- ========================================
select
  '2024/25赛季' as season,
  u.user_ukey,
  g.first_game_id as game_id,
  g.first_game_name as game_name,
  -- 消费金额只分配给第一个game_id
  coalesce(uc.total_consume, 0) as total_consume,
  coalesce(uc.consume_days, 0) as consume_days,
  coalesce(uc.consume_records, 0) as consume_records,
  case when uc.total_consume > 0 then 1 else 0 end as is_consume,
  wr.is_world_retained

from acquisition_user_info u
inner join world_retention wr on u.user_ukey = wr.user_ukey
left join user_game_info g on u.user_ukey = g.user_ukey
left join user_consume uc on u.user_ukey = uc.user_ukey

limit 1000000;