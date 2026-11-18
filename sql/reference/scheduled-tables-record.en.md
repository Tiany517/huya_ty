# Scheduled Tables Record

Updated: 2026-11-18  
Scope: the three scheduled tables added in the current work.

| Table | Scheduled task | Purpose | Grain | Key definition |
| --- | --- | --- | --- | --- |
| `zhgametemp.zty_sudi_belong_user_daily_watch_game_di` | `苏弟归属用户_当日秀场及整体观时_主播游戏归属_日跑调度` | Users attributed to anchor 1860008570, with daily total watch time, entertainment watch time, and the anchor's attributed game. | `dt × user_ukey` | Attribution window is `tdate-104 ~ tdate-14`; anchor game is selected by the largest cumulative `live_hours_only_live`; APP only. |
| `zhgametemp.zty_anchor_belong_user_daily_watch_game_di` | `用户归属主播_当日秀场及整体观时_主播游戏归属_日跑调度` | All users with daily total watch time, entertainment watch time, attributed anchor, and the anchor's attributed game. | `dt × user_ukey` | Attribution window is `tdate-104 ~ tdate-14`; anchor game is selected by the largest cumulative `live_hours_only_live`; APP only. |
| `zhgametemp.zty_anchor_daily_watch_dau_belong_user_cnt_di` | `主播日观看DAU及日归属用户数_APP直播_日跑调度` | Daily watching DAU and daily attributed-user count for each anchor. | `dt × luid` | Watching DAU is the daily distinct viewer count; attributed-user count uses each user's longest-watched anchor that day; APP only. |

Note: This file is a quick operational index. The SQL and validation records remain the source of truth for field definitions.
