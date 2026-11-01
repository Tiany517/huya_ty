# Valorant Watch-Time Contribution Knee and Stable-Candidate Screen

## Objective

Describe monthly concentration in actual Valorant streamer watch time and estimate the curve knee for all-platform, Huya, and external-platform scopes. A separate screen identifies candidates repeatedly meeting a monthly individual watch-time share threshold. The knee answers where the curve bends; the threshold screen answers who repeatedly clears a chosen share bar. They are not interchangeable.

## Data and Scope

- Observation months: 2026-01 through 2026-09; outputs cover all-platform, Huya, and external-platform scopes.
- Primary metric: `actual_view_mins`. Positive values are sorted descending. Aggregations use minutes and are converted to hours for reporting.
- Monthly sample size is the count of positive-watch-time records; all-platform includes Huya and external platforms. The input is a cleaned CSV. Its upstream query and field lineage are not retained in this project folder.
- The primary result is `拐点结果_按实际观时.csv`, not the earlier predicted-watch-time output `knee_summary_raw.csv`. The predicted metric must not be presented as actual watch time.

## Knee Algorithm and Findings

- Sort positive monthly watch-time values descending and calculate streamer rank `x` and cumulative watch-time share `y`.
- For the primary method, take logs of `x` and `y`, min-max normalize both, compute `D = minmax(log(y)) - minmax(log(x))`, and select the rank with the maximum `D` as the knee. Linear and 51-point-smoothed sensitivities are also reported.
- Across January–September 2026, the all-platform primary knee ranks were 57–92 and their cumulative watch-time shares were 75.45%–81.79%. External-platform ranks were 68–99 with shares of 75.50%–84.65%; Huya ranks were 5–13 with shares of 91.89%–97.77%.
- Knee rank varies by month. Do not turn it into a fixed annual streamer count or an operational admission threshold. It is a descriptive concentration summary and does not explain why shares changed.

## Monthly 0.2% Candidate Screen

- A separate rule uses each month's total positive all-platform watch time as the denominator and identifies a streamer-platform key as `pcode|r_lid`. Exact duplicate captures with the same month, key, and watch-time value are collapsed before calculating individual shares.
- A streamer-month qualifies at an individual share >= 0.2%; the candidate rule requires at least 3 qualifying months from January through September 2026. Scripts also compare thresholds from 2 to 6 months and test live-activity stability rules.
- Monthly qualifying counts range from 59 to 90, and qualifying streamers account for 76.7%–81.8% of monthly watch time. This is a threshold-based screen, not a judgment of streamer quality or causal contribution.
- Individual monthly shares, streamer lists, UIDs, and workbooks with MCN/event labels were not migrated. Only de-identified monthly aggregates are retained.

## Files and Reproduction Limits

- `scripts/` retains the cleaning, primary knee, monthly-threshold, stability-check, and shared algorithm scripts.
- `artifacts/` retains monthly knee summaries, Top-N coverage, and monthly qualification aggregates without streamer identifiers.
- Raw and cleaned input CSVs were not copied. Scripts use old absolute paths and depend on an upstream CSV in Downloads; restore approved inputs, update paths, and confirm source definitions before rerunning on the new computer.
- The upstream definition and unit of `actual_view_mins` should be checked against its source task. This analysis treats the field as minutes and divides by 60 for hours.

中文版本见 `README.md`。
