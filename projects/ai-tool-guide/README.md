# AI 工具说明：mav-slidecraft-skill 与 HyperFrames

本页复盘 2026-07-23 编写的两份演示/视频工具使用说明，并把说明所依赖的技能与插件快照加入迁移仓库。目标是让新电脑上的 Codex 先判断应该做 HTML 幻灯片还是 HTML 动效视频，再定位到可恢复的工具文件。

## 结论先行

| 目标 | 优先工具 | 产出 | 不应误用的地方 |
| --- | --- | --- | --- |
| 经营分析汇报、课程讲义、Pitch deck | `mav-slidecraft-skill` | 动画丰富的 HTML 幻灯片 | 不是原生可编辑的 PowerPoint `.pptx` |
| 数据结论短视频、活动复盘、开场动画 | HyperFrames | 由 HTML/CSS/GSAP 驱动并可渲染的 MP4 | 不是图生视频模型，不能只靠一张图生成真实镜头 |
| 真实感视频镜头 | 外部图生视频或其他生成式视频工具 | 视频素材 | 生成素材后可再用 HyperFrames 做包装、字幕和时间轴 |

## mav-slidecraft-skill

- 仓库内快照：`skills/codex/mav-slide-craft-skill/`。
- 来源：<https://github.com/maverickgao8848/slide-craft-skill>。
- 用途：从内容或现有 PPT/PPTX 生成零依赖、动画丰富的 HTML 演示，可继续打印或导出为 PDF。
- 适合：汇报、经营分析 slides、产品介绍、课程讲义、Pitch deck。
- 边界：核心交付是 HTML，不应把它描述成原生 PPTX 生成器。

常用请求示例：

```text
用 mav-slidecraft-skill 把这份经营分析整理成 12 页 HTML 幻灯片，保留关键数字和图表。
```

```text
把这个 PPTX 转成网页演示；先列出内容映射，再生成 HTML。
```

## HyperFrames

- 仓库内离线快照：`skills/plugins/hyperframes/0.1.2/`。
- 插件元数据：`skills/plugins/hyperframes/0.1.2/.codex-plugin/plugin.json`。
- 来源：<https://github.com/heygen-com/hyperframes>。
- 文档：<https://hyperframes.heygen.com>。
- 快照版本：`0.1.2`，共 69 个文件，约 363 KiB。
- 许可证：插件清单声明 Apache-2.0。
- 运行依赖：Node.js 22 或更高版本、`PATH` 中可用的 FFmpeg；CLI 通过 `npx hyperframes` 调用。

快照包含五个 skills：

1. `hyperframes`：HTML/CSS/GSAP 组合、视觉风格、调色板、转场、字幕和音频响应。
2. `hyperframes-cli`：`init`、`lint`、`preview`、`render`、`transcribe`、`tts`、`doctor`、`browser`。
3. `hyperframes-registry`：安装和组合可复用区块、转场、数据可视化和特效。
4. `gsap`：tween、timeline、缓动、stagger 和性能。
5. `website-to-hyperframes`：从网页抓取到视频的七步流水线。

HyperFrames 适合数据结论短视频、产品宣传、活动复盘、汇报开场、赛事战报、字幕包装和图文卡点视频。它要求先有文案、图片、音乐、参考素材或由其他模型生成的素材；不适合被描述成“一张图片直接生成真实动态视频”的工具。

常用请求示例：

```text
用 HyperFrames 做一段 30 秒数据短视频，主题是一个月留存变化；先给我分镜和时间轴，再渲染。
```

```text
把这份分析结论做成带字幕的 HTML 动效短视频，输出 1080×1920 和 1920×1080 两个版本。
```

## 新电脑恢复

1. 先克隆迁移仓库，并把仓库根目录作为以下相对路径的起点。
2. `mav-slidecraft-skill` 是普通 Codex skill。确认快照后，将 `skills/codex/mav-slide-craft-skill/` 整个目录复制到新电脑的 Codex 用户 skills 目录：

```powershell
$source = '.\skills\codex\mav-slide-craft-skill'
$dest = Join-Path $env:USERPROFILE '.codex\skills\mav-slide-craft-skill'
New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
Copy-Item -LiteralPath $source -Destination $dest -Recurse
```

3. HyperFrames 是 Codex 插件，优先在新电脑的 Codex 插件入口重新安装，并确认版本不低于 `0.1.2`。仓库内快照用于离线核对、审计和缺少插件源时恢复，不建议手工覆盖 Codex 管理的插件缓存。
4. 安装后检查 Codex 能看到 `hyperframes`、`hyperframes-cli`、`hyperframes-registry`、`gsap` 和 `website-to-hyperframes` 五个 skills。
5. 分别运行一次无渲染的幻灯片任务和 HyperFrames `doctor` 或最小预览，确认文档、CLI、Node.js 与 FFmpeg 都可用。

## 仓库路径地图

| 仓库内路径 | 内容 |
| --- | --- |
| `projects/ai-tool-guide/README.md` | 中文项目说明 |
| `projects/ai-tool-guide/README.en.md` | 英文项目说明 |
| `projects/ai-tool-guide/artifacts/source-zh/` | 原使用说明的完整中文快照 |
| `projects/ai-tool-guide/artifacts/source_manifest.csv` | 说明、skill 和插件关键文件的 SHA-256 清单 |
| `projects/ai-tool-guide/artifacts/validation_results.csv` | 本页归档完整性检查结果 |
| `projects/ai-tool-guide/scripts/validate_archive.py` | 可重复运行的本地校验器 |
| `skills/codex/mav-slide-craft-skill/` | mav-slidecraft-skill 完整归档 |
| `skills/plugins/hyperframes/0.1.2/` | HyperFrames v0.1.2 插件与五个 skills 的离线快照 |

## 已知限制

- 本页来自一份简短使用笔记，不包含过去生成的具体幻灯片或视频成品。
- 没有证据表明 HyperFrames 插件或 mav skill 已在本机完整跑通所有渲染参数；新电脑恢复后仍须执行环境检查。
- 工具版本会继续变化。快照版本用于追溯，不等同于最新版；重新安装后应核对插件清单和行为差异。

英文版见 `README.en.md`。
