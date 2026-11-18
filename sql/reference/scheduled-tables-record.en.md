# Scheduled Tables Record

Updated: 2026-11-18  
Scope: the four scheduled tables added in the current work.

| Table | Scheduled task | Purpose | Grain | Key definition |
| --- | --- | --- | --- | --- |
| `zhgametemp.zty_sudi_belong_user_daily_watch_game_di` | `苏弟归属用户_当日秀场及整体观时_主播游戏归属_日跑调度` | Users attributed to anchor 1860008570, with daily total watch time, entertainment watch time, and the anchor's attributed game. | `dt × user_ukey` | Attribution window is `tdate-104 ~ tdate-14`; anchor game is selected by the largest cumulative `live_hours_only_live`; APP only. |
| `zhgametemp.zty_anchor_belong_user_daily_watch_game_di` | `用户归属主播_当日秀场及整体观时_主播游戏归属_日跑调度` | All users with daily total watch time, entertainment watch time, attributed anchor, and the anchor's attributed game. | `dt × user_ukey` | Attribution window is `tdate-104 ~ tdate-14`; anchor game is selected by the largest cumulative `live_hours_only_live`; APP only. |
| `zhgametemp.zty_anchor_daily_watch_dau_belong_user_cnt_di` | `主播日观看DAU及日归属用户数_APP直播_日跑调度` | Daily watching DAU, attributed-user count, attributed game, and daily live duration per anchor. | `dt × luid` | Watching DAU is the daily distinct viewer count; attributed-user count uses each user's longest-watched anchor that day; `game_id/game_name` use the game with the largest daily cumulative `live_hours_only_live`; `live_hours` is the daily live duration in hours; APP only. |
| `zhgametemp.zty_category_ecology_health_daily_d_i_0827_v1` | `游戏品类生态健康度_主播及品类日度指标_APP直播_日跑调度` | Daily category ecosystem metrics for each anchor and for each category overall: live status, ACU, watching DAU, revenue, payers, attribution and interest users. | `dt × category × gameid × luid`; category totals use `dt × gameid` | `category='主播明细'/'品类整体'`; DAU uses deduplicated APP live-watch sessions; revenue uses the de-brushing detail table; attribution and interest users come from their existing daily tables; anchor live status comes from `dm_huya_ayyuid_detail_day`. |

Note: This file is a quick operational index. The SQL and validation records remain the source of truth for field definitions.

Open question: `zty_category_ecology_health_daily_d_i_0827_v1.live_mins` is documented as minutes, while existing repository SQL notes that source `live_mins` stores hours despite its name. The current job sums it without multiplying by 60, so the final unit needs confirmation. In addition, `non_category_interest_user_cnt` uses `case when i.gameid <> g.gameid` after joining on equal `gameid`, so the condition is always false and the output may always be zero.
