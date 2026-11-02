# 因果推断实操手册迁移复盘

本项目迁移一套面向零基础读者的 PSM（倾向得分匹配）与 SCM（合成控制法）教学材料。它适合作为分析入门、代码脚手架和口径提醒，不是某次真实活动的分析报告，也没有配套业务源数据或已执行结果。

源目录包含 5 个文件：优化版 Markdown、HTML 和 PDF，较早的 DOCX，以及“第零部分”手算深挖文档。经内容核对，第零部分按去除空白后的文本完整包含在优化版 Markdown 中；DOCX、HTML、Markdown 和 PDF 是同一主题的不同版本/渲染格式，不能同时当作四套独立研究结果。

## GitHub 路径地图

| 仓库内路径 | 内容 |
| --- | --- |
| `projects/causal-inference-handbook/README.md` / `.en.md` | 中英文项目背景、方法风险和使用边界 |
| `projects/causal-inference-handbook/methodology/review-notes.md` / `.en.md` | PSM/SCM 方法审查和正式项目复用清单 |
| `projects/causal-inference-handbook/sources/causal-inference-handbook-optimized.md` | 优化版可编辑主文档，含 74 个代码块 |
| `projects/causal-inference-handbook/sources/causal-inference-handbook-optimized.html` | 优化版网页渲染 |
| `projects/causal-inference-handbook/sources/causal-inference-handbook-optimized.pdf` | 优化版 155 页打印版 |
| `projects/causal-inference-handbook/sources/causal-inference-handbook-base.docx` | 较早 DOCX 版本，含 871 个段落和 4 张表 |
| `projects/causal-inference-handbook/sources/zero-hand-calculation.md` | 6 个示例用户的手算全链路；文本包含于优化版 Markdown |
| `projects/causal-inference-handbook/artifacts/source-manifest.csv` | 5 个源文件的大小、SHA-256、角色和版本关系 |
| `projects/causal-inference-handbook/artifacts/method-review.zh.csv` / `.en.csv` | 11 项方法风险、证据和正式项目复用要求 |
| `projects/causal-inference-handbook/scripts/validate_handbook.py` | 校验源哈希、格式可读性、内容覆盖、代码围栏和中英文风险清单 |
| `projects/causal-inference-handbook/validation/validation-report.md` / `.en.md` | 中英文逐项验证报告 |
| `projects/causal-inference-handbook/validation/validation-report.json` | 机读验证结果 |

以上路径均相对于 GitHub 仓库根目录。

## 文档结构

1. 第零部分：使用 6 个用户、2 个特征手算逻辑回归、倾向得分、1:1 匹配、SMD 和 ATT。
2. PSM：逻辑回归、随机森林、LightGBM/GBDT 三种倾向得分估计、匹配、平衡性、ATT 和参数调整。
3. SCM：用 10 个城市、72 个月模拟面板，通过约束优化构造合成对照并计算安慰剂结果。
4. 方法选择：比较 PSM 与 SCM 的适用边界。
5. 附录：环境安装和常见报错。

## 复用时必须修正或补充的地方

- SMD 小于 0.1 是经验阈值，只能说明已测协变量在当前样本中较平衡，不能证明可交换性。还必须检查共同支持、重叠、匹配率和未观测混杂。
- ATT 示例使用独立样本 t 检验，但 1:1 匹配会形成配对；1:N 匹配还可能重复使用控制对象。正式分析应采用与匹配结构一致的配对、聚类稳健或 bootstrap 推断。
- 1:N 与卡尺示例没有完整展示控制对象的复用台账，容易把同一个控制对象重复选入多个匹配集合；必须报告唯一处理数、唯一控制数、替换策略和未匹配处理数。
- SCM 安慰剂示例用其他城市的等权均值作为简化“合成控制”，不是完整的逐单位 SCM 重估。正式分析应使用干预前拟合、donor prevalence、时间安慰剂、留一法和 post/pre RMSPE 比值。
- “有面板数据就优先 SCM”过于简化；设计应取决于处理单位数量、干扰、donor 池合法性和干预前拟合，而不是只看数据形状。
- 文档没有 notebook、依赖锁或执行日志。用于真实分析时应将参数、随机种子、输入快照、执行环境和结果对账一起保存。

完整 11 项见 `artifacts/method-review.zh.csv`。本项目状态是“教育材料已完整迁移并完成内容校验”，不是“示例代码已在真实业务数据上验证”。

## 新电脑复用步骤

1. 需要理解方法时，先读优化版 Markdown；需要打印或分享时使用 PDF 或 HTML。
2. 需要手工跟随计算时，打开 `zero-hand-calculation.md`，它已包含在优化版主文档中。
3. 正式分析前先读 `methodology/review-notes.md`，把 11 项风险转成项目参数和验证卡。
4. 运行 `python projects/causal-inference-handbook/scripts/validate_handbook.py --write-report` 检查文档和源哈希。
5. 不得把文档中的模拟“150 元真实效果”当作业务事实；真实项目必须重新准备源数据、匹配方案和结果对账。

英文版见 `README.en.md`。
