# SQL Delivery and Validation Record

Status: `draft | pending validation | failed | verified`

Mark the result `verified` only when every triggered high-risk gate passes and both independent recomputation and delivery reconciliation are complete. Fix every `failed` item. If a critical item is `not run`, the status cannot be `verified`; state which conclusion the missing evidence affects.

## 1. Task Metadata

| Item | Content |
| --- | --- |
| Business question |  |
| Claim type | Descriptive / correlational / causal |
| SQL path and version |  |
| Target table, export, or report |  |
| Execution engine | Presto / Spark / Hive / Python / other |
| Input snapshot | Tables or files, latest partition, access time, version or hash |
| Actual run scope | Start time, end time, actual data coverage |
| Author and reviewer | Draft and acceptance should use separate steps or paths where possible |

## 2. Result Contract

| Item | Content |
| --- | --- |
| Population |  |
| Time definition | Source range, event window, observation window, closed-interval rule |
| Base grain | What one row represents |
| Final grain | What one row represents |
| Unique keys | Base, intermediate, and final grains |
| Numerator | Event, filters, and unit |
| Denominator | Same population and business filters as the numerator |
| Grouping dimensions | How NULL and unknown groups are handled |
| Join relationships | Cardinality, match rate, and expected row-count change for each join |
| Expected scale | Row count or order of magnitude and number of key groups |
| Falsifiable expectation | At least one numeric or structural expectation that could disprove the implementation |
| Known limitations | Field, permission, coverage, and unobservable factors |

## 3. Data Facts

| Check | Evidence or query | Result | Status |
| --- | --- | --- | --- |
| Fields, types, and units |  |  | pass / fail / not run |
| Latest partitions and missing dates |  |  |  |
| NULLs, zeros, enums, and outliers |  |  |  |
| Base unique key |  |  |  |
| Small sample and business meaning |  |  |  |

## 4. Risk Profile

| Risk scenario | Triggered | Falsifiable expectation | Mandatory checks | Status |
| --- | --- | --- | --- | --- |
| Retention, funnel, multi-window |  |  | Common denominator, target-date mapping, expansion counterexample |  |
| Multi-table joins |  |  | Uniqueness on both sides, match rate, multiplier |  |
| Time windows or event before/after |  |  | Partition coverage, date boundaries, observability |  |
| Amounts, durations, ACU, or ratios |  |  | Unit counterexample, numerator and denominator rebuild |  |
| Deduplication, ordering, or latest record |  |  | Tie keys, row counts before and after |  |
| `union all`, reshape, or expansion |  |  | Expected multiplier, unique key |  |
| PSM, DID, or PSM-DID |  |  | Sample, matching, balance, parallel trends, effect, and units |  |
| Reports, XLSX, CSV, or charts |  |  | Headers, rows, encoding, ID types, values, and labels |  |

For each scenario not triggered, write `not applicable` and give the reason. A query looking simple is not a risk assessment.

## 5. Implementation and Static Review

| Check | Evidence | Status |
| --- | --- | --- |
| Filters are in the fact CTE or correct join side |  |  |
| NULL and zero are not implicitly conflated |  |  |
| Dates, time zone, and window boundary rules are explicit |  |  |
| Window partition, order, frame, and ties are correct |  |  |
| Deduplication timing and grain match the final key |  |  |
| `union all` branches align on column order, type, and count |  |  |
| Ratio denominator, zero denominator, and common cohort are explicit |  |  |
| Hardcoded dates, thresholds, IDs, and tables fit this task |  |  |
| Numerator, denominator, and key intermediate counts can run independently |  |  |

## 6. Eight Validation Gates

| Gate | Query or method | Key number | Status | Impact if not run |
| --- | --- | --- | --- | --- |
| Data availability |  |  |  |  |
| Schema and semantics |  |  |  |  |
| Grain and uniqueness |  |  |  |  |
| Joins and row multiplication |  |  |  |  |
| Metric invariants |  |  |  |  |
| Independent recomputation and reconciliation |  |  |  |  |
| Boundaries and business spot checks |  |  |  |  |
| Delivery and runtime checks |  |  |  |  |

## 7. Independent Recomputation and Delivery Reconciliation

- How the independent path rebuilds from base grain:
- Reconciliation groups:
- Maximum absolute difference and number of differing rows:
- Manual checks for at least 3 to 5 base units:
- Whether the query, stage tables, target table, export, and report agree:

## 8. Recurrence Control

- Failure mode found:
- Validation SQL, automated check, or minimal counterexample added:
- Related SQL reviewed and results:
- Limitations retained after the repair:

## 9. Completion Decision

| Condition | Status | Explanation |
| --- | --- | --- |
| Result contract complete |  |  |
| Every triggered high-risk gate passed |  |  |
| Independent recomputation shows no differences |  |  |
| Delivery artifacts reconciled |  |  |
| Missing checks disclose their impact |  |  |

Final status: `draft | pending validation | failed | verified`

Final conclusion and conclusions not supported by the evidence:
