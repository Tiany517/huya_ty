-- Spark；诊断脚本，单独运行，不放入调度写入SQL。
-- 预期：rows=users且invalid_ukeys=0。
select count(*) as rows, count(distinct user_ukey) as users,
  sum(case when user_ukey is null or trim(user_ukey) = '' then 1 else 0 end) as invalid_ukeys
from zhgametemp.zty_huya_watch_user_level_202607_v1;

-- 预期：31行；每日rows=users=固定分层人数，bad_rows=0。
select dt, count(*) as rows, count(distinct user_ukey) as users,
  sum(case when user_ukey is null or is_close_ad is null or close_ad_cnt is null
    or close_ad_cnt < 0
    or is_close_ad <> case when close_ad_cnt > 0 then 1 else 0 end
    then 1 else 0 end) as bad_rows
from zhgametemp.zty_huya_close_ad_user_day_202607_v2
where dt between '2026-07-01' and '2026-07-31'
group by dt
order by dt;

-- 独立路径：按指定一天源事件直接计数，与目标按ukey全量核对。
-- 将本示例2026-07-01改为本次验收日；预期mismatch_users=0。
with source_counts as (
  select cast(e.ukey as string) as user_ukey, count(*) as cnt
  from gamelive.dwd_huya_event e
  where e.dt = '2026-07-01'
    and e.ety = 'custom_event'
    and e.eventid = 'click/universal_ad'
    and from_json(e.ext['prop'], 'struct<area:string>').area = 'close'
    and e.ukey is not null and trim(cast(e.ukey as string)) <> ''
    and coalesce(lower(trim(cast(e.yyuid as string))), '')
      not in ('0','','null','other','-','-1')
  group by cast(e.ukey as string)
)
select sum(case when d.user_ukey is null or d.close_ad_cnt <> coalesce(s.cnt, 0)
  or d.is_close_ad <> case when coalesce(s.cnt, 0) > 0 then 1 else 0 end
  then 1 else 0 end) as mismatch_users
from zhgametemp.zty_huya_watch_user_level_202607_v1 w
left join source_counts s on w.user_ukey = s.user_ukey
left join zhgametemp.zty_huya_close_ad_user_day_202607_v2 d
  on w.user_ukey = d.user_ukey and d.dt = '2026-07-01';
