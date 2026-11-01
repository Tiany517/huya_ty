# Huya Star Show Retention Denominator Fix

## Problem

The original `zty_huya_xingxiu_subcategory_monthly_retention_dau_v1.sql` expands each user-day into D7, D14, and D30 rows in `retention_candidate`. The later `retention_monthly` CTE sums `is_danmu` and `is_gift` directly to form the common cohort base. This triples the denominator. Retained users are counted only on their matching horizon, so they are not tripled. Consequently, every stored danmu and gift retention rate is approximately one third of the correct rate.

## Verified Evidence

- The data platform returned the target table successfully: 132 aggregate rows exist, with 2026-10 as the latest month. Its retention base is zero because the script caps retention cohorts at 2026-09-30.
- Across all 132 rows, 122 danmu bases and 126 gift bases are positive and divisible by three; remaining rows are zero or do not meet the condition.
- For 2026-09 Star Show overall, the stored danmu base is 1,655,709 and the inferred correct base is 551,903. With 171,629 D7 retained users, the stored 10.37% rate should be approximately 31.10%. The stored gift base is 812,301 and the inferred correct base is 270,767. With 53,574 D7 retained users, the stored 6.60% rate should be approximately 19.79%.
- Across all 22 Star Show overall months from 2025-01 through 2026-10, every non-zero danmu and gift base is divisible by three. Dividing the stored base by three therefore introduces no rounding error in the inferred correct cohort base.
- The corrected Star Show category mapping found 667 observed calendar days for both danmu and gift sources from 2025-01-01 through 2026-10-29, with zero missing days. No D7, D14, or D30 target partition was absent in this validation.
- Anonymous full-period comparisons are in [`../artifacts/huya-xingxiu-overall-retention-comparison.csv`](../artifacts/huya-xingxiu-overall-retention-comparison.csv) and [`../artifacts/huya-xingxiu-overall-retention-comparison.en.csv`](../artifacts/huya-xingxiu-overall-retention-comparison.en.csv).

## Fix

Replace the original `retention_monthly` CTE with the complete CTE in [`corrected-retention-monthly.sql`](corrected-retention-monthly.sql). The key change counts the base once, on `retention_day = 7`:

```sql
sum(if(retention_day = 7 and is_danmu = 1, 1, 0)) as danmu_base_user_cnt
sum(if(retention_day = 7 and is_gift = 1, 1, 0)) as gift_base_user_cnt
```

Regenerate the target table after applying the change, then run [`verify-huya-retention-output.sql`](verify-huya-retention-output.sql). The checks validate corrected rates, ensure numerators do not exceed their base, and summarize source partition coverage.

## Remaining Risks

- The original script left-joins target dates. A missing target partition marks users as not retained. Confirm D7, D14, and D30 source partitions before rerunning.
- Star Show DAU includes app platforms only and excludes black-market/crawler labels. User-activity retention comes from live danmu and gift events. The populations differ, so retention bases are not components of DAU.
- Empty 2026-10 retention reflects the cohort cutoff and must not be interpreted as zero retention.
- Subcategories can split an anchor-day with multiple tags, and one user can enter several subcategories. The `星秀-整体` row and subcategory rows should not be added together.

Chinese documentation: [`README.md`](README.md).
