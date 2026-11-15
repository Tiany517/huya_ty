# VIP popup coverage and exploratory analysis

Window: November 1–12, 2026. The paid-member denominator uses the November 12 VIP order snapshot so both datasets cover the same period.
Paid VIP means a valid UID with a successful positive-amount order (`status='200'`, `amount>0`), deduplicated across orders. A popup user is any valid UID appearing in the target table on any day or configuration in the window.

| VIP population | Paid VIPs | Exposed | Unexposed | Coverage | No coverage |
| --- | ---: | ---: | ---: | ---: | ---: |
| All successful paid VIPs | 13,535 | 5,031 | 8,504 | 37.17% | 62.83% |
| New VIPs from Aug 31 to Nov 12 | 13,519 | 5,024 | 8,495 | 37.16% | 62.84% |

The near-identical results show that almost the entire paid-member snapshot belongs to the campaign period.

The table contains 2,297,878 distinct popup UIDs and 3,488,613 reports. Users can appear across configurations, so configuration rows and type-level UVs are not additive. Mean exposure count is 1.52 (P50 1, P75 2, P90 3, maximum 300). 678,858 users (29.54%) appear in at least two types.

Among exposed VIPs, 65.57% appear in one type, 27.85% in two, 5.49% in three, 1.05% in four and 0.04% in five. LPL team fans are the strongest single VIP audience at 2,741 users (20.25% of all VIPs); 赛事人群 accounts for 52.11% of exposure reports but only 4.31% of VIPs.

Daily users peak at 1,305,036 on November 8 and 932,792 on November 4. Daily UVs and type UVs must not be summed because users overlap across days and configurations.

See `README.md` for the full type table and daily trend. The analysis is descriptive and does not identify causal effects of exposure on VIP purchase.
