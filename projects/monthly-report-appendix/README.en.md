# Monthly Report Appendix: External Ecosystem and APP Game Exclusivity

## Objective

Preserve the reusable SQL, anonymized series, definitions, and known defects from the 2026 monthly-report appendix so Codex on the new computer can continue these workstreams:

1. Daily and monthly DAU for video-channel MCN single-stream and double-stream content.
2. Monthly live-streaming DAU for Douyin, the video channel, and other external platforms.
3. Douyin MCN live DAU split by game category.
4. Huya APP next-month retention and game versus entertainment user exclusivity.

## GitHub path map

| GitHub path | Contents |
| --- | --- |
| `projects/monthly-report-appendix/README.md` / `README.en.md` | Chinese / English objectives, definitions, risks, and refresh steps |
| `projects/monthly-report-appendix/scripts/export_anonymous_artifacts.py` | Re-extract anonymized results from reviewed sources and run consistency checks |
| `projects/monthly-report-appendix/artifacts/external-ecosystem-dau-monthly-2026.csv` | 2026 monthly DAU for Douyin, the video channel, other platforms, and the total |
| `projects/monthly-report-appendix/artifacts/video-channel-stream-type-monthly.csv` | Video-channel single-stream and double-stream-old-content monthly DAU from 2025-09 through 2026-10 |
| `projects/monthly-report-appendix/artifacts/douyin-mcn-category-dau-monthly-2026.csv` | 2026 Douyin MCN live DAU by game category |
| `projects/monthly-report-appendix/artifacts/video-channel-mcn-daily-2026-05-25_2026-08-18.csv` | Video-channel MCN daily DAU and effective DAU by stream type |
| `projects/monthly-report-appendix/artifacts/app-next-month-retention-monthly.csv` | APP next-month retention from 2021-01 through 2026-02 |
| `projects/monthly-report-appendix/artifacts/app-game-exclusive-monthly.csv` | APP game-exclusive, entertainment-exclusive, and overlap users from 2022-01 through 2026-08 |
| `projects/monthly-report-appendix/artifacts/source-manifest.csv` | File sizes and SHA-256 hashes for reviewed sources |
| `projects/monthly-report-appendix/artifacts/validation-summary.json` | Row counts, coverage, reconciliation results, and known gaps |
| `sql/source/月报附录/视频号月报_单播_双播_DAU取数.sql` | Original SQL for the daily video-channel single/double stream table |
| `sql/source/月报附录/视频号DAU_分单播和双播_主播下钻.sql` | SQL for monthly video-channel stream-type drilldown |
| `sql/source/月报附录/视频号单双播主播下钻_final.sql` | Another stream-type drilldown version; date range and monthly-average risks must be fixed before use |
| `sql/source/月报附录/游戏独占用户取数模板.sql` | APP game and entertainment exclusivity template |

## Core results

### External-platform monthly DAU

`external-ecosystem-dau-monthly-2026.csv` covers January through October 2026. October is observed only through 2026-10-20 and is not comparable with a complete month. In each month, Douyin plus the video channel plus other platforms equals the reported total; the internal source-chart difference is zero.

### Video-channel single and double streams

`video-channel-stream-type-monthly.csv` covers 2025-09 through 2026-10. `double_stream_old_content` retains the source chart's narrower label and must not be rewritten as all double-stream content. Single stream plus double-stream old content equals the source total; the internal difference is zero.

`video-channel-mcn-daily-2026-05-25_2026-08-18.csv` contains 170 records across 85 dates with data. Every available date has exactly one single-stream and one double-stream row. The source CSV omits 2026-08-01, and the archive does not fill it as zero. Daily means reproduce the chart for June and July 2026 after rounding DAU to whole users. August cannot be reconciled directly from the daily file because one day is absent.

### Douyin MCN category DAU

`douyin-mcn-category-dau-monthly-2026.csv` retains category-level game DAU without MCN rankings, anchor names, or anchor IDs. From April through August 2026, the game-category sum differs from the chart total by as much as 377,465.451613. The source does not identify an additional category that explains the gap. The archive therefore keeps the reported values and marks the total as unreconciled rather than forcing a tie-out.

### APP retention and exclusivity

`app-next-month-retention-monthly.csv` covers 62 months from 2021-01 through 2026-02. The series was recovered from the monthly-report appendix deck. No underlying query was present in the reviewed folder, so the chart values are reproducible but the extraction method is not.

`app-game-exclusive-monthly.csv` covers 56 months from 2022-01 through 2026-08. It contains total users, game-exclusive users, entertainment-exclusive users, overlap users, and three shares. Game-exclusive users equal game users minus overlap users. Entertainment-exclusive users equal entertainment users minus overlap users. The three shares sum to 100% each month, with a maximum floating-point difference of 1.11e-16.

## SQL review

### `视频号月报_单播_双播_DAU取数.sql`

- The current date range is 2026-05-25 through 2026-06-14.
- A video-channel creator is labeled double-stream when a same-day Huya live-duration record has positive duration; otherwise the creator is labeled single-stream.
- `effective DAU = DAU × 0.26`. The 0.26 coefficient is a source assumption, not a platform-reported effective DAU.
- `count(distinct userid)` follows the source SQL's anchor-count definition. The business meaning and uniqueness of `userid` in the video-channel table must be verified before reuse.

### `视频号DAU_分单播和双播_主播下钻.sql`

- The date range is 2026-06-01 through 2026-08-18.
- Monthly DAU equals within-month DAU divided by the number of observed days. Effective DAU then applies the 0.26 coefficient.
- Its result includes anchor IDs and nicknames, so only the SQL is archived; identity-level output is not.

### `视频号单双播主播下钻_final.sql`

- `huya_anchor_day` starts at 2015-06-01, which conflicts with the comment describing a 2025 range.
- `anchor_2025_game_duration` is commented as 2025 but filters through 2026-12-31.
- The final query sums DAU without dividing by observed days, so it is not a monthly-average DAU query.
- Despite its `final` filename, the status is draft or pending validation. Correct the date range and monthly-average logic, then rerun data, grain, join, and delivery checks before production use.

### `游戏独占用户取数模板.sql`

- The current range is 2026-03-01 through 2026-04-30. Future refreshes must update the dates and verify the latest partition.
- It excludes black-market and crawler users and limits APP traffic to Android, iPad, Pad, and iOS.
- It first aggregates each user's monthly game and entertainment watch time, then requires `all_dur > 5` within the relevant category.
- Game-exclusive and entertainment-exclusive users equal category users minus overlap users. Do not calculate exclusivity as game users divided by all users.

## Privacy boundary

The following sources were not uploaded:

- `202601-外部生态数据整理_模板.xlsx` and `202608外部生态数据整理.xlsx`, because they contain anchor IDs, nicknames, contracts, revenue, and other commercial detail.
- All source decks, because they contain MCN, guild, or anchor identities or unreviewed commercial data.
- Anchor-level drilldown results and all user-level detail.

The repository retains only anonymized platform, category, and time aggregates plus source hashes.

## Refresh steps

1. Confirm the latest data partitions and the report cutoff date.
2. Update the SQL dates and rerun availability, unique-key, join-fanout, and metric-invariant checks.
3. Run `scripts/export_anonymous_artifacts.py` to rebuild the artifacts. Keep 2026-08-01 explicitly missing rather than converting it to zero.
4. If Douyin MCN categories do not reconcile to the total, identify the missing category or definitional difference before changing the source chart.
5. When citing a partial month, include a visible cutoff such as “through YYYY-MM-DD.”

Chinese version: `README.md`.
