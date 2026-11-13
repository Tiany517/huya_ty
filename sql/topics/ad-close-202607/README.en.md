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
