# Valorant Event Co-Streaming Case Review (De-Identified)

## Objective and Sample

Review one Huya-affiliated streamer on Douyin before and after Valorant event co-streaming, comparing effective ACU, live duration, and total watch time during event and non-event windows, and describing post-event ACU levels. The migration copy omits the streamer's nickname and platform ID.

- Platform scope: `douyin-hushi` (Douyin-side watch-time data).
- Data period: 2026-05-15 through 2026-10-11; the file covers 150 calendar days, with live records on 116 days and no records on 34 days.
- The source was expanded by day × match and contained 122 rows. Metrics on dates with multiple match labels were identical; deduplication by date yielded 116 streamer-days.
- Available data ends on 2026-10-11. Any post-event seven-day window extending beyond that date must be marked as truncated.

## Key Window Results

The table contains streamer-day window aggregates only, with no daily records. Watch time is in 10,000 viewer-minutes/day.

| Window | Type | Live days | Avg live minutes/day | Mean effective ACU | Avg total watch time (10k min/day) | Comparison |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| 2026-05-18 to 05-31 | Event 1 | 9 | 453.3 | 1,119.7 | 40.7 | First event window baseline |
| 2026-06-06 to 06-21 | Event 2, London Masters | 12 | 225.0 | 3,421.0 | 65.9 | 3.06x Event 1 ACU; 11.7% post-event ACU retention |
| 2026-07-02 to 07-12 | Event 3 | 10 | 354.0 | 1,459.1 | 43.0 | 1.30x Event 1 ACU |
| 2026-07-13 to 08-23 | Event 4, VCT CN Stage 2 | 40 | 439.5 | 1,747.6 | 69.5 | 1.56x Event 1 ACU; 82.6% post-event retention |
| 2026-09-03 to 09-13 | Event 5, Evolution Act 3 | 11 | 310.9 | 1,056.7 | 30.7 | 0.94x Event 1 ACU; 28.9% post-event retention |
| 2026-09-24 to 10-07 | Event 6, Shanghai Champions | 11 | 294.5 | 4,025.5 | 116.8 | 3.60x Event 1 ACU; 70.0% post-event retention |
| 2026-05-15 to 05-17 | Pre-event non-event baseline | 3 | 540.0 | 2,089.2 | 95.7 | Baseline |
| 2026-06-25 to 06-30 | Non-event | 5 | 240.0 | 401.6 | 10.8 | 0.19x baseline ACU |
| 2026-08-24 to 09-01 | Non-event | 8 | 405.0 | 1,443.1 | 55.6 | 0.69x baseline ACU |
| 2026-09-15 to 09-23 | Non-event | 3 | 160.0 | 305.9 | 4.6 | 0.15x baseline ACU |
| 2026-10-08 to 10-11 | Non-event | 4 | 330.0 | 2,817.2 | 89.3 | 1.35x baseline ACU |

De-identified machine-readable window results are in [`artifacts/event-and-non-event-windows.csv`](artifacts/event-and-non-event-windows.csv); monthly summaries are in [`artifacts/monthly-summary.csv`](artifacts/monthly-summary.csv).

## Findings and Limits

- Mean effective ACU during the Shanghai Champions window was 3.60 times that of the first event window. It remained 3.64 times higher among the small subset of live days matched to the same duration bins.
- Non-event ACU did not rise monotonically. ACU during 2026-10-08 to 10-11 exceeded the pre-event baseline, while average total daily watch time remained below it. ACU efficiency and total daily consumption therefore tell different stories.
- High ACU on October 1–2 coincided with the National Day holiday. There were also non-live days and overlapping event windows; the changes cannot be attributed solely to the co-streaming format.
- “Post-event ACU retention” is a ratio of window-average ACU, not user retention. Streamer × day data cannot identify D1/D7 user retention or returning users.
- This is a descriptive single-streamer case, not a randomized experiment. Before/after differences do not establish causal uplift from co-streaming.

## Reproduction Files and Privacy

- `scripts/analyze_yuezi_acu.py` and `scripts/calc_post7_retention.py` are the analysis scripts. They read a raw CSV under the local Downloads folder; update the path on the new computer.
- The raw CSV, daily watch-time detail, workbook with identity information, and charts were not migrated. The upstream extraction SQL is not in the project folder; restore approved inputs and verify definitions before rerunning.

中文版本见 `README.md`。
