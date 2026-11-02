# 赛事总结与平台份额复核

本项目复盘 2026-09-14 的赛事总结材料，覆盖 LPL、KPL、FISSURE 和 BLAST。目标是让新电脑上的 Codex 在不依赖原主播级工作簿的情况下，理解各赛事 DAU、拉新回流、同比阶段变化和平台主播 ACU 份额，并明确哪些原表结论需要修正。

## GitHub 路径地图

| 仓库内路径 | 内容 |
| --- | --- |
| `projects/event-summary-review/README.md` | 中文项目说明、结论、口径、限制和路径地图 |
| `projects/event-summary-review/README.en.md` | 完整英文版说明 |
| `projects/event-summary-review/scripts/build_event_summary_artifacts.py` | 从原始工作簿独立生成双语匿名汇总的可复现脚本 |
| `projects/event-summary-review/scripts/validate_event_summary_artifacts.py` | 25 项来源、复算、份额闭合、重复、隐私和状态校验 |
| `projects/event-summary-review/artifacts/zh/赛事DAU汇总.csv` | 中文键名版本的赛事 DAU、APP DAU 增量、内容拉新/回流日均值 |
| `projects/event-summary-review/artifacts/zh/赛事DAU对比.csv` | 中文键名版本的同比与赛段环比 |
| `projects/event-summary-review/artifacts/zh/平台份额汇总.csv` | 中文键名版本的原发布值和去重更正平台份额 |
| `projects/event-summary-review/artifacts/zh/重复审计.csv` | 主播级份额源表的日期/赛程/赛事/平台/UID 重复审计 |
| `projects/event-summary-review/artifacts/zh/质量问题.csv` | 已确认的错误、影响范围和状态 |
| `projects/event-summary-review/artifacts/zh/来源清单.csv` | 三个源文件的哈希、保留方式和排除原因 |
| `projects/event-summary-review/artifacts/zh/校验结果.csv` | 25 项校验的中文表头结果 |
| `projects/event-summary-review/artifacts/en/event-dau-summary.csv` | 英文键名版本的赛事 DAU 汇总 |
| `projects/event-summary-review/artifacts/en/event-dau-comparisons.csv` | 英文键名版本的同比与环比 |
| `projects/event-summary-review/artifacts/en/platform-share-summary.csv` | 英文键名版本的原发布值和去重更正份额 |
| `projects/event-summary-review/artifacts/en/duplication-audit.csv` | 重复审计 |
| `projects/event-summary-review/artifacts/en/quality-findings.csv` | 质量问题 |
| `projects/event-summary-review/artifacts/en/source-manifest.csv` | 来源哈希和处置方式 |
| `projects/event-summary-review/artifacts/en/validation-results.csv` | 25 项校验结果 |
| `projects/event-summary-review/artifacts/project_summary.json` | 项目机器可读摘要 |
| `projects/event-summary-review/artifacts/validation_report.json` | 校验总结果：25 项通过、0 失败、0 未执行 |

GitHub 仓库：<https://github.com/Tiany517/huya_ty>

## 结论摘要

DAU 口径是赛事有效日期行上的“全量聚合 APPDAU”简单日均值，不是区间内去重 UV。FISSURE 和 BLAST 源表在数据行下方还有标题和总计块，本项目只接受 `YYYY-MM-DD` 日期行。

| 赛事 | 有效天数 | 日均 DAU | 关键比较 |
| --- | ---: | ---: | --- |
| 2026 LPL 第一赛段 | 40 | 1,015,694.025 | 同比 -29.2109% |
| 2026 LPL 第二赛段 | 48 | 1,137,042.979 | 同比 -30.6324%；较第一赛段 +11.9474% |
| 2026 LPL 第三赛段 | 36 | 1,517,217.472 | 同比 -17.8995%；较第二赛段 +33.4354% |
| 2026 KPL 春季赛 | 56 | 533,729.107 | 同比 -12.4784% |
| 2026 KPL 夏季赛 | 56 | 447,313.232 | 同比 -28.0096%；较春季赛 -16.1910% |
| BLAST 波尔图公开赛 2026 | 11 | 1,063,165.091 | 较 BLAST 伦敦公开赛 2025 +58.0515% |
| FISSURE 裂变天地 3 苏州 | 6 | 286,238.167 | 当前表内无同赛事上届对照 |

LPL 2026 三个赛段同比均为负，但第三赛段 DAU 明显高于前两段。KPL 夏季赛同时弱于 2025 年同期和 2026 年春季赛。BLAST 波尔图公开赛 DAU 高于 2025 伦敦公开赛，但不能仅凭该差值写成赛事单独造成的影响。

## 平台份额

原始份额表按“赛事日期、赛程ID、赛事名称、竞品平台、主播UID”应唯一，实际存在 20 条完全重复的额外行。项目同时保留原发布值 `published_rows` 和去重值 `deduplicated`。后续分析默认应使用 `deduplicated`，并保留 `published_rows` 作为原表追溯。

| 赛事 | 更正平台份额 |
| --- | --- |
| 2026 LPL 第一赛段 | 虎牙 54.3090%，B 站 45.6910% |
| 2026 LPL 第二赛段 | 虎牙 51.7252%，B 站 48.2748% |
| 2026 LPL 第三赛段 | B 站 50.0337%，虎牙 49.9608%，斗鱼 0.0055% |
| 2026 KPL 春季赛 | 虎牙 45.8045%，斗鱼 19.4868%，B 站 18.8516%，快手 11.2113%，抖音 4.6458% |
| 2026 KPL 夏季赛 | 虎牙 48.2088%，斗鱼 22.4243%，B 站 14.7588%，抖音 7.6489%，快手 6.9591% |
| BLAST 波尔图公开赛 2026 | 虎牙 54.9345%，斗鱼 26.6672%，B 站 12.2709%，抖音 6.1275% |

这里的份额来自各平台主播 `主播ACU` 求和后占赛事跨平台主播 ACU 总和的比例，不是平台 DAU 份额。原汇总工作簿有一步用“虎牙 DAU ÷ 虎牙主播 ACU 份额”估算行业 DAU；该步骤不是原始观测值，后续使用应单独标明模型假设。

## 已发现的原表问题

1. `LPL_份额汇总_Final` 把第一赛段的 B 站和虎牙标签对调。原始源表复算为 B 站 `3,251,602.817`、虎牙 `3,909,919.831`；Final 页把两个数放反。当前归档按源表重新计算，不沿用该错误页。
2. 份额源表存在 20 条完全重复的额外行：LPL 2 条、KPL 16 条、BLAST 2 条。重复使 KPL 夏季赛主播 ACU 总和从更正后的 `4,122,499.572` 膨胀到原发布值的 `4,202,229.338`。
3. `KPL_赛事份额_汇总` 的 `I242`、`J242` 为 `#DIV/0!`，位于次级主播贡献块。顶层平台合计能独立复算，未发现该错误影响顶层总份额，但受影响的主播行不可复用。
4. FISSURE 和 BLAST 源表的数据行下方有标题、总计等非日期行，重算时必须按日期格式过滤。
5. 未保留上游 SQL、字段字典和分区记录，因此本复盘证明的是“当前工作簿到匿名汇总”的复算关系，不等同于上游取数链已验证。

## 未上传内容

- 原始 `0914_赛事总结.xlsx`、`0914_赛事总结_汇总.xlsx` 含 UID、昵称和逐主播 ACU，未上传。
- `版权赛事V1_0921.pptx` 含具名主播和逐主播叙事，共 2 页；即使仓库为私有也不上传。哈希和排除原因已记录在来源清单。
- 本项目不上传任何用户级或主播级明细，只保留赛事/平台级匿名汇总、脚本和校验结果。

## 重新生成与验证

```powershell
python scripts/build_event_summary_artifacts.py --source-dir <原赛事总结目录>
python scripts/validate_event_summary_artifacts.py --source-dir <原赛事总结目录>
```

源哈希记录如下：

| 源文件 | SHA-256 |
| --- | --- |
| `0914_赛事总结.xlsx` | `8fa1c7c2f3d8c21582c76413729423302f22030184097ab8eb583c220b066b6e` |
| `0914_赛事总结_汇总.xlsx` | `01fc2b36ee2ec9aa4b46daa5ae5999656f7f5ebb5b43a9ca50d20a2eb3408b00` |
| `版权赛事V1_0921.pptx` | `218809bb42a13796fad2745d80c8bef48ef624ca08d9305265f0bb6bf3860e56` |

项目状态是“已复核，但保留已记录的源表质量问题和上游血缘缺口”。25 项自动校验全部通过，代表归档与已记录源文件、复算结果和隐私边界一致，不代表原业务结论已被上游 SQL 独立证明。

英文版见 `README.en.md`。
