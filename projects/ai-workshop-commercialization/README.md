# AI 工坊商业化价值分析

## 项目目的

回答 AI 工坊是否在用户原有直播行为之外带来可识别的商业化增量，并拆解增量来自哪里、哪些用户和直播场景更敏感、哪些结论只能作为描述性证据。

核心问题：

1. AI 礼物曝光并支付后，用户后续打赏金额、打赏次数、活跃和观看行为是否提升。
2. 增量主要来自 AI 礼物本身，还是来自随后增加的普通礼物流水。
3. 礼物语义、直播间 ACU 和品类如何影响使用与商业化。
4. AI 工坊的商业模型能否在明确成本和覆盖假设下用于业务估算。

## GitHub 路径地图

| 内容 | GitHub 路径 |
| --- | --- |
| 中文项目说明 | [`projects/ai-workshop-commercialization/README.md`](https://github.com/Tiany517/huya_ty/blob/main/projects/ai-workshop-commercialization/README.md) |
| 英文项目说明 | [`projects/ai-workshop-commercialization/README.en.md`](https://github.com/Tiany517/huya_ty/blob/main/projects/ai-workshop-commercialization/README.en.md) |
| PSM7 最终报告 | [`artifacts/final-report/ai-workshop-psm7-f2-report.xlsx`](https://github.com/Tiany517/huya_ty/blob/main/projects/ai-workshop-commercialization/artifacts/final-report/ai-workshop-psm7-f2-report.xlsx) |
| PSM8 A/B 报告 | [`artifacts/final-report/ai-workshop-psm8-ab-did-report.xlsx`](https://github.com/Tiany517/huya_ty/blob/main/projects/ai-workshop-commercialization/artifacts/final-report/ai-workshop-psm8-ab-did-report.xlsx) |
| 最终单页 | [`artifacts/final-slides/ai-workshop-commercial-value-20260921.pptx`](https://github.com/Tiany517/huya_ty/blob/main/projects/ai-workshop-commercialization/artifacts/final-slides/ai-workshop-commercial-value-20260921.pptx) |
| 版本转换率报告 | [`artifacts/version-analysis/ai-workshop-version-conversion-report.xlsx`](https://github.com/Tiany517/huya_ty/blob/main/projects/ai-workshop-commercialization/artifacts/version-analysis/ai-workshop-version-conversion-report.xlsx) |
| 版本日明细 | [`artifacts/version-analysis/ai-workshop-version-daily-detail.csv`](https://github.com/Tiany517/huya_ty/blob/main/projects/ai-workshop-commercialization/artifacts/version-analysis/ai-workshop-version-daily-detail.csv) |
| 倾向得分匹配图 | [`artifacts/charts/`](https://github.com/Tiany517/huya_ty/tree/main/projects/ai-workshop-commercialization/artifacts/charts) |
| 匿名品类、ACU 和曝光汇总 | [`artifacts/anonymous-summary/`](https://github.com/Tiany517/huya_ty/tree/main/projects/ai-workshop-commercialization/artifacts/anonymous-summary) |
| 礼物人工打标冻结口径 | [`methodology/gift-tagging-rules-v6-frozen.md`](https://github.com/Tiany517/huya_ty/blob/main/projects/ai-workshop-commercialization/methodology/gift-tagging-rules-v6-frozen.md) |
| 礼物人工打标英文口径 | [`methodology/gift-tagging-rules-v6-frozen.en.md`](https://github.com/Tiany517/huya_ty/blob/main/projects/ai-workshop-commercialization/methodology/gift-tagging-rules-v6-frozen.en.md) |
| 核心 SQL | [`scripts/ai-gift-psm-user-revenue-breakdown.sql`](https://github.com/Tiany517/huya_ty/blob/main/projects/ai-workshop-commercialization/scripts/ai-gift-psm-user-revenue-breakdown.sql) |
| 打标、版本和 PSM 脚本 | [`scripts/`](https://github.com/Tiany517/huya_ty/tree/main/projects/ai-workshop-commercialization/scripts) |
| 自动校验结果 | [`artifacts/validation-report.json`](https://github.com/Tiany517/huya_ty/blob/main/projects/ai-workshop-commercialization/artifacts/validation-report.json) |

匿名汇总文件：

- `ai-gift-primary-category-summary.csv`：一级类目送礼次数、人数、金额、礼物数和占比。
- `ai-gift-secondary-category-summary.csv`：二级类目相同指标。
- `ai-vs-regular-gift-category-flow.csv`：AI 礼物与普通礼物按品类的流水分组。
- `ai-vs-regular-gift-category-acu-flow.csv`：AI 礼物与普通礼物按品类和 ACU 分桶的流水。
- `ai-workshop-category-exposure.csv`：品类曝光、点击、支付和转换率。
- 以 `.en.csv` 结尾的文件字段名为英文，数值与中文文件相同。

## PSM7 主分析

来源：`AI工坊PSM7_真实AI支付_F2_PSM_DID_首次cohort_未剔除异常值.xlsx`。

| 项目 | 口径 |
| --- | --- |
| 分析周期 | 2026-07-13 至 2026-08-17；正式排除 2026-08-14、2026-08-15 |
| 样本粒度 | 首次 cohort 用户级一行，每个 `UKEY` 只保留窗口内首次 cohort |
| 实验组 | AI 工坊曝光且真实支付 AI 礼物 |
| 对照组 | 同 cohort 日期、未 AI 曝光且未 AI 支付；全窗口与实验组 `UKEY` 不重叠 |
| 匹配方法 | 分层最近邻匹配；主方案 F2 的 `caliper=0.15 × 分层 logit 标准差` |
| 匹配结果 | 1,804 对；实验组覆盖率 43.5959%；最大绝对 SMD 0.03956 |
| 平衡性 | 所有前置特征匹配后 SMD 均低于 0.1 |
| 异常值 | 保留全部用户，不做 P99 剔除 |

后 7 日整体打赏金额：

| 指标 | 数值 |
| --- | ---: |
| 实验组前置日均 | 79.8884 元/人/日 |
| 实验组后置日均 | 159.7473 元/人/日 |
| 对照组前置日均 | 49.5343 元/人/日 |
| 对照组后置日均 | 44.3965 元/人/日 |
| PSM-DID | 84.9967 元/人/日 |
| DID / 实验组前值 | 106.39% |
| 95% CI | 46.3997 至 123.5937 |
| p 值 | 1.652e-05 |

后 7 日付费留存必须区分“原始组间差”和“DID 净差”：

| 指标 | 实验组 | 对照组 | 原始组间差 | DID 净差 |
| --- | ---: | ---: | ---: | ---: |
| 整体打赏留存率 | 73.28% | 40.52% | +32.76pp | +22.12pp |
| AI 礼物打赏留存率 | 21.34% | 0.22% | +21.12pp | +20.95pp |
| 普通礼物打赏留存率 | 71.67% | 40.52% | +31.15pp | +20.51pp |

解读：报告支持 AI 工坊对打赏金额、打赏次数和部分观看行为有正向净效应；但“+32.76pp”不是 DID，而是未扣除对照组自然变化的原始组间差。对外引用时必须写清是哪一种差异。

## PSM8 A/B 分析

来源：`PSM8_A_B_DID报告_caliper005.xlsx`。

- 实验组为 AI 曝光且支付，候选 4,138 人。
- 对照组为 AI 曝光未支付，候选 3,520 人。
- 首次 cohort、同日期、1:1 最近邻、控制组不复用，`caliper=0.05` logit。
- 匹配 3,520 对，实验组覆盖率 85.07%。
- 后 6 日总打赏金额 DID 为 169.64 元，p=0.0490。
- AI 礼物打赏金额 DID 为 38.47 元，p=0.0119。
- 普通礼物打赏金额 DID 为 131.17 元，p=0.1170，不能单独宣称显著。

PSM8 回答的是“曝光后支付与曝光后未支付”的差异，PSM7 回答的是“AI 曝光支付与未曝光未支付”的差异。两者样本和对照结构不同，不能把两套 DID 数值混成一套结论。

## 版本转换率

来源：`AI工坊_版本周日均转换率_20260713-20260914.xlsx`。

- 样本为 AI 工坊 App 端 8 个白名单版本：13.3.82、13.4.0、13.4.2、13.4.22、13.4.40、13.4.41、13.4.52、13.4.63。
- 时间范围 2026-07-13 至 2026-09-14，共 64 个自然日。
- 周口径为从 07-13 起每 7 天一周，共 10 行；最后一周只有 09-14 一天。
- 日均转换率 = 逐日 `当日支付人数 / 当日曝光人数` 的算术平均；曝光人数为 0 的天不参与平均。
- 累计转换率 = 周合计支付人数 / 周合计曝光人数，不能与日均转换率混用。
- 8 个版本长期共存，版本效应和时间效应高度共线，只能读趋势，不能把版本差异直接解释成版本升级的因果效果。

## 礼物人工打标

- 冻结口径覆盖 5,592 行 AI 礼物明细，时间窗为 2026-07-13 至 2026-09-14。
- 一级与二级类目词表已冻结；判定必须逐行阅读礼物名称、用户提示词和主播上下文。
- 脚本只用于排队、取数、交叉核对、回填和统计，不能用关键词规则自动替换人工判断。
- 不确定案例必须标“存疑”；庆生题材、房间母题、同字巧合和跨房间人名按冻结版规则裁决。
- 最终匿名汇总覆盖 13 个一级类目和 26 个二级类目；累计送礼次数 19,989、送礼人数 13,425、消费金额 3,838,953.4 元、去重礼物数 3,591。

完整礼物级明细、礼物 ID、提示词和逐主播明细不放入 Git。

## 商业结论与证据边界

最终单页采用的业务估算是：平台日均增量流水约 2.0 万元，按约 500 元/日的推送带宽成本计算，ROI 约 40；成本暂不含 VAP 合成等其他机器成本。该页还给出“覆盖 10% 的主播则日均增量流水约 11.2 万元”的情景估算。

需要保留的限制：

1. 最终报告的后 7 日整体打赏金额 PSM-DID 点估计为 84.9967 元/人/日；单页商业模型使用 81 元/用户天。两者未在现有仓库材料中完成逐项勾稽，复用商业估算前应先确认 81 元来自哪个版本、四舍五入还是另一组样本。
2. 业务单页写 ROI 约 40，旧版 `专题交付.pptx` 与 `9月直播打赏V10.pptx` 中出现 ROI 17.9/18 等不同版本。当前迁移只保留较新的单页 V7，并将旧版差异列为待复核，不把多个 ROI 同时当作正式结论。
3. “日均增量流水”是“累计去重付费用户天 × 人均日增量”的业务外推，不是已实现的现金收入，也不是平台净收入。
4. 成本只计入约 500 元/日的推送带宽，不含 VAP 合成、人力和失败重试等其他成本，因此 ROI 是局部口径。
5. AI 工坊数据缺少完整曝光、点击和来源字段时，只能分析已有订单、反馈和礼物结构，不能把描述性结构直接写成推荐系统增量。
6. PSM 只能平衡已观测的前置特征，不能消除未观测混杂；DID 也不能自动排除同期活动、直播间热点和其他运营变化。

## 上传与未上传边界

已上传：

- 两份聚合 PSM 报告、版本报告、最终单页和 PSM 匹配质量图。
- 匿名一级/二级类目、品类流水、ACU 流水和曝光汇总。
- 核心 SQL、打标、版本转换、PSM8 及匿名化/校验脚本。
- 礼物打标冻结口径。

未上传：

- 约 27.6 GB `.pkl` 缓存和约 11.76 GB PSM 源 CSV。
- 用户级 `By天By用户`、`matches_*`、曝光用户和支付用户明细。
- 含主播 UID、昵称、逐主播流水或礼物提示词的原始工作簿。
- 礼物级 `item_id` 明细、原始提示词和人工批次队列。
- `~$` 临时锁文件、中间日志和 `__pycache__`。

这些排除项不影响理解项目方法、核心结论和匿名汇总，但意味着新电脑不能在缺少原机器缓存的情况下逐用户重跑 PSM7。复现脚本保留在 `scripts/`，读取的字段和算法仍可审计。

## 校验

运行：

```powershell
python scripts/validate_ai_project.py
```

校验内容包括：关键文件存在、PSM7 样本和 DID 数值、PSM8 样本数值、版本日期范围与版本数、最终单页页数和关键词、匿名 CSV 禁止字段及关键行数。脚本只读取仓库内匿名附件，不读取原始用户数据。

英文版见 `README.en.md`。
