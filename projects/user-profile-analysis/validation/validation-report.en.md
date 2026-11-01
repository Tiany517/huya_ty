# User Profile Project Validation Report

Status: `incomplete`. The latest source-backed run contains 49 checks: 41 pass, seven record historical issues, one is not run, and none fail. The project is migrated and its aggregate arithmetic is reproducible, but the legacy profile SQL, reports, and all clustering conclusions cannot be declared fully verified.

Machine-readable results are in `../artifacts/validation-report.json`.

## Result Contract

- Objects: device profiles, snooker acquisition profiles, World Championship watcher profiles, and profiles of viewers with at least 10 minutes.
- Conclusion type: descriptive profiles and TGI differences. No causal effect, recommendation lift, or stable population identity is claimed.
- Inputs: aggregate TGI CSVs, four DOCX reports, three SQL files, two XLSX workbooks with user-level worksheets, and two CSVs containing identifiers.
- Data grain: TGI is cohort × profile dimension × profile value; clustering is sampled-user × cluster label before conversion to group aggregates.
- Output grain: anonymous aggregates only; no user identifiers or user rows.
- Key denominators: devices 172,312 / 390,718 / 145,179; snooker 1,072 / 2,676; World Championship watchers 208,206 / 366,543; viewers with at least 10 minutes 192,764 / 395,788.
- Completion condition: denominator closure, independent TGI recomputation, bilingual parity, identifier scan, source hashes, SQL static review, and report-conflict checks all have evidence.

## Risk Profile and Falsifiable Expectations

High-risk areas are multi-day portrait snapshots, product-enum mismatch, unequal observation windows, TGI small denominators, KMeans sampling and label reproducibility, multiple report versions, and accidental export of user-level files.

The predeclared counterexamples were:

1. If TGI denominators change across profile dimensions, cohort construction or duplicate-row counting is wrong.
2. If cluster shares do not sum to 100%, the report or aggregate mixes samples.
3. If report cluster size differs from the available processed sample, the report clustering is not reproducible from retained files.
4. If source SQL has inconsistent product values or an undefined CTE, the stored SQL cannot alone reproduce the CSV.
5. If `mobile/<hash>` or a `user_ukey` CSV header appears in repository artifacts, the privacy boundary fails.

These counterexamples were executed as checks rather than merely written as principles.

## Eight Validation Gates

| Gate | Result | Evidence |
| --- | --- | --- |
| Data availability | Pass | All 151 source files exist; the source manifest has no missing files or hash drift |
| Schema and semantics | Partial | TGI columns, counts, shares, and cluster summaries are readable; `watch_duration` units and semantics are not run |
| Grain and uniqueness | Historical issue | Snooker processed sample has 1,086 rows but 1,074 unique identifiers and the report has 1,072 users; raw device CSV has 188 duplicate-identifier rows |
| Relationships and row multiplication | SQL defect | Device portrait daily data lacks a fixed snapshot rule; comparison branches and windows are defective |
| Metric invariants | Pass | Every TGI dimension returns to fixed denominators; maximum share-closure error is 0.05 pp and maximum TGI arithmetic difference is 0.05 |
| Independent recomputation | Pass | Seven TGI tables were independently rebuilt from counts and fixed denominators; correct cluster shares were rebuilt from cluster count / 50,000 |
| Boundary and business checks | Historical issue | Legacy report has 12 cluster shares at 100%; record count, App share, and “acquisition” wording conflict |
| Delivery and runtime | Pass | Chinese/English structures match, reports contain no user identifiers, SQL hashes match source, and JSON is reproducible |

## Independent Recalculation

All TGI tables pass:

- `tgi/device-all-pairs.csv`: 578 rows; all three pairwise comparisons return to fixed device cohort sizes.
- `tgi/device-harmony-vs-ios.csv`: 190 rows; denominators 172,312 / 145,179.
- `tgi/device-harmony-vs-android.csv`: 195 rows; denominators 172,312 / 390,718.
- `tgi/device-android-vs-ios.csv`: 193 rows; denominators 390,718 / 145,179.
- `tgi/snooker-watchers-v2.csv`: 151 rows; denominators 1,072 / 2,676.
- `tgi/world-championship-watchers.csv`: 257 rows; denominators 208,206 / 366,543.
- `tgi/world-championship-viewers-10min.csv`: 255 rows; denominators 192,764 / 395,788.

Clustering samples:

- Harmony, Android, and iOS each have 50,000 rows and 50,000 unique identifiers; four cluster counts and shares close within each group.
- The 10-minute-viewer target sample has 50,000 rows and 50,000 unique identifiers; four clusters sum to 50,000.
- Device-price tiers reconcile to 192,764 target and 395,788 control users.
- K=4 silhouette is `0.1434`; the model supports only weak descriptive segmentation.

## Static SQL Review

| SQL | Issue | Status |
| --- | --- | --- |
| 鸿蒙安卓和苹果用户的画像 | `huya_andriod` / `huya_android` enum mismatch | Fail |
| 鸿蒙安卓和苹果用户的画像 | 31-day portrait table has no fixed user snapshot | Fail |
| 观看过世锦赛和未观看过世锦赛的画像 | A 2026 date has a 2025 comment | Fail |
| 观看过世锦赛和未观看过世锦赛的画像 | Target ends 05-06; control ends 05-04 | Fail |
| 观看过世锦赛且单日观看时长最长的用户 | Undefined `ot_watch_longest_duration_user` | Fail |
| 观看过世锦赛且单日观看时长最长的用户 | Filename says single-day; SQL sums full period | Fail |
| 观看过世锦赛且单日观看时长最长的用户 | Target and control share one `user_type` | Fail |
| 观看过世锦赛且单日观看时长最长的用户 | `watch_duration` unit, window, and black-market semantics | Not run |

Full evidence is in `../artifacts/anonymous-summary/sql-static-audit.en.csv`.

## Report-to-Data Conflicts

1. The legacy device report prints all 12 cluster shares as `100.0%`. The cluster counts themselves are present, but each share should be count / 50,000.
2. The snooker report says 3,767 user records, while its TGI denominators are 1,072 + 2,676 = 3,748. The source of the 19-row difference is not retained.
3. The snooker TGI table shows music App target share at `56.25%`; another report paragraph says `63.1%`.
4. The 10-minute-viewer report calls 192,764 viewers “users acquired by a large event.” The cohort is defined by at least 10 minutes of viewing, not by being new.
5. The retained snooker processed sample has 1,086 rows, 1,074 unique identifiers, and 12 duplicate-identifier rows; it cannot reproduce the report's n=1,072 clustering.

## Privacy and Delivery

- Repository CSVs have no `user_ukey` header and no `mobile/<hash>` values.
- The XML in all four DOCX files contains no such user identifiers.
- `各设备用户画像数据.csv` and `processed_data_v2.csv` are not uploaded.
- The two XLSX workbooks are not uploaded; only anonymous summary sheets or identifier-free aggregates were written to CSV.
- The 132 generated chart images are not uploaded separately; the final reports already embed the main charts.

## Not Run and Next Steps

1. Obtain the field dictionary, unit, time window, and black-market definition for `watch_duration`, then verify with an independent query.
2. Repair all three SQL files before rerunning: product enum, fixed portrait snapshot, common comparison window, single-day longest watch time, and group labels.
3. To continue KMeans, recover the full features, sampling key, random seed, missing-value rule, and scaling pipeline, then reconcile report and CSV row by row.
4. Retire the incorrect legacy report conclusions. New reports should point to the anonymous TGI tables and this validation report.

Chinese version: `validation-report.md`.
