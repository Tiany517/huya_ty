# Kuaishou Honor of Kings Reverse-Poaching Rules and Definitions

## 1. Source Data and Grain

The source CSV provides platform, category, streamer ID, owner, Kuaishou ACU, live minutes, actual days, and Huya-side prediction and internal-benchmark fields.

- Platform filter: `pcode = kuaishou`.
- Category filter: `r_category = 王者荣耀` (Honor of Kings).
- The raw file is not guaranteed to be unique at streamer-month: the same `(r_lid, mth)` may have multiple `r_owner` rows.
- Analysis grain: streamer-month, with unique key `(r_lid, mth)`.
- Final candidate grain: streamer.

Source coverage:

| Version | Rows | Streamers | Streamer-months | Additional owner rows | Months |
| --- | ---: | ---: | ---: | ---: | --- |
| V1 | 453,551 | 327,768 | 431,103 | 22,448 | 2026-05 through 2026-08 |
| V2 | 579,868 | 402,290 | 551,212 | 28,656 | 2026-04 through 2026-08 |

No data dictionary defines `r_owner`. The current analysis follows the historical workbook by applying day weights. Until the business meaning is confirmed, no owner row should be treated as the streamer itself, and duplicated rows must not be averaged without weights.

## 2. Monthly ACU and Daily Live Minutes

The historical workbooks and the independent rebuild use:

```text
acu_days    = sum(kuaishou_avg_acu * actual_days)
total_days  = sum(actual_days)
month_acu   = acu_days / total_days
daily_live  = sum(kuaishou_live_mins) / total_days
```

Validation results:

- All 159 monthly-detail rows for the initial 53 are reproduced.
- All 129 monthly-detail rows for the old 43 are reproduced.
- All 45 monthly-detail rows for the V2 final 15 are reproduced.
- The maximum absolute difference across the common metrics is no more than `1.1e-11`, treated as floating-point equivalence.

`actual_days` is the source's actual-day field. The business period and unit of `kuaishou_live_mins` still lack a field dictionary. The formula is a historically reproducible definition, not a fully audited official metric.

## 3. Candidate Rules

### 3.1 Initial May–July Screen

Rules:

1. ACU is non-null in 2026-05, 06, and 07.
2. `ACU_05 > ACU_06 > ACU_07`.
3. `daily_live_07 / daily_live_05 >= 80%`.

The rule yields 1,190 streamers overall, but the workbook retains only 53. All 53 belong to the 1,190. The second-stage rule that reduced the set to 53 is undocumented, so the complete historical screen cannot be reproduced.

Only 16 of the 53 exceed ACU 100 in all three months, and monthly ACU can fall as low as 0.45. The initial set is not a stable “ACU >100” list.

### 3.2 The Old 43 “Consecutive Decline” Defect

The workbook filename and columns claim consecutive decline, but independent reconstruction shows that the 43 exactly satisfy:

1. ACU >100 in 2026-05, 06, and 07.
2. `daily_live_06 / daily_live_05 >= 80%`.
3. `daily_live_07 / daily_live_06 >= 80%`.

There is no ACU-decline test. Only 15 of the 43 satisfy `ACU_05 > ACU_06 > ACU_07`. This is a confirmed label-implementation-output defect.

### 3.3 V2 Final 15

V2 adds the missing ACU condition:

1. ACU >100 in 2026-05, 06, and 07.
2. `ACU_05 > ACU_06 > ACU_07`.
3. `daily_live_06 / daily_live_05 >= 80%`.
4. `daily_live_07 / daily_live_06 >= 80%`.

The rule reproduces 15 candidates and exactly matches both the V2 conditioned-summary workbook and the V2 specified-column workbook. The old specified-column workbook also contains the same 15; this does not prove the old rule was correct and only shows that the old final shortlist happens to equal the repaired set.

### 3.4 V2 Four-Month 50% Scenario

Rules:

1. ACU >100 in all four months from 2026-04 through 2026-07.
2. ACU strictly declines across all four months.
3. Daily-live ratios for April/May, May/June, and June/July are each at least 50%.

The current V2 CSV reproduces all eight candidates exactly. The earlier uncommitted “7/8 with one added and one removed” draft was disproved by independent execution and must not be reused.

## 4. Version Timeline

| Role | Candidates | Overlap with V2 final 15 | Assessment |
| --- | ---: | ---: | --- |
| `initial_5_7_model` | 53 | 13 | Complete shortlist rule missing |
| `old_5_7_conditioned` | 43 | 15 | Filename label disagrees with implementation |
| `v2_5_7_conditioned` | 15 | 15 | Final rule passes |
| `old_5_7_columns` | 15 | 15 | Same ID set as V2 |
| `v2_5_7_columns` | 15 | 15 | Final entity-list definition |
| `v2_4_7_50pct` | 8 | 7 | Sensitivity scenario replacing the May–July screen |

## 5. Huya Prediction Fields

| Field | Use | Limitation |
| --- | --- | --- |
| `huya_predict_acu` | Predicted Huya ACU | Heuristic estimate without observed follow-up validation |
| `huya_predict_viewhours` | Predicted watch-time proxy | Unit and definition require the model documentation |
| `huya_predict_pay_year` | Predicted annual income | Model output, not observed income |
| `huya_predict_laxin` | Predicted acquisition | Entirely empty in the relevant data; unusable here |
| `huya_predict_yingshou` | Predicted revenue | Entirely empty in the relevant data; unusable here |

Predicted annual-income P50 for the 15 is CNY 158,400. One duplicated streamer-month has identical prediction values; the analysis deduplicates by `(r_lid, mth)` before expanding to 45 streamer-month rows.

## 6. Huya Waist Benchmark

`王者各等级主播的月ACU均值.csv` contains nine identifier-free aggregate rows for head, waist, and tail streamers from 2026-05 through 2026-09, including ACU, daily live duration, and streamer count.

V2 final 15 versus the waist benchmark:

| Month | Waist ACU | Observed above | Predicted above |
| --- | ---: | ---: | ---: |
| 2026-05 | 529.324919 | 5 | 12 |
| 2026-06 | 542.858610 | 5 | 11 |
| 2026-07 | 562.486635 | 3 | 7 |

Only three candidates exceed the waist benchmark in all three observed months, versus seven under prediction. This shows optimism in this candidate set; it neither estimates model error nor supports a recruiting-impact claim.

## 7. Reproduction and Validation

Build anonymous artifacts:

```powershell
python projects/kuaishou-honor-of-kings-reverse-poaching/scripts/build_anonymized_summary.py `
  --source-dir '<Kuaishou reverse-poaching source directory>' `
  --output-dir projects/kuaishou-honor-of-kings-reverse-poaching/artifacts/anonymous-summary
```

Run full validation:

```powershell
python projects/kuaishou-honor-of-kings-reverse-poaching/scripts/validate_kuaishou_fanwa_project.py `
  --source-dir '<Kuaishou reverse-poaching source directory>' `
  --write-report
```

Any formal rule update must rebuild the V2-15, the old-43 counterexample, and the four-month-8 scenario, then reconcile source hashes and the anonymous artifacts. Chinese documentation: `reverse-poaching-rules.md`.
