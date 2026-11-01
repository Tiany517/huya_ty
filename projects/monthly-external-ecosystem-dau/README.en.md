# Monthly External Ecosystem DAU Summary

## Objective

Preserve the monthly DAU extraction and aggregation workflow for Douyin, Kuaishou, and Douyu in Huya's external ecosystem report so it can be continued on the new computer.

## SQL Definitions

- Source SQL: `sql/source/外部生态DAU取数模板_抖音_快手_斗鱼.sql`.
- The current template covers 2025-07-01 through 2026-05-18. Update the date bounds for future runs and verify the latest available partitions.
- Douyin: aggregate `total_dau` by date across `douyin`, `douyin-huxiao`, and `douyin-hushi`, then average daily totals within each month.
- Kuaishou: average `total_dau` by month for `platform='kuaishou'`.
- Douyu: estimate daily DAU as `sum(totalduration) / 60 / 0.116`, then average by month. This is a watch-duration-coefficient estimate, not a platform-reported DAU.
- `valid_dau` is commented out and not used in the final output; the query returns monthly averages derived from `total_dau`.

## Retained Results

[`artifacts/external-platform-dau-monthly.csv`](artifacts/external-platform-dau-monthly.csv) contains anonymized monthly aggregates extracted from the report workbook: Douyin, Kuaishou, Douyu, and their sum, with no streamer or contract detail. Data ends on 2026-05-18, so May 2026 is partial and should not be compared directly with complete months. Historical source coverage and definitions may differ; interpret the total using the report notes for that period rather than as a uniformly deduplicated user count.

## Source Workbooks Not Migrated

The two Excel files under `Desktop/月报_虎牙外部生态DAU/` contain streamer IDs, nicknames, contracts, revenue, or commercialization details and were not copied. Their reusable monthly aggregate was extracted separately without identifiers. The original workbooks remain local.

## Reuse and Updates

1. Update the three SQL partition date conditions and confirm platform source codes and field definitions.
2. Compare query output with the archived monthly aggregates before updating the report.
3. Preserve platform-specific definitions and the partial-month flag when refreshing the aggregate; do not overwrite raw business detail.

中文版本见 `README.md`。
