# 视频号两周观众数变化归因复盘（去标识版）

## 项目目的与样本

复盘视频号 2026-09-21 至 09-27 相比 2026-09-14 至 09-20 的观众数变化，拆分为主播·天规模、单主播日均产出、主播活动状态、内容分组和开播时长/每小时产出。

- 输入粒度：主播 × 日，唯一键为 `(dt, anchor_alias)`。
- 原始数据覆盖：2026-09-01 至 2026-09-28，共 28 个日期。
- 有效开播记录：2,067 行；全部日期共 110 个主播，比较窗口内出现 107 个。
- 指标：`audiencecnt` 按主播和自然日直接求和。它是**主播维度观看人数计数之和**，不是跨主播去重的平台 DAU。
- 项目未取得用户级曝光、推荐、活动或算法变更信息，因此结论是描述性归因，不是因果效应。

## 核心结果

| 指标 | W1 09-14~09-20 | W2 09-21~09-27 | 变化 | 变化率 |
| --- | ---: | ---: | ---: | ---: |
| 日均观众数计数 | 6,760,166 | 7,163,321 | +403,155 | +6.0% |
| 主播开播天数 | 534 | 510 | -24 | -4.5% |
| 每个主播开播日平均观众数 | 88,616 | 98,320 | +9,704 | +11.0% |

主播活动状态拆分：

| 分组 | 主播数 | 周观众数变化 | 日均变化 | 占净变化 |
| --- | ---: | ---: | ---: | ---: |
| 持续开播 | 97 | +5,830,526 | +832,932 | +207% |
| W2 新增/回流 | 3 | +1,361,538 | +194,505 | +48% |
| W2 未开播 | 7 | -4,369,976 | -624,282 | -155% |

比例超过 100% 是因为正向和负向贡献相互抵消，不是留存率或份额越界。

内容分组拆分：

| 分组 | 主播数 | W1 日均 | W2 日均 | 日均变化 | 变化率 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 棋牌类主口径 | 29 | 5,103,836 | 5,668,419 | +564,583 | +11.1% |
| 非棋牌类 | 81 | 1,656,330 | 1,494,903 | -161,428 | -9.7% |
| 全部源主播 | 110 | 6,760,166 | 7,163,321 | +403,155 | +6.0% |

棋牌类内部：麻将 `+394,640/日`、斗地主 `-589,734/日`、升级/扑克 `+76,917/日`、棋类 `+195,998/日`、棋牌向桌游 `+486,761/日`。边界项独立保留，不并入主口径。

## 增长是否普遍

不是。两周各至少开播 3 天的 83 个主播中，42 个日均观众数上升、41 个下降；个体变化率中位数仅 `+0.1%`，均值 `+12.8%`。整体增长主要由少数主播驱动：

- 正贡献前三合计相当于净变化的 `432%`；
- 剔除这三个主播后，W1/W2 日均观众数从 `6,320,443` 降至 `4,981,473`，变化为 `-1,338,970/日`（`-21.2%`）；
- 因而不能把 `+6.0%` 描述为全量主播普涨。更准确的表述是“少数高增主播抵消了其余主播的下降”。

## 开播时长与每小时产出

标准三因子拆分如下，每一项均可直接加总到净变化：

| 范围 | 主播·天数效应 | 日均时长效应 | 每小时产出效应 | 周净变化 |
| --- | ---: | ---: | ---: | ---: |
| 全部源主播 | -4,470,621 | +788,631 | +6,504,078 | +2,822,088 |
| 棋牌类 | -5,411,376 | +1,615,435 | +7,748,022 | +3,952,081 |
| 非棋牌类 | +940,755 | -826,805 | -1,243,944 | -1,129,993 |

棋牌类主播·天仅从 123 增至 124，但总开播时长由 994 增至 1,104 小时。按日均口径，棋牌类三因子为：主播·天数 `-773,054`、日均时长 `+230,776`、每小时产出 `+1,106,860`，合计 `+564,583`。每小时产出是主要正向因素，但它仍是描述性分解，不能证明推荐、流量分配或内容变化造成了增长。

## 旧版问题与处理

1. 旧文本结果写 `W2未开播=10`，但当前源数据和最终工作簿分组均为 7；旧文本文件是过期派生结果，未迁移。
2. 当前源 CSV 使用 `2026/9/21` 格式，而旧脚本按 `2026-09-21` 过滤，直接重跑会得到空结果。迁移脚本同时支持两种日期格式。
3. 旧工作簿的两因子分项为规模 `-303,828`、效率 `706,983`、交互 `-33,270`，三项实际相加为 `369,885`，不等于报告的 `403,155`。迁移版把效率项固定在 W1 主播·天，得到规模 `-303,828`、效率 `+740,253`、交互 `-33,270`，三项严格闭合到 `+403,155`。
4. 原 JSON、日志、明细工作簿和逐主播原始数据包含主播昵称或平台 ID，未迁移。
5. 内容分组来自原项目的人工主播分类，不是平台官方内容体系；只保留匿名主播类别，不保留分类时的原始 ID。

## 路径地图

| GitHub 路径 | 内容 |
| --- | --- |
| [`scripts/build_anonymous_artifacts.py`](scripts/build_anonymous_artifacts.py) | 从本地原始 CSV 去标识、规范日期并重建全部产物 |
| [`scripts/validate_artifacts.py`](scripts/validate_artifacts.py) | 仅依赖迁移产物执行 40 项独立校验 |
| [`artifacts/wechat-channel-dau-two-week-anonymous-20260929.xlsx`](artifacts/wechat-channel-dau-two-week-anonymous-20260929.xlsx) | 去标识结果工作簿，含汇总、日度、主播匿名对比、分组、三因子和 Top20 |
| [`artifacts/anchor-day-anonymous.csv`](artifacts/anchor-day-anonymous.csv) | 完整去标识主播 × 日分析底表，可独立重算 |
| [`artifacts/anchor-two-week-anonymous.csv`](artifacts/anchor-two-week-anonymous.csv) | 107 个比较窗口主播的两周汇总 |
| [`artifacts/activity-group-summary.csv`](artifacts/activity-group-summary.csv) | 持续开播、新增/回流、未开播拆分 |
| [`artifacts/content-group-summary.csv`](artifacts/content-group-summary.csv) | 棋牌类、非棋牌类、全部源主播汇总 |
| [`artifacts/content-subgroup-summary.csv`](artifacts/content-subgroup-summary.csv) | 棋牌内部子类和边界项 |
| [`artifacts/decomposition-summary.csv`](artifacts/decomposition-summary.csv) | 主播·天、时长、每小时产出三因子拆分 |
| [`artifacts/contribution-top20-anonymous.csv`](artifacts/contribution-top20-anonymous.csv) | 正负贡献 Top20，使用稳定匿名别名 |
| [`artifacts/sensitivity-summary.csv`](artifacts/sensitivity-summary.csv) | 剔除正向贡献前三的敏感性结果 |
| [`artifacts/daily-summary.csv`](artifacts/daily-summary.csv) | 28 天日度汇总 |
| [`artifacts/source-manifest.csv`](artifacts/source-manifest.csv) | 原始文件路径、哈希、行数、日期和唯一性证据 |
| [`artifacts/source-script-manifest.csv`](artifacts/source-script-manifest.csv) | 原 12 个脚本的文件名、哈希与未复制原因 |
| [`validation/validation-summary.json`](validation/validation-summary.json) | 40 项校验明细和已知问题 |

本机原始来源：`C:\Users\tiany\Downloads\视频号DAU_0929.csv`，SHA-256 `17d4e89ad0413fd705b93f63dc37b5aed4e8d0e579055fd44ef9bd2f87e3e261`。原项目目录为 `C:\Users\tiany\Documents\ChatGPT\异动归因`；原输出中的主播身份工作簿、分类 JSON 和日志未上传。

## 复现

本地有原始 CSV 和原分类 JSON 时：

```powershell
python scripts\build_anonymous_artifacts.py --source C:\path\to\视频号DAU_0929.csv --classification C:\path\to\棋牌类主播分类_0929.json
python scripts\validate_artifacts.py
```

仅使用仓库产物复核：

```powershell
python scripts\validate_artifacts.py
```

English version: `README.en.md`.
