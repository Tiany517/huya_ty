# Valorant FPS Cross-Broadcast Events and ACU-Tier Success Rates

## Objective

Identify cross-broadcast events by FPS streamers whose main category is not Valorant, compare each event day with the previous valid live day, and estimate event success rates and probability-adjusted ACU factors by tier.

## Execution and Outputs

1. Run `sql/source/无畏契约/01_FPS跨播事件明细_建表.sql` with Spark to create `zhgametemp.wwqy_val_fps_cross_event_compact_20261023`.
2. Run `sql/source/无畏契约/02_ACU分层成功率_最终查询.sql` with Presto. It aggregates tier success rates directly from the event table and creates no second summary table.

The event table grain is FPS-main-category streamer × actual cross-broadcast event. The SQL files are archived from the project folder; event-level streamer details and result-table data are not included.

## Population and Event Definitions

- Period: 2026-01-01 through 2026-10-20; product range is `huya_andriod`, `huya_ipad`, `huya_pad`, and `huya_ios`.
- Main category is the game with the highest cumulative `user_duration` for each streamer over the full period. Streamers whose main category is Valorant `5937` are excluded; only the original FPS game allowlist is retained.
- A valid live day requires at least 60 minutes of total streamer live time. In this query, detail-table `live_mins` is treated as hours and multiplied by 60.
- Big-match days are computed at date × game × match name. A Delta Force `9449` or CS2 `862` match day with DAU >= 50,000 is marked as a big-match day and removed from the valid-live-day sequence.
- A cross-broadcast event requires Valorant viewing on the current day, no Valorant viewing on the previous valid live day, and positive all-category DAU on that previous day. The comparison is to the prior observed valid live day, not necessarily the prior calendar day.
- Tiers use annual simple average ACU on valid days after excluding big-match days: top >= 2,000; mid >= 100 and < 2,000; all others are bottom tier.

## Metric Definitions

- Simple daily ACU: average `acu` across the streamer's game rows for that day. Annual tiering averages this value across valid days.
- Weighted daily ACU: `sum(acu * live_mins) / sum(live_mins)`. Event ACU growth and the success-only growth average both use this definition.
- Watch time: `view_mins_only_live` is summed as hours and multiplied by 60 to convert to minutes.
- A successful event has weighted ACU growth > 0. Success rate uses events as the denominator; repeated events count separately.
- Probability-adjusted expected ACU growth = event success rate × mean weighted ACU growth among successful events. Final ACU factor = 1 + probability-adjusted expected ACU growth.

## Validation Baseline

These validation values come from the project's metric note; event-level data is not in the repository. A machine-readable summary is in [`artifacts/acu-tier-cross-broadcast-baseline.csv`](artifacts/acu-tier-cross-broadcast-baseline.csv).

| ACU tier | Streamers | Events | Successful events | Success rate | Mean weighted ACU growth after success |
| --- | ---: | ---: | ---: | ---: | ---: |
| Top | 4 | 8 | 3 | 37.50% | 93.82% |
| Mid | 3 | 7 | 3 | 42.86% | 442.56% |
| Bottom | 597 | 860 | 277 | 32.21% | 43.68% |
| All FPS | 604 | 875 | 283 | 32.34% | 48.44% |

## Interpretation Limits

This is a descriptive before/after comparison. Cross-broadcasting was not randomly assigned, and streamer and audience outcomes may also respond to matches, content, timing, or other factors. The success rate and probability-adjusted factor alone do not establish causal uplift or guarantee future results. The `view_mins_only_live` unit follows the project's multiply-by-60 transformation; verify the source field independently before reusing it elsewhere.

中文版本见 `README.md`。
