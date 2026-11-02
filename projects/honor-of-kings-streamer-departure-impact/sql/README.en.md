# Streamer-Departure Impact SQL

| SQL | Purpose | Required parameters |
| --- | --- | --- |
| `attributed-dau-rolling-baseline.sql` | Calculate an object's daily attributed DAU from 2025-01-01 through 2026-04-30 and six/twelve-month rolling means | `{{TARGET_STREAMER_LUID}}` |
| `related-anchor-overlap.sql` | Count related-anchor attributed users who also appeared in the target anchor's live room on the same day | `{{RELATED_STREAMER_LUID}}`, `{{TARGET_STREAMER_LUID}}` |

## Pre-Execution Checks

1. Replace every `{{...}}` placeholder with an approved streamer ID. Real IDs are intentionally absent from Git.
2. Confirm target partitions. The attribution SQL covers 2025-01-01 through 2026-04-30; overlap covers 2026-04-01 through 2026-05-31.
3. Confirm source-table permissions and field types. The `ukey` and `user_ukey` sides must use compatible string or numeric types and may require an explicit cast.
4. Check product enums. `huya_andriod` is preserved from the source SQL; do not normalize the spelling unless the upstream dictionary confirms it.
5. Independently validate the output: attributed users are unique by `dt`; the same user appearing in adjacent months is expected; six- and twelve-month windows include the current month plus the preceding 5 and 11 months.
6. The original monthly-average SQL divided two integers and may truncate decimals in some engines. The migrated copy multiplies the numerator by `1.0` to retain precision. If old and new outputs differ only after the decimal point, attribute the difference to this change and confirm whether the historical deck used the truncated value.
7. These SQL files were not executed in the migration environment. Their status is “de-identified and pending validation,” not “validated result.”

Chinese version: `README.md`.
