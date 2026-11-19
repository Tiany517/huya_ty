# SQL 参考归档

本目录的 `source/` 保留了原 `Desktop\SQL` 来源中的 240 个 `.sql` 文件和 2 个 SQL 格式 `.txt` 文件，维持原文件名和相对目录，不改写 SQL 口径。

另在 `source/月报附录/` 保留 4 份来自 `Desktop\月报_附录` 的原始 SQL，不计入上述 240 份 `Desktop\SQL` 统计。其项目背景、匿名结果和缺陷说明见 `projects/monthly-report-appendix/`。

来源目录还包含 54 个 CSV、22 个 Excel、25 个 Python 脚本以及其他文件。CSV/Excel 明细没有复制；Python 脚本和分类文本 `content_categories_full.txt` 留待项目复盘后决定归属与是否纳入。

复制前对 SQL 文本做了常见密钥格式扫描，未发现命中。`topics/` 下保留经复核的主题索引；第一个主题为 [`topics/retention-analytics/`](topics/retention-analytics/README.md)，说明站外斗鱼/B站/抖音和虎牙星秀的弹幕、打赏留存 SQL 依赖、口径、版本选择及已知缺陷。源归档保持原样。

`reference/` 下维护跨项目 SQL 常用值映射。当前包含 [`common-anchor-and-game-id-maps.md`](reference/common-anchor-and-game-id-maps.md)，记录用户于 2026-11-03 提供的常用主播 ID、业务归属品类和常用 `game_id`；这些是筛选便利表，不替代平台维表。

王者荣耀陪玩主播的月内及季度内跳动分析见 [`topics/wzry-peiwan-anchor-jump-20261119/`](topics/wzry-peiwan-anchor-jump-20261119/README.md)，包含 Spark SQL、独立复算、匿名季度收入结果和已知限制。

游戏品类月度收入、观看用户、观看主播及开播主播汇总见 [`topics/game-category-monthly-core-metrics-20261119/`](topics/game-category-monthly-core-metrics-20261119/README.md)。

[`SQL学习笔记.md`](SQL学习笔记.md) 持续记录函数解释和分析写法，当前包括普通用户观察起点分配、CRC32与取余、数组与Lambda、活跃门槛及日期加权。示例为学习片段，不代表已验证的生产SQL。

English version: `README.en.md`.

广告观看体验抱怨的[每日分母 SQL 与反讽识别复盘](topics/ad-complaint-texts-20261113/README.md)：沿用原用户口径，SQL待执行、待验证。
