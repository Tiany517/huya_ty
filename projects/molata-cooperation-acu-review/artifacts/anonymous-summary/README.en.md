# Anonymous Artifact Guide

| File | Rows | Purpose |
| --- | ---: | --- |
| `daily_series.csv` / `.zh.csv` | 123 | Anonymous anchor roles, group totals, platform benchmarks, daily shares, and reconciliation residual |
| `window_summary.csv` / `.zh.csv` | 52 | ACU sums and daily averages for 13 units by four windows |
| `growth_comparison.csv` / `.zh.csv` | 13 | Pre/post deltas, growth, and benchmark percentage-point differences for 13 units |
| `share_summary.csv` / `.zh.csv` | 4 | Mean daily shares for the six-anchor and five-anchor groups in four windows |
| `reconciliation_failures.csv` / `.zh.csv` | 13 | Dates and residuals where platform differences do not return to source anchor totals |
| `cooperation-acu-anonymous-en.xlsx` | 6 sheets | English anonymous result workbook |
| `cooperation-acu-anonymous-zh.xlsx` | 6 sheets | Chinese anonymous result workbook |
| `source-manifest.csv` | 5 | Source paths, sizes, SHA-256 hashes, and inclusion/exclusion reasons |
| `project-summary.json` | - | Data scale, windows, reconciliation failure count, and privacy boundary |

`anchor_01` is the observed anchor ranked by full-period valid-ACU total; `anchor_02` through `anchor_06` form the collaboration group. These labels are anonymous ordering keys and contain no streamer identifier or nickname-derived information.

The historical result workbook contains streamer identifiers and nicknames and was not copied. The original Python builder also contained hard-coded identities and was not uploaded directly. The repository rebuild script writes anonymous roles and aggregates only.

Chinese version: `README.md`.
