# Six-Anchor Cooperation ACU Review

This project reviews a six-anchor cooperation window from 2026-06-24 through 2026-06-30. It compares one observed anchor and five collaborating anchors across a 31-day pre-period, the 7-day event, a 30-day post-period including the event, and a 30-day post-period excluding it.

The migration goal is not to relabel a descriptive comparison as a causal result. It preserves reproducible window formulas, an anonymous daily series, historical-result reconciliation, and a newly identified benchmark reconciliation defect. The local folder contained three CSV files, one Python report builder, and one identity-bearing result workbook; no source SQL was retained.

## GitHub Path Map

| Repository path | Contents |
| --- | --- |
| `projects/molata-cooperation-acu-review/README.md` / `.en.md` | Chinese and English context, findings, risks, and reuse steps |
| `projects/molata-cooperation-acu-review/methodology/analysis-method.md` / `.en.md` | Sample, windows, formulas, benchmarks, and known defects |
| `projects/molata-cooperation-acu-review/artifacts/anonymous-summary/daily_series.csv` / `.zh.csv` | Anonymous 123-day series with anchor groups, platform benchmarks, and reconciliation residual |
| `projects/molata-cooperation-acu-review/artifacts/anonymous-summary/window_summary.csv` / `.zh.csv` | Natural-day and recorded-day averages for 13 units across four windows |
| `projects/molata-cooperation-acu-review/artifacts/anonymous-summary/growth_comparison.csv` / `.zh.csv` | Deltas, growth rates, and percentage-point differences against platform benchmarks |
| `projects/molata-cooperation-acu-review/artifacts/anonymous-summary/share_summary.csv` / `.zh.csv` | Mean daily shares for the six-anchor and five-anchor groups |
| `projects/molata-cooperation-acu-review/artifacts/anonymous-summary/reconciliation_failures.csv` / `.zh.csv` | The 13 dates whose market differences do not reconcile to source anchor totals |
| `projects/molata-cooperation-acu-review/artifacts/anonymous-summary/cooperation-acu-anonymous-zh.xlsx` / `-en.xlsx` | Anonymous Chinese and English result workbooks with methodology sheets |
| `projects/molata-cooperation-acu-review/artifacts/anonymous-summary/source-manifest.csv` | Relative paths, sizes, SHA-256 hashes, classification, and exclusion reasons for five source files |
| `projects/molata-cooperation-acu-review/artifacts/anonymous-summary/project-summary.json` | Scale, windows, and privacy boundary |
| `projects/molata-cooperation-acu-review/scripts/build_anonymous_review.py` | Rebuilds all anonymous artifacts from local source files without writing identities |
| `projects/molata-cooperation-acu-review/scripts/validate_review.py` | Independent recomputation, historical-workbook reconciliation, hashes, residuals, and privacy checks |
| `projects/molata-cooperation-acu-review/validation/validation-report.md` / `.en.md` | Validation gates, conclusion limits, and unresolved items |
| `projects/molata-cooperation-acu-review/validation/validation-report.json` | Machine-readable result of 21 checks |

All paths are relative to the GitHub repository root.

## Data and Windows

- Source snapshot: 2026-05-01 through 2026-08-31; 608 streamer-day rows, six anchors, and 121 dates with at least one anchor record. `dt + anchor` is unique.
- Platform benchmark: 123 unique dates, plus a second benchmark that removes one anomalously high-ACU account.
- Pre-period: 2026-05-24 through 2026-06-23, 31 calendar days.
- Event: 2026-06-24 through 2026-06-30, seven days.
- Post-month including the event: 2026-06-24 through 2026-07-23, 30 days.
- Post-month excluding the event: 2026-07-01 through 2026-07-30, 30 days.
- Natural-day daily average: window ACU sum divided by all calendar days. A missing anchor-day enters group totals as zero.

## Main Results

| Metric | Pre | Post including event | Post excluding event |
| --- | ---: | ---: | ---: |
| Six-anchor natural-day average ACU | 4,813.57 | 5,631.06 | 6,641.35 |
| Six-anchor growth | - | +16.98% | +37.97% |
| Five collaborating anchors | 3,154.13 | 3,078.73 | 3,346.93 |
| Five-anchor growth | - | -2.39% | +6.11% |
| All-platform natural-day average ACU | 207,105.51 | 166,869.57 | 170,744.49 |
| All-platform growth | - | -19.43% | -17.56% |
| Six-anchor mean daily share of outlier-adjusted platform | 3.90% | 4.18% | 4.82% |

The observed anchor drives the six-anchor increase: its natural-day average ACU rises 53.81% in the post-month including the event and 98.53% in the post-month excluding it. Not every collaborating anchor rises, so the six-anchor total cannot be described as uniform improvement.

The window overlaps an event and the summer period, contains only six anchors, and has no matched control or identification design. The defensible wording is a descriptive change around the cooperation window, not “the cooperation caused” the change.

## Critical Reconciliation Finding

Subtracting the platform benchmark that excludes all six anchors from the full-platform benchmark should equal the six-anchor daily total. It does so within `0.11` ACU on 110 dates, but fails on 13 dates:

- Cumulative residual: `+14,548.03` valid ACU.
- Maximum one-day residual: `+4,159.76` on 2026-06-15.
- Seven dates have a residual above 100 ACU.

No upstream SQL was retained, so the cause cannot be assigned to identifier mapping, duplicate rows, category filtering, or one identifier producing multiple streamer records. Platform-relative uplift must remain `pending validation`. The six-anchor source series, natural-day averages, and historical group growth remain independently reproducible.

## Other Data-Quality Findings

1. The local folder contains CSV exports, a Python report builder, and a result workbook, but no SQL to rebuild the extraction from source tables.
2. No six-anchor record exists on 2026-06-28 or 2026-07-04; other dates may cover only some of the six. Treating missing rows as zero follows the legacy script but does not distinguish no stream from missing data.
3. One very high-ACU platform account materially changes the benchmark. A separate anonymized benchmark excluding that account is retained.
4. The post-month including the event overlaps the seven-day event. The two post windows answer different questions and must not be mixed.
5. The legacy streamer-day workbook contains identifiers and nicknames and is not uploaded; the repository uses role labels only.

## Reuse Steps on a New Computer

1. Read this page and `methodology/analysis-method.en.md`, then confirm the windows and natural-day denominator.
2. The anonymous daily series and four-window group aggregates are reusable. Resolve the 13 reconciliation failures before citing platform-relative uplift.
3. Rebuild with the same three local CSV snapshots:
   `python scripts/build_anonymous_review.py --source-dir <local-project-directory>`.
4. Validate with
   `python scripts/validate_review.py --source-dir <local-project-directory> --write-report`.
   A successful script run should show `failed=0`; the current status remains `incomplete` because one substantive reconciliation issue is known and the SQL audit is not run.
5. Any causal claim requires a separate comparison design, parallel-trend review, or matching analysis. This simple pre/post workbook does not estimate a net cooperation effect.

Chinese version: `README.md`.
