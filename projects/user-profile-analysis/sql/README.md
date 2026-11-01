# 用户画像源 SQL

这里保留 3 份历史 SQL 原文，用于版本追溯和修复起点。它们没有在本次迁移中重新执行，不能把现存 CSV 的成功读取当成 SQL 已验证。

| SQL | 当前状态 | 主要问题 |
| --- | --- | --- |
| `鸿蒙安卓和苹果用户的画像.sql` | 待验证 | Android 产品拼写不一致；31 天画像日表没有固定用户快照 |
| `观看过世锦赛和未观看过世锦赛的画像.sql` | 待验证 | 2025/2026 注释冲突；目标与对照窗口不同 |
| `观看过世锦赛且单日观看时长最长的用户.sql` | 草稿 | 未定义 CTE；全期求和冒充单日；两个分支共用标签；`watch_duration` 单位未确认 |

逐项证据见 `../artifacts/anonymous-summary/sql-static-audit.csv`。重新执行前必须按 `instructions/sql-validation-workflow.md` 写出新的结果契约，并填写 `instructions/templates/sql-validation-record.md`。

英文版见 `README.en.md`。
