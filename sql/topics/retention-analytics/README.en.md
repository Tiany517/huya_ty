# Danmu and Gift Retention SQL Index

## Purpose

This topic organizes recent external-platform and Huya internal retention SQL so a new computer can choose the correct version, restore dependencies, and review metric definitions. The complete SQL is preserved unchanged under `sql/source/`; historical drafts are not mixed into a production schedule without review.

## External Platforms: Douyu, Bilibili, and Douyin

Recommended pipeline:

1. [`zty_jingpin_user_activity_di_日跑调度.sql`](../../source/zty_jingpin_user_activity_di_日跑调度.sql) creates `zhgametemp.zty_jingpin_user_activity_1029_v1` at `dt + pcode + r_category + anchor_uid + user_id` daily grain.
2. [`zty_jingpin_用户活动月度流水留存_调度版_1030_v1.sql`](../../source/zty_jingpin_用户活动月度流水留存_调度版_1030_v1.sql) creates `zhgametemp.zty_jingpin_user_activity_monthly_summary_1030_v1` at `mth + pcode + r_category` grain.
3. [`zty_jingpin_user_activity_202609_validation.sql`](../../source/zty_jingpin_user_activity_202609_validation.sql) reconciles uniqueness, anchor-day watch and live time, danmu volume, gift value, and gift count against source tables. Adapt its test table name to the new environment.

Three earlier scripts, [`站外主播用户日活动明细_日跑调度.sql`](../../source/站外主播用户日活动明细_日跑调度.sql), [`按派生表校准`](../../source/站外主播用户日活动明细_按派生表校准_日跑调度.sql), and [`指定口径`](../../source/站外主播用户活动明细_指定口径_日跑调度.sql), are predecessor designs with different target tables and user-activity grains. They must not run alongside the recommended pipeline; verify historical outputs before deciding which version to keep.

## Huya Internal: Star Show

[`zty_huya_xingxiu_subcategory_monthly_retention_dau_v1.sql`](../../source/zty_huya_xingxiu_subcategory_monthly_retention_dau_v1.sql) creates `zhgametemp.zty_huya_xingxiu_subcategory_monthly_retention_dau_v1` at `mth + pcode + game_name + sub_category` grain, with both the `星秀-整体` total and Star Show subcategories. The script fixes the data range at 2025-01-01 through 2026-10-29 and caps retention cohorts at 2026-09-30.

## Retention Definitions

- D7, D14, and D30 mean exact natural dates T+6, T+13, and T+29, not 7-, 14-, or 30-active-day windows.
- Retention requires the same user to repeat the same behavior on the target date in the same platform and category. It does not require the same streamer on either the external-platform or Huya Star Show calculations.
- The external monthly base is a sum of daily cohort user counts, so it is a user-day measure rather than a monthly unique-user count. D7, D14, and D30 use only cohort dates with all three target partitions available.
- An external gift user requires both `gift_cnt > 0` and `gift_value > 0`; ordinary danmu uses ordinary-message events from the source.
- Huya danmu requires `passed='0'`. Huya gifts require `live_platform='虎牙'`, `consume_order_type='礼物'`, `is_free_item=0`, and positive spend.
- Huya Star Show DAU uses app platforms only and excludes black-market and crawler labels. Watch time converts `view_mins_only_live` hours to minutes by multiplying by 60.

## Confirmed Risks

1. **Huya denominator multiplication:** the Star Show script first expands each user into three D7/D14/D30 rows, then sums `is_danmu` and `is_gift` as the common cohort base. This triples the denominator and understates the stored retention rates. The fix is to count the base on one `retention_day` or retain three flags at the user-day grain, as in the external 1030 script.
2. **Missing Huya target partitions become zero retention:** the Star Show target-date lookup is a left join. A missing target partition marks every affected user as not retained. Unlike the external 1030 script, there is no precheck for the T+6/T+13/T+29 partitions. The current fixed dates assume all partitions through 2026-10-29 are complete.
3. **Uncertain Douyin danmu coverage:** a comment in the external daily script says the current danmu source may have no Douyin data. Douyin users can still enter through gifts, but Douyin danmu retention cannot be treated as a real business value without confirmed danmu partitions.
4. **Unknown category:** external missing categories remain in the explicit `未知品类` group. They are not discarded or backfilled from a streamer main category, and require separate review before interpretation.
5. **Daily averages exclude absent rows:** monthly watch and daily active-user metrics average over rows that exist. Dates absent from the source are not automatically filled with zero.

## Review Record: 2026-11-02

- `zty_jingpin月度流水与7日留存_1029_v1.sql` has only one D7 observation window, so it does not repeat the D7/D14/D30 long-table expansion. Each base user-day is restricted to a T+6 date present in `available_days`, and the denominator is summed directly on that result. Static review found no equivalent triple-denominator defect.
- `zty_jingpin_用户活动月度流水留存_调度版_1030_v1.sql` expands three target dates in `retention_target`, but `retention_flags` then aggregates them into wide flags by `(base_dt, pcode, r_category, user_id)` before joining back to base user-days. D7/D14/D30 therefore share one denominator, which is consistent with counting each base user-day once.
- The external source covers all 59 dates from 2026-09-01 through 2026-10-29; the 2026-10-29 partition contains 2,684,588 rows. See [`artifacts/external-retention-202609-base-denominators.csv`](artifacts/external-retention-202609-base-denominators.csv) for the independently rebuilt September base counts.
- The target table `zhgametemp.zty_jingpin_user_activity_monthly_summary_1030_v1` does not exist in Presto on 2026-11-02, so target-table reconciliation remains **not run**. The reusable check is [`verify-external-retention-denominators.sql`](verify-external-retention-denominators.sql).
- A source-only logic check for September 2026 Valorant and Valorant Mobile is **passed**. Across four platform/category groups, D7/D14/D30 wide-state expansion produced 1,779,759 danmu base user-days and 22,892 gift base user-days, exactly matching the independent user-day rebuild with zero mismatched groups; no numerator exceeded its denominator. See [`verify-external-retention-202609-logic.sql`](verify-external-retention-202609-logic.sql) and [`artifacts/external-retention-202609-logic-check.csv`](artifacts/external-retention-202609-logic-check.csv).

Source files, hashes, and version roles are listed in [`source-manifest.csv`](source-manifest.csv). Confirm the denominator impact against existing outputs before applying a fix.

The Star Show denominator defect, replacement CTE, target-table validation queries, and anonymous 2025-01 through 2026-10 overall comparison are documented separately under [`remediation/`](remediation/README.en.md). The target table has not yet been refreshed with the corrected logic. Corrected rates in the comparison are inferred by dividing the stored base by three and do not replace a formal refresh.

Chinese documentation: [`README.md`](README.md).
