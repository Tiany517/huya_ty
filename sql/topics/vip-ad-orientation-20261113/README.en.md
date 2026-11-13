# VIP ad entry orientation: one-day feasibility test

Exploratory only. Test day 2026-10-24, paid-order snapshot 2026-11-12. There are 22 successful positive-amount from_id=5 Android orders, 22 unique order IDs and UIDs. All match prior same-day APP events; 13 have a prior fullscreen-button click and 8 within five minutes. Five of the 13 have another later room entry, so historical click is not purchase orientation.

The event ext map contains orientation=horizontal/vertical. Among the latest ad_request/ad_return records in the three minutes before creation: 8 orders horizontal, 9 vertical, 1 tied conflicting orientation, 4 unmatched, total22. These are temporal proxies across multiple ad scenes, not verified CTA attribution or conversion rates. Raw event records can repeat; order counts are deduplicated. The three-minute window is diagnostic, not an approved final attribution rule.

Observed extra order enums: 16 My page, 17 4K quality, 18 live highlights. Metadata comments are incomplete. Whole-period from_id=5 appears with Android201 and web168 orders, no iOS payment terminal observed; payment terminal is not exposure platform. Do not infer screen direction from entry name, equate event source enum with order from_id, or claim all ad-motivated orders are captured.

Next: same July heavy UID cohort, actual comparable ad exposure orientation as denominator, source-limited first successful orders as numerator, validated device/session/room/ad-scene and time linkage. Identify actual ad display and CTA exposure events before causal or funnel interpretation. Find first payment across all successful orders before filtering its from_id. Do not delete users from the denominator based on future purchases through other entries.

Presto RIDs: entry1241408228580576256, day selection1241408472793926656, context1241408780454513664, parameters1241409605823171584, all succeeded. No heavy label filter or nonbuyer/exposure denominator was tested. All SQL read-only; raw UID, device, request IDs and event payloads remain outside repository and report.
