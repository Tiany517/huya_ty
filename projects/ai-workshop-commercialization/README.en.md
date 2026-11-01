# AI Workshop Commercialization Analysis

## Project objective

Determine whether AI Workshop created identifiable commercial lift beyond users' existing live-streaming behavior, show where any lift originated, identify the user and room segments with stronger responses, and separate defensible estimates from descriptive evidence.

The core questions were:

1. Did exposure to and payment for an AI gift improve later tipping amount, tipping frequency, activity, and viewing behavior?
2. Did the increase come from AI gifts themselves or from subsequent ordinary-gift spending?
3. How did gift semantics, room ACU, and category affect usage and monetization?
4. Could the result support a business estimate once costs and coverage assumptions were made explicit?

## GitHub path map

| Content | GitHub path |
| --- | --- |
| Chinese project note | [`projects/ai-workshop-commercialization/README.md`](https://github.com/Tiany517/huya_ty/blob/main/projects/ai-workshop-commercialization/README.md) |
| English project note | [`projects/ai-workshop-commercialization/README.en.md`](https://github.com/Tiany517/huya_ty/blob/main/projects/ai-workshop-commercialization/README.en.md) |
| PSM7 final report | [`artifacts/final-report/ai-workshop-psm7-f2-report.xlsx`](https://github.com/Tiany517/huya_ty/blob/main/projects/ai-workshop-commercialization/artifacts/final-report/ai-workshop-psm7-f2-report.xlsx) |
| PSM8 A/B report | [`artifacts/final-report/ai-workshop-psm8-ab-did-report.xlsx`](https://github.com/Tiany517/huya_ty/blob/main/projects/ai-workshop-commercialization/artifacts/final-report/ai-workshop-psm8-ab-did-report.xlsx) |
| Final one-page deck | [`artifacts/final-slides/ai-workshop-commercial-value-20260921.pptx`](https://github.com/Tiany517/huya_ty/blob/main/projects/ai-workshop-commercialization/artifacts/final-slides/ai-workshop-commercial-value-20260921.pptx) |
| Version conversion report | [`artifacts/version-analysis/ai-workshop-version-conversion-report.xlsx`](https://github.com/Tiany517/huya_ty/blob/main/projects/ai-workshop-commercialization/artifacts/version-analysis/ai-workshop-version-conversion-report.xlsx) |
| Version daily detail | [`artifacts/version-analysis/ai-workshop-version-daily-detail.csv`](https://github.com/Tiany517/huya_ty/blob/main/projects/ai-workshop-commercialization/artifacts/version-analysis/ai-workshop-version-daily-detail.csv) |
| Propensity-score charts | [`artifacts/charts/`](https://github.com/Tiany517/huya_ty/tree/main/projects/ai-workshop-commercialization/artifacts/charts) |
| Anonymous category, ACU, and exposure summaries | [`artifacts/anonymous-summary/`](https://github.com/Tiany517/huya_ty/tree/main/projects/ai-workshop-commercialization/artifacts/anonymous-summary) |
| Frozen manual gift-tagging rules | [`methodology/gift-tagging-rules-v6-frozen.md`](https://github.com/Tiany517/huya_ty/blob/main/projects/ai-workshop-commercialization/methodology/gift-tagging-rules-v6-frozen.md) |
| English manual gift-tagging rules | [`methodology/gift-tagging-rules-v6-frozen.en.md`](https://github.com/Tiany517/huya_ty/blob/main/projects/ai-workshop-commercialization/methodology/gift-tagging-rules-v6-frozen.en.md) |
| Core SQL | [`scripts/ai-gift-psm-user-revenue-breakdown.sql`](https://github.com/Tiany517/huya_ty/blob/main/projects/ai-workshop-commercialization/scripts/ai-gift-psm-user-revenue-breakdown.sql) |
| Tagging, version, and PSM scripts | [`scripts/`](https://github.com/Tiany517/huya_ty/tree/main/projects/ai-workshop-commercialization/scripts) |
| Automated validation result | [`artifacts/validation-report.json`](https://github.com/Tiany517/huya_ty/blob/main/projects/ai-workshop-commercialization/artifacts/validation-report.json) |

Anonymous summary files:

- `ai-gift-primary-category-summary.csv`: order count, paying users, amount, item count, and shares by primary category.
- `ai-gift-secondary-category-summary.csv`: the same measures by secondary category.
- `ai-vs-regular-gift-category-flow.csv`: AI and ordinary gift amount by category.
- `ai-vs-regular-gift-category-acu-flow.csv`: AI and ordinary gift amount by category and ACU band.
- `ai-workshop-category-exposure.csv`: category exposure, click, payment, and conversion rates.
- Files ending in `.en.csv` have English headers and the same values as their Chinese-header counterparts.

## PSM7 primary analysis

Source: `AI工坊PSM7_真实AI支付_F2_PSM_DID_首次cohort_未剔除异常值.xlsx`.

| Item | Definition |
| --- | --- |
| Analysis period | 2026-07-13 through 2026-08-17; 2026-08-14 and 2026-08-15 excluded |
| Grain | One row per user at first cohort; first cohort in the window retained for each `UKEY` |
| Treatment | AI Workshop exposure and actual AI-gift payment |
| Control | Same cohort date, no AI exposure and no AI payment; `UKEY` never overlaps treatment in the window |
| Matching | Stratified nearest neighbor; main F2 scenario uses `caliper=0.15 × stratified logit standard deviation` |
| Matching outcome | 1,804 pairs; 43.5959% treatment coverage; maximum absolute SMD 0.03956 |
| Balance | Every post-match pre-period feature has absolute SMD below 0.1 |
| Outliers | All users retained; no P99 exclusion |

Seven-day post-period overall tipping amount:

| Measure | Value |
| --- | ---: |
| Treatment pre-period daily mean | CNY 79.8884 per user-day |
| Treatment post-period daily mean | CNY 159.7473 per user-day |
| Control pre-period daily mean | CNY 49.5343 per user-day |
| Control post-period daily mean | CNY 44.3965 per user-day |
| PSM-DID | CNY 84.9967 per user-day |
| DID / treatment pre-period | 106.39% |
| 95% CI | CNY 46.3997 to 123.5937 |
| p-value | 1.652e-05 |

Seven-day paid-retention results need two labels: the raw between-group difference and the DID net difference.

| Measure | Treatment | Control | Raw difference | DID net difference |
| --- | ---: | ---: | ---: | ---: |
| Overall tipping retention | 73.28% | 40.52% | +32.76 pp | +22.12 pp |
| AI-gift tipping retention | 21.34% | 0.22% | +21.12 pp | +20.95 pp |
| Ordinary-gift tipping retention | 71.67% | 40.52% | +31.15 pp | +20.51 pp |

Interpretation: the report supports positive net effects on tipping amount, tipping frequency, and some viewing measures. The `+32.76 pp` figure is not the DID estimate; it is the raw between-group difference before removing the control group's natural change.

## PSM8 A/B analysis

Source: `PSM8_A_B_DID报告_caliper005.xlsx`.

- Treatment: AI exposure and payment; 4,138 candidates.
- Control: AI exposure without payment; 3,520 candidates.
- Matching: first cohort, same date, 1:1 nearest neighbor, no control reuse, `caliper=0.05` on the logit propensity score.
- Result: 3,520 matched pairs and 85.07% treatment coverage.
- Six-day post-period total tipping amount DID: CNY 169.64, p=0.0490.
- Six-day post-period AI-gift amount DID: CNY 38.47, p=0.0119.
- Six-day post-period ordinary-gift amount DID: CNY 131.17, p=0.1170; this component is not separately significant.

PSM8 compares exposed payers with exposed non-payers. PSM7 compares exposed payers with users who were neither exposed nor paid. Their samples and counterfactuals differ, so their DID estimates must not be blended into one result.

## Version conversion rate

Source: `AI工坊_版本周日均转换率_20260713-20260914.xlsx`.

- Population: AI Workshop app traffic on eight allowlisted versions: 13.3.82, 13.4.0, 13.4.2, 13.4.22, 13.4.40, 13.4.41, 13.4.52, and 13.4.63.
- Period: 2026-07-13 through 2026-09-14, 64 calendar days.
- Week definition: consecutive seven-day windows starting on 07-13, producing 10 rows; the last row contains only 09-14.
- Daily average conversion rate: arithmetic mean of `daily paying users / daily exposed users`; days with zero exposure are excluded from the average.
- Period conversion rate: total weekly paying users divided by total weekly exposed users. It is not interchangeable with the daily average rate.
- The eight versions coexisted for sustained periods, so version and time effects are highly collinear. Read the trend, not a causal upgrade effect.

## Manual gift tagging

- The frozen rules cover 5,592 AI-gift detail rows from 2026-07-13 through 2026-09-14.
- Primary and secondary category vocabularies are frozen. Reviewers must read each gift name, user prompt, and streamer context row by row.
- Scripts may queue rows, fetch data, cross-check repeated terms, write labels back, and calculate summaries. Keyword rules must not replace human judgment.
- Uncertain cases must be labeled `存疑` (uncertain). Birthday/celebration themes, room-specific motifs, character coincidences, and cross-room names follow the explicit frozen rules.
- The anonymous summary covers 13 primary categories and 26 secondary categories. Totals are 19,989 gift orders, 13,425 gift senders, CNY 3,838,953.4, and 3,591 distinct gift items.

Gift-level rows, gift IDs, prompts, and per-streamer detail are not committed.

## Business result and evidence boundary

The final one-page deck estimates about CNY 20,000 of incremental daily platform tipping flow. Using an approximate CNY 500 daily push-bandwidth cost, it reports ROI of about 40. The cost excludes VAP synthesis and other machine costs. The same page presents a scenario of about CNY 112,000 daily incremental flow if gifts cover 10% of streamers.

The following limitations must remain visible:

1. The PSM7 report's seven-day overall tipping DID point estimate is CNY 84.9967 per user-day. The business slide uses CNY 81 per paying-user-day. The repository does not yet reconcile these two values. Confirm whether 81 is from another sample, a rounded estimate, or a different model before reusing the commercial calculation.
2. The current one-page V7 deck reports ROI around 40. Older `专题交付.pptx` and `9月直播打赏V10.pptx` files show ROI 17.9 or 18. Only the newer V7 page is migrated as the final artifact; the older ROI variants remain unresolved.
3. The daily incremental-flow estimate is a business extrapolation of cumulative distinct paying-user days multiplied by incremental daily amount. It is not realized cash revenue or net platform income.
4. Cost includes only approximately CNY 500 per day of push bandwidth. VAP synthesis, labor, retries, and other costs are omitted, so ROI is a partial view.
5. Where complete exposure, click, and source fields are unavailable, the analysis can describe observed orders, feedback, and gift structure but cannot claim recommendation lift or causal product effects.
6. PSM balances observed pre-period features only. DID does not remove unobserved confounding, concurrent campaigns, room-level trends, or other operating changes.

## Included and excluded material

Included:

- Two aggregate PSM reports, the version report, the final one-page deck, and PSM matching-quality charts.
- Anonymous primary/secondary category, category flow, ACU flow, and exposure summaries.
- Core SQL, tagging, version conversion, PSM8, anonymization, and validation scripts.
- The frozen manual gift-tagging rules.

Excluded:

- Approximately 27.6 GB of `.pkl` caches and an approximately 11.76 GB PSM source CSV.
- User-level `By天By用户`, `matches_*`, exposure-user, and paying-user detail files.
- Source workbooks containing streamer UIDs, nicknames, per-streamer flow, or gift prompts.
- Gift-level `item_id` detail, original prompts, and manual-label queues.
- `~$` lock files, intermediate logs, and `__pycache__`.

The exclusions do not prevent a new computer from reading the method, core results, and anonymous summaries. They do mean that PSM7 cannot be rerun user by user without the original machine's cache. The scripts in `scripts/` still preserve the field and algorithm logic.

## Validation

Run:

```powershell
python scripts/validate_ai_project.py
```

The check verifies required files, PSM7 sample and DID values, PSM8 sample values, the version date range and version count, the final slide count and required result wording, and approved headers and row counts for anonymous summaries. It reads only the repository's anonymous artifacts, not raw user data.

Chinese version: `README.md`.
