# User Profile, TGI, and Clustering Review

This project organizes the 2026 device-profile, snooker/World Championship viewer-profile, TGI, KMeans, and source-SQL work. Its migration purpose is to let Codex on a new computer separate reproducible descriptive results from historical report defects and clustering outputs that cannot be rebuilt from the retained files.

No user-level records are uploaded. Raw `user_ukey` values, `mobile/<hash>` identifiers, device and profile rows, and user-level cluster labels remain outside Git. The repository keeps anonymous aggregates, source hashes, reports, original SQL, and validation evidence.

## GitHub Path Map

| Repository path | Contents |
| --- | --- |
| `projects/user-profile-analysis/README.md` / `.en.md` | Chinese / English context, findings, limits, and reuse steps |
| `projects/user-profile-analysis/methodology/profile-tgi-and-clustering.md` / `.en.md` | Cohorts, dates, TGI formula, KMeans settings, SQL logic, and report-version differences |
| `projects/user-profile-analysis/sql/` | Three original SQL files, retained without unauthorized repair; the static audit locates known defects |
| `projects/user-profile-analysis/reports/` | Four historical DOCX reports; see `reports/README.en.md` for scope, replacement status, and known wording |
| `projects/user-profile-analysis/artifacts/anonymous-summary/tgi/` | Chinese/English TGI tables for device groups, snooker acquisition, World Championship watchers, and viewers with at least 10 minutes |
| `projects/user-profile-analysis/artifacts/anonymous-summary/clusters/` | Anonymous device and 10-minute-viewer cluster summaries, KMeans evaluation, price tiers, and one explicitly unreconciled snooker sample |
| `projects/user-profile-analysis/artifacts/anonymous-summary/sql-static-audit.csv` / `.en.csv` | Eight static SQL checks: seven confirmed defects and one unverified unit/semantic item |
| `projects/user-profile-analysis/artifacts/anonymous-summary/source-manifest.csv` / `.en.csv` | 151 source paths with size, SHA-256, and inclusion/exclusion rationale |
| `projects/user-profile-analysis/artifacts/anonymous-summary/project-summary.json` | Cohort sizes, sample sizes, artifact row counts, and privacy boundary |
| `projects/user-profile-analysis/artifacts/validation-report.json` | Machine-readable result of 49 checks |
| `projects/user-profile-analysis/validation/validation-report.md` / `.en.md` | Eight validation gates, independent recomputation, known issues, and not-run work |

All paths are relative to the GitHub repository root.

## Four Cohorts

| Analysis | Target | Control | Reproducibility status |
| --- | ---: | ---: | --- |
| Device profile: Harmony, Android, iOS | 172,312 / 390,718 / 145,179 | Pairwise comparisons | TGI counts, share closure, and formulas reconcile; the raw CSV cannot reproduce the full three-group source |
| Snooker acquisition profile V2 | 1,072 | 2,676 | TGI table reconciles; the report clustering cannot be rebuilt from the retained sample |
| World Championship watchers | 208,206 | 366,543 | TGI table reconciles; report narratives conflict across versions |
| World Championship viewers with at least 10 minutes | 192,764 | 395,788 | TGI, cluster sample, and price tiers reconcile; this is not an acquisition cohort |

Every TGI table uses a fixed cohort denominator within each dimension. Target and control shares close to 100%, and the maximum arithmetic difference attributable to one-decimal rounded shares is `0.05`. This proves internal table arithmetic, not field semantics, sample representativeness, significance, or business causality.

## Reusable Results

For the device cohorts, Harmony users have mean wealth score `2.14`, versus Android `1.68` and iOS `0.91`. The Harmony home-ownership share is `73.62%`, versus Android `25.44%`. The Harmony Android share of the level-2 app category “直播” is `47.09%` versus `24.61%`, TGI `191.3`. These rows are in `tgi/device-harmony-vs-android.csv`.

Among World Championship viewers with at least 10 minutes, the 46+ age group is `9.01%` versus `2.94%` in control, TGI `306.5`; Huawei device TGI is `119.1`; car ownership is `40.10%` versus `34.09%`, TGI `117.6`. The complete 255-row table is in `tgi/world-championship-viewers-10min.csv`.

The device reports sampled 50,000 users per group for KMeans. The legacy report printed every cluster as `100.0%`, a clear denominator or formatting defect. Corrected anonymous shares are, for Harmony, `27.56% / 35.32% / 27.10% / 10.03%`; for Android, `42.16% / 16.82% / 12.16% / 28.86%`; and for iOS, `26.86% / 49.23% / 19.36% / 4.54%`.

The 10-minute-viewer KMeans run uses K=4 with silhouette `0.1434`, a weak structure. It describes differences inside that sample and should not turn cluster nicknames into stable population definitions. The sample clusters contain `22,609 / 15,870 / 6,076 / 5,445` users and sum to 50,000.

## Critical Data-Quality Findings

1. `各设备用户画像数据.csv` has 178,432 rows, 178,244 unique user identifiers, and 188 duplicate-identifier rows. Device OS contains 178,412 iOS rows and only 20 Android rows, so it cannot reproduce the reported 708,209-user three-group population. This sensitive detail file is not migrated.
2. `processed_data_v2.csv` has 1,086 rows, 1,074 unique identifiers, and 12 duplicate-identifier rows. The snooker report clustering contains 1,072 users and different cluster labels. The identifier-bearing file is excluded; only an aggregate explicitly marked “unreconciled” is retained.
3. The device SQL filters on `huya_andriod` but maps `huya_android` in its CASE expression. The stored SQL cannot reliably produce the Android cohort, and the existing CSV cannot be reproduced from this file alone.
4. The World Championship watcher SQL uses 2026-04-18 through 05-06 for target users and 04-18 through 05-04 for control users, giving unequal observation windows. A comment also calls the 2026 event the 2025 event.
5. The “single-day longest watch time” SQL sums `watch_duration` across the full period, references an undefined `ot_watch_longest_duration_user` CTE, and gives both output branches the same label.
6. The legacy device report prints 12 cluster shares as `100.0%`; the snooker report says 3,767 records while its TGI denominators sum to 3,748; its narrative contains both `56.2%` and `63.1%` for the music share; and the 10-minute-viewer report incorrectly calls 192,764 viewers an acquisition cohort.

Evidence is in `validation/validation-report.en.md` and `artifacts/anonymous-summary/sql-static-audit.en.csv`.

## Migration Boundary

- Retain three original SQL files, four final or historical reports, seven Chinese/English TGI tables, anonymous cluster and price summaries, source hashes, and validation scripts.
- Do not retain user-level CSVs, XLSX worksheets with `user_ukey`, 132 duplicate generated chart images, Python caches, or large intermediate outputs.
- Do not treat the legacy cluster-share errors, the incorrect “acquisition” wording, or unreproducible KMeans labels as verified facts.

## Reuse Steps on a New Computer

1. Read `methodology/profile-tgi-and-clustering.md` and `validation/validation-report.en.md` before reusing a result.
2. Use the `tgi/` CSV files for descriptive follow-up. Check counts and confidence when a small denominator makes TGI extreme; do not rank by TGI alone.
3. Before rerunning SQL, repair the product enum, profile-snapshot grain, comparison window, CTE, single-day metric, and group labels. Record evidence in the general SQL validation card.
4. When rerunning KMeans, fix the sampling key, random seed, features, missing-value rules, and standardization. Do not infer the feature mapping from cluster nicknames.
5. The `watch_duration` unit, window, and black-market filter remain “not run” until a field dictionary and independent query confirm them.

Chinese version: `README.md`.
