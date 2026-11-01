# 弹幕与打赏留存 SQL 索引

## 用途

本主题集中说明近期编写的站外平台与虎牙站内留存 SQL，便于新电脑直接选择正确版本、恢复依赖并复核口径。完整 SQL 已在 `sql/source/` 原样归档；未经业务确认，不把历史草稿混入调度链路。

## 站外平台：斗鱼、B站、抖音

推荐链路：

1. [`zty_jingpin_user_activity_di_日跑调度.sql`](../../source/zty_jingpin_user_activity_di_日跑调度.sql)：按日生成 `zhgametemp.zty_jingpin_user_activity_1029_v1`，粒度是 `dt + pcode + r_category + anchor_uid + user_id`。
2. [`zty_jingpin_用户活动月度流水留存_调度版_1030_v1.sql`](../../source/zty_jingpin_用户活动月度流水留存_调度版_1030_v1.sql)：生成 `zhgametemp.zty_jingpin_user_activity_monthly_summary_1030_v1`，粒度为 `mth + pcode + r_category`。
3. [`zty_jingpin_user_activity_202609_validation.sql`](../../source/zty_jingpin_user_activity_202609_validation.sql)：对唯一粒度、主播日观时/开播、弹幕量、打赏金额和笔数做源表对账。测试表名需要在新环境按实际表名调整。

另外三份 [`站外主播用户日活动明细_日跑调度.sql`](../../source/站外主播用户日活动明细_日跑调度.sql)、[`按派生表校准`](../../source/站外主播用户日活动明细_按派生表校准_日跑调度.sql) 与 [`指定口径`](../../source/站外主播用户活动明细_指定口径_日跑调度.sql) 是前序设计版本，存在不同目标表名和用户活动粒度。它们不能与推荐链路同时运行；优先复核推荐版本的历史结果后再决定保留哪一个。

## 虎牙站内：星秀

[`zty_huya_xingxiu_subcategory_monthly_retention_dau_v1.sql`](../../source/zty_huya_xingxiu_subcategory_monthly_retention_dau_v1.sql) 输出 `zhgametemp.zty_huya_xingxiu_subcategory_monthly_retention_dau_v1`，粒度为 `mth + pcode + game_name + sub_category`，同时包含“星秀-整体”和星秀子类。数据期在脚本中固定为 2025-01-01 至 2026-10-29，留存 cohort 截止 2026-09-30。

## 留存口径

- D7、D14、D30 分别指 T+6、T+13、T+29 的精确自然日，不是 7/14/30 个活跃日窗口。
- 留存要求相同用户、相同平台、相同品类在目标日再次出现同类行为；站外不要求仍是同一主播，虎牙星秀也不要求仍是同一主播。
- 站外月度基数把逐日 cohort 用户数相加，属于“用户日”口径，不是整月去重用户数。D7/D14/D30 共用同时具备三个目标分区的 cohort 日期。
- 站外打赏用户要求 `gift_cnt > 0` 且 `gift_value > 0`；普通弹幕以源事件的普通文字弹幕行为准。
- 虎牙弹幕源要求 `passed='0'`；虎牙打赏要求 `live_platform='虎牙'`、`consume_order_type='礼物'`、`is_free_item=0` 且消费金额大于 0。
- 虎牙星秀 DAU 只统计 App 端，并剔除黑产和爬虫标签；观时把 `view_mins_only_live` 小时数乘以 60 转为分钟。

## 已确认风险

1. **站内分母重复计数**：虎牙星秀 SQL 先把每个用户展开为 D7/D14/D30 三行，随后 `sum(is_danmu)` 和 `sum(is_gift)` 作为共同 cohort 基数，会把分母重复算三次，使现存留存率偏低。修复时应只在一个 retention_day 上计基数，或像站外 1030 版本一样在用户日层保留三个留存标志。
2. **站内目标日缺失静默计零**：虎牙星秀使用左连接查询目标日；若目标分区缺失，会把该用户直接记为未留存，脚本没有像站外 1030 版本那样先校验 T+6/T+13/T+29 分区。当前固定日期依赖假设 2026-10-29 前分区齐全。
3. **抖音弹幕覆盖不确定**：站外日表注释说明当前弹幕源可能没有抖音数据。抖音用户可由打赏进入基数，但抖音弹幕留存不能在没有实际弹幕分区时解释为业务真实值。
4. **品类未知值**：站外把缺失品类保留为“未知品类”，没有丢弃或按主播主品类回填；使用结果前必须单独审查该分组。
5. **日均指标不是完整自然日平均**：月内观时和日活用户只对存在的行求平均；没有来源数据的日期不会被自动补零。

## 2026-11-02 复核记录

- `zty_jingpin月度流水与7日留存_1029_v1.sql` 只有 D7 一个观察窗，没有 D7/D14/D30 长表重复展开；每个 base 用户日以内连接 `available_days` 限定到存在 T+6 的日期，分母直接在该结果上求和。静态逻辑未发现同类三倍分母缺陷。
- `zty_jingpin_用户活动月度流水留存_调度版_1030_v1.sql` 在 `retention_target` 中展开三个观察日，但在 `retention_flags` 中按 `(base_dt, pcode, r_category, user_id)` 聚成宽表标志，再回连 base 用户日。D7/D14/D30 共用同一分母，静态逻辑与“同一用户日只计一次”一致。
- 站外源表在 2026-09-01 至 2026-10-29 覆盖 59 天，2026-10-29 分区有 2,684,588 行。2026-09 独立重建的基数见 [`artifacts/external-retention-202609-base-denominators.csv`](artifacts/external-retention-202609-base-denominators.csv)。
- 当前 Presto 中目标表 `zhgametemp.zty_jingpin_user_activity_monthly_summary_1030_v1` 不存在，因此无法完成“目标表 vs 独立分母”的数据级对账。通用目标表检查已保存为 [`verify-external-retention-denominators.sql`](verify-external-retention-denominators.sql)，状态为**未执行**；在目标表重建并通过对账前，不得把正式目标表写成已验证。
- 另用 2026-09“无畏契约”和“无畏契约：源能行动”真实数据执行源侧逻辑校验，状态为**通过**：4 个平台×品类组合中，D7/D14/D30 宽表展开后的弹幕分母合计 1,779,759、打赏分母合计 22,892，分别与独立用户日基数完全一致，不一致组为 0；所有分子均不大于分母。SQL 和结果见 [`verify-external-retention-202609-logic.sql`](verify-external-retention-202609-logic.sql) 与 [`artifacts/external-retention-202609-logic-check.csv`](artifacts/external-retention-202609-logic-check.csv)。

详细源文件、哈希和版本状态见 [`source-manifest.csv`](source-manifest.csv)。修复前应先对照现有产出确认分母重复问题的影响。

虎牙星秀分母缺陷、替换 CTE、目标表验证查询及 2025-01 至 2026-10 匿名整体对比已单独整理在 [`remediation/`](remediation/README.md)。现存目标表尚未按修复版重跑；对比文件中的修正率是按存储分母除以 3 推断，不应替代正式刷新结果。

英文版见 [`README.en.md`](README.en.md)。
