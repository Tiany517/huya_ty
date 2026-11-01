# Big Pot Watch-Time Share Scenario Estimate

## Objective

Review the Big Pot watch-time estimate workbook under the Valorant share-growth folder. Preserve its aggregate formulas, anonymized scenario results, and follow-up checks so the model can be assessed on the new computer.

## Inputs and Definitions

- Source workbook: `C:\Users\tiany\Desktop\无畏契约份额增长\大锅饭观时份额提升估算.xlsx`. The original workbook was not copied.
- The industry baseline comes from the workbook's `行业日均观时` sheet: 2026-01-01 through 2026-10-21, 294 valid days, and 91,858,247.1649 average daily watch minutes.
- The primary scenario comes from `汇总_Final`: eight internal records (one separately uses a 100% success rate and 46.4% growth rate; the other records use 40% and 236.8%), and 26 external records using 40% and 236.8%. The estimated incremental watch minutes for each record are divided by the industry daily watch-time baseline and summed.
- The alternative scenario applies the workbook's 74% factor to the watch-time base. Its formulas sum seven internal and 26 external records, omitting one internal record included in the primary scenario; scenario populations therefore differ.
- Traceable formulas: primary internal `SUM(J5:J12)` and external `SUM(J13:J38)`; alternative internal `SUM(AC6:AC12)` and external `SUM(AC13:AC38)`. Each scenario uses the same industry daily watch-time denominator; the combined result is the sum of group shares.
- These are model scenarios, not realized share changes or causal effects. Percentages represent estimated increments as a share of average daily industry watch time. See the anonymized [`artifacts/scenario-summary.csv`](artifacts/scenario-summary.csv).

## Anonymized Results

The primary scenario estimates internal, external, and combined share increments of approximately 3.0705%, 2.3681%, and 5.4386%. The alternative estimates are approximately 0.7076%, 1.8501%, and 2.5577%. These are the workbook formula outputs, not claims of forecast accuracy.

## Limitations

1. The workbook's `斗鱼大锅饭整体` source sheet is labeled 2024-01-01 through 2024-10-31, while the industry baseline uses 2026 data; the periods do not match.
2. The industry-baseline sheet does not state its category scope, so the denominator cannot be confirmed as matching the target category from the workbook alone.
3. The alternative scenario excludes one internal record, so it is not a like-for-like sensitivity comparison with the primary scenario.
4. The success rates, growth rates, and 74% factor are model assumptions without documented definitions, out-of-sample validation, or uncertainty intervals.
5. The original workbook contains streamer names, platform IDs, and candidate details. It was not migrated; only anonymized group aggregates are retained.

## Migrated Files

- `artifacts/scenario-summary.csv`: anonymized internal, external, and combined results for both scenarios.
- `README.md`: Chinese documentation.

Before reuse, verify the industry denominator's platform and category scope, source-data periods, scenario populations, and the business definitions of all model factors.
