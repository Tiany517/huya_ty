# Event Summary and Platform-Share Review

This project reviews the 2026-09-14 event-summary package for LPL, KPL, FISSURE, and BLAST. It lets Codex on the new computer understand event DAU, acquisition and return, year-over-year and phase comparisons, and platform streamer-ACU shares without exposing the original streamer-level workbooks. It also identifies which published spreadsheet conclusions need correction.

## GitHub Repository Map

| Repository path | Contents |
| --- | --- |
| `projects/event-summary-review/README.md` | Chinese project note, results, definitions, limitations, and path map |
| `projects/event-summary-review/README.en.md` | Complete English note |
| `projects/event-summary-review/scripts/build_event_summary_artifacts.py` | Repeatable builder for bilingual anonymous artifacts from the source workbooks |
| `projects/event-summary-review/scripts/validate_event_summary_artifacts.py` | Twenty-five checks for provenance, recomputation, share closure, duplication, privacy, and status |
| `projects/event-summary-review/artifacts/zh/赛事DAU汇总.csv` | Chinese-keyed event DAU, APP DAU increment, and content acquisition/return averages |
| `projects/event-summary-review/artifacts/zh/赛事DAU对比.csv` | Chinese-keyed year-over-year and phase comparisons |
| `projects/event-summary-review/artifacts/zh/平台份额汇总.csv` | Chinese-keyed published and deduplicated platform shares |
| `projects/event-summary-review/artifacts/zh/重复审计.csv` | Date/schedule/event/platform/UID duplicate audit |
| `projects/event-summary-review/artifacts/zh/质量问题.csv` | Confirmed errors, impact, and status |
| `projects/event-summary-review/artifacts/zh/来源清单.csv` | Hash, disposition, and exclusion reason for each source |
| `projects/event-summary-review/artifacts/zh/校验结果.csv` | Chinese-header results for all twenty-five checks |
| `projects/event-summary-review/artifacts/en/event-dau-summary.csv` | English-keyed event DAU summary |
| `projects/event-summary-review/artifacts/en/event-dau-comparisons.csv` | English-keyed year-over-year and phase comparisons |
| `projects/event-summary-review/artifacts/en/platform-share-summary.csv` | English-keyed published and deduplicated shares |
| `projects/event-summary-review/artifacts/en/duplication-audit.csv` | Duplicate audit |
| `projects/event-summary-review/artifacts/en/quality-findings.csv` | Quality findings |
| `projects/event-summary-review/artifacts/en/source-manifest.csv` | Source hashes and dispositions |
| `projects/event-summary-review/artifacts/en/validation-results.csv` | Twenty-five validation results |
| `projects/event-summary-review/artifacts/project_summary.json` | Machine-readable project summary |
| `projects/event-summary-review/artifacts/validation_report.json` | Aggregate result: 25 passed, 0 failed, 0 not run |

GitHub repository: <https://github.com/Tiany517/huya_ty>

## Result Highlights

DAU is the simple daily average of `全量聚合APPDAU` (total aggregated APP DAU) over valid event-date rows; it is not a de-duplicated interval UV. FISSURE and BLAST sheets include labels and total blocks below the data, so the builder accepts only rows whose date parses as `YYYY-MM-DD`.

| Event | Valid days | Mean daily DAU | Key comparison |
| --- | ---: | ---: | --- |
| 2026 LPL Stage 1 | 40 | 1,015,694.025 | -29.2109% YoY |
| 2026 LPL Stage 2 | 48 | 1,137,042.979 | -30.6324% YoY; +11.9474% vs Stage 1 |
| 2026 LPL Stage 3 | 36 | 1,517,217.472 | -17.8995% YoY; +33.4354% vs Stage 2 |
| 2026 KPL Spring | 56 | 533,729.107 | -12.4784% YoY |
| 2026 KPL Summer | 56 | 447,313.232 | -28.0096% YoY; -16.1910% vs Spring |
| BLAST Porto Open 2026 | 11 | 1,063,165.091 | +58.0515% vs BLAST London Open 2025 |
| FISSURE Fissure 3 Suzhou | 6 | 286,238.167 | No comparable prior edition in this workbook |

All three 2026 LPL stages are below their 2025 counterparts, while Stage 3 is materially above the first two stages. KPL Summer is weaker than both 2025 Summer and 2026 Spring. BLAST Porto is above London 2025, but that difference alone is not a causal event effect.

## Platform Shares

The source share table should be unique by event date, schedule ID, event, platform, and streamer UID, but it contains 20 exact duplicate rows beyond the first occurrence. Both the published view (`published_rows`) and the deduplicated view (`deduplicated`) are retained. Future analysis should default to `deduplicated`, while keeping `published_rows` for traceability.

| Event | Corrected platform shares |
| --- | --- |
| 2026 LPL Stage 1 | Huya 54.3090%, Bilibili 45.6910% |
| 2026 LPL Stage 2 | Huya 51.7252%, Bilibili 48.2748% |
| 2026 LPL Stage 3 | Bilibili 50.0337%, Huya 49.9608%, Douyu 0.0055% |
| 2026 KPL Spring | Huya 45.8045%, Douyu 19.4868%, Bilibili 18.8516%, Kuaishou 11.2113%, Douyin 4.6458% |
| 2026 KPL Summer | Huya 48.2088%, Douyu 22.4243%, Bilibili 14.7588%, Douyin 7.6489%, Kuaishou 6.9591% |
| BLAST Porto Open 2026 | Huya 54.9345%, Douyu 26.6672%, Bilibili 12.2709%, Douyin 6.1275% |

These shares are each platform's summed streamer ACU divided by summed streamer ACU across platforms for the event. They are not platform DAU shares. The consolidated workbook also estimates industry DAU as Huya DAU divided by Huya streamer-ACU share; that is a modeled derivation, not a directly observed platform metric, and must be labeled accordingly.

## Confirmed Source Problems

1. `LPL_份额汇总_Final` reverses the Bilibili and Huya labels in Stage 1. Source recomputation gives Bilibili `3,251,602.817` and Huya `3,909,919.831`, while the final sheet puts the two figures under the opposite labels. The archive does not reuse that erroneous block.
2. The share sources contain 20 exact extra rows: LPL 2, KPL 16, and BLAST 2. Duplication inflates published KPL Summer streamer ACU from the corrected `4,122,499.572` to `4,202,229.338`.
3. `KPL_赛事份额_汇总` has `#DIV/0!` in `I242` and `J242` inside a secondary streamer-contribution block. Top-level platform totals independently reconcile, but the affected streamer row must not be reused.
4. FISSURE and BLAST sheets contain summary labels and totals below the actual date rows. Rebuilds must filter by date format.
5. No upstream SQL, field dictionary, or partition record was retained. The proof therefore covers workbook-to-aggregate reproducibility, not the original data-platform lineage.

## Excluded Material

- `0914_赛事总结.xlsx` and `0914_赛事总结_汇总.xlsx` contain UIDs, nicknames, and streamer-level ACU; the raw workbooks are excluded.
- `版权赛事V1_0921.pptx` has two slides with named broadcasters and streamer-level narratives; it is excluded even in a private repository. Its hash and exclusion reason are recorded in the source manifest.
- No user-level or streamer-level detail is retained. The package contains event/platform aggregates, scripts, and validation evidence only.

## Rebuild and Validation

```powershell
python scripts/build_event_summary_artifacts.py --source-dir <event-summary-source-directory>
python scripts/validate_event_summary_artifacts.py --source-dir <event-summary-source-directory>
```

| Source file | SHA-256 |
| --- | --- |
| `0914_赛事总结.xlsx` | `8fa1c7c2f3d8c21582c76413729423302f22030184097ab8eb583c220b066b6e` |
| `0914_赛事总结_汇总.xlsx` | `01fc2b36ee2ec9aa4b46daa5ae5999656f7f5ebb5b43a9ca50d20a2eb3408b00` |
| `版权赛事V1_0921.pptx` | `218809bb42a13796fad2745d80c8bef48ef624ca08d9305265f0bb6bf3860e56` |

The project status is reviewed with documented source-quality and upstream-lineage limitations. All 25 automated checks pass; this means the archive agrees with the recorded sources, independently recomputed aggregates, and privacy boundary. It does not prove the original business result through upstream SQL.

Chinese version: `README.md`.
