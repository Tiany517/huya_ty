# Monthly core metrics for the game category

Combines monthly revenue, watching users, watched anchors and live anchors for the game category into one monthly result table.

Definitions:

- Period: 2026-07-01 through 2026-10-31.
- Revenue: de-brushing detail table with `game_label='游戏'`, `is_free_item=0`, and positive consumption.
- Big-R user: monthly cumulative consumption of at least 1,000.
- Big-R average consumption: total big-R consumption divided by the number of big-R users.
- Watching: live-watch sessions in `dws_huya_user_behavior_d_i` with `game_label='游戏'`.
- Live anchors: `dm_huya_ayyuid_detail_day` joined to `dim_huya_game_d_a`, retaining only `game_label='游戏'`.
- Although named `live_mins`, the field stores hours; a valid live day requires daily total hours × 60 ≥ 15 minutes.

Files: `game-category-monthly-core-metrics-presto.sql`, `monthly-result.csv`, and `validation-record.md`.
