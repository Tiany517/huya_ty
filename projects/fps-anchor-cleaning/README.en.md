# FPS Streamer Cleaning and Category Live-Time Quantiles

## Objective

Clean the FPS streamer candidate population, audit nickname-to-streamer ID mapping, calculate annual average daily live-time quantiles by tier and main category, and review the static P50/P75 growth scenario.

## Population, Period, and Cleaning

- Source project: `Desktop/FPS主播清洗_20261023/`.
- Observation period: 2026-01-01 through 2026-10-20; annual summaries use 10 calendar months.
- Cleaning started with 91,219 rows and retained 79,723. Sequential exclusions were 3 data-quality rows, 1,906 blank or placeholder nicknames, 658 event/content accounts, 174 club accounts, 6,156 rows below 30 average live minutes per day, and 2,599 high outliers. These are record counts, not deduplicated streamer counts.
- The high-outlier threshold was Q3 + 3×IQR = 733.1732 minutes/day, calculated from 82,322 rows.
- There were 153 top/mid-tier candidates. Applying the threshold of at least 10 average live days per month retained 71 and excluded 82. Average monthly live days equals total live days from January through October 2026 divided by 10; months without streaming count as zero.
- Annual active days and hours are based on all-category streaming records, not only the corresponding FPS category. Some CSV viewers may render `luid` in scientific notation; read it as text and validate it before reuse.

## Annual Average Daily Live-Time Quantiles

The metric is annual average daily live time in minutes/day, using linear interpolation. Quantiles are calculated separately by main category and ACU tier. The table is an anonymized aggregate and contains no streamer-level detail.

| Main category | Tier | P25 | P50 | P75 |
| --- | --- | ---: | ---: | ---: |
| Delta Force | Top | 115.1292 | 141.5250 | 404.7724 |
| Delta Force | Mid | 372.2281 | 415.3825 | 506.8354 |
| PUBG Mobile | Top | 438.8278 | 496.5325 | 566.5177 |
| PUBG Mobile | Mid | 290.0894 | 303.9086 | 474.7670 |
| Valorant | Top | 400.2671 | 476.7331 | 512.6362 |
| Valorant | Mid | 148.5133 | 303.1533 | 456.8487 |
| CS2 | Top | 476.8788 | 478.9474 | 480.0791 |
| CS2 | Mid | 369.3973 | 383.9094 | 415.9046 |
| Peacekeeper Elite | Mid | 363.1142 | 381.9232 | 412.4796 |
| CrossFire | Mid | 333.0229 | 431.1282 | 596.4273 |

Machine-readable results are in [`artifacts/live-duration-quantiles.csv`](artifacts/live-duration-quantiles.csv). Another workbook in the source folder analyzes ACU and average monthly live days; it is not a substitute for these live-time quantiles.

## Nickname Mapping Audit

The nickname mapping audit covered 77,992 input records, with 835 unresolved. The scripts preserve candidate selection and audit-output logic. A successful mapping is not manual identity verification; duplicate names, name changes, and names associated with multiple `luid` values still require audit review.

## P50 Growth Scenario and Metric Limits

- The model extrapolates from successful cross-broadcast event rates and average ACU uplift after success: a 37.50% success rate and 51.28% average ACU uplift for top-tier streamers; 42.86% and 439.44% for mid-tier streamers.
- The source workbook reports a theoretical total of 2,433,208.24 viewer-minutes and a ratio of 2.6489%. Its denominator, 91,858,247.16 viewer-minutes/day, is five-platform Valorant-category interval-average watch time, while the estimated numerator covers multiple main categories. The scopes do not match, so 2.6489% is retained only as a source-workbook value; it must not be interpreted as an overall industry share, realized growth, or causal effect.
- The reference SQL `sql/source/无畏契约/无畏契约_行业区间日均观时_20260101_20261021.sql` filters to Valorant, averages dates with data without filling missing dates with zero, and defines a valid streamer-day as `vaild_acu > 0` with at least 15 live minutes.
- This is a scenario estimate dependent on event success rates, average ACU uplift, streamer mix, and live-supply assumptions; it is not realized incremental performance.

## Code and Reproduction

- `scripts/` contains seven scripts for cleaning, nickname mapping, rule audits, metric preparation, and workbook generation; the originals remain in their local source directory.
- The scripts use local paths under `C:\Users\tiany\Desktop\FPS主播清洗_20261023` and Downloads. Update paths on the new computer and restore inputs from an approved data source before running them.
- Raw inputs, streamer-level CSV/JSON, audit details, and workbooks containing details were not copied. The anonymized quantile CSV is included as a result artifact.

## Sources

- Cleaning summary: `outputs/FPS主播年日均开播时长清洗_20261023.xlsx`, sheet `清洗汇总`.
- Quantile summary: `outputs/01a1624c-a30a-7fb2-920d-19d253f20db4/FPS头部腰部主播_分品类开播时长分位分析_月均10天门槛_20261023.xlsx`.
- Growth scenario: `FPS头部腰部主播_开播时长增长测算_P50P75_20261023.xlsx` in the same directory.
- Source SQL is archived under `sql/source/无畏契约/`.

中文版本见 `README.md`。
