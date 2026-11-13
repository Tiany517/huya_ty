-- v3新增观看直播间数；不修改v2；观看房间与关闭事件不做房间归因。
-- Spark；待执行验证；调度日期：${tdate?string('yyyy-MM-dd')}。
-- 仅回补2026-07-01至2026-07-31；源分区就绪后运行。
-- 复用sql/source/AI工坊的日期宏，写入结构遵循sql-scheduling-conventions.md。
-- 固定样本：7月观看分层表；该表须每个user_ukey唯一，且回补期间保持不变。
-- 全端；保留原口径的有效登录yyuid过滤，最终以ukey计数。
-- count(*)为关闭事件上报条数；无事件唯一ID，不额外去重重复上报。
-- 每天输出全部分层用户；无关闭记录补0。重跑覆盖当天分区。
create table if not exists zhgametemp.zty_huya_close_ad_user_day_202607_v3 (
  user_ukey string comment '用户ukey，不是uid',
  watch_room_cnt bigint comment '当天正观看时长的去重主播直播间数',
  is_close_ad bigint comment '当天是否点击关闭广告：1是，0否',
  close_ad_cnt bigint comment '当天关闭广告事件上报条数'
)
partitioned by (dt string comment '事件日期')
stored as orc;

with watch_user as (
  -- 输入和输出：每个ukey一行；固定7月分层用户总体，不抽样。
  select user_ukey
  from zhgametemp.zty_huya_watch_user_level_202607_v1
),

watch_base as (
  -- 输入：观看明细；输出：ukey+luid；仅调度当天正观看时长，沿用月分层过滤。
  select distinct
    cast(user_ukey as string) as user_ukey,
    luid
  from gamelive.dwt_huya_ayyuid_session_from_server_with_user
  where dt = '${tdate?string('yyyy-MM-dd')}'
    and tag = 'gameid'
    and htime = 'session'
    and user_yyuid is not null
    and user_ukey is not null
    and trim(cast(user_ukey as string)) <> ''
    and user_duration > 0
    and luid is not null
),

watch_count as (
  -- 输入：ukey+luid唯一；输出：ukey唯一；同主播多场直播按一个直播间计数。
  select
    user_ukey,
    count(*) as watch_room_cnt
  from watch_base
  group by user_ukey
),

event_base as (
  -- 输入/输出：事件上报粒度，未去重；仅扫描调度当天分区。
  select
    cast(e.ukey as string) as user_ukey,
    from_json(e.ext['prop'], 'struct<area:string>') as prop
  from gamelive.dwd_huya_event e
  where e.dt = '${tdate?string('yyyy-MM-dd')}'
    and e.ety = 'custom_event'
    and e.eventid = 'click/universal_ad'
    and e.ukey is not null
    and trim(cast(e.ukey as string)) <> ''
    and coalesce(lower(trim(cast(e.yyuid as string))), '')
        not in ('0','','null','other','-','-1')
),

close_count as (
  -- 输入：事件；输出：ukey唯一。area=close表示点击关闭广告。
  select
    user_ukey,
    count(*) as close_ad_cnt
  from event_base
  where prop.area = 'close'
  group by user_ukey
),

final_user as (
  -- 两侧ukey唯一；1:0/1关联，不允许放大；输出行数等于分层表人数。
  select
    w.user_ukey,
    coalesce(r.watch_room_cnt, cast(0 as bigint)) as watch_room_cnt,
    cast(case when c.close_ad_cnt > 0 then 1 else 0 end as bigint) as is_close_ad,
    coalesce(c.close_ad_cnt, cast(0 as bigint)) as close_ad_cnt
  from watch_user w
  left join watch_count r
    on w.user_ukey = r.user_ukey
  left join close_count c
    on w.user_ukey = c.user_ukey
)

insert overwrite table zhgametemp.zty_huya_close_ad_user_day_202607_v3
partition (dt = '${tdate?string('yyyy-MM-dd')}')
select
  user_ukey,
  watch_room_cnt,
  is_close_ad,
  close_ad_cnt
from final_user;
