# ChatGPT / Codex 迁移包

本仓库用于把可复用的工作资料交接到新电脑，包括工作规则、skills、SQL 参考、项目背景和经过筛选的项目证据。它不替代 ChatGPT 账号历史或本机配置。

## GitHub 路径地图

| 仓库内路径 | 内容 |
| --- | --- |
| `README.md` / `README.en.md` | 中文 / 英文说明和新电脑启动步骤 |
| `instructions/AGENTS.md` / `instructions/AGENTS.en.md` | 中文 / 英文数据分析工作规则；秘密值放在加密保险包中 |
| `instructions/sql-validation-workflow.md` / `.en.md` | 通用 SQL 七阶段证明链、静态审查、风险画像、九类校验维度、交付对账和复发控制框架 |
| `instructions/templates/sql-validation-record.md` / `.en.md` | 每份正式 SQL 必须填写的双语验收卡；记录结果契约、风险画像、八类闸门证据、独立复算、交付对账和完成状态 |
| `skills/README.md`、`skills/<source>/<skill-name>/` | Skills 归档说明及按安装来源保留的完整快照 |
| `skills/plugins/hyperframes/0.1.2/` | Codex 插件 HyperFrames v0.1.2 的离线快照，含 5 个演示/视频 skills；新电脑优先重装插件 |
| `sql/README.md`、`sql/source/<file>` | SQL 归档说明和来自现有目录的原名脚本；后续可按主题建立索引 |
| `sql/topics/retention-analytics/` | 站外斗鱼/B站/抖音及虎牙星秀的弹幕、打赏留存 SQL 索引、依赖、口径、版本和已知缺陷 |
| `sql/topics/retention-analytics/remediation/`、`sql/topics/retention-analytics/artifacts/` | 虎牙星秀分母修复 CTE、验证 SQL，以及 2025-01 至 2026-10 的匿名整体对比结果 |
| `projects/<project-slug>/README.md` / `README.en.md` | 项目目的、范围、指标口径、发现、限制和来源；已复盘项目清单见下方各路径 |
| `projects/<project-slug>/scripts/` | 可复现项目的脚本；FPS 项目收录 7 个清洗和分析脚本 |
| `projects/<project-slug>/artifacts/` | 支持理解或继续项目的重要结果文件；FPS 项目含匿名时长分位 CSV |
| `projects/monthly-external-ecosystem-dau/` | 外部生态 DAU 月报的取数口径、SQL 说明和匿名月度聚合附件 |
| `projects/monthly-report-appendix/` | 月报附录：视频号单/双播日与月 DAU、端外平台月 DAU、抖音 MCN 品类 DAU、APP 次月留存和游戏独占；含匿名附件、4 份 SQL、源哈希及已知缺陷 |
| `projects/weekly-ecosystem-monitoring/` | 周报生态监控：日级品类与主播下钻 SQL、6 周匿名快照、平台 DAU、展示模板结构和可重复校验 |
| `projects/wechat-channel-dau-attribution/` | 视频号两周观众数变化归因：完整去标识主播×日底表、两因子修复、活动/内容/时长拆分、匿名工作簿、路径地图和 40 项校验 |
| `projects/ai-workshop-commercialization/` | AI 工坊商业化价值：PSM7/PSM8、DID、付费留存、版本转换、礼物人工打标、匿名品类/ACU 汇总、最终单页和可重复校验 |
| `projects/buxiucup-popup-psm/` | 不朽杯三套独立 PSM/DID 复盘：打卡活动、当天 DOTA2 曝光、4 月兴趣曝光；含最终报告、匿名结果、核心 SQL/脚本、错误复盘和自动校验 |
| `projects/valorant-fps-cross-broadcast/` | FPS 主播跨播事件表、ACU 分层成功率 SQL 和匿名校验基线 |
| `projects/valorant-watchtime-contribution-knee/` | 实际观时月度拐点、Top-N 覆盖和跨月候选筛选的匿名结果及脚本 |
| `projects/valorant-yuezi-event-costream/` | 去标识的赛事二路节目化案例、窗口汇总和分析脚本 |
| `projects/valorant-ob-costream-scenario/` | OB 二路节目化份额情景公式审查和匿名汇总；包含模型假设限制 |
| `projects/huya-douyin-valorant-acu-threshold/` | 虎视虎啸主播月日均 ACU 阈值盘点的匿名月度结果和复盘说明 |
| `projects/valorant-5937-p50-live-time/`、`projects/fps-anchor-cleaning/` | 5937 P50 有效月主播时长测算，以及 FPS 主播时长清洗与分位复盘 |
| `projects/valorant-big-pot-share-scenario/` | 大锅饭观时份额情景估算；含双情景匿名汇总及样本期、分母和覆盖范围限制 |
| `projects/valorant-anti-fraud-event-review/` | 反炸鱼主播 ACU、观时份额与首播窗口的匿名分层结果；含多套事件口径限制 |
| `projects/non-douyin-valorant-streamer-discovery/` | 非抖 B 站/斗鱼/快手无畏主播头部候选、月度基准、战队剔除情景及匿名筛选结果 |
| `projects/valorant-streamer-potential-analysis/` | 无畏契约主播潜力复盘：虎牙站内互动筛选、抖音 v1/v2 持续领先方法对比、2026-09 外部平台人才池及匿名校验结果 |
| `projects/external-streamer-reverse-poaching/` | 反挖启发式估算复盘：斗鱼/B站历史预测表、抖音/快手模型、匿名平台与品类汇总、版本漂移和已知模型缺陷 |
| `projects/kuaishou-honor-of-kings-reverse-poaching/` | 快手《王者荣耀》反挖筛选复盘：6 个工作簿版本链、V1/V2 原始覆盖、V2 最终 15 人规则、虎牙腰部基准、匿名附件和 26 项校验 |
| `projects/user-profile-analysis/` | 用户画像 TGI 与 KMeans 复盘：设备三组、斯诺克拉新、世锦赛观看和 10 分钟以上观看队列；含 3 份 SQL、4 份历史报告、匿名 TGI/聚类附件、源清单和 49 项校验 |
| `projects/xingxiu-interest-index/` | 星秀兴趣指数 2026 年 1–7 月复盘：月度 DAU/兴趣指数、主播状态、7 月 DAU 十分位、11 个假设分组、中英文匿名结果和 34 项校验 |
| `projects/molata-cooperation-acu-review/` | 六位主播合作前后有效 ACU 复盘：四窗口匿名日序列、组内增长、平台基准、13 日勾稽残差、双语文档/结果工作簿和 21 项校验 |
| `projects/ai-live-room-operations/` | AI 直播间 2026-07 至 2026-09 月度快照：运行版/注释版 SQL、匿名主播×品类汇总、跨月覆盖、13 项 SQL 静态风险、双语文档/结果工作簿和 21 项校验 |
| `projects/ai-tool-guide/` | AI 工具选择与恢复：mav-slidecraft-skill 的 HTML 幻灯片、HyperFrames 的 HTML 动效视频、五个插件 skills、工具边界和新电脑恢复步骤；12 项归档检查 |
| `projects/event-summary-review/` | LPL、KPL、FISSURE、BLAST 赛事总结：16 个赛事组的 DAU/拉新/回流、同比与阶段比较、11 个赛事的平台份额、原发布值与去重更正版、20 条重复行和 LPL Final 页错位审计；中英文分开，25 项校验 |
| `projects/snooker-event-review/` | 斯诺克与世锦赛专题：89 个最终交付快照、61 份 SQL、世锦赛拉新/付费/视频直播覆盖、五个赛事到世锦赛留存、视频偏好、匿名画像、7 项质量风险和 36 项校验；中英文分开并附 GitHub 路径地图 |
| `projects/causal-inference-handbook/` | PSM/SCM 教学手册：5 个源版本、74 个可编辑代码块、11 项方法风险、正式项目复用清单、源哈希和中英文校验报告 |
| `archive/chatgpt-export/` | 复核后保留的 ChatGPT 导出归档；需要时使用加密形式 |
| `mcp/bigdata/README.md` / `.en.md`、`config.example.toml`、`tool-catalog.json` | bigdata MCP 的网关配置模板、11 个工具的调用契约、Presto/Spark/下载规范和故障排查；不含账号或 API secret |
| `vault/migration-secrets-v2.aesgcm` | AES-256-GCM 加密的 `.env`、数据平台凭据和原告警脚本凭据副本；解密密钥单独保存 |
| `vault/migration-secrets.aesgcm`、`vault/env-files.aesgcm` | 前两版加密包，保留作历史副本；新电脑优先使用 `migration-secrets-v2.aesgcm` |
| `inventory/migration-inventory.md` / `.en.md` | 中文 / 英文来源盘点和待复核清单；明确跳过的项目只在此登记状态，不生成项目的 GitHub 路径 |
| `local-source-map.md` / `local-source-map.en.md` | 中文 / 英文本机路径映射，仅保存在本机并由 Git 忽略 |

GitHub 仓库地址：<https://github.com/Tiany517/huya_ty>

以上是 GitHub 仓库内的相对路径。例如，`instructions/AGENTS.md` 对应 <https://github.com/Tiany517/huya_ty/blob/main/instructions/AGENTS.md>；目录对应 `https://github.com/Tiany517/huya_ty/tree/main/<folder>`。新电脑上的 Codex 克隆仓库后，可按此地图定位内容。

## 纳入规则

- 需要迁移的凭据会放入客户端加密包；Git 中不保存明文 key、密码、token、`.env` 文件或含凭据的配置。解密密钥放在 GitHub 之外的密码管理器或同等安全位置。
- 保留有用的本地和第三方 skills，包括必要的引用和资源，并记录来源与版本。比较内容后再去重。
- 纳入支持项目结论或后续工作的关键结果文件。逐份复核 Excel 或其他数据文件；详细用户级 Excel 仍按原要求不上传，除非用户明确改变边界。
- 逐项评估 ChatGPT 原始导出和大型生成结果。需要时保留完整加密归档；可重建缓存、依赖和临时文件不放入仓库。
- `.env.example` 中不放真实凭据。聊天或明文规则文件中暴露过的凭据，应先轮换再制作加密包。

## 新电脑启动

1. 登录 GitHub 后克隆本仓库。
2. 阅读 `instructions/AGENTS.md` 和 `inventory/migration-inventory.md`。
3. 从 `skills/` 恢复 skills，并查看来源和版本说明。
4. 按 `mcp/bigdata/README.md` 合并 MCP 配置模板，重启 Codex 并确认 bigdata 工具出现。
5. 参考 `local-source-map.md` 重建本机路径；将仓库外单独保存的 `huya_ty-env-files.key` 安全转移到新电脑，再用 `vault/decrypt-env-files.mjs` 解密 `vault/migration-secrets-v2.aesgcm` 到暂存目录并逐项恢复。
6. 阅读 `projects/` 中的项目背景和结果附件，再继续相关工作。
7. 重新连接获准的数据服务，并在运行 SQL 前验证权限。

## 后续工作同步

每次完成有复用价值的工作复盘，或新增、修订可复用 SQL 后，Codex 应更新对应的中英文说明并自动提交推送到本私有仓库。每次推送前仍须检查变更范围和完整 diff，确认没有明文凭据、未审核数据或其他项目的无关修改。详细规则见 `instructions/AGENTS.md`。

英文版见 `README.en.md`。
