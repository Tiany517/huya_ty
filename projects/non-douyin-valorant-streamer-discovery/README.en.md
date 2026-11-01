# Non-Douyin Valorant Streamer Discovery Review

## Objective

Identify streamers on Bilibili, Douyu, and Kuaishou who reached the Valorant head tier in 2026 and repeatedly outperformed a platform growth benchmark. The project supports external-streamer discovery and recruitment assessment. It does not measure whether a streamer is actually poachable, willing to join, or economically beneficial to acquire.

## Source and Path Mapping

Original directory: `C:\Users\tiany\Desktop\无畏契约份额增长\无畏契约主播潜力分析\非抖无畏主播挖掘`.

| Asset | Local source | GitHub archive |
| --- | --- | --- |
| Primary data workbook | `非抖无畏主播挖掘.xlsx` | Not uploaded; contains streamer IDs and nicknames |
| Final workbook | `非抖无畏主播_头部基准筛选_含战队与剔战队_20261014.xlsx` | Not uploaded; anonymous aggregates only |
| Team-exclusion workbook | `非抖无畏主播_剔除战队_平台基准筛选_20261014.xlsx` | Not uploaded; anonymous aggregates only |
| Final selection script | `scripts/build_final.py` | [`scripts/build_final.py`](scripts/build_final.py) |
| Regression verification script | `scripts/verify_final2.py` | [`scripts/verify_final2.py`](scripts/verify_final2.py) |
| Team-exclusion calculation | `scripts/build_select_team.py` | [`scripts/build_select_team.py`](scripts/build_select_team.py) |
| Team-exclusion workbook generator | `scripts/build_team_xlsx.py` | [`scripts/build_team_xlsx.py`](scripts/build_team_xlsx.py) |
| Anonymized platform and selection summary | Re-aggregated for this review | [`artifacts/non-douyin-discovery-summary.en.csv`](artifacts/non-douyin-discovery-summary.en.csv) |
| Anonymized monthly benchmarks | Final workbook's monthly-benchmark sheet | [`artifacts/non-douyin-monthly-benchmarks.en.csv`](artifacts/non-douyin-monthly-benchmarks.en.csv) |
| Anonymized artifact builder | Added for this review | [`scripts/prepare_anonymized_artifacts.mjs`](scripts/prepare_anonymized_artifacts.mjs) |

The primary workbook has 2,154 rows and 519 unique streamers, covering January through September 2026. Its SHA256 is `ea8137016c5967ea0233d620190e73d61b4e52495164aa4f6ae2bd76da9a6b27`. Streamer names, IDs, and monthly streamer-level performance were excluded from GitHub.

## Population and Definitions

- Platforms: `bilibili`, `douyu`, and `kuaishou`, with 378, 54, and 87 unique streamers respectively.
- Tiers: head `valid ACU >= 2000`; neck `1000-1999`; waist `100-999`; tail `<100`.
- Candidate pool: any streamer reaching valid ACU 2,000 in at least one month of 2026.
- Month-over-month change: `(current-month valid ACU - prior-month valid ACU) / prior-month valid ACU`, using only adjacent natural months with positive prior ACU.
- Team streamers: a streamer whose name ever began with `EDG/BLG/DRG/JDG/XLG/TYL/FPX/TEC/TE/WOL/AG/NOVA`. The strict rule treats a streamer as a team streamer if any historical month carried a prefix.
- Benchmarks: team streamers use the platform head median including teams; non-team Bilibili streamers use the head median excluding teams; Douyu and Kuaishou use the platform-wide median because their head samples contain only zero to two streamers.
- Selection: the share of months beating the benchmark must be at least 50%; at least four comparable months is “robust,” at least two is “relaxed”; the streamer must still have September 2026 data.
- The monthly series observes streamers and uses the supplied monthly `有效acu`; month-over-month change is calculated only when the same streamer has positive ACU in two adjacent calendar months. It is not a user-day or monthly distinct-user metric.

## Findings

There are 249 streamers with September 2026 data and 270 without it. Among streamers with data, the September tiers are 17 head, 22 neck, 88 waist, and 122 tail. The older tier workbook retained only 248 real rows, dropped one Bilibili head record, and reported 16 head streamers; this review uses the primary workbook and confirms 17.

There are 34 candidates: 29 from Bilibili, 3 from Douyu, and 2 from Kuaishou. Twenty-nine are assessable. Eleven are selected, all from Bilibili: 10 robust and 1 relaxed, comprising 7 team and 4 non-team streamers.

The 23 non-selected candidates split into 11 with no September 2026 data, 10 that did not beat the benchmark in at least half of comparable months, and 2 with too few comparable months. All Douyu and Kuaishou candidates lacked September data, so zero selections on those platforms does not imply that they have no potential streamers.

After excluding 24 team streamers, the candidate pool falls from 34 to 26 and assessable candidates from 29 to 21, with 103 adjacent-month pairs. Six are selected under the head-median benchmark and 15 under the platform-wide-median sensitivity benchmark.

See [`artifacts/non-douyin-discovery-summary.en.csv`](artifacts/non-douyin-discovery-summary.en.csv) and [`artifacts/non-douyin-monthly-benchmarks.en.csv`](artifacts/non-douyin-monthly-benchmarks.en.csv).

## Limitations and Run Notes

1. `有效acu` is used as supplied by the platform or collection pipeline. No field dictionary is present; confirm its unit and observation window before rerunning.
2. Bilibili has a meaningful head sample, while Douyu and Kuaishou do not. The final screen therefore mixes head-median and platform-wide-median benchmarks, so the platform rules are not fully identical.
3. “No September data” cannot distinguish stopped streaming, incomplete collection, a renamed account, and a platform-interface failure.
4. Team-prefix matching is a business approximation, not a contract or guild roster. Renamed streamers and teams without a prefix may be missed.
5. Archived scripts default to the recorded local source directory and support `NON_DOUYIN_VALORANT_DIR`; on the new computer, point this variable to the directory containing the primary workbook.
6. `build_select_team.py` creates `_state_team.pkl`, which is not archived. Run it in the same source directory before `build_team_xlsx.py`.
7. An early v3 note said there were 28 assessable candidates, while the candidate table contained 29. The final workbook and this independent aggregation both confirm 29.
8. The anonymized artifact builder requires `@oai/artifact-tool`. The primary workbook is not distributed, so the checked-in anonymized CSVs are readable without it, while a rebuild requires the local source.

Chinese documentation: [`README.md`](README.md).
