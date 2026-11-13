# July ad-close daily users

Status: pending validation; no warehouse queries have been executed.
Run `daily.sql` with Spark for each business date from July 1 through July 31, 2026.
The scheduler macro follows the existing repository template. Each run overwrites one daily partition.
The new table stores all users from the fixed July viewing segmentation snapshot, with zero-filled flags and counts.
Key: date + user_ukey. Preserve the existing valid login yyuid filter; aggregate by ukey, across platforms.
Close means click/universal_ad with prop.area=close. Counts represent raw event reports, without upload deduplication.
After all source partitions and daily writes are verified, run `monthly.sql`.
Monthly percentage = segment users with any close / all users in that segment; this is not an exposure conversion rate.
Check source readiness, schema, unique keys, join cardinality, daily cohort size, 31-day coverage and independent source reconciliation before reporting results.
See `validation.sql` and `validation-record.md`. SQL delivery does not establish execution success.

## v3: daily watched rooms

`daily-v3.sql` writes a separate v3 table with four data columns plus static date partition.
watch_room_cnt counts distinct luid per ukey among positive-duration viewing records, preserving July segmentation filters.
Multiple sessions for one creator count as one room; NULL luid is excluded. Missing daily viewing counts are zero-filled.
Aggregated viewing joins are one-to-zero-or-one and must preserve the fixed cohort size.
To use v3 with monthly.sql, replace its v2 source table name with v3; the monthly denominator remains unchanged.
Room counts are not ad impressions and do not attribute close events to rooms. Execution remains unverified.
