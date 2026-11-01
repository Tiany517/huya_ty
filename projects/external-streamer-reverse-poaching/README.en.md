# External-Streamer Reverse-Poaching Estimation Review

This project preserves the historical “reverse-poaching” logic that mapped external-platform streamer features to heuristic Huya estimates for ACU, acquisition, revenue, and monthly salary. It includes reusable model functions, identifier-free summaries, and explicit method limitations.

Here, “reverse poaching” means external-streamer discovery, screening, and potential estimation. It does not mean that a streamer was contacted, signed, or moved to Huya. The predictions were not validated against each streamer's later Huya outcomes, so they are not evidence of recruiting impact.

## GitHub Path Map

| GitHub path | Content |
| --- | --- |
| `projects/external-streamer-reverse-poaching/README.md` / `README.en.md` | Chinese / English background, key results, and migration boundary |
| `projects/external-streamer-reverse-poaching/methodology/model-and-validation.md` / `.en.md` | Inputs, formulas, parameters, version drift, known defects, and reuse steps |
| `projects/external-streamer-reverse-poaching/scripts/fanwa_estimator.py` | Side-effect-free Douyu, Bilibili, Douyin, and Kuaishou estimation functions with HDFS credentials removed |
| `projects/external-streamer-reverse-poaching/scripts/summarize_fanwa_anonymized.py` | Builds anonymous platform, category, and internal-benchmark summaries from local sources |
| `projects/external-streamer-reverse-poaching/scripts/audit_model_reproducibility.py` | Reconciles source text with the final CSV and reports which historical predictions the current script can reproduce |
| `projects/external-streamer-reverse-poaching/scripts/validate_fanwa_project.py` | Repository-level completeness, anonymization, and base-consistency checks |
| `projects/external-streamer-reverse-poaching/artifacts/anonymous-summary/` | Chinese/English anonymous platform and category summaries, monthly Huya streamer-market benchmark, and model reproducibility evidence |
| `projects/external-streamer-reverse-poaching/artifacts/validation-report.json` | Latest automated validation result |
| `projects/external-streamer-reverse-poaching/source-manifest.csv` | Source size, SHA-256, treatment, and exclusion reason |

Repository: <https://github.com/Tiany517/huya_ty>. Paths above are relative to the repository root; append them to GitHub's `tree/main/` for directories or `blob/main/` for files.

## Background and Data Lineage

The historical workflow had two branches:

1. Douyu / Bilibili: read six-month features from `cys_huya_jingpin_fanwa_feat2`, calculate four prediction fields, and write a date-named temporary table.
2. Douyin / Kuaishou: read online-count percentiles, fans, and live-time features from `cys_huya_jingpin_doukuai_fanwa_6mon_uidcate`, then output ACU, acquisition, and salary estimates separately.

The source scripts hard-coded `HADOOP_USER_NAME` and remote download, upload, and `drop table` commands. The repository version keeps only pure calculation functions and local-file interfaces; it does not connect to or write to the cluster. On the new computer, restore the identity from the encrypted vault and revalidate table names, partitions, and permissions before a rerun.

## Archived Result Overview

`06allres.csv` is the only final prediction table retained here, and it covers only Douyu and Bilibili:

| Platform | Records | Unique anchor IDs | Zero predicted-ACU rate | Predicted ACU P50 | Predicted ACU P90 | Predicted acquisition P50 | Predicted monthly salary P50 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Bilibili | 29,975 | 23,095 | 36.340% | 50 | 150 | 50 | 1,650 |
| Douyu | 4,334 | 2,920 | 17.328% | 50 | 500 | 50 | 1,650 |
| Total | 34,309 | 26,015 | - | - | - | - | - |

Units and interpretation:

- `predict_acu` and `predict_laxin` are model estimates of person-count metrics, not platform-reported values.
- `predict_pay` assumes 20 live days per month, 5.5 hours per live day, and category-specific marginal hourly rates. It is a monthly-salary proxy.
- The original script did not define the period or monetary unit of `predict_yingshou`. Treat it only as a revenue feature, not as a verified monthly revenue value.
- `liucun`, `avg_com`, `danmu`, `fans`, `dingyue_add`, `danmu_only`, `danmu_new`, `live_mins`, `gift_user`, and `gift_value` are external-platform inputs. Their units require the source-table dictionary.

The anonymous category output keeps only platform × category groups with at least 20 records, producing 289 rows. A separate Huya internal benchmark covers 438 calendar days from 2024-06-01 through 2025-08-12. Its source labels are `主播acu` and `主播num`; because the original field definitions are undocumented, the archive uses them only as a time-series and order-of-magnitude reference.

## Required Interpretation Boundaries

1. This is a heuristic mapping with hard-coded parameters, not a fitted regression or machine-learning model. It has no holdout validation or out-of-sample error metric.
2. Predictions depend on manually selected reference streamers, category weights, caps, and platform scales. These choices can change rankings materially and are not observed facts.
3. The archive does not contain final Douyin or Kuaishou output tables, so this repository cannot provide an anonymous result summary for those platforms.
4. The historical output and current scripts differ by version. The current script reproduces all 34,309 `predict_acu` values and all Douyu `predict_laxin` values, but Bilibili `predict_laxin` matches only 23,262 of 29,975 rows (77.605%). To trace an old ranking, use the historical `06allres.csv`; do not present current parameters as the exact historical method.
5. In several Douyu/Bilibili branches, the `danmu_new` cap source is `danmu_only`, which appears to be an implementation defect. The repository copy preserves it and flags it rather than silently changing historical behavior.
6. The Douyin script calls the same function for `predict_acu` and `predict_laxin`, so the two fields are necessarily identical. The archive has no evidence that this was a validated business choice.
7. The source scripts contained HDFS identities and remote table-write commands. Those are removed from the repository version. Any credential present in the source archive should be treated as exposed and rotated.

See `methodology/model-and-validation.en.md` for formulas, parameter tables, and version differences.

## Validation

Run from the repository root:

```powershell
python projects/external-streamer-reverse-poaching/scripts/validate_fanwa_project.py
```

If the original directory is still available locally:

```powershell
$env:FANWA_SOURCE_DIR='<local reverse-poaching source directory>'
python projects/external-streamer-reverse-poaching/scripts/validate_fanwa_project.py --write-report
```

The checks cover row counts, platform distributions, anchor-key uniqueness, anonymous CSV headers, hard-coded credentials in scripts, benchmark month counts, and base-field parity across source files. `model-reproducibility.csv` separately records how well the current script reproduces each historical prediction field.

## Migration Boundary

The approximately 503 MB source directory was not copied. The package excludes two training videos, a RAR archive, the raw `06allres.csv`, `res.txt`, `featt`, row-level names and UIDs, checkpoints, caches, and the raw Hive data and mail configuration inside `mailall.tar.gz`.

The `报警邮件` subdirectory is actually a separate Huya operational-alerting automation project, not part of this estimator. It contains HDFS identities, email-sending logic, and substantial raw data, so it was not mixed into this project. A future migration should review and sanitize it separately.

## Reuse on the New Computer

1. Read this file and `methodology/model-and-validation.en.md`; do not treat predicted values as observed outcomes.
2. Restore the data-platform identity from the encrypted vault, but never write it back into code.
3. Revalidate the latest input partitions, field units, null encoding, and permissions.
4. Run `fanwa_estimator.py` locally and reconcile against the historical `06allres.csv` or a new target table by person and platform.
5. For a new business decision, define labels, thresholds, and human review first. Without subsequent observed Huya outcomes, call the result “candidate discovery,” not “reverse-poaching impact.”

Chinese documentation: `README.md`.
