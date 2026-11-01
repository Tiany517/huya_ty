# Anonymous Summary Artifacts

This directory contains only aggregates, source hashes, and static audit records. It contains no user-level records or user-identifier values.

| Folder / file | Contents |
| --- | --- |
| `tgi/` | TGI tables for pairwise device groups, snooker acquisition, full World Championship watching, and watching for at least 10 minutes; every Chinese file has an English-header `.en.csv` version |
| `clusters/device-groups.csv` / `.en.csv` | Anonymous cluster counts, shares, and core averages from 50,000 sampled users in each device group |
| `clusters/world-championship-10min.csv` / `.en.csv` | Anonymous cluster summary for the 10-minute viewer target cohort |
| `clusters/world-championship-10min-kmeans.csv` / `.en.csv` | SSE, decline, and silhouette for K=2 through K=9 |
| `clusters/world-championship-10min-device-price-tiers.csv` / `.en.csv` | Device-price tiers and cohort counts |
| `clusters/snooker-unreconciled-cluster-generation.csv` / `.en.csv` | Descriptive statistics for a 1,086-row processed sample, explicitly marked as unreconciled with the 1,072-user report |
| `sql-static-audit.csv` / `.en.csv` | Seven confirmed SQL defects and one unexecuted field-semantics check |
| `source-manifest.csv` / `.en.csv` | Hashes, classification, and migration handling for 151 source files |
| `project-summary.json` | Cohorts, sample sizes, and privacy boundary |

English CSVs translate headers only; category values may remain in the source system's Chinese text. Do not infer or reconstruct user identities from these aggregates.

Chinese version: `README.md`.
