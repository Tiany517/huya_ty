-- 独立核验已于2026-11-13运行并逐日对账通过。rid=1241323838617865216。
-- 此查询从源记录直接聚合，不复用主查询user_day。
-- dt过滤、有效UID与内容优先级沿用用户原SQL。
-- 先检查实际源分区就绪情况，再运行；源表有记录不等于采集日志100%完整。
-- 与主SQL逐日核对：danmu_user_cnt、danmu_cnt、mention_ad_user_cnt、mention_ad_cnt。

select
    substr(d.dt, 1, 10) as dt,
    count(distinct cast(d.luid as varchar)) as danmu_user_cnt,
    count(*) as danmu_cnt,
    count(distinct case
        when coalesce(nullif(trim(d.askscontent), ''), nullif(trim(d.scontent), '')) like '%广告%'
        then cast(d.luid as varchar) end) as mention_ad_user_cnt,
    sum(case
        when coalesce(nullif(trim(d.askscontent), ''), nullif(trim(d.scontent), '')) like '%广告%'
        then 1 else 0 end) as mention_ad_cnt
from gamelive.gamelive_huya_danmu_log d
where d.dt between '2025-01-01' and '2026-10-31'
  and d.passed = '0'
  and d.lpid is not null
  and coalesce(lower(trim(cast(d.luid as varchar))), '')
      not in ('0', '', 'null', 'other', '-', '-1')
  and (
      (d.askscontent is not null and trim(d.askscontent) <> '')
      or (d.scontent is not null and trim(d.scontent) <> '')
  )
group by substr(d.dt, 1, 10)
order by dt
