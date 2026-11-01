# 匿名汇总附件

本目录只保留聚合结果、源文件哈希和静态审查记录，不包含用户级记录或用户标识值。

| 子目录 / 文件 | 内容 |
| --- | --- |
| `tgi/` | 设备两两比较、斯诺克拉新、世锦赛完整观看和 10 分钟以上观看的 TGI 表；每个中文文件有英文表头版本 `.en.csv` |
| `clusters/device-groups.csv` / `.en.csv` | 三组设备各 50,000 样本的匿名聚类人数、占比和核心均值 |
| `clusters/world-championship-10min.csv` / `.en.csv` | 10 分钟以上观看目标组的匿名聚类汇总 |
| `clusters/world-championship-10min-kmeans.csv` / `.en.csv` | K=2 至 K=9 的 SSE、下降率和轮廓系数 |
| `clusters/world-championship-10min-device-price-tiers.csv` / `.en.csv` | 设备价格分层与两组人数 |
| `clusters/snooker-unreconciled-cluster-generation.csv` / `.en.csv` | 1,086 行处理样本的描述统计；明确标记为与 1,072 人报告聚类不可勾稽 |
| `sql-static-audit.csv` / `.en.csv` | 7 项已确认 SQL 缺陷和 1 项未执行字段语义检查 |
| `source-manifest.csv` / `.en.csv` | 151 个源文件的哈希、分类和迁移处理 |
| `project-summary.json` | 队列、样本量和隐私边界 |

英文 CSV 仅翻译表头；类别值仍可能保留源系统中的中文。不要从这些汇总回推或重建用户身份。

英文版见 `README.en.md`。
