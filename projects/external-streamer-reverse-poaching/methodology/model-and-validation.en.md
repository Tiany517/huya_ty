# Reverse-Poaching Model and Validation Notes

## 1. Historical Question and Outputs

The historical task screened external-platform streamers for further attention and produced rough Huya-side proxies for ACU, acquisition, revenue, and monthly salary. None of the outputs is an observed outcome:

| Field | Historical meaning | Method | Evidence boundary |
| --- | --- | --- | --- |
| `predict_acu` | Predicted Huya ACU | Scale multiple external features against reference streamers, weight them, apply a platform factor, and round | Hard-coded heuristic; no out-of-sample error |
| `predict_laxin` | Predicted Huya acquisition | Separate weights for Douyu/Bilibili; Douyin/Kuaishou reuse the ACU function | Not observed acquisition |
| `predict_yingshou` | Revenue feature | `ACU×8×0.2 + gift_user×50×0.2 + gift_value×0.6` | Period and currency are undefined; a missing gift field sets the row to zero |
| `predict_pay` | Monthly-salary estimate | Monthly viewer hours = `ACU×20×5.5`, then a category-specific cumulative marginal rate | Depends on live-day/hour assumptions; not a market rate |

## 2. Input Grain and Fields

One Douyu/Bilibili input row represents one external-streamer feature snapshot. The observed unique combination was `uid + pcode + r_category`:

```text
r_owner, uid, pcode, r_category, liucun, avg_com, danmu, fans,
dingyue_add, danmu_only, danmu_new, live_mins, gift_user, gift_value
```

The Douyin/Kuaishou schema was:

```text
r_owner, uid, pcode, r_category,
online_0, online_10, online_20, online_30,
onlineu_0, onlineu_10, onlineu_20, onlineu_30,
fans, fans_add, live_hours, live_dt
```

`06allres.csv` has 34,309 rows. The 14 base fields match `featt` and `res.txt` exactly. The final table covers only Bilibili (29,975 rows) and Douyu (4,334 rows); no final Douyin or Kuaishou output was retained.

## 3. Formula Summary

### 3.1 Douyu / Bilibili

Each external signal is first mapped against three references:

```text
candidate_score = (value / ref_low × 15900
                 + value / ref_mid × 3755
                 + value / ref_high × 1800) / 3
```

The score is capped by field and platform. `predict_acu` combines comment, danmu, subscription, danmu-only, and new-danmu scores using fixed weights, applies a platform scale, and rounds to 50.

| Platform/version | Scale | Weights (comments / danmu / subscription / danmu-only / new danmu) |
| --- | ---: | --- |
| Douyu regular | 1.0; 1.2 for DOTA2 | 0.40 / 0.30 / 0.05 / 0.15 / 0.10 |
| Douyu acquisition | 1.4 | 0.45 / 0.15 / 0.05 / 0.20 / 0.15 |
| Bilibili regular | 0.38 | 0.40 / 0.30 / 0.05 / 0.15 / 0.10 |
| Bilibili acquisition | 0.70 | 0.15 / 0.15 / 0.15 / 0.35 / 0.20 |

### 3.2 Douyin / Kuaishou

Douyin combines the 0, 10, 20, and 30 minute online series with weights `0.1 / 0.35 / 0.35 / 0.20`; regular online contributes 30% and deduplicated online contributes 70%. When fans exceed 10, total and incremental fans are added. The model applies `0.83` and rounds to 10.

Kuaishou combines the deduplicated online series with the same time weights, applies `0.8 × 0.85 × 0.85`, and rounds to 50.

### 3.3 Monthly Salary

Each category has an eight-band cumulative marginal hourly rate. Once viewer hours exceed a threshold, only the additional hours use the next rate. The original script assumes 20 live days per month and 5.5 hours per live day. Unknown categories fall back to the all-category rate.

## 4. Known Implementation Defects and Interpretation Limits

1. The final cap for `danmu_new` uses the `danmu_only` score rather than that field's own score, eliminating the new-danmu signal's independent contribution. The source and repository copies preserve this behavior and flag it.
2. Douyin calls the same function for `predict_acu` and `predict_laxin`, so the two outputs are necessarily identical. No historical document proves this was a business choice.
3. The Kuaishou function first computes a regular-online result that is never used, then uses the deduplicated-online series. The repository copy keeps only the logic that affects the returned value.
4. A missing gift field sets the entire `predict_yingshou` row to zero, even when ACU is positive. It cannot be summed as financial revenue.
5. Reference streamers, weights, caps, and scales are undocumented manual parameters. They lack provenance, estimation sample, time version, and error measures.
6. The inputs are not linked person-by-person to later Huya outcomes; prediction bias, recall, and recruiting return cannot be estimated.

## 5. Version Drift and Independent Rebuild

The final table predates the last script modification in at least one component. Rebuilding it from the current archived script gives:

| Check | Result | Status |
| --- | ---: | --- |
| 14 base fields in `featt` vs final CSV | 34,309 / 34,309 match | Pass |
| 14 base fields in `res.txt` vs final CSV | 34,309 / 34,309 match | Pass |
| Douyu `predict_acu` | 4,334 / 4,334 | Pass |
| Bilibili `predict_acu` | 29,975 / 29,975 | Pass |
| Douyu `predict_laxin` | 4,334 / 4,334 | Pass |
| Bilibili `predict_laxin` | 23,262 / 29,975, 77.605% | Warning: version drift |
| Douyu `predict_yingshou` | 4,334 / 4,334 | Pass |
| Bilibili `predict_yingshou` | 29,975 / 29,975 | Pass |
| Douyu `predict_pay` | 4,328 / 4,334 | Six category-mapping drifts |
| Bilibili `predict_pay` | 29,961 / 29,975 | Fourteen category-mapping drifts |

Therefore, the current code cannot be described as exactly equal to the historical result. The historical `06allres.csv` is the only reliable source for an old ranking; the current module is for continuation and revalidation.

## 6. Reuse Steps

1. Restore and verify source DDL, field units, null encoding, partitions, and latest dates.
2. Calculate locally with `fanwa_estimator.py`; do not execute remote table writes.
3. Reconcile by platform, category, and person against the historical output. Attribute every difference to parameter, script, or input-data version.
4. Before using the result for recruiting, add observed follow-up outcomes and out-of-sample evaluation. Report coverage, error, rank correlation, extremes, and small samples.
5. Pair candidate lists with human review and business rules; never decide from `predict_acu` or a salary proxy alone.

Chinese documentation: `model-and-validation.md`.
