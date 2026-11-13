# VIP popup daily table diagnosis

Read-only BigData MCP / Presto checks on November 13, 2026; no table or scheduler changes.
Within November 1–13, only November 12 has target rows: 1,107,998 rows and distinct non-null UIDs; 1,294,575 exposures.
Target partition metadata includes all dates from September 28 through November 12, including the disputed historical dates.
The November 3 source partition returns no rows for show/activity_layer with material_id=14569.
The November 12 source query totals 1,294,575 exposures, matching the target exposure sum.
Of those events, 2,240 have atime dates other than November 12; some timestamps are in 2010 or after the query date.
The catalog defines atime as the action time from the user operating system and stime as server time.
This does not establish dt-to-stime equivalence or justify blindly using client dates.
Historical November 4, 5, 7 and 8 source partitions, execution-instance logs, source readiness and historical VIP material mappings remain unchecked.
The evidence establishes a source-filter mismatch for November 3, not a universal explanation for every empty partition.
See README.md for query IDs and diagnostics.sql for reproducible queries. No historical data was overwritten.
