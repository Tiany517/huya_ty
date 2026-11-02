# Honor of Kings Decline and Streamer-Departure Impact Review

This project reviews the business impact around the decline of the Honor of Kings category in 2026 and the departure of streamer 吕德华. It covers platform users, category DAU, commercialization, guild spillover, and effects on related anchors above 1,000 ACU. The migration preserves context, methods, reproducible SQL, and the boundary around historical estimates without uploading named user-level data, named-streamer detail, the original deck, or the complete profit model.

## Business Context

In April-May 2026, the Honor of Kings category declined sharply, while the earlier departure of 张大仙 and the concurrent departure of 吕德华 raised broader management concerns. The review needed to answer:

1. How did the attributed and viewing users of 吕德华 change in April-May relative to six- and twelve-month baselines?
2. Could those user losses explain roughly 22% of the Honor of Kings decline, and how large was the platform-wide effect?
3. Did users move to other Honor of Kings anchors, other categories, or leave the platform?
4. Did the guild and anchors above 1,000 ACU experience spillover?
5. Did event dates distort the result, and was the finding stable after excluding them?
6. How was commercialization profit affected, and which parts are project estimates rather than independently reproducible facts?

## GitHub Path Map

| Repository path | Contents |
| --- | --- |
| `projects/honor-of-kings-streamer-departure-impact/README.md` | Chinese context, definitions, methods, estimates, and limitations |
| `projects/honor-of-kings-streamer-departure-impact/README.en.md` | Standalone English version |
| `projects/honor-of-kings-streamer-departure-impact/sql/README.md` / `.en.md` | SQL purpose, parameter rules, and validation requirements |
| `projects/honor-of-kings-streamer-departure-impact/sql/attributed-dau-rolling-baseline.sql` | De-identified daily attributed DAU and six/twelve-month rolling baselines |
| `projects/honor-of-kings-streamer-departure-impact/sql/related-anchor-overlap.sql` | De-identified overlap between a related anchor's attributed users and the target anchor's viewers |
| `projects/README.md` / `README.en.md` | Bilingual index of all projects |

The original `月报交付V6_0610.pptx`, nine XLSX files, three CSVs, and two SQL files with real streamer IDs were not uploaded. The GitHub SQL replaces real LUIDs with parameters.

## Data and Grain

- The daily attribution table assigns each user on each day to the object with their longest watch time.
- Daily attributed users use `count(distinct ukey)`. A monthly value is the mean of daily attributed DAU, not a monthly unique-user count.
- Overlap analysis uses daily sets for a related anchor's attributed users and the target anchor's live viewers.
- The workbooks cover April-May overlap, watch days, monthly attributed DAU, total anchor DAU, event versus non-event splits, retained users' May content, guild trends, and anchors above 1,000 ACU.
- Because the historical workbooks contain user- or streamer-level results, Git retains methods and de-identified SQL rather than the detail.

## Analysis Methods

### 1. Daily and Monthly Attributed DAU

For each user-day, compare watch time and assign the user to the object watched longest. Deduplicate by object and date. Monthly aggregation averages daily attributed DAU and retains six- and twelve-month rolling means as baselines.

This measures the scale of users attributed to an anchor. It is not channel UV, subscriptions, or all viewers, because a user may be attributed elsewhere on any day when another object receives more watch time.

### 2. April-to-May Overlap and Flow

Build monthly user sets for each object and calculate:

- Monthly attributed users of the target object.
- Users present in both months, April-only users, and May-only users.
- Overlap and retention with an explicit denominator: April users, May users, or the relevant union.
- Other anchors, categories, and watch-time changes among retained users, used to distinguish substitution from churn.

### 3. Event/Non-Event Sensitivity

Summarize versions with and without event dates to test whether a few campaign days drove the decline. Event labels and dates must come from a traceable mapping, not subjective date removal.

### 4. Guild and Head-Streamer Spillover

Compare guild traffic before and after the event and inspect daily/monthly attributed DAU for other guild members and anchors above 1,000 ACU. Without an independent control and event design, the safe wording is “contemporaneous association,” “user-structure change,” or “possible spillover,” not isolated causation.

### 5. Content Consumption by Retained Users

Use an April or May attributed-user cohort and observe later retention, remaining Honor of Kings viewing, anchor substitution, and category migration. Keep separate:

- Whether the user remains active.
- Whether the user remains in Honor of Kings.
- Whether the user moves to another anchor.
- Whether the user moves to another category or leaves the platform.

### 6. Platform, Category, and Commercial-Impact Estimates

The final deck linked anchor-attributed user changes to platform scale, Honor of Kings category DAU, and commercialization profit. This is useful for a management scenario but is not a strict causal ATT. The profit formula, parameters, and complete lineage were not retained.

## Historical Project Estimates

The following values came from the final `月报交付V6_0610.pptx` and must remain labeled as historical project estimates, not results revalidated during this migration:

- Platform users fell by about 400,000, approximately 15% of Honor of Kings MAU.
- Estimated Honor of Kings category DAU impact was about 130,000, approximately 22%.
- Estimated monthly commercialization-profit impact was about 410,000.
- Honor of Kings viewing DAU and acquisition DAU associated with 张大仙 fell by about 115,000 and 17,000, respectively. This is context, not causal proof about 吕德华.
- The deck includes a separate AG-team departure scenario and must not merge it with the 吕德华 scenario.

The platform, category, and viewing-user estimates require a live recomputation under the original definitions before being called validated. The 410,000 profit estimate is reported but not fully reproducible without the retained model.

## SQL Usage

- `attributed-dau-rolling-baseline.sql` reproduces daily attributed users and six/twelve-month rolling means; replace `{{TARGET_STREAMER_LUID}}` with an approved object ID.
- `related-anchor-overlap.sql` reproduces overlap between a related anchor's attributed users and the target anchor's viewers; replace `{{RELATED_STREAMER_LUID}}` and `{{TARGET_STREAMER_LUID}}`.
- Both files preserve the original user-key grain and live-session filters. Before formal execution, check partition availability, product enums, user-key type, and output date coverage.
- The join grain is `dt + ukey`. A user can appear in both April and May, so `count(distinct ukey)` across both months is not a two-month common-user count.

## Known Limitations

- The deck has only three slides, and the complete chain from streamer-user loss to platform users, category DAU, and profit was not retained.
- Nine XLSX files contain user-, streamer-, and guild-level expansions and were excluded. Git explains the methods but cannot independently reproduce every historical number.
- April-May 2026 also contained version, campaign, event, content, and supply changes. Without a counterfactual, the evidence is associational rather than isolated causal proof.
- Longest-watch attribution is affected by concurrent viewing, background sessions, replay channels, and abnormal durations. Preserve the original filters and perform edge-case checks.
- Guild and head-streamer spillover require verified guild mappings and overlap deduplication to avoid double-counting the same users.

## Excluded Material

- The original presentation deck and nine XLSX workbooks.
- User-level viewing, retention, overlap, content preference, and platform-flow detail.
- Named streamers, guilds, real LUIDs, streamer-level DAU, rankings, and traceable charts or exports.
- The two original SQL files with real streamer IDs; only parameterized copies are in Git.

Chinese version: `README.md`.
