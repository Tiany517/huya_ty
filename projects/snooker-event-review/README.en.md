# Snooker Event Review Migration Guide

## Purpose

This directory preserves the Snooker and World Championship acquisition, retention, conversion, video-preference, profiling, and final-presentation work so that a new computer can understand and continue it. The objective is not to claim that every historical analysis can be rerun from GitHub alone. The objective is to retain:

1. a complete snapshot of the final delivered files;
2. reusable SQL and profile-analysis scripts;
3. key anonymous aggregates, metric definitions, known defects, and validation evidence;
4. a clear map from repository-relative GitHub paths to project content.

The original source directory remains untouched. User-level details, UIDs, `user_ukey`, nicknames, and large identity-bearing workbooks are not uploaded.

## GitHub Repository Map

| Repository-relative path | Contents | Use on the new computer |
| --- | --- | --- |
| `projects/snooker-event-review/README.md` | Complete Chinese project guide, definitions, findings, and limitations | Quick Chinese onboarding |
| `projects/snooker-event-review/README.en.md` | Complete standalone English guide | Quick English onboarding |
| `projects/snooker-event-review/artifacts/zh/` | Ten Chinese anonymous normalized datasets, source manifest, and 36-check results | Inspect core Chinese metrics and evidence |
| `projects/snooker-event-review/artifacts/en/` | The same dataset structures under English filenames | Inspect English files and validation records |
| `projects/snooker-event-review/artifacts/final-delivery/` | 89 final-delivery files: 38 CSV, 14 XLSX, 9 PPTX, and 28 SQL | Review the original final outputs and presentation versions |
| `projects/snooker-event-review/artifacts/supplemental-results/` | Four supplemental outputs: retention differences, Shanghai acquisition retention, Snooker/non-Snooker acquisition counts, and the profile report | Recover supporting evidence outside the final folder |
| `projects/snooker-event-review/artifacts/project_summary.json` | Machine-readable project scale, key metrics, and status | Read the package summary programmatically |
| `projects/snooker-event-review/artifacts/validation_report.json` | 36-check summary | Check completeness quickly |
| `projects/snooker-event-review/sql/source/` | 61 project SQL files under their source subdirectories | Search and reuse historical queries |
| `projects/snooker-event-review/scripts/build_snooker_package.py` | Builds anonymous summaries and source hashes and copies final delivery from a local source root | Rebuild when the source files are available |
| `projects/snooker-event-review/scripts/verify_snooker_package.py` | Recomputes metrics and checks grain, source hashes, privacy, and file coverage | Rerun acceptance |
| `projects/snooker-event-review/scripts/profile-analysis/` | Three profile-analysis scripts with local absolute paths removed | Review clustering and field handling |

Common direct entry points:

- World Championship audience funnel: `artifacts/en/world-championship-audience-funnel.csv`
- New-user conversion path: `artifacts/en/world-championship-new-user-path.csv`
- New-user tipping: `artifacts/en/world-championship-tipping.csv`
- Independent video/live coverage: `artifacts/en/world-championship-unique-audience-share.csv`
- Event-to-World-Championship retention: `artifacts/en/event-to-world-championship-retention.csv`
- Video affinity: `artifacts/en/snooker-video-affinity.csv`
- Content supply: `artifacts/en/key-video-content-supply.csv`
- New-user profile clusters: `artifacts/en/new-user-profile-clusters.csv`
- Quality findings: `artifacts/en/quality-findings.csv`
- Sources and hashes: `artifacts/en/source-manifest.csv`
- Itemized checks: `artifacts/en/validation-results.csv`

## Metric Definitions and Non-Interchangeable Boundaries

### World Championship Audience Funnel

`world-championship-audience-funnel.csv` preserves the event-period aggregation convention of the original delivery table. “Event viewers” is 4.036454 million in 2025 and 6.312202 million in 2026 under that event-period daily-aggregate convention. These values are not the deduplicated UV of the entire event interval and must not be added to or replaced by another interval-deduplicated metric.

New users, video viewers, Xingxiu viewers, and tipping users must be read separately by season and user group. All user-count fields are in ten thousands (万).

### Independent Video and Live Coverage

`world-championship-unique-audience-share.csv` comes from a separate final-delivery CSV and is not part of the same additive path as the daily funnel above. Video and live coverage use separate denominators and must not be added to 100%. User overlap should be checked against the original SQL and underlying user-level table before any combined audience is asserted.

### New-User Tipping

`tipping_rate_pct` is tipping users divided by new users. Total tipping amount is in CNY ten thousands. The two per-user columns use different denominators: all new users versus actual tipping users.

### Event-to-World-Championship Retention

Each row is a combination of baseline season, stage, and target event. All stages within one baseline-season should use the same baseline new-user denominator. Multiple retention windows do not add rows to this table. Numerators and denominators are user counts; rows copied across windows must not be summed as independent users.

### Profile Clusters

The profile source had 3,638 processing rows and 1,086 users after deduplication by `user_ukey`. The four cluster sizes are 107, 199, 358, and 422, which sum to 1,086. Shares sum to 100%. The user-level feature file is not uploaded.

## Key Findings

### World Championship Audience and Acquisition

| Metric | 2025 World Championship | 2026 World Championship | YoY/change |
| --- | ---: | ---: | ---: |
| Event viewers | 4,036,454 | 6,312,202 | +56.3799% |
| New users | 384,036 | 783,875 | +104.1150% |
| Snooker new-user tippers | 2,115 | 3,833 | +81.2293% |
| Snooker new-user tipping rate | 0.55073% | 0.48898% | -0.06175 pp |

New-user counts are also recorded as 38.4036 and 78.3875 ten-thousands in the source. Acquisition and tipping-user counts increased, while the Snooker new-user tipping rate declined slightly. Tipping-user growth alone is not evidence of improved conversion efficiency.

### Video and Live Coverage

| Metric | 2025 World Championship | 2026 World Championship | Change |
| --- | ---: | ---: | ---: |
| New-user video-viewer coverage | 28.4593% | 30.3321% | +1.8728 pp |
| New-user live-viewer coverage | 52.5909% | 48.8788% | -3.7121 pp |

This table comes from an independent final CSV. It should not be converted or reconciled directly against video viewer counts in the daily funnel.

### Long-Term Retention to the World Championship

| Baseline event | 2024/25 | 2025/26 | Change |
| --- | ---: | ---: | ---: |
| Shanghai Masters | 38.9309% | 39.2245% | +0.2936 pp |
| UK Championship | 47.1312% | 49.6496% | +2.5184 pp |
| English Open | 46.0350% | 37.3098% | -8.7251 pp |
| Saudi Masters | 39.4898% | 30.9291% | -8.5607 pp |
| Masters invitational | 50.4% | 53.7% | +3.3 pp |

Across the four events with complete staged data, weighted long-term retention fell from 42.3368% to 39.4200%, a change of -2.9168 pp. The Masters invitational has only baseline and long-term observations and is not included in that weighted result.

### Video Preference and Content Supply

| Video category | Snooker new-user view share | Non-Snooker new-user view share | Difference |
| --- | ---: | ---: | ---: |
| Curiosities | 30.36% | 15.37% | +14.99 pp |
| Parody/meme | 17.86% | 9.21% | +8.65 pp |
| Film/TV | 6.13% | 3.31% | +2.82 pp |

Curiosities account for only about 1.2% of all Huya video supply but are the largest video-view category for Snooker new users. This supports a descriptive statement about concentrated demand relative to supply; it does not by itself establish a causal gain from changing recommendations or supply.

### Profiles

The “Xiaomi video” cluster has 358 users, or 32.965% of the deduplicated sample. The report suspects programmatic or fake registration because several device, wealth, education, activity, and game fields are highly uniform. No risk-control, IP, device-fingerprint, or registration-path evidence validates that claim. It must remain a hypothesis. It is not valid to state that 33% of users are fake or to remove 33% before recalculating ROI.

## Confirmed Quality Findings

1. The 2025 World Championship final CSV and workbook sheet carry a “2026 World Championship” row label while their values occupy the 2024/25 comparison slot. This project maps season from sheet position and preserves the source label separately.
2. `LPL1_LPL2_王者_斯诺克_转化情况.csv` contains 2025/2026 World Championship video-versus-live ratios rather than the promised four-event conversion comparison. It is retained as provenance but quarantined from normalized analysis.
3. Shanghai Masters baseline denominators conflict across outputs: 91,295 versus 87,485 in 2024/25, and 278,071 versus 265,175 in 2025/26. Retention direction is usable; absolute retained counts must not be combined until the business dictionary is confirmed.
4. The approximately 33% suspected-fake profile cluster has no risk-control validation and remains a high-risk hypothesis.
5. The final deck’s ROI 0.9 and +7.5% cannot be independently reproduced from the retained anonymous workbooks and CSVs. They may be quoted only as historical deck statements.
6. A playhouse tipping workbook’s change row is not consistently expressed in percentage points. This package does not use that row for conclusions.
7. Two very large source workbooks, a 19,456-row retention CSV containing `user_uid`, and the profile feature CSV containing `user_ukey` are not uploaded. The GitHub package cannot rebuild those user-level analyses by itself.

The fielded version is `artifacts/en/quality-findings.csv`.

## Excluded Content

- User-level tipping, viewing, and retention CSVs and workbooks containing user identifiers;
- the 19,456-row retention file containing `user_uid`;
- the profile feature file containing `user_ukey`;
- two very large source workbooks;
- rebuildable caches, runtime logs, and local temporary files;
- the local absolute-path map.

Every source file has an anonymized path, SHA-256, inclusion disposition, and repository destination in `artifacts/en/source-manifest.csv`. Source paths use the `<source-root>/...` placeholder and do not expose the local username or absolute path.

## Validation Status

The verifier currently reports 36 passed, 0 failed, 0 not run, and status `passed`. It covers:

- 89 final-delivery files and their extension counts;
- 61 SQL files;
- existence and equal row counts for ten Chinese/English data-file pairs;
- independent recomputation of audience, acquisition, tipping, coverage, retention, preference, profile, and supply results;
- retention denominator stability and uniqueness;
- seven quality findings and sensitive-source exclusions;
- repository hashes for every copied entry and SHA-256 values for every source file;
- scans for plaintext user-identifier headers, Excel formula errors, absolute Windows user paths, and notebooks.
- the separate Chinese and English guides, GitHub path maps, and validation-status entry points.

This proves internal consistency, traceability, and conformance to the privacy boundary. It does not mean that all 61 historical SQL files were executed again, nor does it resolve the pending business-dictionary question.

## Reproduction Commands

Run these from the repository root. Replace `<source-root>` with the local original Snooker project directory:

```powershell
python projects\snooker-event-review\scripts\build_snooker_package.py --source-dir "<source-root>"
python projects\snooker-event-review\scripts\verify_snooker_package.py --source-dir "<source-root>"
```

The build script only reads the source directory and writes inside `projects/snooker-event-review/`. It does not overwrite source files. The verifier rewrites anonymous validation outputs and the summary status file without modifying the source directory.

## New-Computer Handoff Order

1. Read “Metric Definitions and Non-Interchangeable Boundaries” and “Confirmed Quality Findings” first.
2. Recheck this page’s headline values against `artifacts/en/world-championship-audience-funnel.csv`, `world-championship-tipping.csv`, and `event-to-world-championship-retention.csv`.
3. To trace SQL, begin with same-named or similar queries under `sql/source/`, then use `artifacts/en/source-manifest.csv` for the original relative path and hash.
4. To inspect final delivery, use the complete snapshot under `artifacts/final-delivery/`, but apply the seven quality findings before trusting embedded labels.
5. To continue profiling, first confirm access to the user-level sources in a controlled environment. This repository can reproduce the anonymous cluster result but cannot rerun the user-level feature pipeline by itself.
6. Before changing SQL or profile conclusions, follow the result contract and validation workflow in repository-root `instructions/AGENTS.en.md`.

Chinese version: `README.md`.
