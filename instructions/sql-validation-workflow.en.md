# SQL Construction and Validation Workflow

This workflow raises SQL from “it runs” to “its result can be shown to be correct.” It applies to extraction, aggregation, retention, funnels, event analysis, PSM/DID, exports, and reconciliation. These rules operate alongside `AGENTS.en.md`.

## 1. Define the Result Contract First

Before writing SQL, state:

| Item | Required definition |
| --- | --- |
| Business question | The decision the result supports, not merely “build a table” |
| Population | Platform, category, streamer, user, region, eligibility rules |
| Time definition | Source range, event window, observation window, actual available partitions |
| Base grain | What one row represents: user-day, streamer-day, user-month, order, etc. |
| Unique key | For example, `(dt, pcode, category, user_id)` |
| Output grain | What one final row represents, for example `mth + pcode + category` |
| Numerator | Exact event, filters, and unit |
| Denominator | A base measured under the same definition, not merely “total” |
| Grouping dimensions | Business splits and missing-value handling |
| Expected scale | Maximum rows, key group counts, approximate denominator size |
| Known limitations | Missing dictionary, permissions, coverage, unobservable factors |

Do not start implementation while the result contract is incomplete.

Beyond the written contract, pre-register at least one falsifiable expectation, such as “the independently rebuilt denominator will match exactly by month,” “the fact-row count will not change after this join,” or “the export will have 120 rows and the same headers as the query.” If no expectation can be stated, the data or business structure is not understood well enough; inspect fields, partitions, and a sample before writing the full query.

## 2. Understand Data and Join Cardinality

1. Inspect source DDL, field meaning, partition format, units, nullability, enum values, and time coverage.
2. Filter the fact table by partition and business conditions before joining small dimensions.
3. Validate each join key for uniqueness on both sides; never assume a many-to-many relationship is one-to-one.
4. Document every join as `1:1`, `N:1`, `1:N`, or `N:N`, including whether row count should change.
5. Most errors occur when detail rows are multiplied before aggregation, deduplication, or ratio calculation. Settle aggregation versus expansion order first.

## 3. SQL Construction

1. Use CTEs with clear responsibilities: filtering, grain normalization, mapping, expansion, matching, and final aggregation.
2. Each material CTE should state input grain, output grain, and whether row multiplication is allowed.
3. Do not calculate business ratios directly on a multiplied detail grain. Produce numerator and denominator components that can be independently reproduced.
4. Numerator and denominator must share the same business filters and cohort. When different windows share a denominator, state exactly which inputs are common.
5. For long-format expansion, check the expected multiplier. For long-to-wide conversion, check final-key uniqueness.
6. Define denominator-zero behavior explicitly: null, zero, or drop the group. Do not leave it to implicit behavior.
7. Keep independently reproducible numerator, denominator, and intermediate counts where possible instead of hiding business logic in one large expression.

## 3.1 Build a Risk Profile

Do not apply one generic checklist with equal weight to every query. Before implementation, identify where this task is most likely to fail and make the matching checks mandatory:

| Risk scenario | Define before coding | Minimum validation evidence |
| --- | --- | --- |
| Retention, funnel, multi-window | Cohort grain, common denominator, target-date mapping | Equal denominators across windows; independent reconciliation by group; a counterexample where expansion to N rows still contributes one base unit |
| Multi-table joins | Unique keys on both sides, match rate, cardinality, expected multiplier | Row counts before/after, maximum match count, unmatched samples; explain any one-to-many join |
| Filters around fact-to-dimension joins | Whether the filter belongs in the fact CTE or the join predicate | Compare before/after moving the filter; reconcile unmatched rows and row counts |
| Time windows and pre/post events | Closed intervals, calendar or eligible days, actual partitions | Date edges, missing-partition list, exclusion rule for unobservable cohorts |
| Amount, duration, or ACU | Source units, conversion, aggregation method | Min/max/quantiles, a unit counterexample, totals rebuilt from numerator and denominator |
| Deduplication or latest record | Business key, ordering key, tie-break rule | Row counts before/after, tie counts, deterministic ordered result |
| `union all` or expansion | Source grain, output grain, expected multiplier | Rows per branch, unique keys, multiplier before/after expansion |
| PSM, DID, or PSM-DID | Eligibility, treatment time, matching features, pre/post windows | Sample counts before/after matching, balance, parallel trends, reconciliation between definition and result tables |
| Excel or CSV export | Field names, row count, encoding, ID type | Three-way reconciliation across query result and export; read-back check for Chinese text and long IDs |

Retain the risk profile and result contract in the execution record. If a matched scenario lacks evidence, its status is `not run`, never `verified`.

## 3.2 First Static Review After Writing SQL

After writing the query, do not treat successful execution as the conclusion. Review the behavior most likely to be inferred incorrectly or omitted:

1. Filter placement: fact-table partitions and business filters belong in the fact CTE. A right-table filter in `left join ... on` versus `where` must match the intent to preserve unmatched rows.
2. Null versus zero: check whether `count`, `sum`, `avg`, division, and `coalesce` turn “no data” into zero. Preserve an unknown group when a null grouping key represents real source coverage.
3. Time boundaries: check string versus date types, inclusive endpoints, whether D7 means T+6, T+7, or the seventh eligible day, and timezone consistency.
4. Window functions: verify `partition by`, `order by`, frame, tie handling, and `row_number` versus `rank` against the business rule.
5. Deduplication order: decide whether to deduplicate before a join, join before aggregation, or aggregate before a join. Ensure `distinct` uses the final-key grain.
6. Join semantics: compare key types; avoid putting unrelated filters in the join; check that right-table filters after a `left join` do not remove unmatched rows.
7. Sets and expansion: verify column count, order, and type in every `union all`; check the expected multiplier after pivot, unpivot, or expansion.
8. Rate and population logic: numerator and denominator must share a cohort. Check duplicate-row inflation in both numerator and expanded denominator, and handle zero denominators explicitly.
9. Hardcodes and dependencies: validate dates, game IDs, caps, snapshot partitions, table names, and thresholds for the current task. Do not reuse another week's debugging values.
10. Readability and reproducibility: use stable aliases, make material CTEs independently runnable with grain comments, and find implicit casts that can change semantics.

Static review can reveal problems but cannot prove correctness. Every high-risk check still needs an executed result as evidence.

## 4. Eight Validation Gates

Every gate must have a query, result, and status: `pass`, `fail`, or `not run`. A failure must be fixed; “not run” must never be reported as “verified.”

### 4.1 Data Availability

- Latest available partition, requested end date, and missing dates.
- Empty source tables, absent partitions, and tables that exist without the target date.
- Completeness of event and target observation dates. Distinguish missing partitions from no behavior.

### 4.2 Schema and Semantics

- Field names, types, and units such as minute/hour, yuan/fen, and millisecond/second.
- Enum values, empty strings, nulls, decimals, negatives, and duplicate events.
- Stop before interpreting an unknown business field; do not invent a dictionary.

### 4.3 Grain and Uniqueness

- Base rows are unique under the declared key.
- Final rows are unique under the declared output key.
- Row counts before and after aggregation or deduplication match the contract.
- IDs remain strings and do not lose leading zeroes or precision.

### 4.4 Joins and Row Multiplication

- For each join: left row count, right-key uniqueness, match rate, post-join row count, and maximum match count.
- An `N:1` join should not change fact-row count; any change requires explanation.
- `1:N`, `N:N`, and pivot/unpivot operations state expected multipliers and unique keys.
- Risk metrics must rule out double-counted users or events.

### 4.5 Metric Invariants

- Counts are nonnegative and rates are in their valid ranges.
- Numerator is no larger than denominator; parts do not exceed a total without an explicit overlapping definition.
- Common denominators across D7/14/30, acquisition/reactivation, or pre/post windows satisfy stated consistency rules.
- Overall totals reconcile with group totals; means can be reconstructed from numerator and denominator.
- These are necessary checks, not proof that a denominator is correct.

### 4.6 Independent Recomputation and Reconciliation

- Recompute a key numerator, denominator, or total from base grain through an independent path and compare it exactly with the final result by group.
- Minimize reuse of the CTE under test so the same error is not repeated twice.
- Reconcile stage tables, target tables, and exported output on row counts, keys, metrics, and filters.
- After repairing SQL, preserve the old result, corrected SQL, new result, and difference explanation. A repair is complete only after a successful rebuild and reconciliation.

### 4.7 Boundaries, Sensitivity, and Business Spot Checks

- Inspect minimum and maximum dates, small samples, small denominators, nulls, unknown groups, and extremes.
- Test whether conclusions depend on arbitrary business thresholds.
- Manually trace at least three to five base units from source through joins and aggregation. For retention, include at least one retained and one non-retained case.
- Compare the result direction with business expectations. If it looks implausible, investigate definitions and code before rationalizing the output.

### 4.8 Delivery and Runtime

- Confirm actual execution completed without implicit type changes, resource limits, timeouts, partial results, or permission failures.
- Reconcile stage tables, target tables, exports, and reports on row counts, unique keys, metrics, groups, and filters.
- Verify SQL-to-export headers, string preservation for long IDs, Chinese encoding, blank rows or columns, and formatted numeric values.
- Confirm idempotent target writes: no duplicate write, wrong overwrite, missing partition, or stale result.
- Record the engine, time range, runtime or known performance risk, output paths, and the impact of failures. “It finished” alone proves neither correctness nor adequate performance.

## 5. Copyable Execution Record

Before writing SQL, fill in the task note or delivery document:

```text
Business question:
Population and time:
Source tables and latest partitions:
Base grain and unique key:
Intermediate grains:
Output grain and unique key:
Numerator definition:
Denominator definition:
Join relationships and expected row-count changes:
High-risk scenarios and mandatory checks:
Falsifiable expected results:
Known limitations:
```

After execution, fill in at least the following record. For evidence, cite a query ID, SQL file, result file, or key result; a bare “checked” is insufficient.

| Validation gate | Check | Evidence | Status | Key figures or differences |
| --- | --- | --- | --- | --- |
| Data availability | Partitions, date coverage, empty tables |  | pass/fail/not run |  |
| Schema and semantics | Fields, types, units, nulls |  | pass/fail/not run |  |
| Grain and uniqueness | Row counts before/after, unique keys |  | pass/fail/not run |  |
| Joins and multiplication | Cardinality, match rate, multiplier |  | pass/fail/not run |  |
| Metric invariants | Numerator/denominator, ranges, totals |  | pass/fail/not run |  |
| Independent recomputation | Independent reconciliation by group |  | pass/fail/not run |  |
| Boundaries and spot checks | Date edges, small samples, manual cases |  | pass/fail/not run |  |
| Delivery and runtime | Stage/target/export/report, headers, encoding, idempotency, performance |  | pass/fail/not run |  |

Answer six questions before delivery:

1. What does one final row represent, and does it still match the result contract?
2. Did every join, expansion, or deduplication change the row count as expected?
3. Was the denominator rebuilt independently from base grain rather than by reusing the logic under test?
4. Was the output reconciled against the target table, stage tables, and exported file?
5. Which checks were not run, and which conclusions does each affect?
6. Does actual execution and delivery satisfy type, encoding, idempotency, and performance constraints?

## 6. Delivery Format

A formal SQL delivery includes at least:

1. Executable SQL.
2. Independent validation SQL or validation steps.
3. Result contract and known limitations.
4. Engine, time range, output path, and runtime or known performance risk actually used.
5. Status and key numbers for each validation gate.
6. Items that were not executed or could not be verified.
7. Reconciliation results across stage tables, target tables, exports, and reports.

SQL without validation evidence is a draft and may not be labeled “verified.”

## 7. Failure Pattern Review

When an error occurs, fix more than the immediate SQL. Record:

1. Symptom and business impact.
2. Root cause: requirement, definition, grain, join, expansion, window, type, permission, or implementation.
3. Which validation gate should have caught it and why it did not fire.
4. New rule, validation query, or test case added.
5. Other SQL that may reuse the same failure pattern, including the reviewed scope.

Turn the repair into an executable check or minimal example, such as “every window has the same denominator by month after long-format expansion” or “fact-row count cannot change after joining a user dimension.” Adding “check carefully” to the instructions again is not a control; executable evidence is.

When the same class of error recurs, investigate the upstream design: missing field dictionary, aggregation at the wrong grain, treating a join as one-to-one, reusing the same incorrect CTE as a so-called independent check, skipping independent recomputation, or failing to read back the export. Do not respond only by appending a longer prompt.

Chinese documentation: `sql-validation-workflow.md`.
