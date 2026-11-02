# 抖音 Playwright Top 10 视频分析样例

## 项目目的

这是 `douyin-playwright` skill 自带的公开视频分析样例归档。它的价值是让新电脑上的 Codex 看到该 skill 曾经生成过什么交付物、工作簿如何组织，以及在重新安装或修复 skill 后用什么结果做对照。

这些工作簿不是虎牙内部经营数据，也不是当前时点的平台排名。全部内容来自抖音公开页面，抓取和分析日期集中在 2026-06-25 至 2026-06-26。

## 已保留内容

- 4 个原始 XLSX，共 40 条 Top 10 视频记录：
  - 关键词“世界杯”搜索结果。
  - 博主“小钟Johnny”。
  - 博主“小Lin说”。
  - 博主“黄士铨看世界”。
- 每个工作簿通常包含博主/搜索概览、Top 10 视频数据和 AI 脚本分析三张表。
- 中英文项目说明、中英文机读索引、源文件 SHA-256 和可重复校验脚本。

## 结果口径与限制

1. 工作簿中的数据是抓取时页面展示值，点赞、评论、收藏和转发会随时间变化，不能当作当前值。
2. 部分互动量保存为“27.2万”等中文字符串，部分保存为数值；跨工作簿计算前必须统一解析。
3. “AI 脚本制作深度分析”是对公开标题、画面、文案或评论的归纳，属于主观分析建议，不是平台事实字段，也没有独立人工复核记录。
4. 4 个工作簿均无公式和公式错误；它们主要是数据快照，不是可自动刷新的模型。
5. 原目录中的搜索结果截图、视频详情截图、临时 JSON、`.superpowers` 差异文件、缓存和个性化生成脚本没有纳入项目页。通用生成脚本仍保留在 `skills/codex/douyin-playwright/`；个性化脚本含本机绝对路径和缺失的中间输入，重跑价值低。

## 使用方式

1. 先阅读 `skills/codex/douyin-playwright/SKILL.md` 和 `skill/SKILL.md`。
2. 将本目录的 XLSX 作为历史交付格式样例，不要把其中的互动量当成最新数据。
3. 使用数据源重新抓取后，对比表结构、排名方式、字段完整性和 AI 分析表，而不是逐字照搬旧结论。
4. 运行 `python scripts/verify_examples.py` 校验文件哈希、工作簿结构、公式和错误单元格。

## GitHub 路径地图

| GitHub 路径 | 内容 |
| --- | --- |
| `projects/douyin-playwright-video-analysis/README.md` | 中文项目说明和路径地图 |
| `projects/douyin-playwright-video-analysis/README.en.md` | 英文项目说明和路径地图 |
| `projects/douyin-playwright-video-analysis/artifacts/zh/` | 4 个原始中文 XLSX 快照 |
| `projects/douyin-playwright-video-analysis/artifacts/summary.zh.csv` | 中文机读文件与结果摘要 |
| `projects/douyin-playwright-video-analysis/artifacts/source-manifest.zh.csv` | 中文源文件、字节数和 SHA-256 清单 |
| `projects/douyin-playwright-video-analysis/artifacts/summary.en.csv` | 英文机读文件与结果摘要 |
| `projects/douyin-playwright-video-analysis/artifacts/source-manifest.en.csv` | 英文源文件、字节数和 SHA-256 清单 |
| `projects/douyin-playwright-video-analysis/scripts/verify_examples.py` | 工作簿完整性和结构校验脚本 |
| `projects/douyin-playwright-video-analysis/validation/validation-report.json` | 本次校验结果 |

以上路径均相对于 GitHub 仓库根目录。英文说明见 `README.en.md`。
