# Causal-inference handbook migration review

This project migrates a beginner-oriented teaching handbook for propensity-score matching (PSM) and synthetic control methods (SCM). It is suitable for study, code scaffolding, and design reminders. It is not an empirical report about a real intervention and contains no business source data or executed result set.

The source folder contains five files: optimized Markdown, HTML, and PDF versions, an earlier DOCX version, and a separate hand-calculation deep dive. After normalization, the complete deep-dive text is contained in the optimized Markdown. DOCX, HTML, Markdown, and PDF are editions or renderings of one body of material, not four independent research results.

## GitHub path map

| Repository path | Contents |
| --- | --- |
| `projects/causal-inference-handbook/README.md` / `.en.md` | Bilingual context, method risks, and usage boundaries |
| `projects/causal-inference-handbook/methodology/review-notes.md` / `.en.md` | PSM/SCM method review and production checklist |
| `projects/causal-inference-handbook/sources/causal-inference-handbook-optimized.md` | Canonical editable edition with 74 fenced code blocks |
| `projects/causal-inference-handbook/sources/causal-inference-handbook-optimized.html` | Browser rendering of the optimized edition |
| `projects/causal-inference-handbook/sources/causal-inference-handbook-optimized.pdf` | 155-page print edition |
| `projects/causal-inference-handbook/sources/causal-inference-handbook-base.docx` | Earlier DOCX edition with 871 paragraphs and 4 tables |
| `projects/causal-inference-handbook/sources/zero-hand-calculation.md` | Hand calculation for six example users; text is included in the optimized Markdown |
| `projects/causal-inference-handbook/artifacts/source-manifest.csv` | Size, SHA-256, role, and version relationship for five sources |
| `projects/causal-inference-handbook/artifacts/method-review.zh.csv` / `.en.csv` | Eleven method risks, evidence, and production requirements |
| `projects/causal-inference-handbook/scripts/validate_handbook.py` | Verifies hashes, format readability, content coverage, code fences, and bilingual review inventories |
| `projects/causal-inference-handbook/validation/validation-report.md` / `.en.md` | Itemized bilingual validation reports |
| `projects/causal-inference-handbook/validation/validation-report.json` | Machine-readable validation result |

All paths are relative to the GitHub repository root.

## Structure

1. Part zero uses six users and two features to hand-calculate logistic regression, propensity scores, 1:1 matching, SMD, and ATT.
2. PSM covers logistic regression, random forest, and LightGBM/GBDT propensity scores; matching; balance; ATT; and tuning.
3. SCM uses ten cities and 72 simulated months, constrained optimization, a synthetic comparison, and a placebo example.
4. Method selection compares the applicability of PSM and SCM.
5. The appendix covers environment setup and common errors.

## Corrections and additions required for reuse

- SMD below 0.1 is a heuristic indicating balance in measured covariates; it does not prove exchangeability. Also inspect common support, overlap, match rate, and unmeasured confounding.
- The ATT example uses an independent-sample t-test, while 1:1 matching creates pairs and 1:N matching may reuse controls. Production analysis needs inference consistent with the matching design, such as paired, cluster-robust, or bootstrap inference.
- The 1:N and caliper examples do not fully demonstrate a control-reuse ledger. Report unique treated and control counts, replacement policy, and unmatched treated units.
- The SCM placebo example uses an equal-weight mean of other cities as a simplified benchmark, not a full synthetic-control re-estimation for every unit. Production analysis should use pre-treatment fit, donor prevalence, in-time placebos, leave-one-out checks, and post/pre RMSPE ratios.
- The statement that panel data implies SCM is too broad. Design depends on the treated-unit structure, interference, donor validity, and pre-treatment fit, not data shape alone.
- The document has no notebook, dependency lock, or execution log. A production use should preserve parameters, random seeds, input snapshots, runtime environment, and final reconciliation.

See `artifacts/method-review.en.csv` for all eleven items. The project status is “educational material fully migrated and content-checked,” not “example code verified against real business data.”

## Reuse on a new computer

1. Read the optimized Markdown to understand the method; use the PDF or HTML for print or sharing.
2. To follow the manual calculations, open `zero-hand-calculation.md`, whose text is included in the optimized master document.
3. Before a production analysis, read `methodology/review-notes.en.md` and convert the eleven risks into project parameters and a validation card.
4. Run `python projects/causal-inference-handbook/scripts/validate_handbook.py --write-report` to check source hashes and document structure.
5. Do not treat the simulated “CNY 150 true effect” as a business fact. A real project requires its own source data, matching design, and delivery reconciliation.

Chinese version: `README.md`.
