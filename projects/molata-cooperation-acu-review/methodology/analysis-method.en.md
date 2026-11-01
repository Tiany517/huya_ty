# Analysis Method and Definitions

## Input Grain

- Streamer-day table: one valid-ACU record for one streamer identifier on one calendar day; `dt + identifier` is unique.
- Platform-day tables: one row per calendar day; dates are unique.
- Output: role-level series, group totals, and anonymous platform benchmarks remain at daily grain; the unit-by-window table further aggregates them.

## Role Anonymization

The legacy script hard-coded six streamer identifiers and nicknames. The repository does not retain them. The rebuild script ranks anchors by total source valid ACU across the full snapshot, labels the highest as `anchor_01`, labels the others `anchor_02` through `anchor_06`, and treats the lower five as the collaboration group. This reproduces the historical group-level workbook but is not a substitute for a business-owned role mapping.

## Formulas

- Individual natural-day average ACU = individual ACU sum in the window / all calendar days.
- Collaboration-five total = daily sum of the five collaboration anchors, excluding `anchor_01`.
- Six-anchor total = five collaboration anchors plus `anchor_01`.
- Recorded-day average = ACU sum / days with a row for that anchor.
- Missing anchor-days enter natural-day group totals as zero, following the legacy script.
- Platform excluding five = full platform minus the five collaboration anchors, retaining `anchor_01`.
- Platform excluding six = full platform minus all six reviewed anchors.
- Outlier-adjusted benchmark = platform data with one anomalously high-ACU account removed.
- Six-anchor daily share = six-anchor total / platform benchmark that day. Window share is the simple mean of daily shares, not aggregate window ACU divided by aggregate benchmark ACU.
- `pp` means percentage points: anchor growth minus benchmark growth, not relative growth.

## Windows

| Window | Dates | Calendar days | Purpose |
| --- | --- | ---: | --- |
| Pre-month | 2026-05-24 through 2026-06-23 | 31 | Descriptive baseline |
| Cooperation | 2026-06-24 through 2026-06-30 | 7 | Event window |
| Post-month including event | 2026-06-24 through 2026-07-23 | 30 | First 30 days from the event start |
| Post-month excluding event | 2026-07-01 through 2026-07-30 | 30 | First 30 days after the event |

## Independent Validation

1. Check `dt + identifier` uniqueness, six anchors, 608 rows, and source coverage.
2. Check that both platform tables have 123 unique dates and identical date sets.
3. Rebuild six-anchor and five-anchor series from base streamer-day rows and compare with the anonymous CSV.
4. Recompute all 13 units by four windows and compare numeric outputs.
5. Compare generated six-anchor and five-anchor growth with the historical Excel growth sheet, allowing its four-decimal rounding.
6. Test whether full platform minus platform-excluding-six equals the six-anchor daily total. List failures rather than treating them as passes.
7. Scan anonymous CSV files, workbooks, and documents for streamer identifiers, nicknames, or blocked headers.

## Known Limitations

- No upstream SQL was retained, so the cause of the 13 platform residual failures cannot be established.
- The analysis does not distinguish “no stream” from “missing data” when an anchor-day has no row.
- It does not adjust for events, summer seasonality, platform traffic, scheduling, or content changes.
- Only six anchors are present, and group averages can be driven by one anchor.
- This is a descriptive review, not evidence of causality, ROI, or signing value.

Chinese version: `analysis-method.md`.
