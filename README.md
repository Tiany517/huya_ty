# ChatGPT / Codex 迁移包

本仓库用于把可复用的工作资料交接到新电脑，包括工作规则、skills、SQL 参考、项目背景和经过筛选的项目证据。它不替代 ChatGPT 账号历史或本机配置。

## GitHub 路径地图

| 仓库内路径 | 内容 |
| --- | --- |
| `README.md` / `README.en.md` | 中文 / 英文说明和新电脑启动步骤 |
| `instructions/AGENTS.md` / `instructions/AGENTS.en.md` | 中文 / 英文数据分析工作规则；秘密值放在加密保险包中 |
| `skills/README.md`、`skills/<source>/<skill-name>/` | Skills 归档说明及按安装来源保留的完整快照 |
| `sql/README.md`、`sql/source/<file>` | SQL 归档说明和来自现有目录的原名脚本；后续可按主题建立索引 |
| `projects/<project-slug>/README.md` / `README.en.md` | 项目目的、范围、指标口径、发现、限制和来源；已复盘：`projects/valorant-5937-p50-live-time/`、`projects/fps-anchor-cleaning/` |
| `projects/<project-slug>/scripts/` | 可复现项目的脚本；FPS 项目收录 7 个清洗和分析脚本 |
| `projects/<project-slug>/artifacts/` | 支持理解或继续项目的重要结果文件；FPS 项目含匿名时长分位 CSV |
| `projects/monthly-external-ecosystem-dau/` | 外部生态 DAU 月报的取数口径、SQL 说明和匿名月度聚合附件 |
| `projects/valorant-fps-cross-broadcast/` | FPS 主播跨播事件表、ACU 分层成功率 SQL 和匿名校验基线 |
| `projects/valorant-watchtime-contribution-knee/` | 实际观时月度拐点、Top-N 覆盖和跨月候选筛选的匿名结果及脚本 |
| `projects/valorant-yuezi-event-costream/` | 去标识的赛事二路节目化案例、窗口汇总和分析脚本 |
| `projects/valorant-ob-costream-scenario/` | OB 二路节目化份额情景公式审查和匿名汇总；包含模型假设限制 |
| `archive/chatgpt-export/` | 复核后保留的 ChatGPT 导出归档；需要时使用加密形式 |
| `vault/env-files.aesgcm` | AES-256-GCM 加密的 `.env` 文件包；解密密钥单独保存 |
| `inventory/migration-inventory.md` / `.en.md` | 中文 / 英文来源盘点和待复核清单 |
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
4. 参考 `local-source-map.md` 重建本机路径；将仓库外单独保存的 `huya_ty-env-files.key` 安全转移到新电脑，再按 `vault/decrypt-env-files.mjs` 的说明解密到暂存目录并逐项恢复。
5. 阅读 `projects/` 中的项目背景和结果附件，再继续相关工作。
6. 重新连接获准的数据服务，并在运行 SQL 前验证权限。

## 后续工作同步

每次完成有复用价值的工作复盘，或新增、修订可复用 SQL 后，Codex 应更新对应的中英文说明并自动提交推送到本私有仓库。每次推送前仍须检查变更范围和完整 diff，确认没有明文凭据、未审核数据或其他项目的无关修改。详细规则见 `instructions/AGENTS.md`。

英文版见 `README.en.md`。
