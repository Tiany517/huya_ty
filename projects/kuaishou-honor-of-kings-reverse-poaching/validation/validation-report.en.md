# Kuaishou Honor of Kings Migration and Result Validation

Status: `local source validation completed; 26/26 passed`

This record validates whether the historical workbooks, candidate rules, and migration package are reproduced and explained correctly. It does not establish that the Huya prediction model has been validated against real business outcomes.

## 1. Result Contract

| Item | Definition |
| --- | --- |
| Claim type | Descriptive screening review and rule reconciliation; no causal claim |
| Population | Kuaishou streamers in the Honor of Kings category |
| Time | V1: 2026-05 through 2026-08; V2: 2026-04 through 2026-08; primary candidate window: 2026-05 through 2026-07 |
| Base grain | Source row; one streamer-month may contain multiple `r_owner` rows |
| Intermediate grain | Streamer-month, unique key `(r_lid, mth)` |
| Final grain | Streamer candidate set; 15 in final V2 |
| Metrics | Monthly ACU, daily live minutes, adjacent-month live ratio, predicted streamer-month ACU, predicted annual income, Huya waist ACU benchmark |
| Output | De-identified counts, overlap, quantiles, and rule status; no streamer IDs, names, or owners |
| Falsifiable expectation | The V2 rule must reproduce exactly 15; the old 43 must match the weaker rule with only 15 strict declines |
| Known limitations | No dictionary for `r_owner` or `kuaishou_live_mins`; no observed Huya follow-up outcomes |

## 2. Risk Profile

| Risk | Evidence | Status |
| --- | --- | --- |
| Multiple owner rows per streamer-month inflate counts | Compare raw rows with monthly detail; weight by `actual_days` | Pass; owner business meaning unresolved |
| Filename rule disagrees with implementation | Old 43 exactly match a weaker rule without ACU decline; only 15 strictly decline | Confirmed defect |
| V1/V2 are different snapshots | Recompute hashes, months, rules, and the four-month scenario independently | Pass |
| Prediction duplicate turns 46 rows into 45 streamer-months | One duplicate `(r_lid, mth)` with identical values; deduplicate before use | Pass |
| Model values are mistaken for observed Huya outcomes | Predicted ACU and income are heuristic; `laxin` and `yingshou` are empty | Limitation disclosed |
| Anonymous artifacts leak streamer identity | Scan banned columns and all candidate ID values | Pass |
| Bilingual artifacts diverge structurally | Row and column counts match for eight CSV pairs; English explanatory fields contain no Chinese | Pass |

## 3. Automated Validation Results

| Group | Check | Key result |
| --- | --- | --- |
| Artifact | File set | All 19 expected files exist |
| Artifact | Candidate counts | `53/43/15/15/15/8`, all exact |
| Artifact | Source coverage | V1 `453,551` rows; V2 `579,868` rows |
| Artifact | Duplicate prediction disclosure | 46 rows, 45 streamer-months, one duplicate streamer-month with identical values |
| Artifact | Huya benchmark reconciliation | Three observed and seven predicted above waist in all months; predicted income P50 `158,400` |
| Artifact | Anonymization flags | All three raw-identifier export flags are `False` |
| Artifact | English text | Version descriptions and candidate profiles contain no untranslated Chinese |
| Artifact | Bilingual CSVs | Row and column counts match for all nine pairs |
| Artifact | Bilingual documents | Heading levels and table counts match for all three document pairs |
| Artifact | File size | Largest anonymous artifact is below 1 MiB |
| Artifact | Workbook exclusion | No XLSX/XLS file was copied into the project |
| Source | File count | 9 |
| Source | Hash and size | All match `source-manifest.en.csv` |
| Source | Candidate counts | All six workbooks match |
| Source | Initial shortlist | All 53 belong to the 1,190 population; the second-stage cutoff is missing |
| Source | Initial ACU | Only 16 exceed ACU 100 in all three months |
| Source | Old 43 | Exact weaker-rule match; only 15 strictly decline |
| Source | V2 15 | Exact final-rule match; minimum June/May and July/June live ratio is at least 80% |
| Source | Four-month 8 | Current CSV reproduces all 8 |
| Source | V1/V2 common months | Streamer counts and metrics match in four common months; maximum difference `7.28e-12` |
| Source | Workbook monthly reconciliation | 159, 129, and 45 rows reconcile; maximum difference `1.09e-11` |
| Source | Anonymous content | No candidate ID or banned identifier column appears in an artifact |

The complete machine-readable record is `artifacts/validation-report.json`.

## 4. Independent Rebuild and Correction

1. Monthly ACU and daily live minutes were rebuilt independently from the raw CSV rather than reading workbook monthly results as input.
2. Candidate IDs were read from workbooks only for set comparison and never used to calculate the rules.
3. The monthly-detail sheets for the initial, old, and V2 workbooks were compared row by row with the independent rebuild.
4. An earlier draft concluded that the four-month 50% scenario had 7/8 overlap with one addition and one removal. Independent execution produced eight rule candidates, eight workbook candidates, and eight in the intersection. That draft conclusion was disproved and removed.
5. The prediction data has 46 rows for 45 streamer-months. The duplicate rows belong to one streamer-month and have identical values. The build checks equality before deduplicating by streamer-month and stops if future duplicates conflict.

## 5. Unverified Items

1. No observed Huya ACU, watch time, acquisition, income, or retention is available for these candidates, so predictive accuracy and recruiting impact are unverified.
2. No dictionary defines `r_owner`, whether owners should be combined or separated, or whether live days can repeat across owner rows.
3. No dictionary defines the original time unit and statistical period of `kuaishou_live_mins`; the current formula only reproduces the historical workbook.
4. The workbook does not document how the initial set was reduced from 1,190 to 53.

## 6. Completion Decision

| Condition | Status |
| --- | --- |
| Result contract complete | Pass |
| Triggered data-risk gates | 26/26 pass |
| Independent rebuild | Pass |
| Anonymization and delivery reconciliation | Pass |
| Real model effect | Not run; no follow-up observations |

Final assessment: `migration package and historical rule reproduction verified; Huya model effect not verified`.
