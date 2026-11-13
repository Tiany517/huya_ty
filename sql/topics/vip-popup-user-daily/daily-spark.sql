-- Spark日调度草稿；仅在源分区就绪后执行；重跑覆盖当天目标分区。
-- 沿用已讨论的同日dt+stime口径，不包含其他源分区内迟到的同日事件。
-- 不限制ety；仅12个相关配置+有效UID；类型可跨组，整体UV须重新去重。
-- 次数为上报条数，没有事件唯一键时不擅自排除重复上报。
-- 调度宏沿用sql/source/AI工坊模板；WITH与INSERT为同一条语句。
-- Spark；新建独立日分区表，不覆盖已有曝光表。
create table if not exists zhgametemp.zty_vip_popup_type_user_d_i_v1 (
  popup_type string comment '拍脸配置定向人群类型，非独立身份鉴定',
  material_id string comment '后台配置ID，对应prop.material_id',
  uid string comment '有效登录用户yyuid',
  exposure_cnt bigint comment '当天该配置对该用户的曝光上报次数'
)
partitioned by (dt string comment '服务器stime自然日')
stored as orc;

with event_base as (
  -- 输入/输出：事件上报记录；先按源分区、stime、配置ID和有效UID过滤，不去重事件。
  select
    dt,
    cast(yyuid as string) as uid,
    eventid,
    from_json(ext['prop'], 'struct<material_id:string>').material_id as material_id
  from gamelive.dwd_huya_event
  where dt = '${tdate?string('yyyy-MM-dd')}'
    and stime >= '${tdate?string('yyyy-MM-dd')} 00:00:00'
    and stime < concat(cast(date_add(cast('${tdate?string('yyyy-MM-dd')}' as date), 1) as string), ' 00:00:00')
    and eventid = 'show/activity_layer'
    and from_json(ext['prop'], 'struct<material_id:string>').material_id in (
      '14559', '14491',
      '14481', '14479', '14477', '14475', '14473', '14471', '14469',
      '14521', '14519', '14517'
    )
    and coalesce(lower(trim(cast(yyuid as string))), '')
        not in ('0','','null','other','-','-1')
),

popup_event as (
  -- 输入/输出仍为事件粒度，无关联，不放大；依据截图配置ID打标。
  -- 配置可能改时间重复投放，不把截图当前有效期硬编码成完整历史窗口。
  select
    dt,
    uid,
    eventid,
    material_id,
    case material_id
      when '14559' then '赛事人群'
      when '14491' then 'LPL战队粉丝'
      when '14481' then '贵族-骑士'
      when '14479' then '历史高消费人群'
      when '14477' then '贵族-帝皇'
      when '14475' then '贵族-君王'
      when '14473' then '贵族-公爵'
      when '14471' then '贵族-领主'
      when '14469' then '贵族-剑士'
      when '14521' then '头部主播粉丝'
      when '14519' then '高频关闭广告人群'
      when '14517' then '高频发弹幕人群'
    end as popup_type
  from event_base
),

final_user as (
  -- 输入：上报记录；输出：material_id+uid唯一，类型由配置ID唯一确定。
  select popup_type, material_id, uid, count(*) as exposure_cnt
  from popup_event
  group by popup_type, material_id, uid
)

insert overwrite table zhgametemp.zty_vip_popup_type_user_d_i_v1
partition (dt = '${tdate?string('yyyy-MM-dd')}')
select popup_type, material_id, uid, exposure_cnt
from final_user;
