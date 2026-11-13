-- Spark一次性首次回补：2026-11-01至2026-11-12。
-- 仅在目标范围为空时运行一次；INSERT INTO不得重复提交以免追加重复行。
-- 动态分区dt位于最终SELECT末列；4个普通列+1个动态分区列。
-- 源上报记录聚合至dt+material_id+uid；全ety，有效UID，同日源dt/stime。
with event_base as (
  -- 输入/输出：事件上报记录；先按源分区、stime、配置ID和有效UID过滤，不去重事件。
  select
    dt,
    cast(yyuid as string) as uid,
    eventid,
    from_json(ext['prop'], 'struct<material_id:string>').material_id as material_id
  from gamelive.dwd_huya_event
  where dt between '2026-11-01' and '2026-11-12'
    and stime >= concat(dt, ' 00:00:00')
    and stime < concat(cast(date_add(cast(dt as date), 1) as string), ' 00:00:00')
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
  select dt, popup_type, material_id, uid, count(*) as exposure_cnt
  from popup_event
  group by dt, popup_type, material_id, uid
)

insert into table zhgametemp.zty_vip_popup_type_user_d_i_v1
partition (dt)
select popup_type, material_id, uid, exposure_cnt, dt
from final_user;
