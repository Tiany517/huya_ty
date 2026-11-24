# Data Sources and Query Patterns

## Query rules

- Resolve dates with `scripts/resolve_report_weeks.py` before writing SQL.
- Write the resulting dates as literal values in every SQL statement.
- Do not use SQL-side current-date functions, relative intervals, or date arithmetic.
- Query with BigData MCP: Presto first, Spark only after a Presto failure.
- Use the following examples as patterns. Replace the literal dates manually for each run and record the values used.

## Reports metrics

| Business metric | Source / field |
|---|---|
| 视频号 | `gamelive.dwd_spider_wxmcn_anchor_livedata_list_d_i`, daily sum of `audiencecnt` |
| 先锋 | `zhgametemp.zzz_huya_sdk_dau_v1`, type `先锋宽口径dau` |
| 微软 | `zhgametemp.zzz_huya_sdk_dau_v1`, type `微软视频播放dau` |
| QQ浏览器 | `zhgametemp.zzz_huya_sdk_dau_v1`, type `qq浏览器汇总dau` |
| 应用宝 | `zhgametemp.zzz_huya_sdk_dau_v1`, type `应用宝视频播放dau` |

For video, filter `cast(onlinetimeduration as double) > 0`. Aggregate duplicate rows to daily anchor grain before use.

## Data-readiness query

This example checks the 2026-11-09 through 2026-11-22 windows. Replace both literals manually for another run.

```sql
select
  'zhgametemp.zzz_huya_sdk_dau_v1' as table_name,
  cast(max(dt) as varchar) as latest_partition,
  count(distinct dt) as distinct_days
from zhgametemp.zzz_huya_sdk_dau_v1
where dt between '2026-11-09' and '2026-11-22'

union all

select
  'gamelive.dwd_spider_wxmcn_anchor_livedata_list_d_i' as table_name,
  cast(max(dt) as varchar) as latest_partition,
  count(distinct dt) as distinct_days
from gamelive.dwd_spider_wxmcn_anchor_livedata_list_d_i
where dt between '2026-11-09' and '2026-11-22'
```

Require `latest_partition >= report_week_end` and `distinct_days = 14` for both sources. If either fails, alert and stop.

## Platform daily query

```sql
select
  dt,
  sum(case when type = '先锋宽口径dau' then dau else 0 end) as pioneer_dau,
  sum(case when type = 'qq浏览器汇总dau' then dau else 0 end) as qqbrowser_dau,
  sum(case when type = '应用宝视频播放dau' then dau else 0 end) as yingyongbao_dau,
  sum(case when type = '微软视频播放dau' then dau else 0 end) as microsoft_dau
from zhgametemp.zzz_huya_sdk_dau_v1
where dt between '2026-11-09' and '2026-11-22'
group by dt
order by dt
```

## Video daily query

```sql
select
  dt,
  count(distinct userid) as anchor_num,
  sum(cast(audiencecnt as bigint)) as video_dau,
  sum(cast(onlinetimeduration as double)) as online_duration
from gamelive.dwd_spider_wxmcn_anchor_livedata_list_d_i
where dt between '2026-11-09' and '2026-11-22'
  and cast(onlinetimeduration as double) > 0
group by dt
order by dt
```

## Anchor contribution query grain

First aggregate at `dt + userid + usernickname`. Verify the resulting `dt + userid` key is unique. Then calculate:

```text
anchor_previous_contribution = previous-week anchor DAU sum / 7
anchor_current_contribution  = current-week anchor DAU sum / 7
anchor_delta                 = current contribution - previous contribution
```

An anchor with no live row on a day contributes zero for that day. Use live-day count and average live duration only as diagnostic dimensions, not as multipliers in the contribution formula.
