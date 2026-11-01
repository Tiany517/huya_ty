-- 目的：生成站外主播用户活动日表（单表调度）。
-- 引擎：Spark。
-- 调度变量：tdate，例如 ${tdate?string('yyyy-MM-dd')}。
-- 平台范围：douyu、bilibili、douyin；抖音 douyin_web 统一为 douyin。
-- 用户活动粒度：dt + pcode + r_category + anchor_uid + user_id。
-- 用户活动品类：直接使用源事件品类，不关联主播当天全部品类，不做主品类选择，不做一对多映射。
-- 品类缺失：显式标记为“未知品类”，不丢弃、不平均分摊、不复制到多个品类。
-- 唯一目标表：zhgametemp.zty_jingpin_user_activity_1029_v1。

create table if not exists zhgametemp.zty_jingpin_user_activity_1029_v1 (
  pcode string comment '平台',
  r_category string comment '用户行为对应的直播品类',
  anchor_uid string comment '平台内主播ID',
  user_id string comment '平台内用户ID',
  danmu_cnt bigint comment '普通文字弹幕次数',
  gift_cnt bigint comment '打赏记录次数',
  gift_value double comment '打赏金额'
)
partitioned by (dt string comment '日期分区')
stored as orc;

with danmu_src as (
  -- 普通文字弹幕自带事件级品类，直接保留源品类。
  -- 显式重分区，避免单日高基数用户聚合在 Spark 默认分区数下发生 shuffle 失败。
  select /*+ repartition(512) */
    cast(dt as string) as dt,
    case
      when lower(cast(pcode as string)) = 'douyin_web' then 'douyin'
      else lower(cast(pcode as string))
    end as pcode,
    coalesce(nullif(trim(cast(r_category as string)), ''), '未知品类') as r_category,
    cast(uid as string) as anchor_uid,
    cast(sender as string) as user_id
  from gamelive.dwt_jingpin_danmulog_day
  where dt = '${tdate?string('yyyy-MM-dd')}'
    -- 当前弹幕源无抖音数据；同时接收 douyin 与 douyin_web，避免未来双值漏数。
    and lower(cast(pcode as string)) in ('douyu', 'bilibili', 'douyin', 'douyin_web')
    and cast(msgtype as string) = '0'
    and sender is not null
    and trim(cast(sender as string)) <> ''
),

danmu_user_day as (
  select
    dt, pcode, r_category, anchor_uid, user_id,
    count(*) as danmu_cnt
  from danmu_src
  group by dt, pcode, r_category, anchor_uid, user_id
),

gift_user_raw as (
  -- 斗鱼、B站礼物以源事件r_game_name作为行为品类。
  select
    cast(dt as string) as dt,
    lower(cast(pcode as string)) as pcode,
    coalesce(nullif(trim(cast(r_game_name as string)), ''), '未知品类') as r_category,
    cast(anchor_uid as string) as anchor_uid,
    cast(sender_id as string) as user_id,
    cast(gift_value as double) as gift_value
  from zhgametemp.yty_huya_jingpin_yingshou_gift_times
  where dt = '${tdate?string('yyyy-MM-dd')}'
    and lower(cast(pcode as string)) in ('douyu', 'bilibili')
    and sender_id is not null
    and trim(cast(sender_id as string)) <> ''

  union all

  -- 抖音礼物以源事件r_category作为行为品类。
  select
    cast(dt as string) as dt,
    'douyin' as pcode,
    coalesce(nullif(trim(cast(r_category as string)), ''), '未知品类') as r_category,
    cast(uid as string) as anchor_uid,
    cast(sender_id as string) as user_id,
    cast(gift_value as double) as gift_value
  from zhgametemp.yty_douyin_all_rcategory_gift_detail
  where dt = '${tdate?string('yyyy-MM-dd')}'
    and sender_id is not null
    and trim(cast(sender_id as string)) <> ''
),

gift_src as (
  select /*+ repartition(128) */ * from gift_user_raw
),

gift_user_day as (
  select
    dt,
    pcode,
    r_category,
    anchor_uid,
    user_id,
    count(*) as gift_cnt,
    sum(coalesce(gift_value, 0.0)) as gift_value
  from gift_src
  group by dt, pcode, r_category, anchor_uid, user_id
)

insert overwrite table zhgametemp.zty_jingpin_user_activity_1029_v1
partition (dt='${tdate?string('yyyy-MM-dd')}')

select
  coalesce(d.pcode, g.pcode) as pcode,
  coalesce(d.r_category, g.r_category) as r_category,
  coalesce(d.anchor_uid, g.anchor_uid) as anchor_uid,
  coalesce(d.user_id, g.user_id) as user_id,
  coalesce(d.danmu_cnt, 0) as danmu_cnt,
  coalesce(g.gift_cnt, 0) as gift_cnt,
  coalesce(g.gift_value, 0.0) as gift_value
from danmu_user_day d
full outer join gift_user_day g
  on d.dt = g.dt
 and d.pcode = g.pcode
 and d.r_category = g.r_category
 and coalesce(d.anchor_uid, '') = coalesce(g.anchor_uid, '')
 and d.user_id = g.user_id
;
