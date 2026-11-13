-- Presto；探索性只读诊断，不写入或修改目标表。
-- 目标粒度dt+uid；源为事件上报记录，不对事件额外去重。
-- 目标查询输入逐用户计数行，输出每日一行；对比count(*)与count(distinct uid)。
select dt, count(*) as row_cnt, count(distinct uid) as uid_cnt,
  sum(exposure_cnt) as exposure_cnt
from zhgametemp.zty_vip_ad_popup_activity_user_info_v2
where dt between '2026-11-01' and '2026-11-13'
group by dt order by dt;

-- 分区存在不等于有记录或实例成功。
select * from zhgametemp."zty_vip_ad_popup_activity_user_info_v2$partitions"
order by dt;

-- 保持原事件、素材过滤，不加UID有效性条件；与原写入范围一致。
-- 输入事件粒度，输出源dt+atime日期；允许观察异常客户端时间。
select dt, substr(atime, 1, 10) as event_date,
  count(*) as exposures, count(distinct yyuid) as users,
  min(atime) as min_atime, max(atime) as max_atime
from gamelive.dwd_huya_event
where dt = '2026-11-03'
  and ety = 'custom_event'
  and eventid = 'show/activity_layer'
  and json_extract_scalar(ext['prop'], '$.material_id') = '14569'
group by dt, substr(atime, 1, 10)
order by event_date;

-- 独立源路径对账12日曝光合计，与目标sum(exposure_cnt)比较。
select dt, substr(atime, 1, 10) as event_date,
  count(*) as exposures, count(distinct yyuid) as users,
  min(atime) as min_atime, max(atime) as max_atime
from gamelive.dwd_huya_event
where dt = '2026-11-12'
  and ety = 'custom_event'
  and eventid = 'show/activity_layer'
  and json_extract_scalar(ext['prop'], '$.material_id') = '14569'
group by dt, substr(atime, 1, 10)
order by event_date;
