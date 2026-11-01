# 快手王者荣耀主播反挖筛选复盘

本项目复盘 2026 年围绕快手《王者荣耀》主播的反挖筛选、条件迭代和虎牙侧潜力估算。目标是把能支持后续工作的规则、匿名统计、版本差异、已知缺陷和复现脚本迁移到新电脑，同时明确哪些结论只是筛选或模型估计，哪些结论已经由数据重建验证。

“反挖”在这里指外部主播发现和候选筛选，不代表主播已接触、签约或迁入虎牙。虎牙 ACU、月薪和收入字段均为历史启发式预测，不是主播在虎牙的真实结果。

## GitHub 路径地图

| 仓库内路径 | 内容 |
| --- | --- |
| `projects/kuaishou-honor-of-kings-reverse-poaching/README.md` / `README.en.md` | 中文 / 英文项目背景、核心结果、迁移边界和复用步骤 |
| `projects/kuaishou-honor-of-kings-reverse-poaching/methodology/reverse-poaching-rules.md` / `.en.md` | 数据粒度、计算公式、候选规则、版本时间线、模型字段和限制 |
| `projects/kuaishou-honor-of-kings-reverse-poaching/artifacts/anonymous-summary/` | 中英文匿名候选集、规则复算、月度画像、虎牙腰部基准、源覆盖和版本对照 |
| `projects/kuaishou-honor-of-kings-reverse-poaching/artifacts/validation-report.json` | 最近一次自动校验的完整机读结果 |
| `projects/kuaishou-honor-of-kings-reverse-poaching/validation/validation-report.md` / `.en.md` | 中文 / 英文结果契约、风险画像、26 项校验和未验证边界 |
| `projects/kuaishou-honor-of-kings-reverse-poaching/scripts/inspect_fanwa_workbooks.py` | 只读检查 6 个工作簿的工作表、行列、表头和合并单元格 |
| `projects/kuaishou-honor-of-kings-reverse-poaching/scripts/compare_fanwa_versions.py` | 比较历史候选集、文件哈希和相邻版本流转 |
| `projects/kuaishou-honor-of-kings-reverse-poaching/scripts/diagnose_fanwa_rules.py` | 从原始 CSV 独立重建月度指标并反向匹配候选规则 |
| `projects/kuaishou-honor-of-kings-reverse-poaching/scripts/build_anonymized_summary.py` | 生成中英文匿名汇总和源文件清单 |
| `projects/kuaishou-honor-of-kings-reverse-poaching/scripts/validate_kuaishou_fanwa_project.py` | 校验源哈希、候选人数、月度复算、版本一致性、匿名化和双语结构 |

以上路径均相对于 GitHub 仓库根目录；文件拼到 `blob/main/`，目录拼到 `tree/main/`。

## 数据版本与覆盖

源目录包含 6 个 XLSX、2 个约 102–130 MB 的原始 CSV 和 1 个 623 B 的虎牙月度 ACU 汇总。原始 CSV 只含快手《王者荣耀》记录。

| 数据版本 | 原始行数 | 唯一主播数 | 主播月记录数 | 月份 |
| --- | ---: | ---: | ---: | --- |
| V1 | 453,551 | 327,768 | 431,103 | 2026-05 至 2026-08 |
| V2 | 579,868 | 402,290 | 551,212 | 2026-04 至 2026-08 |

V2 比 V1 多 74,522 个主播，主要来自新增的 2026-04。2026-05 至 2026-08 的共同月份中，V1 与 V2 各月的有效主播数、月 ACU、日均开播分钟和实际天数完全一致；最大浮点差异约 `7.28e-12`。

源表同一主播月可能有多行，原因是 `r_owner` 不同：V1 有 22,448 条额外行，V2 有 28,656 条。历史工作簿按 `actual_days` 对 ACU 加权，并按实际天数计算日均开播分钟。该公式能够逐行复现 3 个工作簿的“月度计算明细”，但 `r_owner` 的业务含义和是否应在主播层去重没有字段字典，仍需新电脑复查。

## 候选集与关键结论

| 工作簿 / 版本 | 候选数 | 复核结论 |
| --- | ---: | --- |
| 早期 5–7 月模型初筛 | 53 | 全部满足 ACU 严格下降和 7 月/5 月日均开播分钟 >=80%，但全量规则总体有 1,190 人，额外截断到 53 人的规则未记录 |
| 旧版条件汇总 | 43 | 文件名声称“连续下降”，实际只等同 `ACU>100 + 6/5、7/6 开播比例>=80%`；43 人中只有 15 人真正严格下降 |
| 旧版指定列名结果 | 15 | 15 个候选与 V2 最终 15 人完全一致 |
| V2 条件汇总 | 15 | 精确满足 5–7 月 ACU>100、严格下降、6/5 和 7/6 日均开播分钟比例>=80% |
| V2 最终指定列名结果 | 15 | 与 V2 条件汇总相同，作为本次复盘的最终口径 |
| V2 四个月 50% 情景 | 8 | 当前 CSV 精确复现全部 8 人；先前草稿的 7/8 判断已被独立复算推翻 |

早期 53 人并不是“ACU>100”的名单：只有 16 人在 5–7 月都高于 100，且月度 ACU 最小值最低只有 `0.45–9.66`。因此早期名单只能作为未完整定义的历史中间结果。

V2 最终 15 人的月度 ACU P50 分别为 354.18、361.06、331.18 和 239.90（2026-04 至 2026-07）；日开播分钟 P50 为 348.16、330.97、343.85 和 339.31。完整分位见 `artifacts/anonymous-summary/candidate-month-profile.csv`。

## 虎牙腰部基准对照

把 V2 最终 15 人分别与实际快手 ACU、历史虎牙预测 ACU同虎牙《王者荣耀》腰部主播月均值比较：

| 月份 | 虎牙腰部 ACU | 实际 ACU P50 | 实际高于腰部人数 | 预测 ACU P50 | 预测高于腰部人数 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 2026-05 | 529.32 | 361.06 | 5 / 15 | 650.00 | 12 / 15 |
| 2026-06 | 542.86 | 331.18 | 5 / 15 | 600.00 | 11 / 15 |
| 2026-07 | 562.49 | 239.90 | 3 / 15 | 550.00 | 7 / 15 |

三个月实际都高于腰部基准的主播为 3 人，按预测值则为 7 人。这个差异提示模型在本次候选中相对乐观，但不能直接判定预测错误，因为预测没有与这些主播在虎牙的真实后续 ACU 对账。

V2 最终 15 人的预测年收入 P50 为 CNY 158,400。`huya_predict_laxin` 和 `huya_predict_yingshou` 在相关源数据中全为空，不能用于本次结论。候选预测数据有 46 行、45 个主播月；唯一的重复主播月三组预测值完全相同，汇总时按主播月去重，结果不受影响。

## 迁移边界

本仓库不复制原始 CSV 和 6 个含主播 ID、昵称、owner 或逐人预测的 XLSX，只保留：

- 去标识的月度分位、候选人数、版本重合和规则复算。
- 源文件名称、大小、SHA-256、处理方式和排除原因。
- 工作簿结构清单，不含单元格级主播信息。
- 可重复运行的分析和校验脚本。

源目录保持不变。大型原始 CSV、用户级或主播级明细、缓存和二进制中间产物均不进入 GitHub。

## 校验

在仓库根目录运行：

```powershell
python projects/kuaishou-honor-of-kings-reverse-poaching/scripts/validate_kuaishou_fanwa_project.py `
  --source-dir '<快手反挖源目录>' `
  --write-report
```

没有源目录时，脚本仍可检查仓库内匿名附件，但会把源依赖项标记为 `not_run`，整体状态为 `incomplete`，不会错误标记为已验证。

本次在本机源目录上执行结果：`26/26` 通过，源依赖校验已执行。校验覆盖文件哈希、原始覆盖、候选人数、旧版 43 人缺陷、V2 15 人精确规则、四个月 8 人精确规则、V1/V2 共同月份一致性、3 个工作簿月度明细复算、重复预测行、虎牙基准、匿名化和双语文档结构。

## 新电脑复用步骤

1. 先读本文件和 `methodology/reverse-poaching-rules.md`，不要把预测 ACU 或预测年收入当成虎牙实测。
2. 用 `source-manifest.csv` / `source-manifest.en.csv` 和 `source-coverage.csv` 确认恢复的是同一数据版本；若有新 CSV，先检查月份、行数、单位、重复 owner 行和空值。
3. 重新确认 `kuaishou_avg_acu`、`kuaishou_live_mins`、`actual_days` 和 `r_owner` 的业务定义。
4. 若继续筛选，先固定结果契约：主播月粒度、owner 处理、共同月份、ACU 门槛、日均开播比例和缺失月份规则。
5. 更新候选后，至少独立重算 V2 15 人规则和一个反例，再与新结果对账；不能用同一段 Python 代码自证。
6. 只有取得候选在虎牙的真实后续 ACU、观时和收入后，才能评估反挖模型或招募效果。

英文版见 `README.en.md`。
