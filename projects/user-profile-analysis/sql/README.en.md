# User-Profile Source SQL

The three historical SQL files are retained as version evidence and repair starting points. They were not rerun during this migration. Merely reading the existing CSV does not make the SQL verified.

| SQL | Current status | Main issue |
| --- | --- | --- |
| `鸿蒙安卓和苹果用户的画像.sql` | Pending validation | Android product values disagree; the 31-day portrait table has no fixed user snapshot |
| `观看过世锦赛和未观看过世锦赛的画像.sql` | Pending validation | Conflicting 2025/2026 comments; target and control windows differ |
| `观看过世锦赛且单日观看时长最长的用户.sql` | Draft | Undefined CTE; full-period sum presented as single-day; duplicated branch label; `watch_duration` unit unconfirmed |

Evidence is in `../artifacts/anonymous-summary/sql-static-audit.en.csv`. Before rerunning, write a new result contract using `instructions/sql-validation-workflow.en.md` and complete `instructions/templates/sql-validation-record.en.md`.

Chinese version: `README.md`.
