# Valorant 5937 Streamer P50 Live-Time Uplift Estimate

## Objective

Estimate the theoretical additional watch time and its share of the five-platform daily watch-time denominator if eligible top-tier and mid-tier streamers increased average daily live time to the P50 for their ACU tier while their current average daily ACU remained unchanged.

## Population and Time Range

- Data period: 2026-01-01 through 2026-10-22, `gameid=5937`.
- Industry watch-time denominator: 91,858,247.16 viewer-minutes/day across five platforms, using valid streamer-days from 2026-01-01 through 2026-10-21. The denominator ends one day earlier than the streamer-metric data; retain this date difference when comparing.
- Initial population: 32,399 streamers.
- ACU tiers: top tier has annual average daily ACU >= 2,000; mid tier has 100 <= annual average daily ACU < 2,000.
- Eligibility filters: average live days per active month >= 10, where active months are months with 5937 streaming records; annual average daily live time >= 60 minutes; exclude event/content accounts, clubs, and high outliers.
- High-outlier cap: Q3 + 3×IQR = 1,269.7273 minutes/day; neither version identified a high outlier.
- Base eligible sample: 14 streamers (5 top-tier, 9 mid-tier).
- Business-adjusted version: one streamer was additionally excluded based on business information dated 2026-10-27, leaving 13 (4 top-tier, 9 mid-tier). This is a business exclusion, not statistical outlier treatment.

## Metrics and Calculation

- Calculate the linearly interpolated P50 of annual average daily live time separately for each ACU tier.
- Streamers needing uplift: count streamers whose current annual average daily live time is below their tier P50.
- Theoretical additional watch time (viewer-minutes/day): for each streamer needing uplift, calculate `annual average daily ACU × max(0, tier P50 target minutes − current average daily live minutes)`, then sum.
- Convert to viewer-hours/day by dividing by 60.
- Industry share: theoretical additional watch time divided by the five-platform daily watch-time denominator.

## Aggregate Results

| Definition | Eligible sample (top/mid) | Need uplift | Top-tier P50 (min/day) | Mid-tier P50 (min/day) | Theoretical additional watch time (viewer-hours/day) | Industry share |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| No additional business exclusion | 14 (5/9) | 6 | 450.5606 | 470.5337 | 38,118.93 | 2.4899% |
| Exclude the streamer per business request | 13 (4/9) | 6 | 460.5311 | 470.5337 | 37,174.84 | 2.4282% |

After the exclusion, the sample falls by one and the top-tier P50 rises by about 9.9705 minutes/day. The number needing uplift remains six. Theoretical additional watch time falls by 56,645.40 viewer-minutes/day (944.09 viewer-hours/day), and the industry-share estimate declines by about 0.0617 percentage points.

## Interpretation Limits

This is a static scenario estimate based on a same-tier P50 target. It does not mean streamers will actually add the estimated live time or that realized watch time will grow by this amount. The formula holds annual average daily ACU constant and does not model audience response to additional supply, time-slot overlap, deduplicated viewers, content quality changes, or category-share substitution. Do not describe 2.4282% as a causal effect or realized share growth.

## Sources and Privacy

- Local source folders: `Desktop/无畏契约份额增长/5937_P50有效月重算_20261027/` and `Desktop/无畏契约份额增长/5937_P50有效月剔除已跳槽_20261027/`.
- Main source materials: both versions of `analysis_summary_p50.json`, `build_workbook_p50*.mjs`, summary-check records, and formula-error-check records.
- Raw CSVs, streamer-level detail CSV/JSON, detailed screening audits, and Excel workbooks containing streamer-level rows were not copied into this repository.
- This summary was compiled from aggregate JSON and saved-workbook verification records. Underlying streamer-level data is not retained here; a full recalculation requires restoring the raw input in an authorized data environment.

Chinese version: `README.md`.
