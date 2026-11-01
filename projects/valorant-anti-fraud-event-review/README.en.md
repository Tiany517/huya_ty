# Valorant Anti-Fraud Event Review

## Objective

Review anti-fraud live streams and changes in streamer ACU and watch-time share. The sources were `反炸鱼主播_首播分层_2026-10-22.xlsx` and `反炸鱼观时份额提升估算.xlsx`. The source workbooks contain streamer IDs, nicknames, and event-level detail and were not copied into the repository.

## Valid Days and Metrics

- A valid day has a valid broadcast, ACU above zero, calculable daily watch-time share, and is not a major-event day. The before/after N-window uses N qualifying double-valid days; dates need not be consecutive.
- Daily watch-time share is the streamer's daily Valorant watch time divided by platform-wide daily Valorant watch time. Window share is the arithmetic mean of these daily shares.
- The first-stream summary defines success as at least 40% higher mean ACU in the N valid days after the first stream than in the N valid days before. This is a descriptive workbook threshold, not a causal effect.
- The all-event stratum sheet states a period from 2025-01-01 through 2026-10-20. This migration note does not infer a full-period cutoff for the first-stream table where it is not stated.

## Result 1: Same-Day Share Change for All Anti-Fraud Events

Using mean ACU over the prior 30 valid days for strata: head streamers had 3 anchors and 21 comparable events, with 57.14% of events associated with a same-event-day share increase; waist had 49 anchors and 2,231 events (50.65%); tail had 342 anchors and 8,633 events (50.12%). Overall, 394 anchors and 10,885 events produced a 50.24% increase rate. See [`artifacts/all-event-stratum-summary.csv`](artifacts/all-event-stratum-summary.csv).

These are descriptive same-day event statistics. Without a contemporaneous control group, the increase cannot be attributed to anti-fraud content.

## Result 2: First Anti-Fraud Stream Windows

Among streamers with complete valid days before and after the first anti-fraud stream, 200 of 1,132 evaluable streamers reached at least 40% ACU growth over the 7-day window (17.67%); 109 of 685 did so over 14 days (15.91%); and 69 of 394 did so over 30 days (17.51%). See [`artifacts/first-stream-window-summary.csv`](artifacts/first-stream-window-summary.csv).

In the complete 30-day cohort, 45.18% of streamers had a higher event-day share than their prior-7-day mean. The arithmetic mean share change was 0.007129 under the workbook's column convention and the median was -0.000246; the mean streamer-level ACU change was 30.59%. See [`artifacts/first-stream-stratum-summary.csv`](artifacts/first-stream-stratum-summary.csv).

## Result 3: Up-Only Event Subsample

The `only increases` sheet contains 12 increases among 21 head events, 230 among 447 waist events, 750 among 1,496 tail events, and 992 among 1,964 events overall. Mean, median, and average ACU changes for that subsample are in [`artifacts/up-event-stratum-summary.csv`](artifacts/up-event-stratum-summary.csv). The event counts are smaller than the all-event sheet, but the workbook does not explain the filter, so the two denominators should not be treated as interchangeable.

## Scenario Estimates

The workbook contains three target-streamer-count scenarios. Using its `target count × up-event rate × mean up-event share change` formula, the combined head-and-waist results are approximately 0.1164, 0.0674, and 0.0776; the column labels use `pp`, but the model's interpretation is weak. A separate `estimated added watch time ÷ industry average daily watch time` result is approximately 0.7768%. See [`artifacts/target-count-scenarios.csv`](artifacts/target-count-scenarios.csv) and [`artifacts/scenario-summary.csv`](artifacts/scenario-summary.csv).

These are workbook formula outputs, not prediction intervals, realized growth, or causal effects.

## Material Limitations

1. The workbook contains at least three event universes: all events, first-stream events, and up-only events. Their event counts differ substantially, and available notes do not explain the filter fully.
2. The 40% ACU threshold, target counts, and projection factors are assumptions without a benchmark selection rule, confidence intervals, or independent validation.
3. The analysis uses both event-day-versus-prior-7-day and before/after N-valid-day windows. Results from these windows must not be read as one series.
4. Platform traffic, tournaments, recommendations, and streamer choices can affect event outcomes. This design does not isolate a causal anti-fraud-content effect.
5. Streamer IDs, nicknames, and event-level detail were excluded; only anonymized strata are retained.

Chinese documentation: [`README.md`](README.md).
