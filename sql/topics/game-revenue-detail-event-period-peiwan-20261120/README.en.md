# Game payment-user drilldown: event period, event users and companion-play identity

This topic preserves the latest Spark SQL for game payment-user drilldowns by day, month, event period, event-user status, game, guild, anchor, companion-play identity and big-R group.

## Definitions

- Period: `2026-07-01` through `2026-11-25`.
- Final grain: day, month, event period, game group, game ID, game name, guild name, anchor ID, anchor nickname, companion-play identity, event-user status and big-R status.
- Payment users: distinct `user_ukey` within each final output row; values must not be summed across drilldown rows.
- Big R: monthly valid game consumption of at least CNY 1,000.
- Event period: calculated independently per `game_id`; remove the lowest 1% of matches by average daily DAU, then use the median average DAU of the remaining matches as the threshold.
- Event user: in the 90 days before the payment date, at least 70% of the user's watch time for the same game comes from event-anchor/date associations.
- Companion-play identity: matched monthly from the first-day snapshot using `is_peiwan_anchor_90d`; unmatched anchors remain `未识别` (unidentified).
- Guild name: uses stable `scid` identity and displays the latest `cname` as of `2026-11-25`.
- Anchor nickname: latest nickname as of `2026-11-25`.
- Game display: quarterly revenue Top 10 games retain their game ID and name; all other games are grouped and labelled `其他游戏` (other games).

## Execution and validation

- Engine: Spark SQL.
- Rerun RID: `1246019534519537152`.
- Output: 646,070 rows; total payment amount CNY 173,546,256.70.
- Honor of Kings revenue for October 2026: CNY 11,641,518.00, with zero difference in independent reconciliation.
- The final-dimensional unique key has no duplicates, covering 148 consecutive days.
- Independent daily source aggregation reconciles to the output with zero amount difference. The amount through `2026-11-18` remains CNY 166,064,676.60; the newly added `2026-11-19` through `2026-11-25` amount is CNY 7,481,580.10.

## Files

- `game-revenue-detail-event-period-user-peiwan-scid-spark.sql`: latest production SQL.
- `validation-record.md`: execution, reconciliation, version differences and limitations.

The user-level result CSV contains detailed user and anchor data and is not uploaded to GitHub.

[中文版](README.md)
