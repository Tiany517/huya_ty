# Xingxiu Interest-Index Analysis

This project reviews January–July 2026 monthly DAU and interest-index behavior for Huya Xingxiu streamers. It preserves reproducible anonymous aggregates, generation scripts, and validation evidence. On a new computer, start with this page and use the GitHub path map below.

## GitHub Path Map

| Repository path | Contents |
| --- | --- |
| `projects/xingxiu-interest-index/README.md` | Independent Chinese project documentation |
| `projects/xingxiu-interest-index/README.en.md` | This English documentation, findings, definitions, and limitations |
| `projects/xingxiu-interest-index/scripts/build_anonymous_artifacts.py` | Rebuilds every anonymous result from the local monthly source CSV |
| `projects/xingxiu-interest-index/scripts/validate_artifacts.py` | Thirty-four source, reconciliation, historical-workbook, privacy, and font checks |
| `projects/xingxiu-interest-index/artifacts/en/monthly_summary.csv` | Seven-row English monthly summary |
| `projects/xingxiu-interest-index/artifacts/en/status_summary.csv` | June–July stock, new/returning, and churned streamer groups |
| `projects/xingxiu-interest-index/artifacts/en/dau_decile_summary.csv` | July 2026 DAU decile summary |
| `projects/xingxiu-interest-index/artifacts/en/hypothesis_group_summary.csv` | Eleven hypothesis groups with counts and changes |
| `projects/xingxiu-interest-index/artifacts/en/quality_findings.csv` | Seven metric, distribution, and reproducibility risks |
| `projects/xingxiu-interest-index/artifacts/en/source_manifest.csv` | Local source size, SHA-256, and upload status |
| `projects/xingxiu-interest-index/artifacts/en/validation_results.csv` | English 34-check report |
| `projects/xingxiu-interest-index/artifacts/en/version_history.csv` | Version history |
| `projects/xingxiu-interest-index/artifacts/en/xingxiu_interest_index_anonymous.xlsx` | English anonymous workbook |
| `projects/xingxiu-interest-index/artifacts/zh/` | Matching Chinese CSVs, validation report, and anonymous workbook |
| `projects/xingxiu-interest-index/artifacts/project_summary.json` | Machine-readable scope and headline metrics |
| `projects/xingxiu-interest-index/artifacts/validation_report.json` | Machine-readable pass/fail summary |

## Question and Scope

The analysis asks how Xingxiu streamer-level monthly DAU and interest index moved from January through July 2026, how June-to-July changes decomposed by streamer status and DAU decile, and which descriptive hypothesis groups explain the apparent difference between falling category DAU and rising interest aggregates.

The source CSV has 22,831 rows, 8,394 unique streamers, and seven months at unique `month + luid` grain. Its fields are `month`, `luid`, `snick`, `game_name`, `dau`, and `user_pro`. The source CSV and historical workbooks contain streamer IDs, nicknames, and per-streamer rankings, so none of them was uploaded.

## Headline Findings

June to July 2026:

- The streamer count fell from 3,540 to 3,381.
- The sum of streamer-level monthly DAU rose from 1,873,101.05 to 1,885,667.77, a net increase of 12,566.72 or `0.671%`.
- The interest-index sum rose from 10,724,252.19 to 11,933,038.49, a net increase of 1,208,786.30 or `11.272%`.
- The hard-coded category DAU fell from 428,326 to 410,709, or `4.113%`.

Status decomposition:

| Status | Streamers | DAU change | Interest-index change |
| --- | ---: | ---: | ---: |
| Present in both months | 2,425 | -23,689.40 | +1,243,561.92 |
| New/returning | 956 | +180,819.10 | +676,691.28 |
| Churned | 1,115 | -144,562.99 | -711,466.90 |

The small net DAU increase occurs because the new/returning contribution exceeds the combined decline from churned and continuing streamers. “New/returning” here means absent from the June file and present in July; “churned” means present in June and absent in July. Neither label proves account-level acquisition or permanent churn.

In July, decile D10 contains 338 streamers and accounts for approximately `88.07%` of summed streamer DAU and `91.72%` of summed interest index. Deciles D1–D9 each contain 338–339 streamers.

The largest hypothesis groups are:

| Group | Streamers | DAU change | Interest-index change |
| --- | ---: | ---: | ---: |
| Other: both DAU and interest up | 946 | +159,870.04 | +898,618.00 |
| New/returning streamers | 956 | +180,819.10 | +676,691.28 |
| Other: both DAU and interest down | 872 | -246,649.54 | -1,087,991.06 |
| Churned streamers | 1,115 | -144,562.99 | -711,466.90 |
| Mid-tier rise: June DAU 3k–10k and both metrics up | 48 | +74,626.06 | +762,730.66 |
| Large/mid-tier rise: June DAU >=10k and both metrics up | 19 | +53,921.83 | +738,413.72 |

These groups are descriptive rules, not validated business mechanisms. They do not show that a streamer action or campaign caused a change in interest.

## Metric Definitions

- `month`: calendar month, fixed to January–July 2026.
- `luid`: streamer key used only for calculation and deduplication; it is absent from uploaded outputs.
- `dau`: the source monthly DAU field. Summing it across streamers may double-count viewers who watched multiple streamers.
- `user_pro`: the source interest-index field. Monthly sums use observed non-null values; the historical June–July status and group analysis treats missing interest as zero.
- `interest_dau_ratio`: streamer-level `user_pro / dau`; aggregate outputs report a median to limit extreme-value influence. It is not retention, conversion, or a user share.
- `category_dau`: seven hard-coded monthly values from the historical analysis script; the project folder has no matching SQL, dashboard extract, or data dictionary.
- July DAU deciles: rank July `dau` with `method="first"`, then split into ten near-equal groups of 338–339 streamers.

## Known Issues and Interpretation Limits

1. Category DAU cannot be traced to a source query; migration validation can only confirm the seven copied values.
2. Summed streamer DAU may double-count viewers, so it is not a deduplicated category DAU and the resulting ratio is not a strict reach rate.
3. Field dictionaries are missing. In addition, `user_pro` is summed across streamers before division by category DAU, so the business unit of the resulting ratio needs owner confirmation.
4. One streamer has missing interest in all seven months. The historical June–July analysis treats that missing value as zero; this migration keeps the convention to reproduce the recorded results.
5. Two July source rows have no `game_name`. The field is not used for grouping, so this does not affect the current aggregates.
6. The streamer-level `user_pro/dau` ratio has a heavy tail: 33 of 22,831 rows exceed 100 and the maximum is about 4,271.61. Its business unit is unconfirmed, so the aggregate review relies heavily on medians.
7. The historical hypothesis workbook has no retained generation script. The migration reconstructs all eleven groups from the source CSV and reconciles their counts and interest changes to that workbook.
8. The project is descriptive. It has no control design, causal identification, or significance testing.

## Validation

Result: `34/34` checks passed with `0` failures.

Checks cover source rows, unique streamer count, month coverage, `month + luid` uniqueness, all seven monthly aggregates, category-DAU inputs, the June–July outer-join statuses, coverage of all 4,496 June–July streamers, status-change closure, ten DAU deciles, decile count and metric closure, reconstruction of all eleven hypothesis groups, Chinese/English agreement, identifier-schema privacy checks, Excel errors, source hashes, and direct reconciliation to the historical monthly, decile, and hypothesis-group sheets.

## Reproduction on a New Computer

Requirements: Python 3, pandas, and openpyxl. The raw CSV is not in GitHub and must come from the encrypted migration backup or the original data source.

```powershell
python projects/xingxiu-interest-index/scripts/build_anonymous_artifacts.py `
  --source <monthly-source-csv> `
  --evidence-workbook <historical-workbook-1> `
  --evidence-workbook <historical-workbook-2> `
  --evidence-workbook <historical-workbook-3>

python projects/xingxiu-interest-index/scripts/validate_artifacts.py `
  --source <monthly-source-csv> `
  --evidence-dir <historical-workbook-folder>
```

Without the raw CSV, read the anonymous CSV/XLSX outputs and this documentation directly. Do not infer streamer-level records from the aggregates.

## Excluded Data

The raw 22,831-row streamer-month CSV, three historical workbooks containing IDs, nicknames, and per-streamer rankings, and all concrete streamer leaderboards were excluded. The source manifest retains file names, sizes, and SHA-256 hashes only.
