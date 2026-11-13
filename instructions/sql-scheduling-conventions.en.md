# Scheduled SQL Conventions

This document defines the structure and checks required when writing, modifying, or delivering scheduled SQL for the Huya data platform. It applies together with `AGENTS.md` and `sql-validation-workflow.md`.

## 1. Reuse Existing Templates First

1. Search `sql/source` for SQL with the same subject, engine, target-table type, and partition pattern.
2. Prefer templates already validated in the scheduling environment, including table naming, DDL, comments, partition handling, and rerun behavior.
3. Reuse is not blind copying. Reconcile the target-table columns, partition columns, and final `SELECT` for every new task.
4. If no suitable template exists, add a clear structure and state in the header whether it was derived from another SQL or created new.

Recommended reference templates:

- `sql/source/AI工坊/AI工坊曝光入口位_按天调度_v2.sql`
- `sql/source/站外主播用户活动明细_指定口径_日跑调度.sql`
- `sql/source/王者荣耀/王者主播潜力_互动过程指标_日跑调度版_Spark.sql`

## 2. Standard Structure

A scheduled SQL file should normally contain, in order:

1. Header comments: purpose, engine, time range, input snapshot, target table, output grain, and partition definition.
2. `CREATE TABLE IF NOT EXISTS`: create only when the target table is absent; never drop existing tables automatically in the script.
3. Complete CTEs: business filters, grain preparation, joins, windows, and final aggregation.
4. `INSERT OVERWRITE TABLE ...`: after all CTEs and before the final `SELECT`; add `PARTITION (...)` only when the target is physically partitioned.
5. Final `SELECT`: return only target-table fields, with no debug fields or presentation-only ordering.
6. No diagnostic query at the end. Keep diagnostics separate or run them temporarily before finalizing the production SQL.

General skeleton for a partitioned target:

~~~sql
-- Purpose, engine, time range, input snapshot, target table, output grain, and rerun behavior

create table if not exists database.target_table (
    metric_1 string comment 'Metric 1',
    metric_2 bigint comment 'Metric 2'
)
partitioned by (
    dt string comment 'Stat date'
)
stored as orc;

with cte_1 as (
    -- Input grain, output grain, filters, and whether row expansion is allowed
    select ...
),
cte_2 as (
    select ...
)

insert overwrite table database.target_table
partition (dt = 'fixed_partition_value')

select
    metric_1,
    metric_2
from cte_2;
~~~

### 2.1 Keep the Query after INSERT Simple

For scheduled SQL, default to `CREATE TABLE ...; WITH ... INSERT OVERWRITE TABLE ... [PARTITION (...)] SELECT explicit_columns FROM final_cte;`. Put filtering, JSON parsing, joins, and aggregation in CTEs; keep only a simple explicit-column projection after INSERT, avoiding nested complex subqueries in the write section. WITH and INSERT form one statement and must not be separated by a semicolon. Do not repeat static partition fields in the final SELECT. This is the preferred platform scheduling convention, not a claim that Spark rejects INSERT queries containing subqueries. A successful source query does not validate the scheduled write. For empty output, inspect the deployed and macro-expanded SQL, business date, source-partition readiness, INSERT execution logs, and target partition; compare structures using the same date, data snapshot, and filters. Without logs or a controlled comparison, do not attribute empty output to CTE/subquery placement or a scheduler limitation.

## 3. Non-Partitioned, Static, and Dynamic Targets

### 3.1 Non-Partitioned Table

Scheduled SQL does not require `dt` or any partition field. When the target has no `PARTITIONED BY`, overwrite the whole table directly:

~~~sql
create table if not exists database.target_table (
    cohort_mth date,
    tag string,
    metric double
)
stored as orc;

with final_cte as (
    select ...
)

insert overwrite table database.target_table

select
    cohort_mth,
    tag,
    metric
from final_cte;
~~~

Rules:

- Never add `PARTITION` to a non-partitioned table.
- The final `SELECT` column count equals the total target-table column count.
- `INSERT OVERWRITE` replaces the entire table. Use it only for a table owned by one job or when the whole batch must be replaced.
- The user-validated `zty_huya_linshi_20260826_left_important_anchor_monitor_qingchun_v1` is a non-partitioned scheduling example.

### 3.2 Static Partition

Use for one-off analyses, monthly summaries, fixed observation windows, or cases where the partition date is already defined by the business scope.

~~~sql
insert overwrite table database.target_table
partition (dt = '2026-10-31')

select
    metric_1,
    metric_2
from final_cte;
~~~

Column-count rule:

- If the target has 18 regular fields and one partition field, a static-partition insert returns only the 18 regular fields.
- Do not return `dt` again in the final `SELECT`.
- If there are multiple static partition fields, specify all values in the `PARTITION` clause.

### 3.3 Dynamic Partition

Use when one query writes multiple partitions or when partition values are produced by the query.

Many Spark/Hive environments default to `hive.exec.dynamic.partition.mode=strict`. A fully dynamic insert must explicitly enable nonstrict mode before writing:

~~~sql
set hive.exec.dynamic.partition.mode=nonstrict;
~~~

~~~sql
insert overwrite table database.target_table
partition (dt)

select
    metric_1,
    metric_2,
    stat_dt as dt
from final_cte;
~~~

Column-count rule:

- If the target has 18 regular fields and one partition field, the dynamic-partition query must return 19 columns.
- The partition field must appear in the final `SELECT`. Spark normally matches partition columns by position, consistent with target-table order.
- Partition values must not be NULL. Validate dynamic-partition coverage and uniqueness before production.
- In strict mode, a fully dynamic insert without any static partition column fails during execution with `Dynamic partition strict mode requires at least one static partition column`. Enable nonstrict mode or switch to a static partition.

### 3.4 Common Mistake

Do not mix the two patterns:

~~~sql
-- Wrong: dynamic partition, but the query returns only 18 regular fields
insert overwrite table database.target_table partition (dt)
select metric_1, metric_2, ... from final_cte;

-- Wrong: static partition, but the query also returns dt, causing too many columns
insert overwrite table database.target_table partition (dt = '2026-10-31')
select metric_1, metric_2, ..., '2026-10-31' as dt from final_cte;
~~~

## 4. Platform Parameters Are Not SQL Variables

System parameters such as `taskDate`, instance date, or task date shown by the scheduler are not necessarily substituted into the SQL text.

Distinguish the following:

1. A task date in the scheduler log does not mean that `PARTITION (dt)` automatically receives a value.
2. Before using a macro, verify that the scheduler actually substitutes it, for example the repository pattern `'${tdate?string('yyyy-MM-dd')}'`.
3. If no substitution occurs, a dynamic-partition query must still return the partition field itself.
4. Never treat `PARTITION (dt)` as an assigned static partition merely because the task has a system date.

Prefer a static partition for a fixed-period analysis. For reusable daily jobs, use the date macro or dynamic-partition convention already validated in the repository.

## 5. Separate the Analysis Window from the Output Partition

Source-data coverage and target partitioning are different concepts. A non-partitioned target has no output partition, but source-data filters are still required.

Example:

- Source window: 2026-10-01 through 2026-10-31.
- Output partition: `dt='2026-10-31'`.
- Event filters in the SQL must still constrain source data to October.
- Do not omit source filters just because the output partition is 10-31, which would scan all history.

If source partitions are incomplete, do not silently produce a seemingly valid monthly summary. Verify that all expected source dates exist first.

## 6. Reconcile Target and Query Columns

Before delivery, verify:

1. Target regular-column list.
2. Whether the target is partitioned; if so, list its partition columns.
3. Whether a non-partitioned insert correctly omits `PARTITION`, or a partitioned insert uses static or dynamic partitioning.
4. Final `SELECT` field list and order.
5. Static partition: selected columns equal regular target columns.
6. Dynamic partition: selected columns equal regular plus partition target columns.
7. Field names, order, and types match the target; DDL comments do not replace type checks.
8. Expressions such as `round`, `cast`, and `coalesce` can change actual types and require review.

Run at least one static check for DDL and final-query field counts, then manually inspect the first field, the last field, and every partition field.

## 7. Rerun and Idempotency

1. Production results normally use `INSERT OVERWRITE`. A non-partitioned rerun replaces the whole table, while a partitioned rerun replaces its target partition; neither should append.
2. Do not use `INSERT INTO` for a production daily or monthly partition unless append semantics are explicitly required and protected by a unique-key design.
3. A rerun must overwrite the same logical partition. Do not let the execution date silently write to an unrelated partition.
4. Do not automatically drop or recreate an existing target table. Structural changes require downstream-impact review and explicit confirmation.
5. If the workflow uses intermediate tables, document their names, partitions, overwrite behavior, and retention.

## 8. Performance and Scan Scope

1. Filter large fact tables by partitions and business conditions in dedicated CTEs before large joins.
2. Avoid running multi-stage windows directly over platform-wide facts when user-level or room-level filtering can reduce the input first.
3. Review whether repeated scans can safely share one derivation, without weakening grain or metric definitions.
4. For wide time ranges, confirm scanned bytes, partition count, and expected runtime.
5. Spark broadcast joins can fail when the supposedly small side is too large; disable automatic broadcast in scheduler configuration when needed.

## 9. Engine Differences

1. Spark SQL: use DDL, CTEs, windows, and partition syntax supported by the platform Spark version.
2. Hive: do not assume Spark functions or CTE placement are supported; follow the Hive template and syntax.
3. Presto: use it mainly for analysis queries; do not apply Spark or Hive table-creation and partition DDL directly to Presto jobs.
4. When rewriting a definition across engines, preserve field names, grain, filters, and NULL rules, then validate again.

## 10. Pre-delivery Checklist

1. Did you search and reuse repository scheduling templates first?
2. Does the header state purpose, engine, time range, snapshot, target table, grain, and partition behavior?
3. Is the order create table, CTEs, `INSERT OVERWRITE`, final `SELECT`?
4. Was the target confirmed as partitioned or non-partitioned?
5. For a non-partitioned table, is `PARTITION` absent and does the query return all target columns?
6. For a static partition, is the partition field absent from the final `SELECT`?
7. For a dynamic partition, is a non-null partition field present in the final `SELECT`?
7. Did you verify whether scheduler parameters are actually substituted into SQL?
8. Does `INSERT OVERWRITE` provide idempotent reruns?
9. Is the analysis window clearly separated from the output partition?
10. Are diagnostic fields, hourly fields, ordering, and temporary validation queries absent from the production script?
11. Was the SQL executed in the target environment? If not, the status may only be pending validation.
12. Were data, grain, metric, and delivery reconciliations completed under `sql-validation-workflow.en.md`?

## 11. Known Failure Case

The VIP entry-danmu reaction scheduling task on 2026-11-09 had:

- 18 regular target columns and one partition column `dt`, for 19 total columns.
- A dynamic `PARTITION (dt)` clause.
- A final query returning only 18 regular columns.
- A second rerun included `dt` in the query, but the platform still defaulted to strict mode, so a fully dynamic insert was rejected: dynamic partitioning requires at least one static partition column unless `hive.exec.dynamic.partition.mode=nonstrict` is explicitly set.

Spark first failed because the target had 19 columns while the insert returned 18, with no constant partition value. The root cause was not placing CTEs before `INSERT OVERWRITE`; dynamic partitioning requires the query to return the partition field. A fully dynamic insert also requires nonstrict mode or a static partition field. The final implementation uses `PARTITION (dt)`, a final `dt='2026-10-31'` column, and `SET hive.exec.dynamic.partition.mode=nonstrict`. Updating a repository file does not update the deployed Lighthouse task; confirm that the actual SQL was republished before rerunning.

## 12. Related Documents

- `AGENTS.md`
- `AGENTS.en.md`
- `sql-validation-workflow.md`
- `templates/sql-validation-record.md`

Chinese version: `sql-scheduling-conventions.md`.
