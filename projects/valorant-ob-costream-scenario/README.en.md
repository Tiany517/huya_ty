# Valorant OB Co-Streaming Scenario Estimate

## Objective

Review the ACU and watch-time scenario model in the workbook titled “Potential Co-Streaming Event Program List.” Only anonymized model definitions and aggregate outputs are migrated; streamer lists, UIDs, nicknames, and detailed workbook data are excluded.

## Workbook Scope and Assumptions

- The workbook selects nine streamer candidates and describes the event scope as large events with DAU above 200,000.
- ACU increment for each candidate is calculated as `mean event-period ACU × 3.56`; this is then multiplied by the candidate's average live minutes to estimate incremental watch time per event day.
- The candidate estimates are summed, multiplied by 125 annual large-event days, and divided by 360 days to obtain an annualized daily watch-time scenario.
- The denominator is 91,858,247.16 viewer-minutes/day from the five-platform Valorant-category interval-average watch-time query. The reference SQL covers Valorant only, averages dates with data from 2026-01-01 through 2026-10-21, and does not fill missing dates with zero. The workbook does not fully document whether its numerator shares the denominator's platform, time, and user-deduplication scope.
- The final ratio is multiplied by a 21% success-probability assumption. A nearby workbook note says “1 success out of 5,” which corresponds to 20%, not 21%, and is a very small sample.

## Source Workbook Aggregates

| Metric | Value | Unit | Interpretation |
| --- | ---: | --- | --- |
| Candidate streamers | 9 | streamers | Anonymized candidate set |
| Estimated incremental watch time per event day | 33,942,960.13 | viewer-minutes | Source workbook aggregate |
| Annual large-event days | 125 | days | Source workbook assumption |
| Annualized total incremental watch time | 4,242,870,016.60 | viewer-minutes/year | Per-event-day increment × 125 |
| Annualized daily incremental watch time | 11,785,750.05 | viewer-minutes/day | Annual total ÷ 360 |
| Five-platform Valorant-category daily watch-time denominator | 91,858,247.16 | viewer-minutes/day | Category denominator from reference SQL |
| Ratio before success-probability adjustment | 12.8304% | ratio | Annualized daily increment ÷ denominator |
| Workbook success probability | 21% | probability | Source workbook assumption |
| Ratio after probability adjustment | 2.6944% | ratio | Unadjusted ratio × 21% |

Machine-readable figures are in [`artifacts/scenario-summary.csv`](artifacts/scenario-summary.csv). These figures reproduce the workbook scenario; they are not realized watch-time or share growth.

## Review Findings and Limits

- The workbook also lists “original average event watch time 6.32 minutes” and “current event watch time 17.79 minutes,” a difference of 11.47 minutes. Formula inspection shows that this difference does not enter the per-event-day increment formula, which is `ACU increment × average live minutes`. Confirm whether this column is contextual only or was intended to affect the estimate.
- The 3.56 ACU-increment coefficient, 125 annual event days, 360-day annualization, and 21% success probability are assumptions. The workbook does not include reusable source SQL, candidate-selection code, or a sufficiently documented probability estimate.
- “One success in five” is too small a historical sample to represent a stable future probability. Do not present 2.6944% as certain expected growth or a causal effect.
- The denominator SQL is scoped to five-platform Valorant watch time, but the workbook does not fully document the numerator's platform coverage, deduplication rules, or valid-date scope. Retain this scope limitation whenever quoting the ratio.
- The source workbook contains streamer identities and performance details and was not copied. Any model revision should restore the input in an approved data environment, verify formulas and inputs, and then refresh the anonymized summary.

Source: `Desktop/无畏契约份额增长/OB二路赛事节目化份额提升估算.xlsx`. Denominator SQL: `sql/source/无畏契约/无畏契约_行业区间日均观时_20260101_20261021.sql`.

中文版本见 `README.md`。
