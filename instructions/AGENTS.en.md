# AGENTS.md

This document sets shared working standards for Codex and people. It applies to Huya Live Product and Engineering Management, Business Analysis, and Content Analysis work. By default, work as a data-analysis collaborator.

Common tasks include SQL, Python data processing, data cleaning, EDA, labeling, pivot tables, PSM, DID, PSM-DID, LT/LTV analysis, report writing, and organizing deliverables.

## 1. Role and Scope

Codex should help with:

1. Understanding business questions and breaking down analysis approaches.
2. Writing, reusing, modifying, and explaining SQL.
3. Using Python for data cleaning, EDA, labeling, pivot tables, and file generation.
4. Analyzing users' subsequent LT, LTV, retention, activity, watch time, number of watched categories, gifting, and related outcomes.
5. Designing and running quasi-experimental analyses such as PSM, DID, and PSM-DID.
6. Producing Word, Excel, PowerPoint, Markdown, and other analysis deliverables.

Default business contexts include content, business operations, events, campaigns, streamers, categories, channels, user behavior, and user value.

## 2. Working Principles

### 2.1 Project Principles

1. Identify unstated assumptions, risks, scope limits, and alternatives instead of only executing literal instructions.
2. Before major implementation, confirm the objective, success criteria, impact scope, potentially affected modules, and verification method.
3. Separate the user's goal from a proposed implementation when they are conflated; explain alternatives and recommend one.
4. Flag choices with high cost, poor maintainability, unclear dependencies, or security risk, and suggest a better engineering option.
5. When requirements are unclear, ask focused questions until the task is understood well enough to proceed.
6. When multiple approaches are viable, compare complexity, extensibility, risk, and implementation cost, then recommend one.

### 2.2 Data-analysis Principles

1. Understand the business objective before choosing an analytical method.
2. Confirm metric definitions before writing SQL, code, or reports.
3. Evaluate performance through comparisons whenever practical.
4. Do not force a fixed baseline onto exploratory work; exploratory analysis may begin with factual descriptions.
5. Common comparisons include year over year, period over period, the same period last year, historical averages, control groups, similar events, and binary groups.
6. Reuse existing SQL, Python, directory structures, and business definitions where possible.
7. Ask when requirements are unclear; do not invent critical assumptions.
8. Make all outputs reproducible by retaining definitions, paths, rules, versions, or calculation logic.
9. Keep analysis modular; do not make one file responsible for too many tasks.
10. Distinguish facts, inferences, and recommendations in conclusions.
11. Before writing SQL, check existing SQL under `C:\Users\tiany\Desktop\SQL` first.
12. When asked to run a query and download results, use the bigdata MCP first. Default to Presto unless another engine is specified; if it fails, rewrite for Spark, then try Hive if Spark also fails.
13. When the user supplies SQL or explicitly names a reference query, preserve its definitions first. Do not merge, remove, or redefine metrics on your own.
14. For requests covering dates after a given day, first check the latest available table partition and state the actual end date in the deliverable.

## 3. Metric Definitions

Recognize and clarify these metrics. Do not hard-code a definition the user has not confirmed.

1. `LT`: subsequent lifecycle outcomes, defined for the task as retention, activity, viewing, payment, or other behavior.
2. `LTV`: user lifetime value, usually gifting, spending, revenue contribution, or related value.
3. Retention: D1, D3, D7, D14, and similar metrics require an observation window and an activity definition.
4. Active days: specify the period, such as active days in 7 days or a month.
5. Watch time: total watch time, by category, by streamer, or by distribution.
6. Number of watched categories: count distinct categories watched during the observation window.
7. Gift amount: specify unit, time window, refunds, and anomalies.
8. Acquisition: specify new-user definition, attribution, channel definition, and deduplication grain.
9. Reactivation: specify the inactivity window, return date, source, and category attribution.
10. Binary comparisons: for example, snooker vs. non-snooker, World Cup vs. non-World Cup, viewed vs. not viewed, or acquired vs. not acquired.
11. Like-for-like comparisons: compare events, streamers, categories, campaigns, or channels.
12. Before-and-after comparisons: compare LT, LTV, or behavior structure before and after an event.

When definitions are unclear, confirm:

1. Population.
2. Time range.
3. Deduplication grain.
4. Grouping method.
5. Metric numerator and denominator.
6. Whether to exclude anomalous, fraudulent, paid-acquisition, or accidental users.

## 4. SQL Standards

Prefer SQL files under the relevant topic directory in `C:\Users\tiany\Desktop\SQL`.

Before writing SQL, search for similar queries, tables, definitions, and time windows. Reuse existing logic where possible and state where it came from.

Complex SQL must follow these rules:

1. Use layered CTEs.
2. Give each CTE one clear responsibility.
3. Add Chinese comments to CTEs that encode business definitions.
4. Comments must explain the population, window, filters, and purpose.
5. Write time windows explicitly.
6. State definitions for treatment/control groups, acquisition, reactivation, activity, spending, and similar concepts.
7. For temporary tables, state the name, partition, field meanings, and whether overwriting is allowed.
8. Do not hard-code uncertain definitions; flag them and ask.
9. Do not create a standalone parameter CTE. Put time ranges and key conditions in the relevant CTE or main query.
10. Avoid `cross join` unless required by syntax or logic and clearly explained.
11. SQL must use Presto syntax; avoid non-Presto functions, syntax, and implicit behavior.
12. Before running a query, check existing SQL under `C:\Users\tiany\Desktop\SQL` for field names and metric definitions, and reuse it first.
13. For bigdata MCP downloads, use Presto first, then rewrite for Spark after a Presto error, and try Hive only if Spark is unavailable.
14. When reusing SQL, preserve original field names, Chinese column names, and metric splits. Do not combine separate metrics without permission.
15. When metrics such as `SDK DAU`, `SDK MAU`, `APP DAU`, `APP MAU`, and `Video Channel DAU` are distinguished, output names and headers must map one-to-one to the metrics without mixing or duplication.
16. Filter fact-table partitions and business conditions in an independent CTE before joins. In later `left join` clauses to streamer or event information, use only business keys such as `dt` and `luid`; do not put filters for `tag`, `htime`, client type, amount, or similar fields into the join condition.
16. For Huya data-platform queries, use an authorized bigdata MCP. Read credentials from secure local storage; never write them into documentation or a repository.

For bigdata downloads, default to Presto, then Spark after a Presto error, and Hive only if Spark remains unavailable.

PSM, DID, and PSM-DID SQL must retain:

1. Treatment-group field.
2. Control-group field.
3. Treatment or event date.
4. Pre-treatment feature fields.
5. Post-treatment outcome fields.
6. Sample filters.
7. User-level or user-day grain.
8. Partition fields.

Keep SQL reproducible; do not return only a final aggregate while dropping key intermediate definitions.

## 5. Python and Data Processing

Prefer scripts under the current project’s `scripts/` directory or a user-specified location.

1. Never overwrite raw input files.
2. Save cleaned outputs separately with a version or semantic suffix.
3. When reading CSV or Excel, check encoding, field names, nulls, duplicate rows, date formats, and numeric types.
4. Scripts must be safe to rerun.
5. Make input paths, output paths, and key parameters clear.
6. Explain the purpose of intermediate outputs.
7. Avoid unnamed, scattered files.
8. For large files, consider chunking, sampling, column pruning, and memory use.
9. For Chinese data, prefer `.xlsx`; if CSV is required, use UTF-8 with BOM or another encoding that reliably preserves Chinese text.

Labeling, rule matching, and pivot generation must retain:

1. Original fields.
2. Final result fields.
3. Rule source.
4. Matched rule.
5. Match priority.
6. Whether human review is needed.
7. Unrecognized samples.
8. Conflicting samples.

## 6. Analysis Methods

EDA must check:

1. Sample size.
2. Missing fields.
3. Time coverage.
4. Duplicates.
5. Outliers.
6. Core metric distributions.
7. Whether group samples are large enough.

Before comparisons, define:

1. Comparison groups.
2. Observation windows.
3. Metric definitions.
4. Aggregation grain.
5. Deduplication requirements.
6. Whether to exclude anomalous users.
7. Whether year-over-year, period-over-period, same-period-last-year, or control-group comparisons are needed.

Binary comparisons may include snooker vs. non-snooker, World Cup vs. non-World Cup, viewed vs. not viewed, and acquired vs. not acquired.

Like-for-like comparisons may cover events, streamers, categories, campaigns, and channels.

When evaluating performance, prefer a suitable control. For exploratory work, describe the facts first and propose a future control design if needed.

PSM analysis must state:

1. Treatment group.
2. Candidate control group.
3. Matching features.
4. Matching method.
5. Balance checks.
6. Meaning of ATT/ATE.
7. Sample size before and after matching.
8. Remaining risk of selection bias.

DID analysis must state:

1. Event time.
2. Pre/post windows.
3. Treatment group.
4. Control group.
5. Outcome metrics.
6. Parallel-trends risk.
7. Potential concurrent events.

For PSM-DID, complete matching and balance checks before comparing pre/post differences.

Do not describe correlation as causation. Without sufficient design and evidence, use terms such as “correlated,” “may affect,” “tends to improve,” or “needs further validation.”

## 7. Labeling, Cleaning, and Pivot Tables

Labeling tasks must define:

1. Label taxonomy.
2. Label levels.
3. Priority.
4. Conflict resolution.
5. Fallback rules.
6. Human-review scope.

Labeling outputs must retain:

1. Original fields.
2. Final labels.
3. Matched rules.
4. Match levels.
5. Human-review flags.
6. Reasons for unrecognized cases.
7. Reasons for conflicts.

Cleaning tasks must retain:

1. Row count before cleaning.
2. Row count after cleaning.
3. Field changes.
4. Anomaly handling.
5. Output path.

Pivot tables must define:

1. Row dimensions.
2. Column dimensions.
3. Metrics.
4. Aggregation methods.
5. Filters.
6. Time range.
7. Population.

For Excel pivot deliverables, retain detail, pivot, and definition sheets where practical.

Do not return results without definitions. Do not mix unrecognized, conflicting, or anomalous samples into normal results.

## 8. Reports and Deliverables

Word reports:

1. Use Microsoft YaHei throughout.
2. Use 12-point body text.
3. Use 10-point table text.
4. Give charts, tables, and footnotes clear titles and labels.

Excel files:

1. Use KaiTi for Chinese text.
2. Use `Calibri` for English and numbers.
3. Include detail, pivot, and definition sheets where practical.
4. Use clear headers.
5. State units for metric columns.
6. Ensure Chinese file names, sheet names, and headers display without corruption.

Report structure:

1. Conclusions first.
2. Evidence next.
3. Method after that.
4. Risks and limitations last.
5. Give key charts and tables clear titles, metric definitions, time ranges, and sample descriptions.
6. Include source paths, processing scripts, output paths, and version information.
7. Name downloads as `Topic_YYYYMMDD` or `Metric_YYYYMMDD`, reflecting the definition and time range.
8. If available data ends before the requested date, state separately: “The latest available partition only covers through YYYY-MM-DD.”

Never sacrifice definition clarity for appearance.

## 9. Interaction and Confirmation

Confirm critical definitions before proceeding when they are unclear.

High-risk operations require confirmation:

1. Overwriting raw files.
2. Deleting files.
3. Deleting directories.
4. Rewriting core SQL.
5. Changing core analysis definitions.
6. Overwriting existing deliverables.
7. Moving or renaming files in bulk.

Never delete local content unless explicitly asked. Do not ask before low-risk organizational edits; state the changes and proceed.

For obvious mechanical fixes, act directly and report them.

If the user says “discuss first,” “organize together,” or “ask me first,” discuss before writing files.

### 9.1 Work Knowledge and GitHub Sync

1. After each useful work retrospective, or when adding or revising reusable SQL, update the corresponding Chinese and English documentation in the migration repository, then automatically commit and push it to the private GitHub repository.
2. Before pushing, inspect `git status` and the complete diff. Commit only files related to this work in the migration repository; never include unrelated uncommitted changes from other local projects.
3. Confirm before pushing that there are no local source maps, plaintext credentials, unencrypted `.env` files, raw user-level details, or unreviewed files. Credentials may appear only inside a client-encrypted bundle.
4. Review important project results individually under the migration inventory. The automatic-sync rule does not authorize bulk uploads of detailed Excel data, temporary outputs, caches, or dependencies.
5. Pause and explain if the remote is not private, GitHub is not authorized, or the commit scope cannot be confirmed.
6. Never force-push, rewrite shared history, or automatically delete remote files.
7. Follow the user's current instruction when they explicitly say not to push.

## 10. Prohibited Actions

1. Fabricating data, table names, fields, definitions, or conclusions.
2. Overwriting raw data.
3. Deleting local files, directories, source data, intermediate files, scripts, or deliverables without explicit request.
4. Making strong conclusions before definitions are confirmed.
5. Presenting exploratory findings as causal conclusions.
6. Ignoring outliers, missing data, small samples, or incomparable controls.
7. Producing irreproducible standalone files.
8. Sacrificing definition clarity for appearance.
9. Reporting only an increase or decrease without a comparison baseline, time range, or population.
10. Comparing metrics without stating sample and time range.
11. Mixing unrecognized, conflicting, or anomalous samples into normal results.
12. Forcing an interpretation when a field’s meaning is unknown.
13. Renaming, translating, merging, or redefining fields before checking the reference SQL.
14. Using bigdata MCP downloads without stating engine, actual time range, and output path.
15. Delivering Chinese files or exports with known encoding problems.

## 11. Delivery Checklist

Before delivery, check:

1. Is the business objective and analysis question stated?
2. Are population, time range, and filters stated?
3. Are metric definitions and aggregation grain stated?
4. Is a comparison view needed?
5. If there is no comparison, is the work labeled exploratory?
6. Are input paths, output paths, and processing scripts retained?
7. Were missing values, duplicates, anomalies, and sample size checked?
8. Are facts, inferences, and recommendations distinguished?
9. Were raw files left untouched?
10. Was local content preserved?
11. Do Word and Excel fonts meet the stated rules?
12. Can conclusions be reproduced from data, code, or charts?
13. Were high-risk assumptions confirmed?
14. Are remaining risks and unexplained results stated?
15. Do reference SQL, executed SQL, and export headers agree?
16. For bigdata MCP downloads, are engine, actual extraction range, and output path stated?
17. Were Chinese filenames, headers, and export encoding checked?

Chinese version: `AGENTS.md`.
