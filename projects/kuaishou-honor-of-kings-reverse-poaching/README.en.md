# Kuaishou Honor of Kings Reverse-Poaching Screening Review

This project reviews the 2026 screening logic used to discover Kuaishou Honor of Kings streamers and estimate their potential on Huya. It preserves reusable rules, anonymous statistics, version differences, known defects, and reproducibility scripts while separating observed screening facts from heuristic model estimates.

Here, “reverse poaching” means external-streamer discovery and candidate screening. It does not mean a streamer was contacted, signed, or moved to Huya. The Huya ACU, salary, and revenue fields are historical heuristic predictions, not observed outcomes for these streamers.

## GitHub Path Map

| Repository path | Content |
| --- | --- |
| `projects/kuaishou-honor-of-kings-reverse-poaching/README.md` / `README.en.md` | Chinese / English background, key findings, migration boundary, and reuse steps |
| `projects/kuaishou-honor-of-kings-reverse-poaching/methodology/reverse-poaching-rules.md` / `.en.md` | Data grain, formulas, candidate rules, version timeline, model fields, and limitations |
| `projects/kuaishou-honor-of-kings-reverse-poaching/artifacts/anonymous-summary/` | Bilingual anonymous candidate sets, rule reconciliation, monthly profiles, Huya waist benchmark, source coverage, and version comparisons |
| `projects/kuaishou-honor-of-kings-reverse-poaching/artifacts/validation-report.json` | Latest machine-readable validation result |
| `projects/kuaishou-honor-of-kings-reverse-poaching/validation/validation-report.md` / `.en.md` | Chinese / English result contract, risk profile, 26 checks, and unverified boundaries |
| `projects/kuaishou-honor-of-kings-reverse-poaching/scripts/inspect_fanwa_workbooks.py` | Read-only workbook structure, row/column, header, and merged-range inspection |
| `projects/kuaishou-honor-of-kings-reverse-poaching/scripts/compare_fanwa_versions.py` | Historical candidate-set comparison, source hashes, and adjacent-version transitions |
| `projects/kuaishou-honor-of-kings-reverse-poaching/scripts/diagnose_fanwa_rules.py` | Independent monthly reconstruction from raw CSV and reverse rule matching |
| `projects/kuaishou-honor-of-kings-reverse-poaching/scripts/build_anonymized_summary.py` | Generates bilingual anonymous summaries and the source manifest |
| `projects/kuaishou-honor-of-kings-reverse-poaching/scripts/validate_kuaishou_fanwa_project.py` | Validates source hashes, candidate counts, monthly reconciliation, version parity, anonymization, and bilingual structure |

Paths are relative to the repository root; append files to `blob/main/` and directories to `tree/main/` on GitHub.

## Data Versions and Coverage

The source directory contains six XLSX workbooks, two raw CSVs of approximately 102–130 MB, and one 623 B Huya monthly ACU benchmark. Both raw CSVs contain only Kuaishou Honor of Kings records.

| Version | Raw rows | Unique streamers | Streamer-month records | Months |
| --- | ---: | ---: | ---: | --- |
| V1 | 453,551 | 327,768 | 431,103 | 2026-05 through 2026-08 |
| V2 | 579,868 | 402,290 | 551,212 | 2026-04 through 2026-08 |

V2 adds 74,522 streamers, mainly because it includes 2026-04. In the common months from 2026-05 through 2026-08, V1 and V2 have identical active-streamer counts, monthly ACU, daily live minutes, and actual days. The maximum floating-point difference is about `7.28e-12`.

An anchor-month may have multiple source rows because `r_owner` differs: V1 has 22,448 additional rows and V2 has 28,656. The historical workbooks weight ACU by `actual_days` and divide total live minutes by actual days. This formula reproduces the “monthly calculation detail” sheet in all three reviewed workbooks, but the business meaning of `r_owner` and the correct entity-level deduplication remain undocumented.

## Candidate Sets and Key Findings

| Workbook / version | Candidates | Reconciliation result |
| --- | ---: | --- |
| Initial May–July model screen | 53 | All 53 have strict ACU decline and July/May daily live minutes >=80%, but the full rule population is 1,190; the extra rule that reduced it to 53 is undocumented |
| Old conditioned summary | 43 | The filename says “consecutive decline,” but the set exactly matches `ACU>100 + June/May and July/June live ratios >=80%`; only 15 of the 43 strictly decline |
| Old specified-column result | 15 | Its 15 candidates exactly match the V2 final 15 |
| V2 conditioned summary | 15 | Exact match for ACU >100 in May–July, strict decline, and June/May plus July/June daily-live ratios >=80% |
| V2 final specified-column result | 15 | Same as the V2 conditioned summary and treated as the final definition in this review |
| V2 four-month 50% scenario | 8 | The current CSV reproduces all eight exactly; the earlier 7/8 draft was disproved by independent recomputation |

The initial 53 are not an “ACU >100” list: only 16 exceed 100 in all three months, and the minimum monthly ACU ranges from `0.45` to `9.66`. The initial list is therefore an incompletely documented historical intermediate output.

For the V2 final 15, monthly ACU P50 is 354.18, 361.06, 331.18, and 239.90 from 2026-04 through 2026-07. Daily live-minute P50 is 348.16, 330.97, 343.85, and 339.31. Full quantiles are in `artifacts/anonymous-summary/candidate-month-profile.en.csv`.

## Huya Waist Benchmark Comparison

The following comparison uses the V2 final 15 and compares their observed Kuaishou ACU and historical Huya-predicted ACU with the monthly average of Huya Honor of Kings waist-tier streamers:

| Month | Huya waist ACU | Observed ACU P50 | Observed above waist | Predicted ACU P50 | Predicted above waist |
| --- | ---: | ---: | ---: | ---: | ---: |
| 2026-05 | 529.32 | 361.06 | 5 / 15 | 650.00 | 12 / 15 |
| 2026-06 | 542.86 | 331.18 | 5 / 15 | 600.00 | 11 / 15 |
| 2026-07 | 562.49 | 239.90 | 3 / 15 | 550.00 | 7 / 15 |

Three candidates exceed the waist benchmark in all three observed months, versus seven under the model estimate. This suggests optimism in this candidate set, but it is not proof that the model is wrong because no subsequent Huya outcome is available for validation.

The predicted annual-income P50 for the V2 final 15 is CNY 158,400. `huya_predict_laxin` and `huya_predict_yingshou` are entirely missing or blank in the relevant source data and cannot support a conclusion. The candidate prediction data has 46 rows for 45 anchor-months; the only duplicated anchor-month has identical values, so the summary deduplicates to anchor-month without changing the result.

## Migration Boundary

The repository does not copy the raw CSVs or the six workbooks containing streamer IDs, names, owners, or row-level predictions. It retains only:

- De-identified monthly quantiles, candidate counts, version overlap, and rule reconciliation.
- Source filenames, sizes, SHA-256 hashes, treatment, and exclusion reasons.
- Workbook structure manifests without streamer-level cells.
- Reproducible analysis and validation scripts.

The source directory remains untouched. Large raw CSVs, streamer-level details, caches, and binary intermediates are excluded from GitHub.

## Validation

Run from the repository root:

```powershell
python projects/kuaishou-honor-of-kings-reverse-poaching/scripts/validate_kuaishou_fanwa_project.py `
  --source-dir '<Kuaishou reverse-poaching source directory>' `
  --write-report
```

Without the source directory, repository-only checks still run, but source-dependent checks are marked `not_run` and the overall status is `incomplete`; it is never falsely labeled verified.

The local source run passed `26/26` checks with source-dependent checks executed. Coverage includes file hashes, raw coverage, candidate counts, the old 43-candidate defect, exact V2-15 and four-month-8 rules, common-month V1/V2 parity, reconciliation with three workbook monthly-detail sheets, duplicate prediction rows, the Huya benchmark, anonymization, and bilingual document structure.

## Reuse on the New Computer

1. Read this file and `methodology/reverse-poaching-rules.en.md`; never treat predicted ACU or predicted income as observed Huya outcomes.
2. Use `source-manifest.csv` / `source-manifest.en.csv` and `source-coverage.csv` to confirm the restored version. For a newer CSV, first verify months, row counts, units, duplicated owner rows, and nulls.
3. Reconfirm the business definitions of `kuaishou_avg_acu`, `kuaishou_live_mins`, `actual_days`, and `r_owner`.
4. For a new screen, define the contract first: streamer-month grain, owner handling, common months, ACU threshold, daily-live ratio, and missing-month policy.
5. After updating candidates, independently rebuild the V2-15 rule and at least one counterexample; do not use the same code path as its own proof.
6. Only after observed Huya ACU, watch time, and revenue become available can the reverse-poaching model or recruiting effect be evaluated.

Chinese documentation: `README.md`.
