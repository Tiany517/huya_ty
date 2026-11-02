# World Cup Content and Platform-Impact Review

This project reviews the 2026 World Cup content campaign on Huya. It covers platform activity, acquisition and reactivation, retention quality, user profiles, and the migration of sports interests. The objective is not to copy 38 GB of raw data, but to let Codex on the new computer understand why the analysis was done, which definitions were used, which conclusions remain reusable, and where the evidence limits lie.

## Business Context

The campaign had four objectives: acquire and reactivate sports users at low cost, increase existing-user activity during leisure hours, validate Huya's sports-content positioning, and assess the commercial return on content and operating cost. The final business judgment was that World Cup content delivered low-cost user acquisition and reactivation, but view sessions were short and sports content lacked a mature in-platform monetization path, leaving event ROI relatively low.

The analysis addressed five questions:

1. How large were World Cup acquisition and reactivation relative to other H1 licensed events?
2. Did watching World Cup content improve subsequent activity for existing users beyond raw correlation?
3. Did acquired and reactivated users have different retention quality?
4. How did World Cup users differ from regular users and snooker users in demographics, devices, apps, spending power, and interests?
5. Did snooker users reactivated through World Cup expand their search interests from billiards into other sports?

## GitHub Path Map

| Repository path | Contents |
| --- | --- |
| `projects/world-cup-content-review/README.md` | Chinese background, methods, findings, and limitations |
| `projects/world-cup-content-review/README.en.md` | Standalone English version |
| `README.md` / `README.en.md` | Repository-wide path map |

All paths are relative to the repository root. Original decks, workbooks, user-level CSVs, PSM partitions, checkpoints, and search detail were not uploaded.

## Scope

- The core event window includes `2026-06-12` through `2026-07-07`. The acquisition-retention cohort covers `2026-06-12` through `2026-07-01`, with D7/D14 observed at T+6/T+13.
- User behavior data includes World Cup exposure, platform activity, watch duration, number of watched streamers and games, and spending.
- Profile reports compare World Cup users with regular users and snooker users. Their effective samples are 2,150 and 2,148 users, respectively.
- The search-tagging source contains 347,195 rows from 2025-01-01 through 2026-07-12, with date, user key, period label, query, query count, and result count.

## Analysis Methods

### 1. Acquisition, Reactivation, and Cost Efficiency

Daily acquired and reactivated users were compared with other H1 licensed events on scale and cost. Event cost was split into bandwidth, copyright, streamer OB, digital-human technology, and other operational components. Purchased-traffic attribution was excluded from the new-user definition. The final review combined user scale, cost, and ROI rather than reporting traffic alone.

### 2. Propensity-Score Matching for Platform Impact

World Cup viewers formed the treatment group and eligible non-viewers the control pool. The main analysis used each user's first-view cohort and included prior 29/30-day watch duration, active days, number of watched streamers and games, spending, active days, and main game as pre-treatment features. Long-tailed continuous variables were winsorized and log-transformed; categorical variables were encoded before estimating propensity scores.

The balanced version used a `0.05 × SD(logit(PS))` caliper and retained only matched strata with maximum `|SMD| <= 0.1`. It retained 1,253,218 pairs, or 92.75% of initial candidates, with maximum `|SMD| = 0.0997`. Outcomes were D6 retention, active days in the next six days, watch duration, watch days, streamer count, game count, and spending. Inference used user-clustered robust standard errors.

This design reduces observable selection bias but remains observational. Special events, concurrent initiatives, and unobserved preferences can still affect outcomes. The result should be described as an adjusted difference associated with viewing, not automatically as an isolated causal effect of the World Cup.

### 3. Retention and a Common Cohort

Acquired users were grouped by attribution streamer and acquisition date. D7/D14 required activity at T+6/T+13. The activity source excluded black-market user keys. Output retained total new users, retained users, retention rate, and active days. A future rerun must confirm complete target-date partitions; a missing partition must never be treated as non-retention.

### 4. Profiles, TGI, and K-Means

Profile analysis covered demographics, devices, app preference, wealth/spending tags, and game interests. TGI is target-group share divided by comparator-group share, multiplied by 100. Values above 120 indicate over-indexing, values below 80 indicate under-indexing, and 80-120 indicates limited difference.

World Cup users were clustered with K-Means. `K=3` was selected using SSE, elbow change, and silhouette score. The silhouette was about 0.1261 against regular users and 0.1252 against snooker users, both weak cluster structures. The clusters are useful for operational communication but should not be treated as stable, intrinsically distinct user types.

### 5. Search Tagging and Interest Migration

The search workflow first validated fields, then retained the raw and normalized query. It applied sports dictionaries and human-defined strong rules in priority order and recorded the matched rule, tag level, and review flag. Major ambiguity risks included “火箭” (a billiards nickname or the NBA Rockets) and “世锦赛” (a world championship in many sports). Such terms require contextual exclusions and manual review.

The summaries retained both record-count and `cnt`-weighted views, while explicitly disclosing original rows, exact duplicates, invalid rows, and rows used in tagging.

## Key Findings

- World Cup daily acquisition/reactivation ranked near the top of H1 licensed events at low cost, but the final review estimated event ROI at only about 0.25 because traffic value did not translate sufficiently into commercialization.
- Reactivated users had better quality than acquired users; roughly 86% of acquisition came from lottery-style fission and included many one-off users.
- Under the balanced PSM, content viewing was associated with a small but statistically significant improvement in subsequent activity for some existing users.
- Snooker users represented nearly half of World Cup reactivations, indicating some established sports-content affinity.
- Search interests expanded from billiards/snooker toward football, basketball, tennis, and badminton. This finding depends on keyword disambiguation and tagging rules, so unmatched and conflicting terms must be reviewed together with the final labels.

## Known Limitations

- The source project has many versions and no complete retained SQL/field-dictionary lineage. This note preserves the method, but not every historical number can be independently rebuilt from Git.
- Profile silhouette scores are low; clusters are not stable user segments.
- Search tagging contains high-risk ambiguous terms and requires review flags.
- PSM only controls observed characteristics. Post-match balance is not evidence that all selection bias is gone.
- User records, search detail, PSM checkpoints, profile reports, historical decks, and the approximately 38 GB source directory were excluded.

## Excluded Material

- User-level viewing, retention, spending, profile, and search data.
- Twenty-six historical PPTX files, user-level workbooks, PSM partitions, and caches.
- CSVs, `.pkl` files, and checkpoints containing identities or reusable user keys.

Chinese version: `README.md`.
