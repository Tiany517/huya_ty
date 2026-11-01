# 无畏契约主播潜力与外部人才池复盘

## 项目目的

本目录复盘三个相互关联、但不能混成一个结论的问题：

1. 虎牙站内哪些无畏契约主播连续多月互动率跑赢同层级，同时满足 ACU 和观看人数门槛。
2. 抖音哪些主播在不同月份覆盖不完整的情况下连续保持 ACU 相对领先，以及旧、新两种月份算法为何得到不同人数。
3. 2026-09 外部平台无畏契约主播池的规模和层级结构，为后续反挖筛选提供底表说明。

这里的“潜力”是历史行为筛选标签，不等于未来增长预测；“反挖情况”文件实际是平台主播池快照，不代表已经发生反挖或签约。

## 匿名结果

### 虎牙站内互动潜力

| 指标 | 结果 |
| --- | ---: |
| 源数据行数 | 75,832 |
| 唯一主播 ID / 名称 | 15,753 / 15,446 |
| 日期范围 | 2026-06-01 至 2026-10-07 |
| 同名对应多个 ID | 84 个名称 |
| 同 ID 对应多个名称 | 204 个 ID |
| 单日 DAU 超 10 万而剔除的官方台名称 | 5 个 |
| 清洗后唯一主播 ID | 13,493 |
| 候选池 | 187 个 ID |
| 筛选窗口内主播月记录 | 526 行 |
| 达标主播月记录 | 259 行 |
| 最终入选 | 8 人：腰部 3、尾部 5 |

筛选窗口为 2026-06 至 2026-09。候选池按全源数据期计算，入选要求为 ACU 至少 5、在筛选窗口内至少 3 个月加权互动率高于所在层级月基准，并排除名称命中赛事或官方关键词的主播。8 人中有 7 人达标 3 个月、1 人达标 4 个月；筛选窗口只有 4 个月，所以不存在 5 个月档。

独立重算得到的主播 ID 集合与旧工作簿“入选名单”首个连续有效明细块完全一致。旧工作簿候选池只保存 160 个 ID，而当前原始 CSV 直接重算为 187 个 ID，说明工作簿是旧快照或候选池存在丢失；最终 8 人仍可完全复现，因此把 160/187 作为警告而不是当前候选数。旧页第 9 至第 24 行基本为空，之后还有透视表残片，不能把工作表的 `max_row` 解释成 40 人名单。

### 抖音持续领先方法对比

原文件有 280,254 行、117,185 个唯一主播 ID，日期为 2026-01-01 至 2026-10-09，但月份覆盖不完整：

| 月份 | 观测天数 | 状态 |
| --- | ---: | --- |
| M1 | 21 | 有效 |
| M2 | 20 | 有效 |
| M3 | 8 | 有效 |
| M4 | 0 | 缺失 |
| M5 | 7 | 有效 |
| M6 | 14 | 有效 |
| M7 | 1 | 无效短月 |
| M8 | 8 | 有效 |
| M9 | 12 | 有效 |
| M10 | 2 | 无效短月 |

“有效月份”定义为全局至少 3 个观测日。两种方法结果如下：

| 方法 | 持续领先主播数 | 头部 | 颈部 | 腰部 | 尾部 |
| --- | ---: | ---: | ---: | ---: | ---: |
| v1：日历相邻月，保留 1–2 天短月 | 267 | 0 | 1 | 9 | 257 |
| v2：相邻有效月，主播月至少 3 个观测日 | 95 | 1 | 1 | 15 | 78 |

v2 有 1,700 个主播至少有 2 个可比月。v1 是两个旧工作簿口径的复现，不应把 267 和 95 解释成同一种筛选规则的自然波动；差异主要来自短月是否有效、缺失月如何处理和主播月最小观测天数。两版重算人数分别与对应旧工作簿一致。

### 2026-09 外部平台主播池

| 平台 | 快照行数 | 唯一 ID | 头部 | 颈部 | 腰部 | 尾部 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Bilibili | 198 | 198 | 17 | 22 | 76 | 83 |
| 抖音 | 4,076 | 4,075 | 17 | 28 | 289 | 3,742 |
| 斗鱼 | 24 | 24 | 0 | 0 | 9 | 15 |
| 虎牙 | 4,633 | 4,633 | 4 | 1 | 17 | 4,611 |
| 快手 | 27 | 27 | 0 | 0 | 3 | 24 |
| 合计 | 8,958 | 8,957 | 38 | 51 | 394 | 8,475 |

快照日期为 2026-09-30。合计行有 8,958 条记录但只有 8,957 个唯一 ID，存在 1 条重复记录。该表只描述人才池，不能证明已经完成反挖、联系或入职。

## 文件与 GitHub 路径

| 内容 | GitHub 路径 |
| --- | --- |
| 中文项目说明 | `projects/valorant-streamer-potential-analysis/README.md` |
| 英文项目说明 | `projects/valorant-streamer-potential-analysis/README.en.md` |
| 虎牙互动潜力重算脚本 | `projects/valorant-streamer-potential-analysis/scripts/reproduce_huya_internal_potential.py` |
| 抖音 v1/v2 方法对比脚本 | `projects/valorant-streamer-potential-analysis/scripts/reproduce_douyin_potential.py` |
| 外部平台池汇总脚本 | `projects/valorant-streamer-potential-analysis/scripts/summarize_external_valorant_pool.py` |
| 虎牙 9 月 ACU 并表辅助脚本 | `projects/valorant-streamer-potential-analysis/scripts/merge_huya_september_acu.py` |
| 虎牙匿名总览 | `projects/valorant-streamer-potential-analysis/artifacts/huya-internal-potential-summary.csv` |
| 虎牙匿名月度筛选 | `projects/valorant-streamer-potential-analysis/artifacts/huya-internal-potential-monthly.csv` |
| 虎牙交叉校验 | `projects/valorant-streamer-potential-analysis/artifacts/huya-internal-potential-validation.csv` |
| 抖音匿名总览 | `projects/valorant-streamer-potential-analysis/artifacts/douyin-potential-summary.csv` |
| 抖音月份覆盖 | `projects/valorant-streamer-potential-analysis/artifacts/douyin-potential-month-coverage.csv` |
| 抖音方法对比 | `projects/valorant-streamer-potential-analysis/artifacts/douyin-potential-method-comparison.csv` |
| 抖音工作簿校验 | `projects/valorant-streamer-potential-analysis/artifacts/douyin-potential-validation.csv` |
| 外部平台池匿名汇总 | `projects/valorant-streamer-potential-analysis/artifacts/external-valorant-pool-202609-summary.csv` |

每个中文 CSV 都有对应的 `.en.csv` 英文版本。英文版本使用英文列名。

## 本机来源映射

| 本机来源 | 仓库内处理 | SHA256 |
| --- | --- | --- |
| `C:\Users\tiany\Downloads\无畏契约主播互动潜力分析_不剔除赛事日_近3月.csv` | 重算后只提交匿名汇总 | `F9EEAD76D06A56285728F82A14792161AA6FA52BE9C3BD5D3ACFFB489AF2F0DC` |
| `C:\Users\tiany\Downloads\抖音无畏主播有效ACU_剔除大赛事日.csv` | 重算后只提交匿名汇总 | `7435FA6114174D92E21A760A7CBD741E2AFA69D531803B38C77C92AD08D574DD` |
| `C:\Users\tiany\Desktop\无畏契约份额增长\无畏契约主播潜力分析\无畏契约行业主播反挖情况_并入虎牙9月ACU_20261010.xlsx` | 汇总平台级数量和层级 | `E6B6032B44CAA8DDE73A73626CA1A31FE134C11D423A650AC6B22642058D7B8C` |
| `C:\Users\tiany\Desktop\无畏契约份额增长\无畏契约主播潜力分析\无畏契约潜力主播_最终名单.xlsx` | 只作交叉校验，不上传 | `D6AC5F3F021562EFC9BF585CFD5D770DE640121D6C9E98EEB8D92C37C3EC89BA` |
| `C:\Users\tiany\Desktop\无畏契约份额增长\无畏契约主播潜力分析\抖音无畏主播_月日均ACU持续领先分层_20261010.xlsx` | v1 人数校验，不上传 | `4A4B857BD5A62A170135BE5621C53C5FD79286B0B4E196AC37802238C6E45A1A` |
| `C:\Users\tiany\Desktop\无畏契约份额增长\无畏契约主播潜力分析\抖音无畏主播_相邻环比持续领先分层_20261010.xlsx` | v2 人数校验，不上传 | `E279D6A15674A8114BB658FADB8A865F3A96511F21EBBC96FE9DE20208B2F1ED` |

源工作簿、逐主播明细、主播 ID、主播昵称和用户级数据均未上传。

## 校验与限制

| 检查 | 状态 | 证据 |
| --- | --- | --- |
| 数据可用性 | 通过，但抖音覆盖不完整 | 虎牙 2026-06-01 至 2026-10-07；抖音月份覆盖已在 CSV 明示 |
| Schema 与语义 | 通过 | 两个原始 CSV 的主播键、日期、ACU、互动率字段经过类型和范围检查 |
| 粒度与唯一性 | 通过，并有警告 | 虎牙按主播 ID 聚合；外部池 8,958 行 / 8,957 个唯一 ID |
| 关联与行数放大 | 通过 | 层级基准 join 使用 `many_to_one`；月度聚合按主播月重新计算 |
| 指标不变量 | 通过 | 互动率和层级、人数、月份覆盖与源表重算一致 |
| 独立复算与对账 | 通过，并有警告 | 虎牙入选 8 个 ID 与首个连续明细块完全一致；抖音 267/95 与两版工作簿人数一致 |
| 边界与业务抽查 | 通过 | 核对空行、透视残片、1 条重复 ID、缺失月和短月；尚未做主播级人工业务抽样 |

本复盘保留的核心限制是：抖音月份覆盖不完整且不同方法的月份定义不同；虎牙候选池旧快照与当前源文件存在 160/187 差异；外部平台池只有一个月度和层级快照；结果不能解释为未来 ACU、留存或收入提升，也不能解释为反挖成效。

## 复现

在仓库根目录运行：

```powershell
$env:PYTHONIOENCODING='utf-8'
python projects/valorant-streamer-potential-analysis/scripts/reproduce_huya_internal_potential.py
python projects/valorant-streamer-potential-analysis/scripts/reproduce_douyin_potential.py
python projects/valorant-streamer-potential-analysis/scripts/summarize_external_valorant_pool.py
```

脚本默认读取上表中的本机路径，可通过环境变量覆盖。脚本只创建匿名汇总，不修改源文件。

`merge_huya_september_acu.py` 会写回指定工作簿；若目标已存在，脚本默认拒绝运行。只有在确认目标、备份并显式设置 `VALORANT_EXTERNAL_POOL_OVERWRITE=1` 后才能覆盖。
