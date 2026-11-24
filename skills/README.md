# Skills 归档

本目录按安装来源保存本机 skills 快照：

| 来源目录 | Skill 文件夹数 | 归档文件数 | 说明 |
| --- | ---: | ---: | --- |
| `codex/` | 57 | 508 tracked | Codex 用户和系统管理的 skills |
| `shared-agent/` | 45 | 82 | 共享 agent skills |
| `claude/` | 54 | 503 tracked | Claude skills |
| `plugins/hyperframes/0.1.2/` | 5 | 69 | HyperFrames v0.1.2 的完整 Codex 插件离线快照，含 `gsap`、`hyperframes`、`hyperframes-cli`、`hyperframes-registry` 和 `website-to-hyperframes` |

本机快照复制了 1,187 个来源文件；仓库实际跟踪 1,093 个 skill 文件，另有 2 份本说明。保留各来源下的同名副本，便于恢复来源差异。排除了 `.git`、缓存、虚拟环境、依赖目录、字节码和真实 `.env`；`.env.example` 可以保留。另有 94 个被源目录 `.gitignore` 排除的工作产物；其中 `douyin-playwright` 的 4 个公开 Top 10 视频分析 XLSX 已单独复核并迁移至 `projects/douyin-playwright-video-analysis/`。`.superpowers/sdd` 任务日志/差异、个性化生成脚本、截图和临时 JSON 继续排除。测试 token 或环境变量示例维持原状；未发现真实 `.env` 或常见 token 格式。

`codex/huya-external-sdk-weekly-report/` 是本地自建的虎牙外部SDK周报技能，包含固定日期分区、自然周日期解析、BigData取数、0值剔除、总量校验、视频号主播贡献归因和老板版汇报模板。该技能不来自第三方仓库。

`plugins/` 是额外的 Codex 插件归档，不与三个用户/agent skill 来源目录的文件计数混算。HyperFrames 来源为 <https://github.com/heygen-com/hyperframes>，插件清单声明版本 `0.1.2`、Apache-2.0；新电脑优先通过 Codex 插件入口重新安装，仓库快照用于离线核对和恢复。英文版见 `README.en.md`。
