# First paid platform VIP order after the first ad mention

Executed and independently reconciled with Presto on 2026-11-15. Both source tables are available through 2026-11-14; message partitions cover 2025-01-01 through that date.

The denominator is 584,593 distinct valid senders whose message content contains the Chinese ad keyword. The numerator is 2,623 users whose earliest historical successful positive-value platform VIP order occurs strictly after their first qualifying mention, before the observation cutoff. The descriptive conversion rate is 0.4486882327%. Another 269 bought VIP before mentioning ads and remain in the denominator but not the numerator; 581,701 have no qualifying purchase.

`main-presto.sql` aggregates first ad mentions by UID before joining unique first VIP orders. `independent-presto.sql` counts distinct senders directly and independently checks whether each first VIP order has an earlier qualifying message. Both counts agree exactly. The precheck SQL files inspect the cumulative order snapshot and five source-message dates. See `validation-record.md` for evidence.

Preserves the existing passed/lpid/UID filters and trimmed askscontent with scontent fallback. Ad mentions are not equivalent to complaints; semantic labels are not used. VIP uses the latest cumulative snapshot with status 200 and a positive amount, taking the earliest order across its full history before applying the conversion condition. Renewals must not become first purchases.

Successful-order creation time is a proxy, not an independently available payment-settlement timestamp. Recomputing with order update time also gives 2,623 users, with zero users crossing the ad timestamp between these two fields. Temporal association is descriptive, not causal. Follow-up length varies and no fixed conversion window is imposed.

Whole-period users are a UID union, never the sum of daily UVs. The independent existence query can scan its message CTE repeatedly in Presto and run longer than the main query. Any intentional one-to-many expansion must regroup to UID before counting people. Equal timestamps and purchases before ad mentions do not qualify.

Only SQL, aggregate counts, and validation documentation are committed. No raw messages, UID samples, credentials, or local source mappings are included.

[中文](README.md)
