# AI 直播间快照复盘校验

总体状态：`incomplete`

| 检查 | 状态 | 证据 |
| --- | --- | --- |
| 源快照可读且表头可识别 | PASS | 字段数：{'2026-08-07': 13, '2026-09-04': 11, '2026-10-09': 11} |
| 两份 0807 CSV 完全一致 | PASS | SHA-256 一致 |
| 源文件清单大小与哈希一致 | PASS | 6 个源文件；异常=[] |
| 两份 SQL 与源文件逐字节一致 | PASS | 运行版=True; 注释版=True |
| 2026-08-07 快照粒度与月份 | PASS | 行=12; 唯一主播×品类=12; 重复键=0; 数据月=['2026-07'] |
| 2026-09-04 快照粒度与月份 | PASS | 行=18; 唯一主播×品类=18; 重复键=0; 数据月=['2026-08'] |
| 2026-10-09 快照粒度与月份 | PASS | 行=18; 唯一主播×品类=18; 重复键=0; 数据月=['2026-09'] |
| 1009 重复 UID 是多品类主播 | PASS | 12 个主播形成 18 个主播×品类键；跨多个品类主播 4 个 |
| 快照总览独立复算 | PASS | 3 rows and all fields match |
| category 汇总独立复算 | PASS | 16 rows and all fields match |
| tier 汇总独立复算 | PASS | 3 rows and all fields match |
| 跨快照主播覆盖独立复算 | PASS | 4 rows and all fields match |
| 快照质量检查无失败项 | PASS | 22 项；失败=[] |
| 中英文 SQL 风险清单完整对应 | PASS | 英文 13 项；中文 13 项；编号一致=True |
| SQL 核心表、日期和指标结构存在 | PASS | 缺失=[] |
| SQL 日期字符串已补零 | PASS | 未出现 2026-9-30；存在 2026-09-30 |
| 有效日与 DAU 端口差异已记录 | PASS | 涉及 hmos_kiwi 的编号 SQL-07 已列入；hmos_kiwi 缺失=False |
| 生成交付物不含源 UID 或昵称 | PASS | no source UID or nickname found in generated deliverables |
| 中英文结果工作簿结构一致 | PASS | ai-live-room-snapshot-review-zh.xlsx=['快照总览', '品类汇总', 'ACU分层汇总', '主播覆盖重叠', '数据质量', 'SQL静态审查', '方法说明']; ai-live-room-snapshot-review-en.xlsx=['Snapshot overview', 'Category summary', 'Tier summary', 'Anchor overlap', 'Data quality', 'SQL static review', 'Method'] |
| 中英文项目文档齐全 | PASS | 缺失=[] |
| SQL 正式执行和最终指标对账 | NOT_RUN | 未执行项=['SQL-11']；当前结果只能标记为静态审查 |

汇总：21 项，通过 20，失败 0，未执行 1，复核 0。

结论：快照文件、匿名汇总、主播覆盖和隐私边界已验证；SQL 仍为静态审查，不能把三份导出结果当作已由当前 SQL 重跑并通过业务对账。
