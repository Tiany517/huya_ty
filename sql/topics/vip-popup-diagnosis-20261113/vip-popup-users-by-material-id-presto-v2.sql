-- Presto用户明细修正版v2；待完整验收；不自动写表。
-- 11月7日已在源样本确认：eventid=show/activity_layer，后台ID14559位于prop.material_id。
-- 同类12个后台ID按material_id筛选；不限制ety；仅有效登录UID。
-- 2026-11-01至2026-11-12，每个源dt匹配同日stime；不使用atime。
-- 类型表示配置定向人群，同UID可跨配置出现；次数为原始上报条数。
with event_base as (
  -- 输入/输出：事件上报记录；先按源分区、stime、配置ID和有效UID过滤，不去重事件。
  select
    dt,
    cast(yyuid as varchar) as uid,
    eventid,
    json_extract_scalar(ext['prop'], '$.material_id') as material_id
  from gamelive.dwd_huya_event
  where dt between '2026-11-01' and '2026-11-12'
    and stime >= concat(dt, ' 00:00:00')
    and stime < concat(
      cast(date_add('day', 1, cast(dt as date)) as varchar),
      ' 00:00:00'
    )
    and eventid = 'show/activity_layer'
    and json_extract_scalar(ext['prop'], '$.material_id') in (
      '14559', '14491',
      '14481', '14479', '14477', '14475', '14473', '14471', '14469',
      '14521', '14519', '14517'
    )
    and coalesce(lower(trim(cast(yyuid as varchar))), '')
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
)

-- 输出：日期+事件动作+配置ID+UID唯一；次数是上报条数，未排除重复上报。
-- 同UID跨配置出现时，不得将各配置人数直接相加作为整体去重人数。
select
  dt,
  popup_type,
  eventid,
  material_id,
  uid,
  count(*) as exposure_cnt
from popup_event
group by dt, popup_type, eventid, material_id, uid;
