# 六位主播合作前后有效 ACU 复盘

本项目复盘 2026-06-24 至 2026-06-30 的一次主播合作活动。分析对象是 1 位观察主播和 5 位合作主播，比较合作前 31 个自然日、合作期 7 日、合作后 30 日及剔除合作期后的后续 30 日有效 ACU，并同时查看平台基准。

项目迁移的重点不是重新认定合作效果，而是保留可复用的窗口计算、匿名日序列、历史结果复算和已发现的数据勾稽问题。原目录只有 3 份 CSV、1 份 Python 脚本和 1 份含主播身份的结果工作簿；未附底层取数 SQL。

## GitHub 路径地图

| 仓库内路径 | 内容 |
| --- | --- |
| `projects/molata-cooperation-acu-review/README.md` / `.en.md` | 中英文项目背景、结论、风险和复用步骤 |
| `projects/molata-cooperation-acu-review/methodology/analysis-method.md` / `.en.md` | 样本、日期窗口、指标公式、基准定义和已知缺陷 |
| `projects/molata-cooperation-acu-review/artifacts/anonymous-summary/daily_series.csv` / `.zh.csv` | 123 个平台日的匿名主播日序列、组内合计、平台基准和勾稽残差 |
| `projects/molata-cooperation-acu-review/artifacts/anonymous-summary/window_summary.csv` / `.zh.csv` | 13 个统计单位 × 4 个窗口的自然日和开播日日均 |
| `projects/molata-cooperation-acu-review/artifacts/anonymous-summary/growth_comparison.csv` / `.zh.csv` | 合作前后增量、增幅及相对平台基准的百分点差 |
| `projects/molata-cooperation-acu-review/artifacts/anonymous-summary/share_summary.csv` / `.zh.csv` | 六人和合作五人组在四个窗口的平均日份额 |
| `projects/molata-cooperation-acu-review/artifacts/anonymous-summary/reconciliation_failures.csv` / `.zh.csv` | 13 个无法勾稽的日期及偏差 |
| `projects/molata-cooperation-acu-review/artifacts/anonymous-summary/cooperation-acu-anonymous-zh.xlsx` / `-en.xlsx` | 中英文匿名结果工作簿，含方法说明 |
| `projects/molata-cooperation-acu-review/artifacts/anonymous-summary/source-manifest.csv` | 5 个源文件的相对路径、大小、SHA-256 和纳入/排除原因 |
| `projects/molata-cooperation-acu-review/artifacts/anonymous-summary/project-summary.json` | 数据规模、窗口和隐私边界 |
| `projects/molata-cooperation-acu-review/scripts/build_anonymous_review.py` | 从本机源文件重建全部匿名结果，不输出身份字段 |
| `projects/molata-cooperation-acu-review/scripts/validate_review.py` | 独立重算、历史工作簿对账、源哈希、勾稽和隐私校验 |
| `projects/molata-cooperation-acu-review/validation/validation-report.md` / `.en.md` | 校验闸门、结论边界和未完成项 |
| `projects/molata-cooperation-acu-review/validation/validation-report.json` | 21 项机读校验结果 |

以上路径均相对于 GitHub 仓库根目录。

## 数据与窗口

- 源快照：2026-05-01 至 2026-08-31，主播日数据 608 行、6 个主播、121 个有记录日期；主播×日为唯一键。
- 平台基准：123 个日期，日期唯一；另有一份剔除异常高 ACU 账号的基准。
- 合作前：2026-05-24 至 2026-06-23，31 个自然日。
- 合作期：2026-06-24 至 2026-06-30，7 日。
- 合作后 1 月含合作期：2026-06-24 至 2026-07-23，30 日。
- 合作后 1 月剔合作期：2026-07-01 至 2026-07-30，30 日。
- 自然日日均：窗口 ACU 合计 / 窗口全部日历日；主播无记录日按 0 计入组内合计。

## 主要结果

| 指标 | 合作前 | 后 1 月含合作期 | 后 1 月剔合作期 |
| --- | ---: | ---: | ---: |
| 六人合计自然日日均 ACU | 4,813.57 | 5,631.06 | 6,641.35 |
| 六人环比增幅 | - | +16.98% | +37.97% |
| 合作五人组合计自然日日均 ACU | 3,154.13 | 3,078.73 | 3,346.93 |
| 合作五人组环比增幅 | - | -2.39% | +6.11% |
| 全平台自然日日均 ACU | 207,105.51 | 166,869.57 | 170,744.49 |
| 全平台环比增幅 | - | -19.43% | -17.56% |
| 六人平均日份额，分母为剔异常账号全平台 | 3.90% | 4.18% | 4.82% |

观察主播是六人合计增长的主要来源；其自然日日均 ACU 在含合作期的后续 1 月增长 53.81%，在剔除合作期的后续 1 月增长 98.53%。五个合作主播中并非全部上涨，因此“六人合计增长”不能解释成六位主播共同改善。

这些差异与赛事及暑期重叠，只有 6 位主播，没有对照匹配或因果识别设计。正确的表述是“合作窗口前后出现描述性变化”，不能写成“合作导致 Y% 增长”。

## 关键勾稽问题

把平台全量基准减去“剔除六人”基准，本应等于六位主播的当日 ACU 合计。110 个日期的差额不超过 `0.11` ACU，但有 13 个日期不成立：

- 累计偏差：`+14,548.03` 有效 ACU。
- 最大单日偏差：`+4,159.76`，出现在 2026-06-15。
- 7 个日期的单日偏差超过 100 ACU。

由于原目录未保留底层 SQL，无法判断偏差来自主播 ID 映射、重复行、品类过滤还是一个 ID 对应多个主播记录。受影响的平台超额增幅只能标为“待验证”；六位主播自身的日数据、自然日日均和历史工作簿组级增幅仍可独立复算。

## 其他质量发现

1. 原目录没有 SQL，只有导出的 CSV、Python 报表脚本和结果工作簿，无法从原始表重建取数链路。
2. 2026-06-28 和 2026-07-04 没有任何六位主播记录；其他日期也可能只覆盖部分主播。把缺失按 0 处理是原脚本口径，但“未开播”和“数据缺失”未被区分。
3. 全平台中存在一个高 ACU 异常账号，最高会显著改变平台基准，因此额外保留剔除该账号的匿名基准。
4. 后 1 月含合作期与合作期有 7 天重叠；两个后续窗口回答不同问题，不能混用。
5. 原结果工作簿的主播日明细包含主播 ID 和昵称，未上传；仓库只保留角色编号。

## 新电脑复用步骤

1. 先读本页和 `methodology/analysis-method.md`，确认窗口与自然日分母。
2. 可直接复用匿名日序列和四个窗口的组级聚合；引用平台超额增幅前必须先解决 13 个日期的勾稽残差。
3. 如需重跑，准备与本机同版本的 `data/` 三个 CSV，并执行 `scripts/build_anonymous_review.py --source-dir <本地项目目录>`。
4. 执行 `scripts/validate_review.py --source-dir <本地项目目录> --write-report`，确认 `failed=0`。当前状态是 `incomplete`，原因是 1 个勾稽已知问题和 1 项 SQL 缺失未执行。
5. 新增因果结论前必须另行设计对照、平行趋势或匹配方案；本项目的简单前后比较不足以估计合作净效应。

英文版见 `README.en.md`。
