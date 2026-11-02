# AI live-room monthly operations snapshot review

This project reviews AI live-room snapshots for the Waist tier in July, August, and September 2026 and preserves the SQL that produced them. Its purpose is to let Codex on a new computer recover the monitoring population, metric definitions, known quality issues, and the checks required before a refresh.

The three exports were created on 2026-08-07, 2026-09-04, and 2026-10-09, but each contains the preceding month. The filename date is not the data month. The raw files contain streamer UIDs and nicknames and are not uploaded; the repository retains only anonymous summaries and byte-identical SQL copies.

## GitHub path map

| Repository path | Contents |
| --- | --- |
| `projects/ai-live-room-operations/README.md` / `.en.md` | Bilingual context, results, risks, and operating instructions |
| `projects/ai-live-room-operations/methodology/analysis-method.md` / `.en.md` | Grain, formulas, de-identification, and static SQL review method |
| `projects/ai-live-room-operations/scripts/ai-live-room-monthly-tiering.sql` | Runtime monthly anchor-category SQL, copied verbatim |
| `projects/ai-live-room-operations/scripts/ai-live-room-monthly-tiering-annotated.sql` | Corrected and annotated SQL with three validation queries, copied verbatim |
| `projects/ai-live-room-operations/scripts/build_snapshot_review.py` | Rebuilds every anonymous summary from local snapshots without exporting UIDs or nicknames |
| `projects/ai-live-room-operations/scripts/validate_snapshot_review.py` | Independently recomputes metrics and checks hashes, SQL copies, privacy, and workbook structure |
| `projects/ai-live-room-operations/artifacts/anonymous-summary/overview-summary.zh.csv` / `.en.csv` | Anonymous overview of all three snapshots |
| `projects/ai-live-room-operations/artifacts/anonymous-summary/category-summary.zh.csv` / `.en.csv` | Anonymous category summaries by data month |
| `projects/ai-live-room-operations/artifacts/anonymous-summary/tier-summary.zh.csv` / `.en.csv` | Anonymous ACU-tier summaries |
| `projects/ai-live-room-operations/artifacts/anonymous-summary/overlap-summary.zh.csv` / `.en.csv` | Cross-month anchor overlap and Jaccard values |
| `projects/ai-live-room-operations/artifacts/anonymous-summary/quality-summary.zh.csv` / `.en.csv` | Header, null, duplicate-key, month, and tier checks |
| `projects/ai-live-room-operations/artifacts/anonymous-summary/sql-static-review.zh.csv` / `.en.csv` | Thirteen SQL risks with evidence and next actions |
| `projects/ai-live-room-operations/artifacts/anonymous-summary/ai-live-room-snapshot-review-zh.xlsx` / `-en.xlsx` | Bilingual anonymous result workbooks |
| `projects/ai-live-room-operations/artifacts/anonymous-summary/source-manifest.csv` | Relative paths, sizes, SHA-256 values, and inclusion boundaries for six local sources |
| `projects/ai-live-room-operations/artifacts/anonymous-summary/project-summary.json` | Data scale, anchor overlap, and privacy boundary |
| `projects/ai-live-room-operations/validation/validation-report.md` / `.en.md` | Itemized bilingual validation reports |
| `projects/ai-live-room-operations/validation/validation-report.json` | Machine-readable validation result |

All paths are relative to the GitHub repository root.

## Snapshot scale

| Export date | Data month | Rows | Unique anchors | Anchor-category keys | Multi-category anchors | Categories |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 2026-08-07 | 2026-07 | 12 | 12 | 12 | 0 | 3 |
| 2026-09-04 | 2026-08 | 18 | 18 | 18 | 0 | 6 |
| 2026-10-09 | 2026-09 | 18 | 12 | 18 | 4 | 7 |

The 2026-10-09 snapshot has 18 rows but 12 unique UIDs. `UID + category` has 18 unique keys, showing that four anchors cover multiple categories. A repeated UID is not by itself a duplicate-row defect.

## Main results

| Data month | Mean ACU | Median ACU | Max ACU | Max PCU | Mean app DAU | Mean view hours | Mean view minutes per user |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2026-07 | 193.25 | 144.50 | 529.00 | 4,947 | 16,022.67 | 965.67 | 4.08 |
| 2026-08 | 215.41 | 146.00 | 731.46 | 7,170 | 15,086.74 | 737.16 | 5.18 |
| 2026-09 | 202.27 | 168.86 | 439.01 | 1,509 | 8,632.35 | 1,672.81 | 12.34 |

These are descriptive statistics from different list snapshots. September contains only 12 anchors and overlaps August by only 6, so the change in means cannot be interpreted as improvement or deterioration among the same anchors.

Cross-month coverage:

- July vs August: intersection 8; union 22.
- August vs September: intersection 6; union 24.
- July vs September: intersection 5; union 19.
- Present in all three snapshots: 5; three-month union: 28.

Every exported row is in the Waist tier, with ACU between 100 and 1,000. This describes the three outputs, not an eligibility rule that excludes Neck or Head anchors; the final SQL filter is `acu >= 100`, which can include all three tiers.

## Core SQL logic

The runtime SQL uses `zhgametemp.zty_ai_liveroom_uid_list_v1` as the target list and builds anchor-category-month ACU, PCU, app DAU, view time, and per-user view time from streamer-day, user-session, and online-user tables. Eligible anchors require at least five live days; the query removes 19 dates with the highest daily user counts and returns records with ACU of at least 100.

The static review records 13 risks. The highest-priority items are:

1. `game_full_name != '其他直播'` follows a `LEFT JOIN`, so unmatched game dimensions are also removed; the intended handling of unknown categories must be confirmed.
2. Eligibility groups by both `luid` and `nickname`, so a nickname change can split live-day counts and affect eligibility.
3. A comment describes a 30-day duration average, but the one-hour threshold actually uses the mean over live-record days.
4. The displayed `average daily live hours` is an average over retained detail rows, not automatically a 30-calendar-day average.
5. ACU is a mean over selected hourly rows; `pcu_h > 10` also filters hours after ranking, so it is not an unconditional all-day ACU.
6. The eligibility-date query excludes `hmos_kiwi`, while app DAU and view time include it.
7. Dates, the 30-day divisor, game snapshot, and nickname snapshot are hardcoded for September 2026.
8. The uploaded target list lacks a partition, version, upload timestamp, and UID-precision proof; record its hash and match rate before execution.

`huya_andriod` looks like an English spelling error, but existing Huya SQL repeatedly uses the same source enum. It must not be silently changed to `huya_android`; verify it against the product dictionary on the next run. See the `sql-static-review` files for all 13 risks.

## Validation status

The snapshot files, anchor-category grain, month mapping, anonymous summaries, anchor overlap, and privacy boundary are independently reproducible. The SQL has only received a static review. It was not rerun in an authorized bigdata environment, and no refreshed target table was reconciled against the three exports. The overall status is therefore `incomplete`, not `SQL verified`.

## Reuse on a new computer

1. Read this page and `methodology/analysis-method.en.md` first; distinguish export dates from data months.
2. The anonymous overview, category/tier summaries, and anchor coverage are reusable. Do not make causal claims from ACU means computed over changing anchor lists.
3. With the three local CSV/XLSX snapshots available, run `scripts/build_snapshot_review.py --source-root <desktop-root>` to rebuild the outputs.
4. Run `scripts/validate_snapshot_review.py --source-root <desktop-root> --write-report`. If `failed=0` but `not_run=1`, the file layer passed while the SQL execution layer remains incomplete.
5. Before a formal refresh, resolve every `HIGH` risk in `sql-static-review` and execute the list-match, month-distribution, and field-type checks at the end of the annotated SQL.

Chinese version: `README.md`.
