# Daily VIP popup users by configuration

Target: zhgametemp.zty_vip_popup_type_user_d_i_v1; ORC, static dt partitions.
Columns: popup_type, material_id, uid, exposure_cnt. Key: dt + material_id + uid.
Scope: show/activity_layer, twelve material IDs, all ety values, valid login UIDs, same-day source dt and half-open stime window. Counts are raw exposure reports. Users may overlap across configurations; overall UV must be deduplicated. Late records in other source partitions are excluded.

Historical inserts for November 1–12 completed on November 13, 2026. November 1 succeeded with no rows; November 2–12 are nonempty. Scheduler publication was not performed.
November 9 source-based Spark writes failed twice without error details. A Presto aggregate snapshot was written using seven sequential Spark batches: first overwrite, then append, only to the November 9 partition.
Final November 9: 24,886 rows, 24,881 UIDs, 25,685 reports. Every configuration/UID key, type label and count matches the extracted source snapshot exactly. No duplicate keys or invalid rows. Other daily summaries are unchanged.
Target integrity checks cover all written dates; November 7 also matches an independent source total. Complete source-to-target reconciliation for every other date remains outstanding; do not call the entire range fully validated.

See backfill-run-20261113.md and validation-record.md. daily-spark.sql is the daily scheduling template; backfill-spark.sql is the rejected oversized scan and should not be resubmitted. Private UID snapshots and literal recovery inserts remain local and are excluded from Git.
