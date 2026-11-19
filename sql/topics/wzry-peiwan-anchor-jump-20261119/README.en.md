# Honor of Kings companion-play anchor transitions

This topic measures whether Honor of Kings anchors (`game_id=2336`) show both companion-play days and non-companion-play days within a calendar month or quarter.

Definitions:

- An anchor-day is a companion-play day when at least one live-title row matches the user-supplied keyword list; otherwise it is a non-companion-play day.
- Monthly transition: both day states occur in the same month.
- Quarterly transition: both day states occur anywhere in the quarter, not necessarily in the same month.
- Denominator: distinct anchors with Honor of Kings live activity in the same period.
- Direction: based on the status on the first and last active day in the period. Jumping anchors whose first and last states match are counted as round trips.
- Quarterly revenue: `zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i`, filtered to `consume_order_type='礼物'`, `game_id=2336`, and positive `user_consume_amount`.

Results:

| Quarter | Active anchors | Jumping anchors | Jump ratio | Total Honor of Kings gift revenue | Jumping-anchor revenue | Revenue ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 2026Q3 | 49,861 | 1,412 | 2.8319% | 43,096,023.70 | 20,950,773.60 | 48.6142% |
| 2026Q4 through November 18 | 37,486 | 833 | 2.2222% | 17,332,236.70 | 6,279,723.60 | 36.2315% |

2026Q4 is incomplete and should not be compared directly with full-quarter Q3 on absolute volume. The broad companion-play keywords may create false positives.

Supplementary quarterly anchor and full-consumption view (Presto): revenue is limited to Honor of Kings `game_id=2336` without a `consume_order_type` filter.

| Quarter | Companion-play anchors | Share of active anchors | Jumping share of companion-play anchors | Total Honor of Kings consumption | Companion-play revenue share | Jumping share of companion-play revenue |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 2026Q3 | 2,788 | 5.5915% | 50.6456% | 45,580,810.30 | 58.1891% | 81.7255% |
| 2026Q4 through November 18 | 1,892 | 5.0472% | 44.0275% | 18,375,359.80 | 52.1443% | 67.2194% |

Files: `monthly-jump-spark.sql`, `quarterly-jump-revenue-spark.sql`, `quarterly-active-denominator-presto.sql`, `quarterly-peiwan-denominator-presto.sql`, matching validation SQL, anonymized result CSVs, and `validation-record.md`.

Chinese version: `README.md`.
