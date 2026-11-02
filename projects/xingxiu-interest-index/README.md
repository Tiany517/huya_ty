# 星秀兴趣指数分析

本页复盘 2026 年 1–7 月虎牙星秀主播的月度 DAU 与兴趣指数变化，保留可独立重算的匿名聚合、生成脚本和校验证据。新电脑应优先阅读本页，再按下方 GitHub 路径取文件。

## GitHub 路径地图

| GitHub 仓库内路径 | 内容 |
| --- | --- |
| `projects/xingxiu-interest-index/README.md` | 本中文说明、结论、口径和限制 |
| `projects/xingxiu-interest-index/README.en.md` | 完全独立的英文说明 |
| `projects/xingxiu-interest-index/scripts/build_anonymous_artifacts.py` | 从本地月度源 CSV 重建全部匿名结果 |
| `projects/xingxiu-interest-index/scripts/validate_artifacts.py` | 34 项源重算、内部对账、历史工作簿对账、隐私和字体检查 |
| `projects/xingxiu-interest-index/artifacts/zh/monthly_summary.csv` | 中文月度汇总，7 行 |
| `projects/xingxiu-interest-index/artifacts/zh/status_summary.csv` | 存量、新增/回归、流失三种 6–7 月状态汇总 |
| `projects/xingxiu-interest-index/artifacts/zh/dau_decile_summary.csv` | 2026-07 主播 DAU 十分位汇总 |
| `projects/xingxiu-interest-index/artifacts/zh/hypothesis_group_summary.csv` | 11 个业务假设分组的人数与变化汇总 |
| `projects/xingxiu-interest-index/artifacts/zh/quality_findings.csv` | 7 项口径、分布和复现风险 |
| `projects/xingxiu-interest-index/artifacts/zh/source_manifest.csv` | 本地源 CSV 和 3 份历史工作簿的大小、SHA-256 与上传状态 |
| `projects/xingxiu-interest-index/artifacts/zh/validation_results.csv` | 中文 34 项校验结果 |
| `projects/xingxiu-interest-index/artifacts/zh/version_history.csv` | 版本变化记录 |
| `projects/xingxiu-interest-index/artifacts/zh/星秀兴趣指数_匿名汇总.xlsx` | 中文匿名结果工作簿 |
| `projects/xingxiu-interest-index/artifacts/en/` | 与中文目录一一对应的英文 CSV、校验结果和匿名工作簿 |
| `projects/xingxiu-interest-index/artifacts/project_summary.json` | 机器可读的核心规模和结果摘要 |
| `projects/xingxiu-interest-index/artifacts/validation_report.json` | 校验总结：总数、通过数、失败数 |

## 项目问题与范围

核心问题是：星秀主播整体 DAU 和兴趣指数在 2026 年 1–7 月怎样变化；6 月到 7 月的变化由哪些主播状态和 DAU 层级贡献；哪些假设分组更能解释“大盘 DAU 下降但部分主播兴趣指标上升”的现象。

源 CSV 共 22,831 行、8,394 个唯一主播、7 个月，采用 `month + luid` 粒度且唯一。源列包括 `month`、`luid`、`snick`、`game_name`、`dau`、`user_pro`。源文件和历史工作簿含有主播 ID、昵称和逐主播榜单，因此均未上传。

## 核心结果

2026-07 与 2026-06 比较：

- 主播数从 3,540 降至 3,381。
- 主播 DAU 加总从 1,873,101.05 升至 1,885,667.77，净增 12,566.72，增幅 `0.671%`。
- 兴趣指数加总从 10,724,252.19 升至 11,933,038.49，净增 1,208,786.30，增幅 `11.272%`。
- 同一时期硬编码的品类 DAU 从 428,326 降至 410,709，降幅 `4.113%`。

主播状态拆解：

| 状态 | 主播数 | DAU 变化 | 兴趣指数变化 |
| --- | ---: | ---: | ---: |
| 存量 | 2,425 | -23,689.40 | +1,243,561.92 |
| 新增/回归 | 956 | +180,819.10 | +676,691.28 |
| 流失 | 1,115 | -144,562.99 | -711,466.90 |

整体 DAU 的小幅净增，是新增/回归主播贡献超过流失主播和存量主播净下降后的结果。这里的“新增/回归”只表示 6 月不在表、7 月出现；“流失”只表示 6 月有记录、7 月不在表，不能解释为已确认的账号生命周期新增或流失。

2026-07 的 DAU 十分位中，D10 含 338 个主播，占主播 DAU 加总约 `88.07%`、兴趣指数加总约 `91.72%`。D1–D9 每个分位均为 338–339 人。

假设分组中，规模最大的变化项为：

| 分组 | 主播数 | DAU 变化 | 兴趣指数变化 |
| --- | ---: | ---: | ---: |
| 其他上涨：DAU 和兴趣双升 | 946 | +159,870.04 | +898,618.00 |
| 新增/回归主播 | 956 | +180,819.10 | +676,691.28 |
| 其他下滑：DAU 和兴趣双降 | 872 | -246,649.54 | -1,087,991.06 |
| 流失主播 | 1,115 | -144,562.99 | -711,466.90 |
| 腰部上涨：6 月 DAU 3 千–1 万且双升 | 48 | +74,626.06 | +762,730.66 |
| 大/腰部上涨：6 月 DAU ≥1 万且双升 | 19 | +53,921.83 | +738,413.72 |

这些分组是描述性规则，不是已经验证的业务机制；不能用它们证明某个主播或运营动作导致了兴趣指数变化。

## 指标与计算口径

- `month`：自然月，范围固定为 2026-01 至 2026-07。
- `luid`：主播键，仅用于计算和去重，不进入迁移产物。
- `dau`：源文件的主播月度 DAU 字段。对主播跨月求和得到“主播 DAU 加总”，可能重复统计同时观看多个主播的用户。
- `user_pro`：源文件的兴趣指数字段。月度汇总使用非空值求和；6–7 月状态和假设分组沿用历史工作簿规则，把缺失兴趣指数按 0 处理。
- `兴趣_DAU比`：`user_pro / dau` 的主播级比例；汇总时另给中位数，避免被极端值主导。不是留存率、转化率或用户占比。
- `品类DAU`：7 个硬编码月度值，来自历史分析脚本中的外部口径；源目录没有对应 SQL、看板导出或字段字典。
- DAU 十分位：按 2026-07 的 `dau` 使用 `rank(method="first")` 后做 10 等分，每层约 338 人。

## 已知问题和解释边界

1. 品类 DAU 没有可追溯源查询，只能验证与历史脚本中的 7 个值一致，不能证明这些值来自哪张表或哪个看板。
2. 主播 DAU 加总会跨主播重复用户，不等同于去重品类 DAU；因此“主播 DAU 加总/品类 DAU”不是严格用户覆盖率。
3. 缺少 `dau`、`user_pro` 字段字典，且先把 `user_pro` 跨主播求和再除以品类 DAU，其业务单位仍需数据 owner 确认。
4. 1 个主播在 7 个月中均缺失兴趣指数。历史 6–7 月变化分析把该缺失按 0 处理；本迁移保留此规则，以便复现原结果，但这可能轻微影响状态与假设分组。
5. 7 月有 2 行源数据缺少 `game_name`；本项目不用该字段分组，因此不影响当前聚合。
6. 主播级 `user_pro/dau` 比值存在明显长尾，22,831 行中有 33 行大于 100，最大约 4,271.61。比值业务单位尚未确认，汇总主要参考中位数。
7. 历史“假设验证”工作簿没有生成脚本。本次已从源 CSV 重建 11 个分组，并确认原工作簿的人数及兴趣变化与迁移版一致。
8. 这是描述性分析，不包含对照设计、因果识别或显著性检验；不能把月度同步变化解释为因果效果。

## 校验

运行结果：`34/34` 通过，`0` 失败。

校验覆盖源行数、主播数、月份覆盖、`month + luid` 唯一性、7 个月度聚合、品类 DAU 输入、6–7 月外连接状态、4,496 个 6–7 月主播覆盖、状态变化闭合、10 个 DAU 分位、分位人数与指标闭合、11 个假设分组重算、变化闭合、中英文一致性、匿名字段、Excel 错误和源哈希，并与 3 份历史工作簿中的月度汇总、DAU 分层和假设分组逐项对账。

## 在新电脑复现

依赖：Python 3、pandas、openpyxl。原始 CSV 不在 GitHub，需要从当前电脑的加密备份或原数据源取得。

```powershell
python projects/xingxiu-interest-index/scripts/build_anonymous_artifacts.py `
  --source <月度源CSV路径> `
  --evidence-workbook <历史工作簿1> `
  --evidence-workbook <历史工作簿2> `
  --evidence-workbook <历史工作簿3>

python projects/xingxiu-interest-index/scripts/validate_artifacts.py `
  --source <月度源CSV路径> `
  --evidence-dir <历史工作簿目录>
```

如果新电脑没有原始 CSV，仍可直接读取已推送的匿名 CSV/XLSX 和本 README；不要用仓库中的聚合值反推主播明细。

## 未上传内容

未上传原始 22,831 行主播月度 CSV、3 份含 luid/昵称/逐主播 Top 榜的历史工作簿，以及任何具体主播排名。源清单只保留文件名、大小和 SHA-256。
