# 输入文件契约

所有 CSV 使用 UTF-8 或 UTF-8 with BOM。不得修改列名；空值可以留空，但关键日期、品类、主播 UID 不能为空。刷新脚本会先做 header、非空、周一和连续周检查。

## 1. 品类日表

建议文件名：`category_daily_all_<latest_partition>.csv`

唯一键：`dt + gameid`

必需列：

`dt,gameid,game_name,content_group,dau,daily_revenue,daily_pay_user_cnt,arppu,avg_view_mins,attribution_user_cnt,live_anchor_cnt,group_live_anchor_cnt,total_live_anchor_cnt`

来源：`zhgametemp.zty_category_ecology_health_daily_d_i_0827_v1` 的 `category='品类整体'`，内容大类由 `gamelive.dim_huya_game_d_a` 映射。

## 2. 主播周表

建议文件名：`anchor_weekly_guild_<start>_<end>.csv`

唯一键：`week_start + gameid + guild_name + luid`

必需列：

`week_start,gameid,game_name,content_group,guild_name,luid,roomid,snick,dau_sum,revenue_sum,pay_sum,live_sum,acu_sum,acu_days,view_sum,view_days,attribution_sum,interaction_cnt_sum,interaction_user_sum,live_days`

要求：`week_start` 全部是周一，按时间升序且相邻间隔恰好 7 天。`luid` 为字符串，禁止 Excel 把长整数转成科学计数法。

## 3. 主播日表

建议文件名：`anchor_daily_focus_<start>_<end>.csv`

唯一键：`dt + luid`

必需列：

`dt,gameid,content_group,guild_name,luid,snick,roomid,dau,daily_revenue,daily_pay_user_cnt,is_live,live_mins,avg_acu,avg_view_mins,attribution_user_cnt,interaction_cnt,interaction_user_cnt`

日表只保留当前周表覆盖范围内满足以下任一条件的主播：归属 DAU `>=10`、流水 `>=1 元`、互动人数 `>=10`。该筛选用于控制 HTML 体积，不影响周表归因。

### 4. 开播主播数附加字段

- 品类日表的 `live_anchor_cnt`：当天该品类 `is_live=1` 的去重主播数。
- 品类日表的 `group_live_anchor_cnt`：当天该内容大类跨品类去重后的主播数。
- 品类日表的 `total_live_anchor_cnt`：当天全平台去重后的主播数。
- 主播周表的 `live_days`：该周主播有开播的日期数，范围 `0–7`。
- 主播日表的 `is_live`：当天是否开播，`1/0`。

## 5. 赛事支付属性表（可选）

建议文件名：`event_user_revenue_<start>_<end>.csv`

唯一键需覆盖最终输出粒度，实际为 `dt + gameid + guild_name + luid + user_event_type`。

必需列：

`dt,week_start,gameid,game_name,content_group,guild_name,luid,snick,user_event_type,revenue,pay_user_cnt`

当前口径：支付日前 90 天，赛事主播日期观时 / 同游戏总观时 `>=70%` 为“赛事用户”。该表未产出时脚本写入 `eventStatus=pending`，看板应禁用赛事筛选，不能推断为 0。

## 交接前检查

- 文件名、周期、最新分区相互一致。
- CSV 能被 UTF-8 读取，中文无乱码。
- 行数大于 0；关键 ID 不是科学计数法。
- 同一唯一键没有重复。
- 周表不含缺周；日表日期落在声明区间。
- 记录输入文件 SHA-256，接收方重新计算后必须一致。
