# 游戏品类月度核心指标

用于把游戏品类当月的收入、观看用户、观看主播和开播主播指标汇总到同一张月度结果表。

口径：

- 时间范围：2026-07-01 至 2026-10-31。
- 收入：剔刷单收入明细表，`game_label='游戏'`、`is_free_item=0`、消费金额大于 0。
- 大 R：用户当月累计消费金额大于等于 1,000。
- 大 R 用户人均消费：大 R 用户消费总额 ÷ 大 R 用户数。
- 观看：`dws_huya_user_behavior_d_i` 的直播观看会话，`game_label='游戏'`。
- 开播：`dm_huya_ayyuid_detail_day` 关联 `dim_huya_game_d_a`，仅保留 `game_label='游戏'`。
- `live_mins` 虽名为分钟，实际存小时；有效开播日按当日累计开播时长 × 60 ≥ 15 分钟判断。

文件：`game-category-monthly-core-metrics-presto.sql`、`monthly-result.csv` 和 `validation-record.md`。
