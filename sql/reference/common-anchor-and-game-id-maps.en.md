# Common Anchor and Game ID Maps

## Source and Scope

- The user supplied both maps on 2026-11-03. Names, category assignments, and IDs are recorded as provided.
- Use these maps for SQL filters, `game_id` lookups, and result reconciliation; they do not replace the platform dimension tables.
- This archive does not independently verify current ID validity, anchor-name changes, or category changes.
- Before querying, confirm the actual source fields, ID types, partition coverage, and current business definitions.

## Common Anchor IDs

| Anchor name | Assigned category | Anchor ID | Note |
| --- | --- | ---: | --- |
| 吕德华 | 王者荣耀 | 1354740567 |  |
| 童锦程 | 户外 | 1199568157971 |  |
| 姿态 | 英雄联盟 | 2367547387 |  |
| AmazingJ | 户外 | 1199517808234 | Previously 英雄联盟 |
| Dank1ng | CS2 | 333393123 |  |
| 狂魔哥解说 | 王者荣耀 | 1567578875 |  |
| 明凯 | 王者荣耀 | 1705516953 |  |
| 魔创-雅一儿【许仙】 | 主机游戏 | 1784500555 |  |
| Letme严君泽 | 英雄联盟 | 1430972471 |  |
| 药水哥 | 英雄联盟 | 2319419933 |  |
| 东星耀扬【单枪匹马】 | 王者荣耀 | 1279521053571 |  |
| XLX金木 | 王者荣耀 | 1199610004865 |  |
| Karsamzing苏弟 | 无畏契约 | 1860008570 |  |
| 神枪小子 | 无畏契约 | 1199630339535 |  |
| 节奏 | 无畏契约 | 1014447803 |  |

## Common Game `game_id` Values

| Game name | `game_id` |
| --- | ---: |
| 英雄联盟 | 1 |
| 王者荣耀 | 2336 |
| 体育 | 2356 |
| Dota2 | 7 |
| 户外 | 2165 |
| 星秀 | 1663 |
| 交友 | 4079 |
| 二次元 | 2633 |
| Apex英雄 | 5011 |
| 主机游戏 | 1964 |
| 我的世界 | 1732 |
| 炉石传说 | 393 |
| 天天吃鸡 | 2793 |
| 天天吃鸡手机版 | 4341 |
| 方舟 | 1997 |
| CS2 | 862 |
| 无畏契约 | 5937 |
| 和平精英 | 3203 |
| 王者万象棋 | 8127 |
| 三角洲行动 | 9449 |

## SQL Reuse Rules

1. Treat anchor IDs and `game_id` values as identifiers; do not infer an ID from a display name.
2. Check both join-side data types before joining. Do not cast string anchor UIDs to numeric merely for convenience.
3. `Assigned category` is a business ownership label. It is not necessarily the anchor's category on a particular day or the category of a user event.
4. `AmazingJ` is currently assigned to 户外. The historical 英雄联盟 label is retained only as a note and must not be used as the current category filter.
5. These are common-value lists, not complete anchor or game dimensions. A missing value does not imply that the anchor or game does not exist.

Chinese version: [`common-anchor-and-game-id-maps.md`](common-anchor-and-game-id-maps.md).
