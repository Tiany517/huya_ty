# Skills 归档

本目录按安装来源保存本机 skills 快照：

| 来源目录 | Skill 文件夹数 | 归档文件数 | 说明 |
| --- | ---: | ---: | --- |
| `codex/` | 56 | 503 tracked | Codex 用户和系统管理的 skills |
| `shared-agent/` | 45 | 82 | 共享 agent skills |
| `claude/` | 54 | 503 tracked | Claude skills |
| `plugins/hyperframes/0.1.2/` | 5 | 69 | HyperFrames v0.1.2 的完整 Codex 插件离线快照，含 `gsap`、`hyperframes`、`hyperframes-cli`、`hyperframes-registry` 和 `website-to-hyperframes` |

本机快照复制了 1,182 个来源文件；仓库实际跟踪 1,088 个 skill 文件，另有 2 份本说明。保留各来源下的同名副本，便于恢复来源差异。排除了 `.git`、缓存、虚拟环境、依赖目录、字节码和真实 `.env`；`.env.example` 可以保留。另有 94 个被源目录 `.gitignore` 排除的工作产物未推送，包括 `.superpowers/sdd` 任务日志/差异文件，以及 `douyin-playwright` 下的 Excel、脚本、图片和临时 JSON；它们留待项目复盘决定是否作为项目结果纳入。测试 token 或环境变量示例维持原状；未发现真实 `.env` 或常见 token 格式。

`plugins/` 是额外的 Codex 插件归档，不与三个用户/agent skill 来源目录的文件计数混算。HyperFrames 来源为 <https://github.com/heygen-com/hyperframes>，插件清单声明版本 `0.1.2`、Apache-2.0；新电脑优先通过 Codex 插件入口重新安装，仓库快照用于离线核对和恢复。英文版见 `README.en.md`。
