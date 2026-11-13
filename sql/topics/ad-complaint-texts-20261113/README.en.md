# Ad viewing-experience complaints: daily denominator SQL

Date: 2026-11-13. Status: not executed, not data-validated. This topic contains reusable SQL only, without user-level data.

## Definition

Preserves the supplied Spark filters over 2025-01-01 through 2026-10-31: passed=0, non-null lpid, original invalid-luid exclusions, askscontent with scontent fallback, and nonempty text. The denominator includes all valid text-message users each day, without an ad-keyword filter. Grain: source record to date/user to date; expected 669 unique dates. Source partition completeness remains unconfirmed.

The main SQL returns the denominator plus keyword user/message counts for reconciliation. The independent SQL directly counts distinct UIDs without reusing the main user-day aggregation. The accompanying acceptance card records the result contract, risks, and unexecuted checks.

## Classification lesson

The user explicitly classifies the three Chinese examples in README.md as sarcastic complaints about viewing experience. Literal revenue or entertainment interpretations are insufficient. This does not establish that every matching phrase in another context is a complaint.

Classification remains a rule-based first pass: approximately 53.22% of records require review, and semantic accuracy has not been assessed. No final complaint rate is available. After denominator reconciliation, calculate daily distinct complaint users divided by all valid text-message users, then average daily rates within each month. Do not divide pooled monthly counts. Missing partitions are not zero activity, and unknown messages are not confirmed negatives.

Regression examples validate rule behavior, not population semantic accuracy. Raw records, UIDs, workbooks, and local source mappings are intentionally absent.

[中文](README.md)
