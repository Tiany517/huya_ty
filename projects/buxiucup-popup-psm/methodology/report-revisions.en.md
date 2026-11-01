# Buxiucup Report Versions and Failure Patterns

## Version History

| Version | Treatment | Reason |
| --- | --- | --- |
| Multiple V4 runs from 2026-06-10 to 2026-06-11 | Not final | Tight iteration, duplicated definitions, and filenames do not establish the final method; only core scripts are retained for lineage |
| Older DOTA2 report dated 2026-06-12 | Not final | It says every SMD is below 0.1 while also reporting maximum \|SMD\| = 0.2028; it also contains overstrong causal wording |
| Check-in report at 2026-06-15 17:23 | Final campaign version | 13,846 pairs, 100% match rate, maximum post-match SMD 0.0403 |
| Same-day DOTA2 exposure report dated 2026-06-16 | Final exposure version | 7,631 pairs, maximum post-match SMD 0.0350; one-day intervention |
| April-interest exposure report dated 2026-06-16 | Final exposure version | 7,175 pairs, maximum post-match SMD 0.0589; one-day intervention |

## Confirmed Defects and Risks

### 1. Balance Was Used as a Substitute for Identification Assumptions

The final reports still contain claims such as “all SMDs are below 0.1, so the difference was entirely caused by the campaign” and “the causal conclusion is reliable.” Post-match balance only reduces observed-covariate differences. It does not remove unobserved confounding or prove parallel trends.

Required treatment: retain the historical files, but describe the result as an estimate under the stated PSM/DID design. Add evidence or an explicit `not verified` status for parallel trends, common shocks, intervention window, and external validity.

### 2. The Older SMD Conclusion Contradicted Itself

The 2026-06-12 report said all SMDs were below 0.1 while reporting a maximum \|SMD\| of 0.2028. A later rebuild replaced it; the older version is not final evidence.

### 3. Median Significance Labels Cannot Be Reused Directly

- In the same-day DOTA2 exposure result, watch-days median DID is zero with p=0.0001 but the label says `not significant`; games-watched median DID is zero with p near zero and is also labeled `not significant`.
- In the April-interest result, watch-anchor, games-watched, and active-days median DIDs are zero with p near zero but are labeled `not significant`.

These labels are not safe conclusions. Generate significance labels programmatically from the test method, p-value, effect direction, and threshold. When a zero DID and a very small p-value coexist, explain whether the test describes a distributional difference or a DID before assigning a label.

### 4. Unit and Narrative Errors

A pay-conversion group difference is in percentage points, but some report text calls the unit `days`. Keep amount, minute, day, count, percentage point, and percent distinct; never apply one numeric template to every metric.

### 5. Short-Window and Event Design

The APP popup treatment occurs only on 2026-05-12 while outcomes span seven days before and after. This design can describe a short-window difference. It cannot by itself establish a long-term retention or revenue effect and may be affected by same-day traffic, matches, and other operations.

## Required Checks for the Next Rewrite

1. Define the three estimands separately: treatment population, control population, treatment date, pre/post windows, output grain, and interpretation target.
2. Preserve sample counts before and after matching, match rate, caliper, algorithm, per-covariate SMD, and the disposition of unmatched records.
3. Produce a pre/post SMD table and compute the maximum. Never write `balance passed` when any maximum SMD is at least 0.1.
4. Before reporting any DID, provide parallel-trends or at least pre-event-trend evidence; otherwise mark it `not verified`.
5. Generate means, medians, p-values, and significance labels from the same result objects rather than hardcoding static text in separate branches.
6. Build minimal cases for p<0.05, p<0.01, p<0.001, zero effects, positive effects, and negative effects, then test the label function.
7. Reconcile report, XLSX, CSV, and script output on sample counts, metric names, DID, p-values, units, and labels.
8. Record historical defects, the final-version decision, and unresolved issues here. A new report must not erase the failure history.

Chinese version: `report-revisions.md`.
