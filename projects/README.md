# 项目索引

本目录保存已复盘项目的可交接说明。每个 `projects/<project-slug>/` 都以 `README.md` 和 `README.en.md` 作为入口；目录内可能另有 `scripts/`、`sql/`、`methodology/`、`validation/` 和 `artifacts/`。原始用户级明细、详细 Excel、历史缓存和可重建依赖不默认上传。

## 先看哪里

- 新电脑接手某个项目：先读该目录的中文或英文 README，再按其中的 GitHub 路径地图读取 SQL、脚本和匿名结果。
- 查全部项目入口：使用本页；根目录 `README.md` / `README.en.md` 说明仓库级结构和新电脑启动顺序。
- 查凭据：使用顶层 `vault/` 中的加密包。`vault/` 是跨项目迁移基础设施，不属于任何单个项目，也不应移动到 `projects/` 下。
- 查 ChatGPT/Codex 历史：使用顶层 `archive/codex-work-history/` 中的加密归档。
- 查工作规则：使用 `instructions/AGENTS.md`、`instructions/AGENTS.en.md` 和 SQL 验收工作流。

## 项目路径地图

| 项目目录 | 中文项目 | English project | 主要材料 |
| --- | --- | --- | --- |
| `projects/ai-live-room-operations/` | AI 直播间月度运营快照复盘 | AI live-room monthly operations snapshot review | SQL、匿名月度/品类/分层汇总、双语文档和校验 |
| `projects/ai-tool-guide/` | AI 工具说明 | AI tool guide | HTML 幻灯片/动效视频、插件快照、恢复说明和校验 |
| `projects/ai-workshop-commercialization/` | AI 工坊商业化价值分析 | AI workshop commercialization analysis | PSM/DID、礼物打标、匿名汇总、单页和校验 |
| `projects/buxiucup-popup-psm/` | 不朽杯弹窗 PSM / DID 复盘 | Buxiucup popup PSM / DID review | 三套活动分析、最终报告、SQL/脚本、错误复盘和校验 |
| `projects/causal-inference-handbook/` | 因果推断实操手册迁移复盘 | Causal-inference handbook migration review | 手册多版本、方法风险、源哈希和校验 |
| `projects/console-game-revenue-review/` | 主机游戏营收同比复盘 | Console-game revenue year-over-year review | 业务背景、主播×月口径、匿名月度汇总、方法和限制 |
| `projects/daily-alerting-automation/` | 日常数据告警与自动报表 | Daily data alerting and automated reporting | 监控模块、阈值、数据流程、复用建议和风险 |
| `projects/douyin-playwright-video-analysis/` | 抖音 Playwright Top 10 视频分析样例 | Douyin Playwright video-analysis examples | 4 个样例工作簿、Top 10 记录和结构校验 |
| `projects/event-summary-review/` | 赛事总结与平台份额复核 | Event summary and platform-share review | 赛事 DAU/拉新/份额、重复审计、质量问题和中英文结果 |
| `projects/external-streamer-reverse-poaching/` | 外部平台主播反挖估算项目复盘 | External-streamer reverse-poaching review | 计算函数、匿名平台/品类汇总、模型复现风险和校验 |
| `projects/fps-anchor-cleaning/` | FPS 主播清洗与分品类开播时长分位 | FPS streamer cleaning and category live-time quantiles | 清洗/映射脚本、匿名分位结果和口径说明 |
| `projects/honor-of-kings-streamer-departure-impact/` | 王者荣耀下滑与吕德华离开影响复盘 | Honor of Kings decline and streamer-departure impact review | 业务背景、归因方法、历史项目估计、去标识 SQL 和限制 |
| `projects/huya-douyin-valorant-acu-threshold/` | 虎视虎啸无畏契约主播月日均 ACU 达标盘点 | Huya-affiliated Douyin Valorant ACU threshold review | 月度阈值计数、匿名图表和复盘说明 |
| `projects/kuaishou-honor-of-kings-reverse-poaching/` | 快手王者荣耀主播反挖筛选复盘 | Kuaishou Honor of Kings reverse-poaching review | 规则版本链、匿名覆盖/基准汇总、脚本和校验 |
| `projects/molata-cooperation-acu-review/` | 六位主播合作前后有效 ACU 复盘 | Six-anchor cooperation ACU review | 匿名日序列、四窗口汇总、平台基准和校验 |
| `projects/monthly-external-ecosystem-dau/` | 外部生态月度 DAU 汇总 | Monthly external ecosystem DAU summary | 取数 SQL、匿名月度和口径说明 |
| `projects/monthly-report-appendix/` | 月报附录：外部生态与 APP 游戏独占 | Monthly report appendix: external ecosystem and APP game exclusivity | 视频号/端外/MCN/留存/独占、匿名附件、SQL 和校验 |
| `projects/non-douyin-valorant-streamer-discovery/` | 非抖无畏主播挖掘复盘 | Non-Douyin Valorant streamer discovery review | 头部候选、月度基准、战队剔除情景和匿名筛选结果 |
| `projects/snooker-event-review/` | 斯诺克赛事专题迁移说明 | Snooker event review migration guide | 最终交付快照、SQL、留存/画像、质量风险和路径地图 |
| `projects/user-profile-analysis/` | 用户画像、TGI 与聚类分析复盘 | User profile, TGI, and clustering review | SQL、历史报告、匿名 TGI/聚类附件和校验 |
| `projects/valorant-5937-p50-live-time/` | 无畏契约 5937 主播 P50 开播时长提升测算 | Valorant 5937 streamer P50 live-time estimate | 有效月主播时长测算、口径和结果说明 |
| `projects/valorant-anti-fraud-event-review/` | 无畏契约反炸鱼事件复盘 | Valorant anti-fraud event review | ACU、观时份额、首播窗口和匿名分层结果 |
| `projects/valorant-big-pot-share-scenario/` | 大锅饭观时份额提升情景估算 | Big Pot watch-time share scenario estimate | 双情景公式、匿名汇总和分母/覆盖限制 |
| `projects/valorant-fps-cross-broadcast/` | 无畏契约 FPS 跨播事件与 ACU 分层成功率 | Valorant FPS cross-broadcast ACU-tier review | 事件 SQL、成功率 SQL 和匿名校验基线 |
| `projects/valorant-ob-costream-scenario/` | 无畏契约 OB 二路赛事节目化份额情景测算 | Valorant OB co-streaming scenario estimate | 份额公式审查、匿名汇总和模型假设 |
| `projects/valorant-streamer-potential-analysis/` | 无畏契约主播潜力与外部人才池复盘 | Valorant streamer potential and external talent pool review | 站内筛选、抖音方法对比、外部人才池和匿名校验 |
| `projects/valorant-watchtime-contribution-knee/` | 无畏契约观时贡献率拐点与稳定候选筛选 | Valorant watch-time contribution knee and stable-candidate screen | 月度拐点、Top-N 覆盖、筛选脚本和匿名结果 |
| `projects/valorant-yuezi-event-costream/` | 无畏契约赛事二路节目化案例复盘（去标识版） | Valorant event co-streaming case review (de-identified) | 窗口汇总、分析脚本和身份排除边界 |
| `projects/wechat-channel-dau-attribution/` | 视频号两周观众数变化归因复盘（去标识版） | Two-week WeChat Channel audience attribution review | 去标识主播×日底表、两因子修复、拆分和校验 |
| `projects/weekly-ecosystem-monitoring/` | 周报生态监控 | Weekly ecosystem monitoring | 日级品类/主播 SQL、匿名快照、平台 DAU 和展示结构 |
| `projects/world-cup-content-review/` | 世界杯内容与大盘影响复盘 | World Cup content and platform-impact review | 拉新/回流、PSM、留存、画像、搜索打标、方法和限制 |
| `projects/xingxiu-interest-index/` | 星秀兴趣指数分析 | Xingxiu interest-index analysis | 月度 DAU/兴趣指数、主播状态、十分位、假设分组和校验 |

## 目录责任

| 顶层目录 | 责任 |
| --- | --- |
| `projects/` | 已复盘项目的上下文、方法、SQL、脚本、匿名结果和项目级路径地图 |
| `vault/` | 跨项目加密凭据包；与 `projects/` 平级，不能放进单个项目 |
| `archive/` | ChatGPT/Codex 本地工作历史的加密归档 |
| `instructions/` | AGENTS 规则、SQL 验证工作流和模板 |
| `skills/` | 可用 skills 的来源化快照和恢复说明 |
| `sql/` | 跨项目 SQL 总索引、主题和版本化修复 |
| `mcp/` | bigdata MCP 配置模板、工具契约和恢复说明 |
| `inventory/` | 来源盘点、完成状态、已跳过事项和待复核清单 |

英文版见 `README.en.md`。
