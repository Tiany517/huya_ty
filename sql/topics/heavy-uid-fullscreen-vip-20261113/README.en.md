# Heavy July UID fullscreen behavior and paid VIP conversion

Status: descriptive output available; NOT fully validated. Independent recomputation has small count differences whose cause is not yet established. No causal interpretation.

July 2026 positive watch sessions are combined by UID across devices. Watch days and minutes per viewing day each receive tercile scores 1–3; score sum >=5 is heavy. Event products are the five mobile APP products. Entry/click events are not restricted by ety.
Index dates are Aug 31–Oct 13, with complete 30 elapsed days through Nov 12. A indexes on first fullscreen click after entry; B indexes on first entry and has no click for 30 days, excluding A UIDs. Later clicks after day30 may remain in B. VIP is first successful positive-amount order creation timestamp, excluding earlier paid users; trial entitlements are unknown.

|Group|Fixed UIDs|7d paid|14d paid|30d paid|
|---|---:|---:|---:|---:|
|A|3832390|160|388|1437|
|B|455439|20|42|203|

Rates A/B: 7d 0.0042%/0.0044%; 14d 0.0101%/0.0092%; 30d 0.0375%/0.0446%. Main SQL is the single source for displayed outputs.
Independent sample sizes: A3838368, B456311; A30d1439, other paid counts equal. Separate approximate percentile calculations are a possible cause, not proven. Freeze one UID label snapshot before further reconciliation.

Main Presto RID1241332043389523456 and independent RID1241332644803316736 succeeded. Optimized query failed at the 8GB per-node memory limit; Spark fallback rejected for data volume. The validation card records coverage, exclusions, remaining checks, and performance. All SQL is read-only; no credentials, user records or local source mappings are archived.
