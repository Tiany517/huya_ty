# Buxiucup Popup PSM / DID Review

This project preserves three separate quasi-experimental analyses for the Buxiucup check-in campaign and APP popup exposure. It is intended for method and result review. Historical report wording is not treated as proof of a completed causal claim.

## GitHub Repository Map

| GitHub path | Contents |
| --- | --- |
| `projects/buxiucup-popup-psm/README.md` / `README.en.md` | Chinese / English project notes |
| `projects/buxiucup-popup-psm/methodology/report-revisions.md` / `.en.md` | Report versions, failure patterns, and recomputation cautions |
| `projects/buxiucup-popup-psm/scripts/psm_did_activity_final.py` | Final 2026-06-15 check-in analysis script |
| `projects/buxiucup-popup-psm/scripts/psm_did_exposure_current_dota2.py` | Exposure analysis for users who watched DOTA2 that day |
| `projects/buxiucup-popup-psm/scripts/psm_did_exposure_april_interest.py` | Exposure analysis for users whose longest April watch time was DOTA2 |
| `projects/buxiucup-popup-psm/scripts/*.sql` | Participant/non-participant seven-day windows and the final feature wide table |
| `projects/buxiucup-popup-psm/artifacts/final-reports/` | Three final DOCX reports and XLSX result tables |
| `projects/buxiucup-popup-psm/artifacts/anonymous-summary/` | Study-level DID results and SMD balance CSVs |
| `projects/buxiucup-popup-psm/artifacts/charts/` | Three anonymized propensity-score or matching-quality charts |
| `projects/buxiucup-popup-psm/scripts/validate_buxiucup_project.py` | File, sample-size, SMD, key-DID, sheet-name, and PII-header checks |
| `projects/buxiucup-popup-psm/artifacts/validation-report.json` | Latest automated validation result |

Repository: <https://github.com/Tiany517/huya_ty>. Append the table paths to `tree/main/` or `blob/main/` to open them on GitHub.

## The Three Analysis Questions Are Not Interchangeable

| Analysis | Treatment | Control | Time definition | Matched sample | Max SMD after matching |
| --- | --- | --- | --- | ---: | ---: |
| Check-in campaign | Ever participated in the Buxiucup check-in | Never participated; DOTA2 viewers | Seven days before/after first click | 13,846 pairs, 100% | 0.0403 |
| Same-day DOTA2 exposure | Watched DOTA2 and was exposed on the campaign day | Watched DOTA2 but was not exposed that day | Seven days around 2026-05-12 | 7,631 pairs, 100% | 0.0350 |
| April-interest exposure | Active that day, April top game DOTA2, and exposed | Same population but not exposed that day | Seven days around 2026-05-12 | 7,175 pairs, 100% | 0.0589 |

The exposure studies cover a one-day intervention and cannot be compared directly with the multi-day campaign. Population eligibility, treatment timing, and the estimand differ.

## Key Results

Values below are DID point estimates. Amounts are CNY, watch duration is minutes, and pay-conversion differences are percentage points.

### Check-in Campaign

- Watch duration: `+53.23` minutes, about `+12.0%`, p=`2.39e-05`.
- Watch days: `+0.51` days, about `+10.3%`, p=`1.44e-95`.
- Payment amount: CNY `+7.98`, about `+63.3%`, p=`5.56e-03`.
- Pay conversion: `+1.7622` percentage points, about `+15.53%`, p=`4.01e-75`.
- Active days: `+0.63` days, about `+12.9%`, p=`1.57e-107`.
- Watch anchors: `+0.90`, p=`0.5178`; ARPPU: CNY `+64.28`, p=`0.2273`. Neither mean estimate is significant.

### APP Popup Exposure: Same-Day DOTA2 Viewers

- Watch duration DID: `-19.97` minutes, p=`0.9068`, not significant.
- Watch days `+0.07`, p=`0.0024`; watch anchors `+0.59`, p=`0.0018`; games watched `+0.15`, p=`0.0003`; active days `+0.07`, p=`0.0195`.
- Payment amount `+0.08` CNY, p=`0.2020`; ARPPU `+5.84` CNY, p=`0.3654`; both not significant.
- Pay conversion `-1.009` percentage points, p=`0.0171`, a significant negative mean estimate.

### APP Popup Exposure: April DOTA2 Interest

- Watch duration `+9.39` minutes, p=`0.9894`, not significant.
- Watch days `+0.19`, p=`4.50e-17`; watch anchors `+0.65`, p=`8.20e-09`; games watched `+0.16`, p=`4.95e-07`; active days `+0.18`, p=`0.0026`.
- Payment amount `-0.47` CNY, p=`0.4482`; pay conversion `-0.1672` percentage points, p=`0.6427`; ARPPU `-12.59` CNY, p=`0.4302`; all not significant.

## Required Interpretation Limits

1. PSM improves balance only on observed covariates and does not remove unobserved confounding. DID also requires assumptions such as parallel trends; the archived materials do not provide proof of them.
2. Statements such as “all SMDs are below 0.1, so the later difference was entirely caused by the campaign” and “the causal conclusion is reliable” are too strong. Report the estimate under the stated PSM/DID design, not a verified real-world causal effect.
3. The older 2026-06-12 report simultaneously said all SMDs were below 0.1 and that the maximum absolute SMD was 0.2028. The 2026-06-15 rebuild superseded it and is the retained campaign result.
4. Some median-result significance labels conflict with their p-values, including small p-values labeled “not significant.” Rebuild labels from p-values, effect direction, and one explicit threshold before reuse; do not copy the historical labels.
5. Some report text calls the pay-conversion unit “days.” The correct unit is percentage points.
6. A one-day exposure with seven-day pre/post windows is sensitive to daily noise and contemporaneous events. Treat these as short-window estimates, not long-term effects.

See `methodology/report-revisions.en.md` for the complete version and defect review.

## Validation

From the repository root:

```powershell
python projects/buxiucup-popup-psm/scripts/validate_buxiucup_project.py
```

The validator is read-only. It checks required files, user-level CSV headers, XLSX sheet names and key DID values, the DOCX sample sizes and maximum SMD values, and records the remaining median-label anomalies. A failed hard check returns a nonzero exit code.

## Migration Boundary

The source folder has 195 files and is about 10.89 GB. This repository excludes the approximately 9.71 GB full user-behavior CSV, an approximately 831 MB non-participant CSV, the approximately 320 MB check-in-analysis source CSV, user-level exposure source CSVs, IDs, account-level exposure/click detail, all historical chart iterations, temporary files, and caches. It retains final reports, anonymous aggregates, key matching charts, core SQL, and final analysis scripts.

## New-Computer Reuse

1. Read this note and `methodology/report-revisions.en.md` first; keep the three estimands separate.
2. Follow `instructions/sql-validation-workflow.en.md` to restore the result contract, source grain, partitions, units, and matching design.
3. The scripts contain Windows source paths and CSV names from the old computer. Update them before rerunning and reverify fields and partitions.
4. Run the automated check, then rebuild sample counts, match rate, SMD, parallel-trend evidence, DID, p-values, and labels. Reconcile report, XLSX, and CSV.
5. If independent recomputation is unavailable, label the output as a historical upload or `validation not executed`; never call it verified.

Chinese version: `README.md`.
