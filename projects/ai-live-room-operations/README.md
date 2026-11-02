# AI 直播间月度运营快照复盘

本项目复盘 2026-07、2026-08、2026-09 三个月的人工智能（AI）直播间腰部主播快照，并保留生成这些快照的核心 SQL。迁移目标是让新电脑上的 Codex 能理解当时的监控名单结构、指标口径、已经发现的质量问题，以及后续刷新时应先验证什么。

三份导出文件分别产生于 2026-08-07、2026-09-04 和 2026-10-09，但内容月份分别是上一个月；文件名日期不能当作数据月份。原始文件含主播 UID 和昵称，均未上传。仓库只保留匿名汇总和 SQL 原样副本。

## GitHub 路径地图

| 仓库内路径 | 内容 |
| --- | --- |
| `projects/ai-live-room-operations/README.md` / `.en.md` | 中英文项目背景、主要结果、风险和使用方法 |
| `projects/ai-live-room-operations/methodology/analysis-method.md` / `.en.md` | 数据粒度、指标公式、匿名化与静态 SQL 审查方法 |
| `projects/ai-live-room-operations/scripts/ai-live-room-monthly-tiering.sql` | 生成月度主播×品类结果的运行版 SQL，原样复制 |
| `projects/ai-live-room-operations/scripts/ai-live-room-monthly-tiering-annotated.sql` | 带修正说明和三段验证查询的注释版 SQL，原样复制 |
| `projects/ai-live-room-operations/scripts/build_snapshot_review.py` | 从本机三份快照重建全部匿名汇总，不输出 UID 或昵称 |
| `projects/ai-live-room-operations/scripts/validate_snapshot_review.py` | 从原始快照独立复算、核对哈希、SQL 副本、隐私和结果结构 |
| `projects/ai-live-room-operations/artifacts/anonymous-summary/overview-summary.zh.csv` / `.en.csv` | 三份快照的匿名总览 |
| `projects/ai-live-room-operations/artifacts/anonymous-summary/category-summary.zh.csv` / `.en.csv` | 按数据月份和品类的匿名汇总 |
| `projects/ai-live-room-operations/artifacts/anonymous-summary/tier-summary.zh.csv` / `.en.csv` | 按 ACU 分层的匿名汇总 |
| `projects/ai-live-room-operations/artifacts/anonymous-summary/overlap-summary.zh.csv` / `.en.csv` | 跨月主播覆盖、交集和 Jaccard |
| `projects/ai-live-room-operations/artifacts/anonymous-summary/quality-summary.zh.csv` / `.en.csv` | 表头、空值、重复键、月份和分层检查 |
| `projects/ai-live-room-operations/artifacts/anonymous-summary/sql-static-review.zh.csv` / `.en.csv` | 13 项 SQL 静态风险、证据和下一步 |
| `projects/ai-live-room-operations/artifacts/anonymous-summary/ai-live-room-snapshot-review-zh.xlsx` / `-en.xlsx` | 中英文匿名结果工作簿 |
| `projects/ai-live-room-operations/artifacts/anonymous-summary/source-manifest.csv` | 6 个本机源文件的相对路径、大小、SHA-256 和纳入边界 |
| `projects/ai-live-room-operations/artifacts/anonymous-summary/project-summary.json` | 数据规模、主播覆盖和隐私边界 |
| `projects/ai-live-room-operations/validation/validation-report.md` / `.en.md` | 中英文逐项验证报告 |
| `projects/ai-live-room-operations/validation/validation-report.json` | 机读验证结果 |

以上路径均相对于 GitHub 仓库根目录。

## 快照与规模

| 导出日期 | 数据月份 | 数据行 | 唯一主播 | 主播×品类唯一键 | 跨多个品类主播 | 品类数 |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 2026-08-07 | 2026-07 | 12 | 12 | 12 | 0 | 3 |
| 2026-09-04 | 2026-08 | 18 | 18 | 18 | 0 | 6 |
| 2026-10-09 | 2026-09 | 18 | 12 | 18 | 4 | 7 |

`2026-10-09` 的 18 行只有 12 个唯一 UID，但 `UID + 品类` 是 18 个唯一键，说明重复 UID 来自 4 位主播分别覆盖多个品类；“重复 UID”本身不是行重复错误。

## 主要结果

| 数据月份 | ACU 均值 | ACU 中位数 | ACU 最大值 | PCU 最大值 | APP DAU 均值 | 观时均值（小时） | 人均观时均值（分钟） |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2026-07 | 193.25 | 144.50 | 529.00 | 4,947 | 16,022.67 | 965.67 | 4.08 |
| 2026-08 | 215.41 | 146.00 | 731.46 | 7,170 | 15,086.74 | 737.16 | 5.18 |
| 2026-09 | 202.27 | 168.86 | 439.01 | 1,509 | 8,632.35 | 1,672.81 | 12.34 |

这些是不同名单快照的描述性统计。2026-09 只有 12 位主播、且与 2026-08 仅重合 6 位，因此不能把均值变化直接解释为原有主播经营改善或恶化。

跨月主播覆盖如下：

- 2026-07 与 2026-08：交集 8 位，并集 22 位。
- 2026-08 与 2026-09：交集 6 位，并集 24 位。
- 2026-07 与 2026-09：交集 5 位，并集 19 位。
- 三个月都出现：5 位；三个月并集：28 位。

三份快照的可见行全部落在 `腰部` 分层，ACU 范围为 100 至 1,000。这里说的是当前导出结果，不代表目标名单只允许腰部主播；SQL 的最终过滤实际上是 `acu >= 100`，理论上还允许颈部和头部。

## SQL 核心逻辑

运行版 SQL 以 `zhgametemp.zty_ai_liveroom_uid_list_v1` 为目标名单，从主播日表、用户会话表和在线人数表构造主播×品类×月的 ACU、PCU、APP DAU、观时和人均观时；有效主播要求至少 5 个开播日，随后按业务规则剔除 19 个最高观看人数日期，最终输出 ACU 不低于 100 的记录。

静态审查确认了 13 项风险，最需要新电脑先处理的是：

1. `game_full_name != '其他直播'` 位于 `LEFT JOIN` 后，会把未匹配游戏维度一起过滤；需要明确是否应保留未知品类。
2. 有效主播聚合同时按 `luid` 和 `nickname` 分组，昵称变化可拆分开播天数并影响资格。
3. 注释称日均直播时长按 30 天计算，但 1 小时门槛实际使用有开播记录日期的均值。
4. 输出“日均直播时长(h)”是有效日期和品类明细行上的平均，不天然等于 30 个自然日平均。
5. ACU 是筛选小时内的小时均值；`pcu_h > 10` 又会在排名后过滤小时，因此不是无条件“全天 ACU”。
6. 有效日期查询不含 `hmos_kiwi`，但 APP DAU 和观时包含 `hmos_kiwi`，端口样本不一致。
7. 日期、30 天除数、游戏维度和昵称快照均硬编码为 2026-09，换月要修改多处。
8. 上传名单表没有分区、版本、上传时间或 UID 精度证明，执行前必须记录名单哈希与命中率。

`huya_andriod` 虽像拼写错误，但现有虎牙 SQL 长期使用同一源枚举，不能擅自改成 `huya_android`；仍需在下次运行时通过产品字典复核。完整 13 项见 `sql-static-review` 文件。

## 验证状态

快照文件、主播×品类粒度、月份映射、匿名汇总、主播覆盖和隐私边界均可独立复算。SQL 只完成静态审查，没有在授权的 bigdata 环境重跑，也没有把刷新后的目标表与三份导出逐项对账；因此项目总体状态是 `incomplete`，不能标成“SQL 已验证”。

## 新电脑复用步骤

1. 先读本页和 `methodology/analysis-method.md`，区分文件导出日期与数据月份。
2. 可直接复用匿名总览、品类/分层汇总和主播覆盖结果；不要用不同名单的 ACU 均值变化做同一群体的因果解释。
3. 准备本机同名三份 CSV/XLSX 后，运行 `scripts/build_snapshot_review.py --source-root <桌面目录>` 重建匿名结果。
4. 运行 `scripts/validate_snapshot_review.py --source-root <桌面目录> --write-report`；如果 `failed=0` 但仍有 `not_run=1`，说明文件层验证通过、SQL 执行层仍未完成。
5. 正式刷新前，先解决 `sql-static-review` 中所有 `HIGH` 项，并执行注释版 SQL 末尾的名单命中率、月份分布和字段类型检查。

英文版见 `README.en.md`。
