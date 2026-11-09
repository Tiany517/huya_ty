# SQL 交付验收卡

状态：`待验证`

## 1. 任务信息

| 项目 | 内容 |
| --- | --- |
| 业务问题 | 比较 2026 年 10 月 VIP 用户与普通用户在进房、发弹幕、送礼三类触发事件前后各 3 分钟的直播间弹幕反应 |
| 结论类型 | 描述性对比；不支持因果结论 |
| SQL 路径及版本 | `sql/source/VIP会员/VIP会员三类事件弹幕反应_2026年10月_Spark_调度版_v3_非分区.sql` |
| 目标表 | `zhgametemp.zty_ads_huya_vip_event_danmu_reaction_month_v3`，非分区表 |
| 执行引擎 | Spark SQL |
| 输入快照 | VIP 订单表 `dt='2026-11-08'`；事件数据为 2026-10-01 至 2026-10-31；弹幕反应源补充读取 2026-09-30 至 2026-11-01 以覆盖跨日窗口 |
| 实际运行范围 | 尚未运行 V3 三类事件完整 SQL |
| 调度模板基线 | 用户已验证跑通的非分区模板 `zty_huya_linshi_20260826_left_important_anchor_monitor_qingchun_v1` |

## 2. 结果契约

| 项目 | 内容 |
| --- | --- |
| 样本总体 | 仅统计 10 月至少有一位 VIP 用户购卡后进入过的直播场次；三类触发事件均限定在这些场次内 |
| 进房触发 | `gamelive.dwt_huya_ayyuid_session_from_server_with_user`，`tag='gameid'`、`htime='session'`，事件时间使用 `user_start_time` |
| 发弹幕触发 | `gamelive.gamelive_huya_danmu_log`，`passed='0'`，内容取 `askscontent/scontent` 首个非空值，排除主播本人 |
| 送礼触发 | `gamelive.dws_huya_revenue_detail_d_i`，`consume_order_type='礼物'`、金额大于 0、`order_id` 非空，按 `dt+order_id` 去重 |
| 时间口径 | 触发事件 2026-10-01 00:00:00 至 2026-11-01 00:00:00；前窗 `[t-180s,t)`，后窗 `[t,t+179s)` |
| 基础粒度 | 触发事件；事件键包含事件类型、日期、用户、主播、`live_id`、事件时间；送礼增加 `order_id`，发弹幕增加内容 |
| 最终粒度 | `user_group + event_type + breakdown_type + user_type + acu_bin`；`dt` 为普通日期字段；不输出小时 |
| 唯一键 | 上述五个输出维度 |
| 场次键 | `dt + 主播UID + live_id` |
| 用户组 | 10 月首笔成功订单后为 VIP；事件发生时尚未购卡为普通用户 |
| 主指标 | 每个触发事件的房间级前 3 分钟、后 3 分钟有效弹幕数，并扣除触发事件用户本人弹幕 |
| 去除条件 | 主播本人弹幕；`passed<>'0'`；内容为空弹幕 |
| 分类口径 | 事件日期、用户、主播、`live_id` 下 `game_label` 唯一为游戏或娱乐；多标签或缺失归入品类未知 |
| ACU 分层 | 沿用原有 `(0,2]` 至 `(100000,+]` 和 `unknown` 分层 |
| 可反驳预期一 | 对每个 `user_group + event_type`，整体 `event_cnt` 必须等于游戏、娱乐、品类未知三者之和；否则分类或 join 发生放大 |
| 可反驳预期二 | 三类事件任一类型的 `total_danmu_before_3m`、`total_danmu_after_3m` 必须可由事件级窗口表独立复算；若不一致，窗口 frame 或去重错误 |
| 可反驳预期三 | 送礼事件数不得超过去重后的正金额礼物订单数；发弹幕事件数不得超过去重后的有效用户弹幕数 |

## 3. 调度模板对齐

| 检查 | 证据 | 状态 |
| --- | --- | --- |
| 使用非分区建表结构 | `CREATE TABLE IF NOT EXISTS ... STORED AS ORC`，不包含 `PARTITIONED BY` | 通过 |
| 使用整表覆盖写入 | CTE 结束后执行 `INSERT OVERWRITE TABLE ...`，不包含 `PARTITION` | 通过 |
| 输入与目标列数对齐 | 目标表 20 个普通字段，最终查询返回 20 列 | 通过（静态） |
| 不依赖宏变量 | SQL 中不存在 `${...}` | 通过 |
| 不输出小时 | SQL 中不存在 `event_hour` | 通过 |
| 建表字段与最终查询字段对齐 | 20 个普通字段逐一对应，末列 `dt='2026-10-31'` | 通过（静态） |

## 4. 已完成静态验证

- 使用 `sqlglot` Spark 方言解析通过：脚本被识别为 `CREATE TABLE`、`INSERT OVERWRITE` 和一个结束符，未发现语法解析错误。
- 已修复 `target_room_window` 仅输出日期、但后续引用 `creator_uid/live_id` 的字段缺失问题；窗口表现保留 `event_dt + creator_uid + live_id + window_dt` 四个关联字段。
- 三类触发事件均按同一目标场次集合、同一 VIP/普通用户分类规则、同一 ACU 分箱和同一前后窗口汇总。
- 发弹幕触发事件按日期、用户、主播、`live_id`、时间和内容去重。
- 送礼触发事件按日期和 `order_id` 去重。
- 房间级窗口、用户个人扣除窗口均增加 `event_dt`，避免相同 `live_id` 或跨日时间在不同场次日期之间串窗。
- 弹幕反应源额外投影目标日期前后一天，并只读取目标日期边界前后 3 分钟，支持跨日窗口。
- `is_window_overlap` 使用 `event_dt+主播+live_id` 分区，避免跨日事件被错误比较。

## 5. 待执行验证

- 当前 V3 三类事件完整 10 月任务尚未在调度环境实际运行，因此不得标记为“已验证”。
- 首次调度后核对：输出唯一键无重复；每个用户组、事件类型的整体事件数等于三个品类分组之和。
- 分别核对进房、发弹幕、送礼的源事件行数与 `classified_event` 聚合数，确认关联未放大。
- 对每类事件至少抽取 3 至 5 个明细事件，检查事件时间、目标场次、ACU 分钟、前后窗口和扣除本人弹幕后数值。
- 复核礼物表 `order_id` 的唯一性；若同一订单存在多个版本记录，以 `dt+order_id` 去重后的有效订单数作为事件数上限。
- `INSERT OVERWRITE` 会覆盖整个 V3 目标表；该表必须只由本任务维护，避免与其他任务并发写入。

## 6. 调度建议

如调度平台支持 Spark 会话参数，建议设置：

- `spark.sql.autoBroadcastJoinThreshold=-1`
- `spark.sql.adaptive.enabled=true`
- `spark.sql.adaptive.coalescePartitions.enabled=true`

最终状态：`待验证`
