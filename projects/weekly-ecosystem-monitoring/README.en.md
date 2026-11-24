# Weekly Ecosystem Monitoring

Status as of 2026-11-24: the project now includes an interactive HTML dashboard and the complete refresh workflow; historical anonymized snapshots remain available. Raw CSV files, build JSON, and large working directories are not committed.

## Latest Interactive Dashboard (2026-11-24)

The latest delivery snapshot is in `interactive-dashboard-20261124/`; start with that directory's `README.md` and `RELEASE_NOTES.md`. It contains:

- The single-file dashboard at `interactive-dashboard-20261124/dashboard/生态监控看板_多维度MVP_新增开播主播数_2026-11-24.html`.
- The metric/SQL workbook, end-to-end documentation, production SQL, build and verification scripts, and the cross-computer refresh skill.
- W47 evidence for 13/13 data checks, 171/171 independent source reconciliations, 8/8 live-anchor UI checks, and browser smoke testing.

The HTML embeds streamer-level aggregates plus UIDs, nicknames, and RoomIDs. It is limited to the private repository and local use. The three raw core CSVs, dashboard JSON, and user-level detail are not uploaded.

## Project Background

This weekly workflow monitors the Huya game-content ecosystem. It converts daily category data into week-over-week changes, category attribution, streamer drilldowns, and a management presentation. The archive covers six weekly category snapshots from 2026-08-31 through 2026-10-11, together with a compact category-overview extract from the presentation workflow and the 2026-10-13 result snapshot.

The workflow supports four recurring questions:

1. How did DAU, gifting, attribution, and interested users change by game category this week?
2. Which streamers or categories contribute most to the ecosystem?
3. Which Honor of Kings streamers meet the ACU threshold, and how do competition days affect comparisons?
4. How can daily query output be loaded reliably into a consistent weekly presentation template?

The figures below establish that the migration files are traceable and reproducible. They are not long-term business conclusions independent of period, category, and population.

## Latest Validated Snapshot

The latest anonymized category snapshot covers 2026-10-05 through 2026-10-11: seven consecutive calendar days, 22 categories, and an additional overall row, for 154 rows in total.

| Metric | Independently rebuilt value | Result-workbook location | Status |
| --- | ---: | --- | --- |
| Overall average daily viewing DAU | 3,627,835.428571 | `品类总览!J14` | Matches |
| Overall average daily attributed users | 4,338,349.285714 | `品类总览!Q14` | Matches |
| Platform current-week DAU | 4,338,349.286 | Platform snapshot | Numerically equal to overall attributed users; definitions still require a rerun check |
| Platform week-over-week change | -106,756.5714 | Platform snapshot | Rebuilds from `current_week_dau - last_week_dau` |
| Maximum rebuild error for revenue per paying user | About `2.98e-08` | Seven daily overall rows | Pass |

## Metric Definitions

### Category DAU and Watch Time

- Source grain is user, date, and category. Sessions are first combined by `dt + user_ukey + game_name`.
- DAU uses `count(distinct user_ukey)`.
- Average watch time is `user_duration / 1000 / 60 / DAU`; source session duration is measured in milliseconds.
- The overall row is deduplicated independently at overall-day grain. Category DAUs must not be summed because one user can watch several categories.

### Gifting

- Only records with `user_consume_amount > 0` are retained.
- Revenue is summed by category and day; paying users use `count(distinct ext['ukey'])`.
- Revenue per paying user is `gift revenue / paying users`.
- Zero revenue and missing data must remain distinct. The archived result SQL uses zero for unmatched rows; rerun validation should confirm that treatment against actual source partitions.

### Attribution and Interested Users

- Attributed users come from `cwq_huya_ukey_shichang_luid_gameid_guishu_day_v1` and are deduplicated by `dt + game_name + user_ukey`.
- Interested users come from `cwq_huya_7days_xqzs_detail_tmp`; the current SQL sums `user_pro`.
- Non-League-of-Legends interest excludes `gameid = 1`. Its business definition should be checked against the data dictionary on the new computer.

### Streamer Drilldown

- Streamer-day grain is `dt + game_name + luid`.
- Streamer detail joins DAU, gifting, attribution, and interest metrics by `dt + game_name + luid`.
- Records not matched to a live-streaming streamer are summarized under `__UNATTRIBUTED__`. Paying-user and attributed-user counts in that row are summed across streamer-days and must not be treated as independently deduplicated category totals.
- The streamer drilldown contains UIDs, nicknames, and streamer-level detail, so it is not included in this repository.

## SQL Chain

### Daily Category Data and Weekly Base Table

`scripts/category-weekly-metrics.sql` is the main weekly base-table query. It builds:

1. A game-ID-to-display-category snapshot.
2. User-day-category sessions and DAU.
3. Category-day and overall-day gifting.
4. Category-day and overall-day attribution.
5. Interested-user metrics.
6. Category result rows and overall result rows.

The archived SQL uses a hardcoded week of 2026-08-31 through 2026-09-06 and a game-map snapshot dated 2026-09-06. These are debugging values and must not be reused unchanged for a new week. A refresh must update all of the following together:

1. Fact-table start and end dates.
2. Game-map snapshot partition.
3. Presentation week window and latest complete partition.
4. Derived week and `between` fields.

### Read Models

- `scripts/category-daily-read-model.sql` reads category overview data for a selected week from the daily ecosystem-health table.
- `scripts/anchor-drilldown-read-model.sql` reads a previous-week streamer drilldown; its archived window is 2026-08-24 through 2026-08-30.

Both read models hardcode week windows and core game IDs. Confirm the target week and dependency partitions before use.

### Streamer Drilldown Build

`scripts/anchor-drilldown.sql` produces:

- Streamer-day detail.
- An unmatched-streamer supplement row.
- Category overall rows.

This query has high definition risk. Every join must be checked for uniqueness at both grains. `daily_pay_user_cnt` and `daily_attribution_user_cnt` in the supplement row may double-count the same person when added across streamer rows. The supplement explains unmatched revenue or users; it is not a deduplicated cross-streamer total.

### Platform DAU

`scripts/platform-dau.sql` calculates average daily DAU for two weeks from the SDK active-user table. The archived SQL uses a debugging window from 2026-08-24 through 2026-09-06. Its population differs from category overall attribution, so equal values in one week do not prove that the two metrics use the same definition.

### Honor of Kings Top 20 Examples

- `scripts/top20-honor-of-kings-dau-acu.sql` compares ACU, DAU, attribution, and interest metrics for Honor of Kings streamers across two consecutive weeks.
- `scripts/top20-honor-of-kings-dau-acu-excluding-events.sql` removes competition days before monthly aggregation.

Competition days come from the copyrighted-event dimension. The snapshot date and month filter are also hardcoded in the archived SQL. A refresh must recheck event coverage and union grain.

## Presentation Template and Formula Chain

The migration package retains compact result extracts, not the complete presentation workbook. `artifacts/weekly-results/final-presentation-template.xlsx` is a single-sheet `品类总览` snapshot of about 85 rows by 17 columns with no formulas. `artifacts/weekly-results/weekly-result-20261013.xlsx` is a single-sheet `品类总览` result snapshot of about 91 rows by 21 columns with two difference/growth formulas. Both are about 26 KB.

The local source presentation template contains 22 worksheets. Its scanned summary and attribution sheets contain about 116,177 formula cells, and six streamer data-source sheets contain about 2.8 million detail rows. The source template, complete formula sheets, and streamer detail are excluded; the repository retains only the structure inventory and compact category-overview snapshots.

The principal scanned worksheets are:

- `各品类的DAU和打赏情况`: daily category aggregates and derived weekly fields.
- `品类总览`: category DAU, gifting, attribution, and averages.
- `品类归因`: weekly structure and trend.
- Overview and attribution sheets for League of Legends, Honor of Kings, CS2, sports, Valorant, and outdoor content.

Full worksheet dimensions and formula counts are in `artifacts/template-structure.en.csv`.

The source template has known title defects: `王者总览!B1` and `户外归因!B1` currently display “英雄联盟” (League of Legends). These are likely copy-template remnants. Restore the source workbook locally on the new computer, then confirm and repair them. The uploaded single-sheet category-overview snapshot does not contain these worksheets, and this review did not modify the source workbook.

## Upload Boundary

### Included

- Nine SQL and Python scripts.
- Six anonymized weekly category CSVs.
- Five anonymized platform DAU snapshots.
- Two small workbook snapshots.
- Template structure, weekly-file inventory, platform-file inventory, and Chinese/English validation records.
- Reproducible validation in `scripts/validate_weekly_snapshots.py`.

### Excluded

- Source workbooks from about 186 MB to 291 MB, including `生态监控模板_1013.xlsx`.
- Six streamer-day source worksheets containing streamer UIDs, nicknames, and streamer-level detail.
- Category streamer-drilldown CSVs from about 5 MB to 7 MB.
- Other unreviewed large templates, caches, and intermediate files.

No source workbook was modified, and no user-level or streamer-level detail was pushed to GitHub.

## Validation Status

`scripts/validate_weekly_snapshots.py` regenerates the four Chinese/English inventories and validation attachments. Current results:

| Check | Status | Result |
| --- | --- | --- |
| Six weekly category schemas | Warning | All have seven consecutive days, 22 categories, 154 rows, and no duplicate keys or parse failures; four early files contain Excel presentation placeholders |
| Latest overall DAU | Pass | Independent CSV mean matches `J14` |
| Latest overall attributed users | Pass | Independent CSV mean matches `Q14` |
| Platform current-week DAU | Pass | Numerically matches overall attributed users; definitions still need review |
| Platform week-over-week change | Pass | Rebuilds from the two weekly values |
| Revenue per paying user | Pass | Maximum absolute error about `2.98e-08` |
| Historical platform-file structure | Warning | Contains one duplicate snapshot and one manual export format |

The validation proves continuity among the current anonymized CSVs, two result workbooks, and platform snapshots. It does not replace rerunning source partitions, field dictionaries, and business definitions on the new computer.

## Known Data Issues

1. `platform-active-20260923-copy-of-20260914.csv` has the same SHA256 as `platform-active-20260914.csv`. The 20260923 file was probably copied without updating and must not be treated as a genuine new week.
2. `platform-active-20261008-exported.csv` is a manual Excel export with extra blank header columns, blank rows, and formatted percentages. Other files in the directory are clean three-column tables.
3. Four category CSVs for 20260907, 20260914, 20260923, and 20261008 contain dash placeholders and blanks in `非LOL兴趣用户数`. The validator preserves them as missing and does not convert them to zero.
4. Template titles in `王者总览!B1` and `户外归因!B1` appear to be copy errors.
5. Paying-user and attributed-user counts in the unmatched streamer supplement cannot be summed across streamers.
6. Platform active DAU and overall attributed users are equal in the current week, but no field-level evidence proves the definitions are identical.

## Continue on the New Computer

1. Clone the repository and enter `projects/weekly-ecosystem-monitoring/`.
2. Use the local source map stored outside Git to reconnect the project to `Desktop/周报监控模型`.
3. Run `python scripts/validate_weekly_snapshots.py` to confirm the archive and result workbook remain consistent.
4. Confirm the latest partitions, field units, and permissions for all six source tables.
5. Update week windows, map snapshot dates, and event-dimension dates in the SQL. Do not reuse archived debugging dates.
6. Generate the anonymized daily category CSV first, reconcile overview totals with the result workbook, and then produce the presentation workbook.
7. Apply the SQL validation workflow to every join, `union all`, `__UNATTRIBUTED__` row, and common denominator.
8. Save title repairs as a new workbook version and do not overwrite the original template.

## GitHub Path Map

| GitHub path | Contents |
| --- | --- |
| `projects/weekly-ecosystem-monitoring/README.md` | Chinese project guide and path map |
| `projects/weekly-ecosystem-monitoring/README.en.md` | English project guide and path map |
| `projects/weekly-ecosystem-monitoring/scripts/category-weekly-metrics.sql` | Daily category, weekly base table, and overall deduplication logic |
| `projects/weekly-ecosystem-monitoring/scripts/category-daily-read-model.sql` | Category daily read model |
| `projects/weekly-ecosystem-monitoring/scripts/anchor-drilldown.sql` | Streamer drilldown, unmatched supplements, and category overall rows |
| `projects/weekly-ecosystem-monitoring/scripts/anchor-drilldown-read-model.sql` | Streamer drilldown read model |
| `projects/weekly-ecosystem-monitoring/scripts/platform-dau.sql` | Two-week platform average DAU |
| `projects/weekly-ecosystem-monitoring/scripts/top20-honor-of-kings-dau-acu.sql` | Two-week Honor of Kings Top 20 example |
| `projects/weekly-ecosystem-monitoring/scripts/top20-honor-of-kings-dau-acu-excluding-events.sql` | Monthly Honor of Kings streamer example after event-day exclusion |
| `projects/weekly-ecosystem-monitoring/scripts/csv_to_excel.py` | CSV cleaning and Excel conversion helper |
| `projects/weekly-ecosystem-monitoring/scripts/validate_weekly_snapshots.py` | Reproducible snapshot, workbook, and platform-file validation |
| `projects/weekly-ecosystem-monitoring/artifacts/weekly-category/` | Six anonymized weekly category CSVs |
| `projects/weekly-ecosystem-monitoring/artifacts/platform-dau/` | Five anonymized platform DAU snapshots |
| `projects/weekly-ecosystem-monitoring/artifacts/weekly-results/` | Single-sheet category-overview template and 2026-10-13 result snapshots; the complete source template is excluded |
| `projects/weekly-ecosystem-monitoring/artifacts/template-structure.csv` | Chinese worksheet and formula inventory |
| `projects/weekly-ecosystem-monitoring/artifacts/template-structure.en.csv` | English worksheet and formula inventory |
| `projects/weekly-ecosystem-monitoring/artifacts/weekly-validation.csv` | Chinese validation record |
| `projects/weekly-ecosystem-monitoring/artifacts/weekly-validation.en.csv` | English validation record |

All paths are relative to the GitHub repository root. Codex on the new computer should read `README.en.md`, the scripts, and validation attachments first, then decide whether to restore excluded source workbooks from the local machine.

Chinese version: `README.md`.
