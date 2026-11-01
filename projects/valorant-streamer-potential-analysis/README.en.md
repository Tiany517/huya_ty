# Valorant Streamer Potential and External Talent Pool Review

## Purpose

This directory reviews three related questions that must not be combined into one conclusion:

1. Which Huya Valorant streamers consistently beat the interaction-rate benchmark for their ACU tier for multiple months while satisfying ACU and viewer thresholds.
2. Which Douyin streamers consistently remained ahead on ACU despite incomplete monthly coverage, and why the old and new month algorithms produce different counts.
3. What the September 2026 external-platform Valorant talent pool looked like by platform and tier.

“Potential” is a historical behavior label, not a forecast of future growth. The workbook named as a poaching review is actually a platform snapshot; it does not show that poaching, outreach, or recruitment occurred.

## De-identified Results

### Huya Internal Interaction Potential

| Metric | Result |
| --- | ---: |
| Source rows | 75,832 |
| Unique streamer IDs / names | 15,753 / 15,446 |
| Date range | 2026-06-01 through 2026-10-07 |
| Names mapped to multiple IDs | 84 names |
| IDs mapped to multiple names | 204 IDs |
| Official-channel names removed by single-day DAU above 100,000 | 5 names |
| Unique streamer IDs after cleaning | 13,493 |
| Candidate pool | 187 IDs |
| Streamer-month rows in the selection window | 526 |
| Passing streamer-month rows | 259 |
| Final selections | 8 people: 3 waist, 5 tail |

The selection window is June through September 2026. The candidate pool uses the full source period. Selection requires ACU of at least 5, at least three months in the selection window with a watch-weighted interaction rate above the monthly tier benchmark, and no event or official keyword match in the streamer name. Seven selections pass three months and one passes four; the window contains only four months, so no five-month tier exists.

The independently rebuilt selected-ID set exactly matches the first contiguous detail block in the legacy workbook. The workbook candidate sheet stores 160 IDs, while a direct rebuild from the current source CSV gives 187. This indicates an older workbook snapshot or a lost candidate subset. Because the final eight IDs still reproduce exactly, the 160-versus-187 result is recorded as a warning, not as the current candidate count. Rows 9 through 24 of the legacy sheet are mostly blank and later rows contain pivot remnants, so the worksheet's `max_row` cannot be read as a 40-person list.

### Douyin Sustained-Leader Method Comparison

The source has 280,254 rows and 117,185 unique streamer IDs from 2026-01-01 through 2026-10-09. Monthly coverage is incomplete:

| Month | Observed days | Status |
| --- | ---: | --- |
| M1 | 21 | valid |
| M2 | 20 | valid |
| M3 | 8 | valid |
| M4 | 0 | missing |
| M5 | 7 | valid |
| M6 | 14 | valid |
| M7 | 1 | invalid short month |
| M8 | 8 | valid |
| M9 | 12 | valid |
| M10 | 2 | invalid short month |

A valid month is defined as at least three observed days globally. Results are:

| Method | Sustained leaders | Head | Neck | Waist | Tail |
| --- | ---: | ---: | ---: | ---: | ---: |
| v1: calendar-adjacent months, retaining one- and two-day months | 267 | 0 | 1 | 9 | 257 |
| v2: adjacent valid months, with at least three observed days per streamer-month | 95 | 1 | 1 | 15 | 78 |

In v2, 1,700 streamers have at least two comparable month pairs. v1 reproduces the legacy workbook method. The 267-versus-95 difference is not ordinary noise under one fixed rule: it comes from short-month eligibility, missing-month handling, and the streamer-month minimum observation rule. Each recomputed count matches its corresponding legacy workbook.

### September 2026 External Talent Pool

| Platform | Snapshot rows | Unique IDs | Head | Neck | Waist | Tail |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Bilibili | 198 | 198 | 17 | 22 | 76 | 83 |
| Douyin | 4,076 | 4,075 | 17 | 28 | 289 | 3,742 |
| Douyu | 24 | 24 | 0 | 0 | 9 | 15 |
| Huya | 4,633 | 4,633 | 4 | 1 | 17 | 4,611 |
| Kuaishou | 27 | 27 | 0 | 0 | 3 | 24 |
| Total | 8,958 | 8,957 | 38 | 51 | 394 | 8,475 |

The snapshot date is 2026-09-30. The total has 8,958 records but only 8,957 unique IDs, leaving one duplicate record. This table describes a talent pool; it does not prove that poaching, contact, or hiring took place.

## Files and GitHub Paths

| Content | GitHub path |
| --- | --- |
| Chinese project note | `projects/valorant-streamer-potential-analysis/README.md` |
| English project note | `projects/valorant-streamer-potential-analysis/README.en.md` |
| Huya interaction-potential rebuild | `projects/valorant-streamer-potential-analysis/scripts/reproduce_huya_internal_potential.py` |
| Douyin v1/v2 method comparison | `projects/valorant-streamer-potential-analysis/scripts/reproduce_douyin_potential.py` |
| External talent-pool summary | `projects/valorant-streamer-potential-analysis/scripts/summarize_external_valorant_pool.py` |
| Huya September ACU merge helper | `projects/valorant-streamer-potential-analysis/scripts/merge_huya_september_acu.py` |
| Huya de-identified summary | `projects/valorant-streamer-potential-analysis/artifacts/huya-internal-potential-summary.en.csv` |
| Huya de-identified monthly selection | `projects/valorant-streamer-potential-analysis/artifacts/huya-internal-potential-monthly.en.csv` |
| Huya cross-check | `projects/valorant-streamer-potential-analysis/artifacts/huya-internal-potential-validation.en.csv` |
| Douyin de-identified summary | `projects/valorant-streamer-potential-analysis/artifacts/douyin-potential-summary.en.csv` |
| Douyin month coverage | `projects/valorant-streamer-potential-analysis/artifacts/douyin-potential-month-coverage.en.csv` |
| Douyin method comparison | `projects/valorant-streamer-potential-analysis/artifacts/douyin-potential-method-comparison.en.csv` |
| Douyin workbook validation | `projects/valorant-streamer-potential-analysis/artifacts/douyin-potential-validation.en.csv` |
| External talent-pool summary | `projects/valorant-streamer-potential-analysis/artifacts/external-valorant-pool-202609-summary.en.csv` |

Every English artifact has a Chinese counterpart with the `.csv` suffix. English files use English column names.

## Local Source Map

| Local source | Repository handling | SHA256 |
| --- | --- | --- |
| `C:\Users\tiany\Downloads\无畏契约主播互动潜力分析_不剔除赛事日_近3月.csv` | anonymous aggregates only after rebuild | `F9EEAD76D06A56285728F82A14792161AA6FA52BE9C3BD5D3ACFFB489AF2F0DC` |
| `C:\Users\tiany\Downloads\抖音无畏主播有效ACU_剔除大赛事日.csv` | anonymous aggregates only after rebuild | `7435FA6114174D92E21A760A7CBD741E2AFA69D531803B38C77C92AD08D574DD` |
| `C:\Users\tiany\Desktop\无畏契约份额增长\无畏契约主播潜力分析\无畏契约行业主播反挖情况_并入虎牙9月ACU_20261010.xlsx` | platform counts and tiers only | `E6B6032B44CAA8DDE73A73626CA1A31FE134C11D423A650AC6B22642058D7B8C` |
| `C:\Users\tiany\Desktop\无畏契约份额增长\无畏契约主播潜力分析\无畏契约潜力主播_最终名单.xlsx` | validation only; not uploaded | `D6AC5F3F021562EFC9BF585CFD5D770DE640121D6C9E98EEB8D92C37C3EC89BA` |
| `C:\Users\tiany\Desktop\无畏契约份额增长\无畏契约主播潜力分析\抖音无畏主播_月日均ACU持续领先分层_20261010.xlsx` | v1 count validation only; not uploaded | `4A4B857BD5A62A170135BE5621C53C5FD79286B0B4E196AC37802238C6E45A1A` |
| `C:\Users\tiany\Desktop\无畏契约份额增长\无畏契约主播潜力分析\抖音无畏主播_相邻环比持续领先分层_20261010.xlsx` | v2 count validation only; not uploaded | `E279D6A15674A8114BB658FADB8A865F3A96511F21EBBC96FE9DE20208B2F1ED` |

Source workbooks, streamer-level details, streamer IDs, nicknames, and user-level data were not uploaded.

## Validation and Limitations

| Check | Status | Evidence |
| --- | --- | --- |
| Data availability | Pass, with incomplete Douyin coverage | Huya spans 2026-06-01 through 2026-10-07; Douyin coverage is explicit in CSV |
| Schema and semantics | Pass | Streamer keys, dates, ACU, and interaction fields were type- and range-checked in the source CSVs |
| Grain and uniqueness | Pass with warnings | Huya aggregates by streamer ID; the external pool has 8,958 rows and 8,957 unique IDs |
| Joins and row multiplication | Pass | Tier benchmarks use `many_to_one`; monthly metrics are rebuilt at streamer-month grain |
| Metric invariants | Pass | Interaction rates, tiers, counts, and month coverage reconcile with source rebuilds |
| Independent reconciliation | Pass with warnings | Huya's eight selected IDs match the first contiguous detail block exactly; Douyin counts 267 and 95 match the two legacy workbooks |
| Boundaries and business spot checks | Pass | Blank rows, pivot remnants, one duplicate ID, missing months, and short months were reviewed; no streamer-level manual business sample was performed |

Primary limitations remain: Douyin monthly coverage is incomplete and method-dependent; the Huya legacy candidate workbook has a 160/187 mismatch against the current source; the external pool is one monthly tier snapshot; and these results do not predict ACU, retention, revenue, or poaching success.

## Reproduce

From the repository root:

```powershell
$env:PYTHONIOENCODING='utf-8'
python projects/valorant-streamer-potential-analysis/scripts/reproduce_huya_internal_potential.py
python projects/valorant-streamer-potential-analysis/scripts/reproduce_douyin_potential.py
python projects/valorant-streamer-potential-analysis/scripts/summarize_external_valorant_pool.py
```

The scripts read the local defaults in the source map and accept environment overrides. They create de-identified aggregates without modifying source files.

`merge_huya_september_acu.py` writes a workbook. If the target exists, the script refuses to continue by default. Set `VALORANT_EXTERNAL_POOL_OVERWRITE=1` only after confirming the destination and a backup.
