# VIP popup configuration IDs and users

Draft, not executed. Previous query polling remains stopped; this change only supplies SQL.
The user confirmed excluding configuration IDs 12499, 10041 and 91, while retaining the three separately supplied IDs 14521, 14519 and 14517.
The query follows the user's report that configuration IDs map to source eventid; this has not been independently verified against event samples.
It removes the old custom_event, show/activity_layer and material_id=14569 constraints.
Presto query range: November 1–12, 2026; each source partition must match the same server-time calendar day.
Output key: date + eventid + valid login UID. exposure_cnt counts raw reports; upload duplicates are not removed.
Configuration audience labels come from the supplied screenshots; they are not independently verified user attributes.
Users may overlap across configurations and types. Current configuration validity dates do not establish complete historical schedules because operators reuse configurations.
Before interpreting reports as exposures, verify both the numeric eventid mapping and exposure-action semantics with source samples and the tracking definition.
See id-mapping.md for the ID mapping and id-mapping-validation.md for outstanding validation.
