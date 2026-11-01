# User Profile, TGI, and Clustering Method

## 1. Sources and Cohorts

### 1.1 Device Profile

The source SQL reads active products from `gamelive.dws_huya_active_product_ukey_info_withsdk_d_i` for 2026-03-01 through 2026-03-31 and joins portrait fields from `gamelive.dws_tx_portrait_active_ukey_d_i`. The reported cohorts are:

| Group | Users |
| --- | ---: |
| Harmony | 172,312 |
| Android | 390,718 |
| iOS | 145,179 |

The retained aggregate TGI tables support pairwise comparisons across these groups. The raw device CSV has only 178,432 rows: 178,412 iOS rows, 20 Android rows, and 178,244 unique identifiers. It therefore cannot reproduce the complete three-group source and is only an incomplete, sensitive historical export.

### 1.2 Snooker Acquisition Profile

The source SQL identifies event viewers through a sports-event streamer registration table and session-viewing table for 2026-04-18 through 2026-05-06, then joins the portrait daily table for 2026-04-18 through 2026-05-04. The aggregate TGI table contains 1,072 target users and 2,676 control users.

The stored SQL gives the control group two fewer days because its window ends on 05-04. A comment also calls the 2026 event the 2025 event. Both defects remain; the aggregate is retained only as historical evidence.

### 1.3 World Championship Watchers

The full watcher cohort contains 208,206 target and 366,543 control users. The cohort with at least 10 minutes contains 192,764 target and 395,788 control users. The aggregate folder does not include the complete date range, source tables, and user-filter SQL for these cohorts, so only within-table shares and TGI arithmetic can be independently verified.

## 2. TGI Definition

For each profile dimension and value:

```text
TGI = (target users with value / target cohort size)
      / (control users with value / control cohort size) * 100
```

Within a dimension, category counts should sum to the fixed cohort denominator, and target and control shares should each close to 100%. Shares are displayed with one or two decimals, so recomputation from displayed values allows about 0.16 absolute difference in TGI.

Validation results:

- All seven device, snooker, and World Championship TGI tables pass denominator, share-closure, and formula checks.
- Every dimension returns to the fixed cohort denominator; no repeated display rows were counted as additional users.
- The maximum share-closure error is `0.05` percentage points.
- The maximum TGI arithmetic difference is `0.05`.

TGI is not a significance test. Tiny shares, small samples, and boundary values such as 20, 40, or 200 do not prove a strong business difference. Check counts, denominators, missingness, and multiple comparisons.

## 3. KMeans and PCA

### 3.1 Three Device Groups

The legacy report states that each device group used KMeans with K=4 and a 50,000-user sample. Each cluster-label worksheet has 50,000 rows and 50,000 unique user identifiers. The legacy report displays every cluster share as 100%, even though the cluster counts sum to the 50,000 sample. The anonymous summary recomputes each share as cluster count / 50,000.

Reported silhouette scores were Harmony `0.1156`, Android `0.1180`, and iOS `0.1685`. These are weak. The source folder does not retain complete feature engineering, scaling, random-seed, and fitting code, so the labels cannot be rebuilt.

### 3.2 World Championship Viewers with At Least 10 Minutes

The report states StandardScaler, KMeans K=4, and a 50,000-user sample from 192,764 target users. K=4 has silhouette `0.1434`; two PCA components explain about `30.1%` of variance. The label worksheet has 50,000 rows and 50,000 unique `user_ukey` values.

A silhouette below 0.2 indicates weak structure. Cluster nicknames are labels for this run, not stable population definitions. The source does not establish that the sample is representative or that missing-feature handling is suitable.

### 3.3 Snooker User Clustering

The report states K=4, n=1,072, and silhouette `0.3237`. The retained `processed_data_v2.csv` has 1,086 rows, 1,074 unique pseudonymous identifiers, and 12 duplicate-identifier rows. Its four cluster sizes differ from the report. The folder does not explain the sample, the duplicates, or how the report's 1,072-user clustering was produced from another stage.

The report's cluster profiles, silhouette, and business interpretation are therefore historical material, not verified results. A separate anonymous table retains descriptive statistics from the unreconciled sample and marks its status explicitly.

## 4. Static SQL Risks

| SQL | Confirmed issue | Business effect |
| --- | --- | --- |
| `鸿蒙安卓和苹果用户的画像.sql` | Filter uses `huya_andriod`; CASE maps `huya_android` | Android cohort is not reproducible |
| `鸿蒙安卓和苹果用户的画像.sql` | A 31-day portrait table is joined only by user and then deduplicated | A user may have changing snapshots; no fixed user-level snapshot rule exists |
| `观看过世锦赛和未观看过世锦赛的画像.sql` | Target ends 05-06; control ends 05-04 | Unequal observation windows |
| `观看过世锦赛和未观看过世锦赛的画像.sql` | A 2025 comment sits beside 2026 dates | Event-version ambiguity |
| `观看过世锦赛且单日观看时长最长的用户.sql` | References an undefined CTE | The second branch cannot run |
| `观看过世锦赛且单日观看时长最长的用户.sql` | Filename says single-day; code sums the whole period | Metric does not answer the stated question |
| `观看过世锦赛且单日观看时长最长的用户.sql` | Both branches use the same `user_type` | Target and control cannot be distinguished |
| `观看过世锦赛且单日观看时长最长的用户.sql` | `watch_duration` unit is unconfirmed | Ranking validity remains unproven |

## 5. Correct Use Order

1. Start with the relevant denominator and counts under `artifacts/anonymous-summary/tgi/`.
2. Read `validation/validation-report.en.md` and check whether the result is reproducible, a known issue, or not run.
3. Read the historical DOCX only after the data evidence. Its cluster shares and “acquisition” wording do not override the source checks.
4. Before new campaign, investment, or product decisions, repair the SQL, rerun the cohort, fix the snapshot rule and common window, verify field units, independently rebuild the denominator, and reconcile report, XLSX, CSV, query, and script outputs.

Chinese version: `profile-tgi-and-clustering.md`.
