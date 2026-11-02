# Two-Week WeChat Channel Audience Attribution Review (De-Identified)

## Objective and Sample

Review the change in WeChat Channel audience counts from 2026-09-21–27 versus 2026-09-14–20, decomposing it by anchor-day scale, average output per active anchor-day, anchor activity status, content group, live duration, and hourly output.

- Input grain: anchor x day, unique on `(dt, anchor_alias)`.
- Source coverage: 2026-09-01 through 2026-09-28, 28 dates.
- Valid live rows: 2,067; 110 anchors occur anywhere in the source and 107 occur in either comparison week.
- Metric: `audiencecnt` summed over anchors and calendar days. It is an **audience-count sum at anchor grain**, not cross-anchor deduplicated platform DAU.
- No user-level exposure, recommendation, campaign, or platform-change data is available. The findings are descriptive attribution, not causal effects.

## Main Results

| Metric | W1 09-14–09-20 | W2 09-21–09-27 | Change | Rate |
| --- | ---: | ---: | ---: | ---: |
| Daily audience-count sum | 6,760,166 | 7,163,321 | +403,155 | +6.0% |
| Anchor live-days | 534 | 510 | -24 | -4.5% |
| Audience count per anchor live-day | 88,616 | 98,320 | +9,704 | +11.0% |

Anchor activity status:

| Group | Anchors | Weekly audience change | Daily change | Share of net change |
| --- | ---: | ---: | ---: | ---: |
| Persistently live | 97 | +5,830,526 | +832,932 | +207% |
| New or returning in W2 | 3 | +1,361,538 | +194,505 | +48% |
| Not live in W2 | 7 | -4,369,976 | -624,282 | -155% |

Shares exceed 100% because positive and negative contributions offset. These are contribution shares, not retention or out-of-range percentages.

Content groups:

| Group | Anchors | W1 daily | W2 daily | Daily change | Rate |
| --- | ---: | ---: | ---: | ---: | ---: |
| Qipai main scope | 29 | 5,103,836 | 5,668,419 | +564,583 | +11.1% |
| Non-qipai | 81 | 1,656,330 | 1,494,903 | -161,428 | -9.7% |
| All source anchors | 110 | 6,760,166 | 7,163,321 | +403,155 | +6.0% |

Within qipai: Mahjong `+394,640/day`, Landlord `-589,734/day`, poker/upgrade `+76,917/day`, board games `+195,998/day`, and tabletop games `+486,761/day`. Boundary categories are stored separately and excluded from the main qipai scope.

## Was the Increase Broad-Based?

No. Among 83 anchors live at least three days in each week, 42 increased and 41 decreased; the median individual change was only `+0.1%`, while the mean was `+12.8%`. The aggregate increase was concentrated:

- The top three positive contributors equal `432%` of the net weekly change.
- Removing those three reduces average daily audience from `6,320,443` to `4,981,473`, a change of `-1,338,970/day` (`-21.2%`).
- The `+6.0%` total is therefore not evidence of broad growth. It reflects a small set of strong gainers offsetting declines elsewhere.

## Duration and Hourly Output

The following three-factor decomposition closes exactly to the weekly net change:

| Scope | Anchor-day effect | Duration effect | Hourly-output effect | Weekly net change |
| --- | ---: | ---: | ---: | ---: |
| All source anchors | -4,470,621 | +788,631 | +6,504,078 | +2,822,088 |
| Qipai | -5,411,376 | +1,615,435 | +7,748,022 | +3,952,081 |
| Non-qipai | +940,755 | -826,805 | -1,243,944 | -1,129,993 |

Qipai anchor-days moved only from 123 to 124, while total live hours rose from 994 to 1,104. In daily terms, qipai scale is `-773,054`, average duration is `+230,776`, hourly output is `+1,106,860`, and the sum is `+564,583`. Hourly output is the largest positive factor, but this decomposition does not prove that recommendations, traffic allocation, or content changes caused the change.

## Legacy Issues and Handling

1. A stale derived text file records `10` anchors as not live in W2, while the current source and final workbook both contain `7`. The stale text file was not migrated.
2. The current source CSV uses dates such as `2026/9/21`, while the old scripts compare `2026-09-21`. Running them unchanged now produces an empty result. The migrated build normalizes both formats.
3. The legacy two-factor components were scale `-303,828`, efficiency `706,983`, and interaction `-33,270` per day; they sum to `369,885`, not the reported `403,155`. The migrated version fixes efficiency at W1 anchor-days: scale `-303,828`, efficiency `+740,253`, interaction `-33,270`, closing to `+403,155`.
4. The original JSON, logs, detail workbook, and raw anchor identities were not migrated.
5. The content grouping is a manual classification from the original project, not an official platform taxonomy. Only anonymous anchor categories are retained.

## Path Map

| GitHub path | Content |
| --- | --- |
| [`scripts/build_anonymous_artifacts.py`](scripts/build_anonymous_artifacts.py) | De-identify the local source, normalize dates, and rebuild all outputs |
| [`scripts/validate_artifacts.py`](scripts/validate_artifacts.py) | 40 independent checks using committed artifacts only |
| [`artifacts/wechat-channel-dau-two-week-anonymous-20260929.xlsx`](artifacts/wechat-channel-dau-two-week-anonymous-20260929.xlsx) | De-identified workbook with summary, daily, anchor, group, three-factor, and Top20 sheets |
| [`artifacts/anchor-day-anonymous.csv`](artifacts/anchor-day-anonymous.csv) | Complete de-identified anchor x day analysis basis |
| [`artifacts/anchor-two-week-anonymous.csv`](artifacts/anchor-two-week-anonymous.csv) | Two-week summaries for the 107 anchors present in either comparison week |
| [`artifacts/activity-group-summary.csv`](artifacts/activity-group-summary.csv) | Persistent, new/returning, and absent-anchor groups |
| [`artifacts/content-group-summary.csv`](artifacts/content-group-summary.csv) | Qipai, non-qipai, and all-source summaries |
| [`artifacts/content-subgroup-summary.csv`](artifacts/content-subgroup-summary.csv) | Qipai subcategories and boundary categories |
| [`artifacts/decomposition-summary.csv`](artifacts/decomposition-summary.csv) | Anchor-day, duration, and hourly-output decomposition |
| [`artifacts/contribution-top20-anonymous.csv`](artifacts/contribution-top20-anonymous.csv) | Positive/negative Top20 by stable anonymous alias |
| [`artifacts/sensitivity-summary.csv`](artifacts/sensitivity-summary.csv) | Result after removing the top three positive contributors |
| [`artifacts/daily-summary.csv`](artifacts/daily-summary.csv) | Daily summary for 28 dates |
| [`artifacts/source-manifest.csv`](artifacts/source-manifest.csv) | Source path, hash, row counts, date range, and uniqueness evidence |
| [`artifacts/source-script-manifest.csv`](artifacts/source-script-manifest.csv) | Names, hashes, and exclusion reasons for the 12 original scripts |
| [`validation/validation-summary.json`](validation/validation-summary.json) | All 40 checks and known issues |

Local source: `C:\Users\tiany\Downloads\视频号DAU_0929.csv`, SHA-256 `17d4e89ad0413fd705b93f63dc37b5aed4e8d0e579055fd44ef9bd2f87e3e261`. Original project folder: `C:\Users\tiany\Documents\ChatGPT\异动归因`. The original identity-bearing workbook, classification JSON, and logs were not uploaded.

## Reproduction

With the raw CSV and original classification JSON available locally:

```powershell
python scripts\build_anonymous_artifacts.py --source C:\path\to\视频号DAU_0929.csv --classification C:\path\to\棋牌类主播分类_0929.json
python scripts\validate_artifacts.py
```

Validate from the committed artifacts alone:

```powershell
python scripts\validate_artifacts.py
```

Chinese version: `README.md`.
