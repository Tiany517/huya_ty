-- 2026年虎牙主站守护日时间表
-- 引擎：Presto / Spark
-- 输入快照：zhgametemp.zty_main_site_activity_daily_v1_20261029
-- 口径：2026-01-01 至 2026-12-31，is_guard = 1
-- 粒度：一行一个守护日

select distinct
    substr(cast(dt as varchar), 1, 10) as guard_date
from zhgametemp.zty_main_site_activity_daily_v1_20261029
where dt between '2026-01-01' and '2026-12-31'
  and cast(is_guard as int) = 1
order by guard_date;
