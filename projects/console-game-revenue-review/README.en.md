# Console-Game Revenue Year-over-Year Review

This project reviews Huya's console-game revenue in January-May 2026 against the same months of 2025. Its purpose is to preserve the business question, source grain, analytical methods, and known quality risks for Codex on the new computer. It does not reproduce the source workbooks containing streamer UIDs, nicknames, and streamer-level revenue.

## Business Context

Console-game revenue declined materially in the first five months of 2026. The original analysis needed to answer:

1. Which months and streamers contributed to the total decline, and how concentrated was it?
2. Did the decline come from fewer payers, lower viewing UV, a lower payment rate, or lower payment per user?
3. What happened to head, tail, entering, and exiting streamer supply?
4. Did the structure of large spenders and ordinary payers change?
5. Where should operations intervene based on supply efficiency, traffic conversion, and tipping intent?

The main grain is streamer by month. The analysis compares 2025-01 through 2025-05 with 2026-01 through 2026-05 on a same-month basis rather than comparing cumulative periods with different observable windows.

## GitHub Path Map

| Repository path | Contents |
| --- | --- |
| `projects/console-game-revenue-review/README.md` | Chinese background, definitions, methods, anonymous summary, and limitations |
| `projects/console-game-revenue-review/README.en.md` | Standalone English version |
| `projects/README.md` / `README.en.md` | Bilingual index of all projects |
| `README.md` / `README.en.md` | Repository-wide path map and new-computer setup |

The original `主机游戏营收分析.xlsx`, `_V2.xlsx`, and `V3.xlsx` workbooks were not uploaded.

## Data Grain and Fields

- Base grain: `luid × month`, one row per streamer per month.
- The V3 cleaned workbook's console-game base sheet has a used range of 8,923 rows. Of these, 3,232 contain valid revenue data and produce 3,232 unique `month × luid` keys with no duplicates. Valid monthly rows are roughly 242-438 each, so blank and display-area rows must not be mistaken for streamer records.
- Key fields: `revenue`, `pay_users`, `monthly_uv`, and `avg_payment_amt`.
- Additional sheets cover tipping-process detail, monthly revenue Top 20, monthly revenue-decline Top 20, and tipping intent.
- Currency units, UV deduplication, and upstream SQL were not retained completely. Reconfirm the field dictionary before reuse.

## Analysis Methods

### 1. Same-Month YoY and Total Decomposition

Aggregate the streamer-month table by month and calculate the revenue difference and decline rate between 2026 and the same month of 2025. At streamer level, retain:

- Revenue change: `2026 revenue - 2025 revenue`.
- YoY: change for the same streamer against the same month of the prior year.
- Impact: streamer change divided by the platform total change, used to rank contributors.
- Contribution: streamer change divided by the platform baseline revenue.

The denominator must be explicit. Without a stable full-universe denominator, impact and contribution are ranking aids, not causal attribution.

### 2. Payment-Structure Decomposition

Calculate and compare by month:

- Payment rate: `pay_users / monthly_uv`.
- Revenue per payer: `revenue / pay_users`.
- Revenue per viewing user: `revenue / monthly_uv`; this is observational until the UV deduplication scope is confirmed and should not be labeled formal ARPU.
- Number of large spenders and their share of total revenue, used to test reliance on a small group.

### 3. Rankings and Supply Efficiency

Build monthly revenue and revenue-decline Top 20 lists and inspect:

- Head concentration and rank changes.
- Effects of entering, exiting, and retained streamers on the net change.
- Count of effective live streamers and movement in supply thresholds.
- Differences in traffic-to-revenue conversion, supply efficiency, and tipping intent.

The effective-streamer threshold and upstream SQL were not fully retained. Do not silently redefine the population from the visible columns; recover the original definition first.

## Anonymous Monthly Summary

The table sums nonblank revenue rows from the V3 base sheet by month. Values remain in the source workbook's original scale; because the unit definition was not retained, the table does not assert a currency label.

| Month | 2025 source revenue | 2026 source revenue | YoY change | YoY decline |
| --- | ---: | ---: | ---: | ---: |
| January | 1,463,981.00 | 716,788.10 | -747,192.90 | -51.04% |
| February | 1,162,449.60 | 753,189.10 | -409,260.50 | -35.21% |
| March | 1,619,356.60 | 591,477.40 | -1,027,879.20 | -63.47% |
| April | 1,303,608.70 | 572,984.00 | -730,624.70 | -56.05% |
| May | 1,324,776.30 | 714,008.90 | -610,767.40 | -46.10% |
| January-May | 6,874,172.20 | 3,348,447.50 | -3,525,724.70 | -51.29% |

Under this source-table definition, revenue fell in every month and roughly halved over the five-month period. Without upstream SQL, a field dictionary, and the complete supply definition, the decline cannot be attributed causally to a particular streamer, event, or content strategy.

## Known Quality Risks

- V1 and V2 contain opposite-direction YoY formulas in the monthly revenue Top 20 sheet. V3 is the cleaned final edition, but the complete upstream pipeline was not rerun during migration.
- The source SQL, field dictionary, currency unit, UV deduplication, and effective-streamer threshold were not retained.
- Streamer-level impact must use a verified denominator; ranking without a fixed denominator is not causal attribution.
- Only January-May is covered and cannot be extrapolated to the full year. Later 2026 campaigns and supply changes are outside the evidence.

## Excluded Material

- All three original XLSX workbooks.
- Streamer UIDs, nicknames, streamer-level revenue, payers, UV, tipping-process data, and rankings.
- Any chart or export that can be traced back to an individual streamer or user.

Chinese version: `README.md`.
