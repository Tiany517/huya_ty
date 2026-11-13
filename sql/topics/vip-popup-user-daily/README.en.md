# Daily VIP popup users by configuration

Table zhgametemp.zty_vip_popup_type_user_d_i_v1 was created successfully via BigData MCP / Spark on November 13, 2026 (rid 1241323692366679040).
A separate get_table_ddl read confirmed four data columns, the dt partition and ORC storage.
Key: dt + material_id + uid. Columns: audience type, configuration ID, valid login UID and raw exposure report count.
Users can overlap across types; recompute distinct users for overall totals.
Only table creation was executed. No event data was inserted, historical partitions backfilled or scheduler jobs published.
The daily Spark script is an unexecuted draft using the existing tdate macro and same-day dt/stime scope, all ety values and twelve configuration IDs under show/activity_layer.
Source data validation, independent user-level reconciliation and write validation remain outstanding.
