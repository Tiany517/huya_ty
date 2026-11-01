# Validation Report

Status: the validator runs with zero failures, but the project remains `incomplete` because of one substantive reconciliation issue and one upstream SQL audit that was not run.

## Summary

- Checks: 21
- Passed: 19
- Known issues: 1
- Not run: 1
- Failed: 0

The machine-readable result is `validation-report.json`.

## Eight Gates

| Gate | Status | Evidence |
| --- | --- | --- |
| Data availability | Pass | 608 streamer-day rows, six anchors, and 121 dates with records; both platform tables have 123 unique dates with full date parity |
| Schema and semantics | Pass with limits | `valid_acu`, natural-day averages, and exclusion definitions follow the source script; zero-filling missing rows does not establish that the anchor did not stream |
| Grain and uniqueness | Pass | No duplicate `dt + anchor identifier`; no duplicate platform dates; anonymous daily output has 123 rows |
| Joins and row multiplication | Pass | Platform tables remain 123 rows after an outer join on date; output row counts match expected shapes |
| Metric invariants | Pass with critical issue | Six- and five-anchor daily totals equal the sum of roles, but platform differences fail to return to the source total on 13 dates |
| Independent recomputation | Pass | All 13 units by four windows were rebuilt from base streamer-days; four historical group-growth values reproduce within four-decimal rounding |
| Boundaries and business spot checks | Pass with limits | Four windows, two post definitions, and outlier-adjusted benchmarks were reviewed; scheduling, events, and other concurrent factors were not audited |
| Delivery and runtime | Pass | Chinese/English CSV shapes match, each workbook has six sheets, and both scripts compile and execute |

## Critical Failure Mode

Residual between “full platform minus platform-excluding-six” and the six-anchor source total:

- 110 dates have an absolute residual no greater than `0.11` ACU.
- 13 dates exceed that threshold.
- Cumulative residual is `+14,548.03` ACU.
- The maximum one-day residual is `+4,159.76` on 2026-06-15.
- Seven dates exceed 100 ACU.

No upstream SQL was retained, so the cause cannot be attributed to identifier type, list matching, duplicate rows, category filters, or one identifier producing multiple streamer records. Any platform-relative excess-growth statement remains pending until this is repaired.

## Privacy Checks

- No streamer identifier or nickname headers were found in CSV, text, or XLSX outputs.
- No 10-plus-digit pure numeric identifier values were found.
- The identity-bearing source workbook and original Python script were not uploaded.
- The source manifest retains hashes without absolute local paths.

## Currently Citable Findings

Citable: six-anchor total natural-day average ACU is 4,813.57 before the cooperation, 5,631.06 in the post-month including the event, and 6,641.35 in the post-month excluding it. These group values are independently reproducible from streamer-day input.

Use with caution: platform comparisons, excess percentage points, daily shares, and outlier-adjusted benchmarks. They depend on the unreconciled platform differences.

Not supported: claims that the cooperation caused ACU growth, cooperation ROI, signing value, or future growth.

Chinese version: `validation-report.md`.
