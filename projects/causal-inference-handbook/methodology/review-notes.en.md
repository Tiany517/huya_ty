# PSM and SCM teaching-material review

## 1. Nature of the material

The handbook explains methods using simulated data or minimalist examples. It contains no real treatment population, source data, execution environment, or business output. It is therefore not causal evidence for any intervention. Its migration value is the explanation of propensity scores, matching, SMD, ATT, synthetic controls, and placebo logic.

## 2. Version relationships

- Optimized Markdown is the editable master: about 85.9 KB, 2,025 lines, and 74 fenced code blocks (148 fence markers).
- The optimized PDF is 155 pages with about 55,804 extractable characters; it is the print edition.
- The optimized HTML has about 53,374 visible characters; it is the browser rendering.
- The DOCX is an earlier edition with 871 paragraphs and four tables; it must not be assumed to match the optimized text exactly.
- After whitespace normalization, the zero-part hand-calculation text is fully contained in the optimized Markdown.

## 3. PSM production checklist

### 3.1 Treatment and outcome

1. Define the treatment event, timing, treated units, candidate controls, and outcome window.
2. Outcomes must be observed after treatment; covariates must be available before or at treatment.
3. Check treatment leakage, concurrent events, and donor contamination.

### 3.2 Propensity scores and common support

1. Start with logistic regression as an interpretable baseline, then compare random forest or GBDT.
2. Report score distributions, group overlap, and the common-support truncation rule.
3. Draw conclusions only within common support.
4. Never present `SMD < 0.1` alone as proof of causal identification.

### 3.3 Matching

1. Fix the random seed, matching order, and distance definition.
2. State whether replacement is allowed; report unique treated units, unique controls, reuse counts, and unmatched treated units.
3. Record whether the caliper is absolute or relative to the propensity-score standard deviation.
4. For 1:N matching, distinguish N controls per treated unit from N unique controls across the whole design.

### 3.4 Balance and effect

1. Report pre/post SMD, means or proportions, and sample sizes for every prespecified covariate.
2. Do not select favorable balance checks after looking at results; disclose failures.
3. Use paired inference for 1:1 pairs and cluster-robust or bootstrap inference when controls repeat.
4. Report ATT, confidence interval, p-value, pairing rule, and variance method.
5. Add an unmeasured-confounding sensitivity analysis such as Rosenbaum bounds or an E-value.

## 4. SCM production checklist

1. Define the one or few treated units, intervention time, donor pool, and evidence that donors were untreated.
2. Fit weights from pre-treatment outcome paths and key covariates; weights must be nonnegative and sum to one.
3. Report pre-treatment RMSE or SPE, weight sparsity, and fragile donors.
4. Run donor-prevalence, in-time placebo, spatial placebo, and leave-one-out checks.
5. Spatial placebos should re-estimate SCM for each unit and compare post/pre RMSPE ratios, not merely average other donors equally.
6. Do not present a post-period difference as a net causal effect without predictor selection, fit error, and donor-contamination evidence.

## 5. Choosing PSM versus SCM

The number of treated units and panel shape matter, but they are not the only criteria. Also evaluate:

- whether donors are valid and untreated;
- spillovers and interference;
- the length and stability of the pre-treatment period;
- credible covariates and outcome trajectories;
- support from placebo, leave-one-out, and sensitivity checks.

## 6. Validation status

The project has verified SHA-256 values, format readability, and major-section coverage for all five sources. Eleven method risks are recorded in matching Chinese and English inventories. The embedded examples were not executed because they depend on generated data and an unpinned environment; successful execution would not by itself establish correct design. The status is “content verified with production-use caveats.”
