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

## Subsequent execution and definition revision, 2026-11-13

- The user authorized direct retrieval. The original unexecuted Spark drafts remain intact. [Executed Presto SQL and acceptance record](validated-denominator-20261113/) document 669-day exact agreement between the main query, direct distinct-UID recomputation, and the local keyword-record counts. This validates the denominator only.
- [Semantic labeling protocol v3](语义打标协议_v3.md) reflects the user's final choices: read identical text once and map to original records; include bare ad mentions and ambiguous targets or possible sarcasm by default; exclude explicit sponsored promotion, other targets, genuine support, or voluntary rewarded viewing. The metric is not a strict negative-sentiment rate.
- The user rejected Python classification rules. Subagents read each text and record reasons; code only partitions, stores metadata, validates, maps and aggregates UIDs. Semantic labeling remains in progress; no final monthly average of daily complaint rates has been delivered.
- Review lesson: Chinese numeric slang such as 4000+ can be a curse rather than a count of supporters. Revenue and no-ad statements must be interpreted under the user's definition. Preserve initial judgments and exact-text adjudications, inspect exclusions, and distinguish regression behavior from semantic review.
