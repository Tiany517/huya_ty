# Huya-Affiliated Douyin Valorant Monthly ACU Threshold Review

## Objective

Count streamers in the HuShi/HuXiao (Douyin-side) Valorant pool whose monthly average `valid_acu` reached 2,000, 3,000, 4,000, or 5,000, and review the monthly qualifying counts alongside the changing pool size.

## Population and Definitions

- Source input: `Downloads/虎视虎啸无畏契约主播情况.csv`.
- Period: 2026-01 through 2026-10, ten months. The source does not specify the October data cutoff, so October may be partial and should not be interpreted as a complete month.
- Input grain is streamer × month. The project does not recalculate or rename `valid_acu`; a streamer qualifies in a month when the source value is `valid_acu >= threshold`.
- The full period contains 250 streamer IDs and 1,418 streamer-month records. Monthly pool size varies from 109 to 164; read qualifying counts with the corresponding pool size.
- The same streamer is joined across months using `anchor_id`. The source workbook displays the latest nickname, but identity information is removed from the migration outputs.
- No data dictionary explains the exact numerator and denominator of `valid_acu`; confirm its business definition before further reuse.

## Aggregate Results

The anonymized number of streamers who reached each threshold at least once during the period was 4 for `valid_acu >= 2,000`, 3 for `>= 3,000`, 1 for `>= 4,000`, and 1 for `>= 5,000`. Monthly results are available as Chinese [`artifacts/monthly-threshold-counts.csv`](artifacts/monthly-threshold-counts.csv) and English [`artifacts/monthly-threshold-counts.en.csv`](artifacts/monthly-threshold-counts.en.csv).

The chart [`artifacts/monthly-counts-and-maximum-acu.png`](artifacts/monthly-counts-and-maximum-acu.png) shows monthly threshold counts and the pool maximum; it contains no streamer names.

## Reading the Monthly Results

- One streamer reached 2,000 in January 2026; none did so from February through May; two did so in June. In July, two reached 2,000 and one reached 3,000. In August and September, two reached 2,000 and one reached 4,000. In October, the pool maximum was 5,307.1; three reached 2,000, three reached 3,000, one reached 4,000, and one reached 5,000.
- The pool size changes monthly and October coverage is unknown. Count changes alone do not establish streamer growth or a change in pool quality.
- This is a descriptive threshold review, not causal analysis; “ever reached” does not mean sustained qualification.

## Script and Privacy

- `scripts/analyze_hushi_acu_threshold.py` reads the raw CSV and generates an Excel workbook and two charts containing streamer identities. The raw CSV, streamer list, and identity-bearing workbook were not copied.
- To rerun on the new computer, restore approved input, update the script's old paths, and confirm the `valid_acu` definition and October cutoff.

中文版本见 `README.md`。
