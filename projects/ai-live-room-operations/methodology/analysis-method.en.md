# AI live-room snapshot review method

## 1. Sources

The local source set contains six files: two byte-identical 2026-08-07 CSV copies, a 2026-09-04 XLSX, a 2026-10-09 XLSX, and two SQL versions (runtime and annotated). Relative paths, sizes, and SHA-256 values are recorded in `artifacts/anonymous-summary/source-manifest.csv`. Raw CSV/XLSX files are not uploaded.

Export dates must be separated from data months:

| Export date | Data month |
| --- | --- |
| 2026-08-07 | 2026-07 |
| 2026-09-04 | 2026-08 |
| 2026-10-09 | 2026-09 |

## 2. Row grain and uniqueness

The candidate row grain is anchor by category. Validation compares row count, unique UID count, and unique `UID + category` count:

- July 2026: 12 rows, 12 UIDs, and 12 `UID + category` keys.
- August 2026: 18 rows, 18 UIDs, and 18 `UID + category` keys.
- September 2026: 18 rows, 12 UIDs, and 18 `UID + category` keys.

Four September anchors cover multiple categories. Only a repeated `UID + category` is a duplicate at the current grain; a repeated UID is not itself a defect.

## 3. De-identification boundary

The builder reads UIDs and nicknames in memory to calculate unique counts, cross-month intersections, and groupings. It removes both fields from every output. Result workbooks, CSV, JSON, README, and methodology files do not contain UIDs or nicknames. The independent validator compares source UID/nickname values with generated file cells, CSV, JSON, and Markdown.

## 4. Metric aggregation

- ACU mean, median, minimum, and maximum use the ACU values present in each month-group.
- Maximum PCU uses the maximum existing PCU value in the group.
- Mean daily live hours is the group mean of the exported `日均直播时长(h)` field.
- Mean app DAU is the group mean of `日均appdau`.
- Mean view hours is the group mean of `日均观时(h)`.
- Mean view minutes per user is the group mean of `日均人均观时(min)`.
- Cross-month coverage de-duplicates UID in memory, then reports intersection, differences, and Jaccard values without exporting UIDs.

These are secondary snapshot summaries, not a rerun of the SQL, and cannot repair upstream definitions.

## 5. SQL flow

The runtime SQL follows this chain:

1. Read the target anchors from `zhgametemp.zty_ai_liveroom_uid_list_v1`.
2. Read streamer-day duration and category-day metrics from `gamelive.dm_huya_ayyuid_detail_day`.
3. Read app-session DAU and view time from `gamelive.dwt_huya_ayyuid_session_from_server_with_user`.
4. Read hourly online users from `gamelive.dw_huya_online_users` and rank the first six hours per anchor/category/day.
5. Resolve category names from `gamelive.to_main_games_day`.
6. Require at least five live days per eligible anchor and remove the 19 dates with the highest daily user counts.
7. Output anchor by category by month, remove records below ACU 100, and assign Head, Neck, Waist, or Tail with thresholds 2,000, 1,000, and 100.

## 6. Static risks

Major risks include:

- `game_full_name != '其他直播'` after a `LEFT JOIN` removes unmatched rows.
- Eligibility groups by UID and nickname together, so nickname changes can split live-day counts.
- The documented monthly one-hour threshold differs from the implemented mean over live-record days.
- The output live-duration denominator is not automatically calendar days.
- Hourly ACU is affected by both the ranking rule and the PCU filter.
- Eligibility dates and DAU use different app product scopes.
- The target list has no partition, version, or precision evidence.

See `artifacts/anonymous-summary/sql-static-review.en.csv` for all risks, evidence, and next actions.

## 7. Validation scope

The independent validator does not import or reuse builder aggregates. It rereads the raw CSV/XLSX and recomputes:

1. Headers, row counts, unique UIDs, and unique `UID + category` keys.
2. Export-date to data-month alignment.
3. Snapshot overview, category summary, tier summary, and cross-month overlap.
4. Source-manifest sizes and SHA-256 values.
5. Byte identity of both repository SQL copies.
6. Presence of core SQL tables, dates, de-duplication, and final filters.
7. Matching IDs in the 13-item English and Chinese risk inventories.
8. Absence of source UIDs and nicknames in generated deliverables.
9. Expected sheet structure in both bilingual workbooks.

Formal SQL execution, target-table refresh, and final-metric reconciliation were not run. The project therefore remains `incomplete`.
