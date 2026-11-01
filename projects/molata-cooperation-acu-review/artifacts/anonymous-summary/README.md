# 匿名附件说明

| 文件 | 行数 | 用途 |
| --- | ---: | --- |
| `daily_series.csv` / `.zh.csv` | 123 | 匿名主播角色、组内合计、平台基准、六人日份额和勾稽残差 |
| `window_summary.csv` / `.zh.csv` | 52 | 13 个统计单位 × 4 个窗口的 ACU 合计与日均 |
| `growth_comparison.csv` / `.zh.csv` | 13 | 13 个统计单位的前后增量、增幅及相对基准的百分点差 |
| `share_summary.csv` / `.zh.csv` | 4 | 四个窗口内六人和合作五人组的平均日份额 |
| `reconciliation_failures.csv` / `.zh.csv` | 13 | 平台差值无法回到源主播合计的日期和残差 |
| `cooperation-acu-anonymous-en.xlsx` | 6 sheets | 英文匿名结果工作簿 |
| `cooperation-acu-anonymous-zh.xlsx` | 6 sheets | 中文匿名结果工作簿 |
| `source-manifest.csv` | 5 | 源文件路径、大小、SHA-256 和纳入/排除原因 |
| `project-summary.json` | - | 数据规模、窗口、勾稽失败数量和隐私边界 |

`anchor_01` 是按全期有效 ACU 合计排序得到的观察主播，`anchor_02` 至 `anchor_06` 是合作五人组。角色编号是匿名顺序，不包含主播 ID、昵称或昵称派生信息。

历史结果工作簿含主播 ID 和昵称，未复制；原 Python 脚本也因硬编码身份未直接上传。仓库中的重建脚本只输出匿名角色和聚合。

英文版见 `README.en.md`。
