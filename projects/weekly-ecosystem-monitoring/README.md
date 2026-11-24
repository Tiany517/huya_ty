# 周报生态监控

状态：2026-11-24 已新增可交互 HTML 看板和完整刷新工作流；历史匿名快照继续保留。原始 CSV、构建 JSON 和大体量工作目录不进入 Git。

## 最新互动看板（2026-11-24）

最新交付快照位于 `interactive-dashboard-20261124/`，入口为该目录的 `README.md` 和 `RELEASE_NOTES.md`。内容包括：

- 单文件 HTML 看板：`interactive-dashboard-20261124/dashboard/生态监控看板_多维度MVP_新增开播主播数_2026-11-24.html`。
- 口径与 SQL 资源工作簿、全流程文档、生产 SQL、构建/验证脚本和跨电脑刷新 Skill。
- W47 的 13/13 数据检查、171/171 源表独立复算、8/8 开播主播数 UI 专项和浏览器冒烟证据。

该 HTML 内嵌主播级聚合数据和 UID、昵称、RoomID，仅限当前私有仓库和本机使用。三类原始核心 CSV、看板 JSON 和用户级明细未上传。

## 项目背景

这套流程用于按周观察虎牙游戏内容生态，核心是把日级品类数据转换成周度变化、品类归因、主播下钻和管理层可读的结果页。当前归档覆盖 2026-08-31 至 2026-10-11 的六个周度品类快照，并保留从最终展示流程提取的小型品类总览与 2026-10-13 结果快照。

项目主要用于回答：

1. 各游戏品类本周 DAU、打赏、归因和兴趣用户相对上周如何变化。
2. 哪些主播或品类对公司生态的贡献更集中。
3. 王者荣耀等重点品类中，哪些主播达到 ACU 阈值，赛事日是否影响比较。
4. 如何把日级查询结果稳定写入一套周度展示模板。

本页中的数字用于证明迁移文件可追溯和可复算，不是脱离时间、品类与总体范围的长期业务结论。

## 最新已校验快照

最新匿名品类快照覆盖 `2026-10-05` 至 `2026-10-11`，共 7 个连续自然日、22 个品类，另含“整体”行，共 154 行。

| 指标 | 独立重算值 | 结果工作簿位置 | 状态 |
| --- | ---: | --- | --- |
| 整体日均观看 DAU | 3,627,835.428571 | `品类总览!J14` | 一致 |
| 整体日均归因人数 | 4,338,349.285714 | `品类总览!Q14` | 一致 |
| 平台当前周 DAU | 4,338,349.286 | 平台快照 | 与整体归因人数在数值上相等，但口径仍需重跑复核 |
| 平台周变化 | -106,756.5714 | 平台快照 | 可由 `current_week_dau - last_week_dau` 重建 |
| 人均打赏流水最大重建误差 | 约 `2.98e-08` | 7 个整体日行 | 通过 |

## 指标口径

### 品类 DAU 与观时

- 源粒度是用户、日期和品类；先按 `dt + user_ukey + game_name` 合并同用户当天在同品类的会话时长。
- DAU 使用 `count(distinct user_ukey)`。
- 人均观时按 `user_duration / 1000 / 60 / DAU` 计算，其中会话时长原始单位为毫秒。
- “整体”行从整体日粒度独立去重，不能把各品类 DAU 直接相加，因为同一用户可能观看多个品类。

### 打赏

- 仅保留 `user_consume_amount > 0` 的有效流水记录。
- 打赏流水按品类日汇总；打赏人数使用 `count(distinct ext['ukey'])`。
- 人均打赏流水为 `打赏流水 / 打赏人数`。
- 零流水与缺失数据不能混为一谈；当前结果 SQL 对无匹配记录使用 0，新电脑重跑时应结合源分区情况再确认这一处理。

### 归因与兴趣用户

- 归因人数来自 `cwq_huya_ukey_shichang_luid_gameid_guishu_day_v1`，按 `dt + game_name + user_ukey` 去重。
- 兴趣用户数来自 `cwq_huya_7days_xqzs_detail_tmp`，当前 SQL 对 `user_pro` 求和。
- “非 LOL 兴趣用户数”排除 `gameid = 1`。该字段的业务定义仍应在新电脑用字段字典复核。

### 主播下钻

- 主播日粒度为 `dt + game_name + luid`。
- 主播明细按 `dt + game_name + luid` 关联 DAU、打赏、归因和兴趣指标。
- 未匹配到开播主播的记录被汇总到 `__UNATTRIBUTED__` 行。该行的打赏人数和归因人数是把各主播日值相加，不能当作跨主播独立去重后的品类总数。
- 主播下钻结果含 UID、昵称和逐主播数据，因此不进入本仓库。

## SQL 链路

### 品类日级与周报底表

`scripts/category-weekly-metrics.sql` 是最主要的周报底表 SQL。它分别构造：

1. 游戏 ID 到展示品类的映射快照。
2. 用户日品类会话与 DAU。
3. 品类日打赏和整体日打赏。
4. 品类日归因和整体日归因。
5. 兴趣用户。
6. 品类结果行与“整体”结果行。

归档 SQL 的周窗口是 `2026-08-31` 至 `2026-09-06`，品类映射快照日期是 `2026-09-06`。这两个日期是硬编码调试值，不能直接用于新一周。更新时必须同时处理：

1. 源事实表起止日期。
2. 游戏映射快照的分区。
3. 展示模板的周窗口与最新完整分区。
4. `week/between` 等派生字段。

### 读模型

- `scripts/category-daily-read-model.sql`：从日级生态健康表读取指定周的品类总览数据。
- `scripts/anchor-drilldown-read-model.sql`：读取上一周主播下钻数据；归档日期窗口为 `2026-08-24` 至 `2026-08-30`。

两个读模型都硬编码了周窗口和核心品类 ID。使用时先确认目标周和依赖表分区，不能直接复用旧日期。

### 主播下钻构建

`scripts/anchor-drilldown.sql` 同时产出：

- 主播日明细。
- 未匹配开播主播的补充行。
- 品类整体行。

该 SQL 的口径风险高。任何 `join` 都必须先检查左右粒度唯一性；补充行中的 `daily_pay_user_cnt` 和 `daily_attribution_user_cnt` 按主播相加时可能重复计人。补充行只能用于解释未匹配金额或人数，不能直接当作跨主播去重总数。

### 平台 DAU

`scripts/platform-dau.sql` 从带 SDK 的活跃用户表按周计算日均 DAU。归档 SQL 使用 `2026-08-24` 至 `2026-09-06` 的调试窗口，输出上周和本周两个值。它与品类整体归因人数的业务定义不同，不能因为某周数值相等就认定两套口径相同。

### 王者 Top 20 示例

- `scripts/top20-honor-of-kings-dau-acu.sql`：按两个连续周比较王者主播的 ACU、DAU、归因和兴趣用户。
- `scripts/top20-honor-of-kings-dau-acu-excluding-events.sql`：先排除赛事日，再按月聚合。

赛事日来自版权赛事维表。归档 SQL 的赛事维表快照日期和月份筛选同样是硬编码，刷新时必须重新检查赛事覆盖和 union 粒度。

## 展示模板与公式链

迁移包只保留了从展示流程中提取的小型结果文件：`artifacts/weekly-results/final-presentation-template.xlsx` 是单页 `品类总览` 快照，约 85 行 × 17 列，无公式；`artifacts/weekly-results/weekly-result-20261013.xlsx` 是单页 `品类总览` 结果快照，约 91 行 × 21 列，含 2 个差值/环比公式。两份文件都约 26 KB。

本机源展示模板共 22 个工作表。已扫描的汇总与归因工作表约有 116,177 个公式单元格；6 个主播数据源工作表包含约 280 万个明细行。源模板、完整公式页和主播明细都没有进入上传范围，仓库仅保留结构清单与小型品类总览快照。

已扫描的主要工作表：

- `各品类的DAU和打赏情况`：日级品类汇总和派生周字段。
- `品类总览`：品类 DAU、打赏、归因及均值。
- `品类归因`：周度结构与趋势。
- 英雄联盟、王者荣耀、CS2、体育、无畏契约、户外的总览和归因页：主播层指标及趋势。

完整工作表、行列数和公式数量见 `artifacts/template-structure.csv`。

源模板中发现标题问题：`王者总览!B1` 和 `户外归因!B1` 当前显示“英雄联盟”。这可能是复制模板时残留的错误标题，新电脑应从本机恢复源模板后人工确认并修复；上传的单页品类总览快照不含这两个工作表，本轮没有修改原工作簿。

## 已上传与未上传边界

### 已上传

- 9 个 SQL 和 Python 脚本。
- 6 个匿名品类周度 CSV。
- 5 个匿名平台 DAU 快照。
- 2 个小型工作簿快照。
- 模板结构、周表清单、平台文件清单和中英文校验记录。
- 可重复运行的 `scripts/validate_weekly_snapshots.py`。

### 未上传

- `生态监控模板_1013.xlsx` 等约 186 至 291 MB 的源工作簿。
- 6 个主播日级数据源工作表，其中含主播 UID、昵称和逐主播明细。
- 5 至 7 MB 的品类主播下钻 CSV。
- 其他未复核的大型模板、缓存和中间文件。

本轮没有修改任何源工作簿，也没有把用户级或主播级明细推送到 GitHub。

## 校验状态

`scripts/validate_weekly_snapshots.py` 会重新生成四个中英文清单和校验附件。当前结果：

| 检查 | 状态 | 结果 |
| --- | --- | --- |
| 六个品类周表结构 | 警告 | 均为 7 个连续自然日、22 个品类、154 行、无重复键和解析失败；4 个早期文件含 Excel 展示格式占位 |
| 最新周整体 DAU | 通过 | CSV 独立均值与 `J14` 一致 |
| 最新周整体归因人数 | 通过 | CSV 独立均值与 `Q14` 一致 |
| 平台当前周 DAU | 通过 | 与整体归因人数在数值上一致，但定义仍需复核 |
| 平台周变化 | 通过 | 可由两周指标独立重建 |
| 人均打赏流水 | 通过 | 最大绝对误差约 `2.98e-08` |
| 历史平台文件结构 | 警告 | 存在重复快照和一次手工导出格式 |

校验只证明当前匿名 CSV、两个结果工作簿和平台快照之间的连续性。它不能替代新电脑上对源表分区、字段字典和业务定义的重跑验证。

## 已知数据问题

1. `platform-active-20260923-copy-of-20260914.csv` 与 `platform-active-20260914.csv` 的 SHA256 完全相同。20260923 文件很可能是漏更新后复制，不能视为真实的新一周数据。
2. `platform-active-20261008-exported.csv` 是手工 Excel 导出，表头有多余空列、空行和格式化百分比；同目录其他文件是干净的三列表。
3. 20260907、20260914、20260923、20261008 四个品类 CSV 中，`非LOL兴趣用户数` 含 `-` 占位和空单元格。脚本将这些值保留为缺失，不擅自转为 0。
4. `王者总览!B1` 和 `户外归因!B1` 的标题疑似复制错误。
5. 主播未归属补充行中的人数不能跨主播相加。
6. 平台活跃 DAU 与整体归因人数在本周相等，但没有字段级证据证明二者同口径。

## 在新电脑上继续

1. 克隆仓库后进入 `projects/weekly-ecosystem-monitoring/`。
2. 使用仓库外保存的本机路径映射，把项目对应回 `Desktop/周报监控模型`。
3. 先运行 `python scripts/validate_weekly_snapshots.py`，确认归档和结果工作簿一致。
4. 用数据平台确认 6 个源表的最新分区、字段单位和权限。
5. 更新 SQL 中的周窗口、映射快照日期和赛事维表日期，不直接沿用归档调试值。
6. 先产出日级匿名品类 CSV，再与结果工作簿的总览指标对账，最后生成展示工作簿。
7. 对所有 `join`、`union all`、`__UNATTRIBUTED__` 行和共同分母执行 SQL 验证工作流。
8. 修复模板标题后，另存新版本，不覆盖原始模板。

## GitHub 路径地图

| GitHub 路径 | 内容 |
| --- | --- |
| `projects/weekly-ecosystem-monitoring/README.md` | 中文项目说明和路径地图 |
| `projects/weekly-ecosystem-monitoring/README.en.md` | 英文项目说明和路径地图 |
| `projects/weekly-ecosystem-monitoring/scripts/category-weekly-metrics.sql` | 品类日级、周报底表和整体去重逻辑 |
| `projects/weekly-ecosystem-monitoring/scripts/category-daily-read-model.sql` | 品类日级读模型 |
| `projects/weekly-ecosystem-monitoring/scripts/anchor-drilldown.sql` | 主播下钻、未归属补充行和品类整体行 |
| `projects/weekly-ecosystem-monitoring/scripts/anchor-drilldown-read-model.sql` | 主播下钻读模型 |
| `projects/weekly-ecosystem-monitoring/scripts/platform-dau.sql` | 平台两周日均 DAU |
| `projects/weekly-ecosystem-monitoring/scripts/top20-honor-of-kings-dau-acu.sql` | 王者 Top 20 两周比较示例 |
| `projects/weekly-ecosystem-monitoring/scripts/top20-honor-of-kings-dau-acu-excluding-events.sql` | 排除赛事日后的王者主播月度示例 |
| `projects/weekly-ecosystem-monitoring/scripts/csv_to_excel.py` | CSV 清洗和 Excel 转换辅助脚本 |
| `projects/weekly-ecosystem-monitoring/scripts/validate_weekly_snapshots.py` | 快照、工作簿和平台文件的可重复校验脚本 |
| `projects/weekly-ecosystem-monitoring/artifacts/weekly-category/` | 6 个匿名品类周度 CSV |
| `projects/weekly-ecosystem-monitoring/artifacts/platform-dau/` | 5 个匿名平台 DAU 快照 |
| `projects/weekly-ecosystem-monitoring/artifacts/weekly-results/` | 单页品类总览模板快照和 2026-10-13 结果快照；完整源模板未上传 |
| `projects/weekly-ecosystem-monitoring/artifacts/template-structure.csv` | 中文模板结构与公式清单 |
| `projects/weekly-ecosystem-monitoring/artifacts/template-structure.en.csv` | 英文模板结构与公式清单 |
| `projects/weekly-ecosystem-monitoring/artifacts/weekly-validation.csv` | 中文校验记录 |
| `projects/weekly-ecosystem-monitoring/artifacts/weekly-validation.en.csv` | 英文校验记录 |

以上路径都相对于 GitHub 仓库根目录。新电脑上的 Codex 应优先读取 `README.md`、`scripts/` 和校验附件，再决定是否从本机恢复被排除的源工作簿。

英文版见 `README.en.md`。
