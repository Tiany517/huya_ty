---
name: douyin-playwright
description: 抖音数据采集与AI分析 Skill。使用 Playwright 抓取抖音博主主页或单个视频的数据，生成 AI 文字摘要 + Excel 表格。当用户提到"抖音"、"分析博主"、"视频摘要"、"总结这个抖音"、"博主高赞视频"、"抖音数据导出"、"抖音数据分析"、"抖音视频分析"时使用此 Skill。即使用户只说"帮我看看这个抖音博主"或"这个抖音视频讲了什么"，也应触发。
---

# 抖音 Playwright 数据采集 Skill

基于 Playwright 的抖音数据采集工具，支持两种核心场景：
1. **博主主页分析** → Top N 高赞视频的文字摘要 + Excel 表格
2. **单个视频分析** → 标题+文案+热评的摘要 + Excel 表格

## 项目位置

- 项目根目录: `C:\Users\tiany\Desktop\douyin-playwright`
- CLI 入口: `C:\Users\tiany\Desktop\douyin-playwright\cli\main.py`
- Cookie 文件: `C:\Users\tiany\Desktop\douyin-playwright\data\cookie.json`
- Excel 输出: `C:\Users\tiany\Desktop\douyin-playwright\data\output\`

## 实战经验（重要！先读）

这些是从真实抓取中总结的教训，直接影响执行策略：

1. **抖音主页不直接显示播放量和评论数** — 主页视频卡片只展示点赞数、标题和视频ID。播放量、评论数、收藏数、转发数需要进入视频详情页才能获取。
2. **CSS 选择器极不稳定** — 抖音 DOM 结构频繁变动，深层 CSS 选择器随时可能失效。优先使用 URL 模式匹配（`/video/xxx`）、文本内容匹配和 `data-e2e` 属性，而非类名选择器。
3. **Playwright Chromium 可能下载失败** — 在中国大陆网络环境下，`playwright install chromium` 经常失败。此时应降级为 CDP 模式（使用用户本地 Chrome）。
4. **Windows 环境注意** — `python3` 命令通常不可用，用 `python`；`/tmp` 映射到 `C:\Users\...\AppData\Local\Temp`；路径分隔符用 `\` 或 `/` 均可。
5. **中文编码统一 UTF-8** — 所有文件读写强制指定 `encoding='utf-8'`，避免跨系统乱码。
6. **CDP 模式下逐页操作耗时** — 每个页面跳转 2-3 秒硬开销，10 个视频累积 30 秒+。应在 Skill 执行时告知用户预估耗时。

## 执行流程

### Step 0: 环境预检（每次执行前必须完成）

在执行任何抓取操作前，先运行环境预检，把问题提前暴露：

```bash
cd C:\Users\tiany\Desktop\douyin-playwright

# 1. 检查 python 命令
python --version

# 2. 检查依赖是否安装
python -c "import playwright; import pydantic; import openpyxl; print('deps OK')"

# 3. 检查 Playwright 浏览器是否可用
python -c "from playwright.sync_api import sync_playwright; p = sync_playwright().start(); b = p.chromium.launch(headless=True); b.close(); p.stop(); print('browser OK')"
```

**如果 Step 3 失败**（Chromium 未安装或下载失败），降级为 CDP 模式：
- 改用 `web-access` Skill 的 CDP Proxy 操作用户本地 Chrome
- CDP 模式天然携带用户登录态，无需单独处理 Cookie
- 告知用户："Playwright 浏览器不可用，将使用你的本地 Chrome 浏览器操作（需要 Chrome 已开启远程调试）"

**如果 Step 2 失败**（依赖缺失），先安装：
```bash
pip install -r requirements.txt
pip install openpyxl
```

### Step 1: 确认登录态

**Playwright 模式**：
```bash
python cli/main.py check-auth
```

- 返回 `{"valid": true}` → 继续下一步
- 返回 `COOKIE_NOT_FOUND` 或 `COOKIE_EXPIRED` → 引导用户登录

**CDP 模式**：用户 Chrome 天然携带登录态，跳过此步骤。但需先确认 CDP 可用：
```bash
node "C:/Users/tiany/.claude/skills/web-access/scripts/check-deps.mjs"
```

**登录（仅 Playwright 模式需要）**：
```bash
python cli/main.py auth
```
会弹出 headed 浏览器，用户手动扫码或短信登录，完成后按 Enter 保存 Cookie。

### Step 2: 判断场景并执行抓取

根据用户提供的 URL 判断场景：

| URL 特征 | 场景 | 命令 |
|----------|------|------|
| 包含 `/user/` | 博主主页分析 | `python cli/main.py blogger <URL> --top 10` |
| 包含 `/video/` | 单个视频分析 | `python cli/main.py video <URL>` |

**博主主页分析 — 批量策略（关键优化）**：

由于抖音主页只显示点赞数，而评论数、收藏数、转发数需要进详情页，采用两阶段策略：

1. **阶段一：批量获取主页数据**（快） — 滚动加载主页，获取所有可见视频的标题+点赞数+视频ID
2. **阶段二：选择性补全详情**（慢） — 只对用户需要的 Top N 视频逐个访问详情页补全数据

如果用户只需要"高赞视频排名"，阶段一就够了（快很多）。只有用户明确要求评论数、播放量等详情时，才执行阶段二。

**告知用户预估耗时**：
- 阶段一（仅点赞排名）：约 1-2 分钟
- 阶段一 + 阶段二（Top 10 完整数据）：约 3-5 分钟

**CDP 模式替代方案**：

当 Playwright 不可用时，使用 CDP Proxy 执行：
1. 创建新 tab 打开博主主页：`curl -s "http://localhost:3456/new?url=<URL>"`
2. 滚动加载：`curl -s "http://localhost:3456/scroll?target=<ID>&direction=bottom"`
3. 提取视频数据：`curl -s -X POST "http://localhost:3456/eval?target=<ID>" -d '<提取脚本>'`
4. 逐个打开视频详情：`curl -s "http://localhost:3456/new?url=<VIDEO_URL>"`
5. 关闭 tab：`curl -s "http://localhost:3456/close?target=<ID>"`

### Step 3: 解析输出

CLI 输出结构化 JSON 到 stdout，Skill 层读取并解析。

**博主输出**：
```json
{
  "blogger_name": "博主名",
  "blogger_id": "MS4wLjABAAAA...",
  "total_videos": 156,
  "scrape_time": "2026-06-25T14:30:00",
  "top_videos": [
    {
      "rank": 1,
      "title": "视频标题",
      "desc": "视频描述",
      "url": "https://www.douyin.com/video/xxx",
      "like_count": 45000,
      "play_count": 0,
      "comment_count": 0,
      "publish_time": "2026-06-12",
      "top_comments": []
    }
  ]
}
```

注意：`play_count`、`comment_count` 可能为 0（主页未获取），需要阶段二补全。

**视频输出**：
```json
{
  "title": "视频标题",
  "desc": "视频描述",
  "like_count": 45000,
  "play_count": 8500000,
  "comment_count": 3200,
  "publish_time": "2026-06-12",
  "blogger_name": "博主名",
  "top_comments": [{"user": "...", "text": "...", "likes": 1200}]
}
```

### Step 4: AI 生成文字摘要

基于 JSON 数据，生成结构化的文字摘要。

**博主摘要模板**：
```markdown
## 博主「{blogger_name}」Top {N} 高赞视频分析

> 粉丝数: {fans} | 获赞: {total_likes} | 作品数: {total_videos}

| # | 视频标题 | 点赞 | 评论 | 收藏 | 转发 | 发布日期 |
|---|---------|------|------|------|------|----------|
| 1 | {title} | {likes} | {comments} | {collects} | {shares} | {date} |

### 各视频摘要

**Top 1: {title}**（{likes} 赞）
- 内容摘要: [基于 title + desc + 评论生成的 AI 摘要]
- 关键话题: [从标签和内容中提取]
- 链接: {url}

...
```

**视频摘要模板**：
```markdown
## 视频「{title}」内容分析

- 博主: {blogger_name}
- 点赞: {likes} | 播放: {plays} | 评论: {comments}
- 发布时间: {date}

### 内容摘要
[AI 基于标题+文案+热评生成的摘要]

### 热门评论 Top 5
1. {user}: "{text}" ({likes} 赞)
2. ...
```

### Step 5: 生成 Excel 表格

根据用户需求决定输出格式：

| 用户说法 | 输出 |
|----------|------|
| "帮我总结/分析这个博主" | 文字摘要 + Excel |
| "导出 Excel" / "生成表格" | Excel 文件 |
| "视频内容是什么" / "讲了什么" | 仅文字摘要 |

**Excel 生成方式**：使用 Python + openpyxl 生成（项目已内置 `data/output/generate_excel_v2.py` 作为参考模板）。

**Excel 文件路径**: `data/output/YYYY-MM-DD_博主名_Top10视频分析.xlsx`

**博主 Excel 结构（3 个 Sheet）**：

Sheet 1 — 博主信息：
| 字段 | 内容 |
|------|------|
| 博主名称 | xxx |
| 抖音号 | xxx |
| 粉丝数 | xxx |
| ... | ... |

Sheet 2 — Top N 视频数据：
| 排名 | 视频标题 | 点赞数 | 评论数 | 收藏数 | 转发数 | 发布日期 | 时长 | 标签 | 视频链接 |

Sheet 3 — AI 脚本制作深度分析（可选，用户要求时生成）：
| 排名 | 视频标题 | 核心主题 | 脚本结构分析 | 叙事手法 | 信息呈现方式 | 互动设计 | 话题策略 | 爆款因素 |

**数据兜底规则**：
- 当某个字段获取失败时，在 Excel 中填入 "—" 而非留空
- 在摘要中标注 "（需详情页获取）" 说明该字段来源
- 不因单个字段缺失而阻塞整个流程

## 降级策略

当主要方式失败时，按以下顺序降级：

| 优先级 | 方式 | 适用场景 |
|--------|------|----------|
| 1 | Playwright CLI | Chromium 可用，Cookie 有效 |
| 2 | CDP Proxy + 用户 Chrome | Chromium 不可用或 Cookie 失效 |
| 3 | 截图 + OCR | DOM 解析完全失败，但页面可见 |
| 4 | 保存 HTML 本地解析 | 页面可加载但实时解析有问题 |

**超时控制**：
- 主页加载：30 秒超时
- 单个视频详情页：15 秒超时
- 滚动加载等待：3 秒
- 超时自动跳过，不卡死

## 错误处理

| 错误场景 | 处理方式 |
|----------|----------|
| Cookie 不存在 | 提示用户运行 `python cli/main.py auth` 登录，或降级为 CDP 模式 |
| Cookie 过期 | 同上 |
| Chromium 下载失败 | 自动降级为 CDP 模式 |
| 页面加载超时 | 重试 1 次，仍失败则跳过该页面 |
| 博主主页无法访问 | 检查 URL 格式，确认是否私密账号 |
| 抓取字段为空 | 在输出中标注 "—" 或 "（需详情页获取）" |
| DOM 选择器失效 | 尝试备选选择器，最终降级到截图 |
| Windows python3 不可用 | 使用 `python` 代替 |

## 注意事项

- 本工具仅用于合法的数据采集和研究用途
- 遵守抖音平台使用条款
- Cookie 文件本地存储，不上传任何服务器
- 首次登录后 Cookie 可复用，无需每次登录
- 抓取频率已内置反爬延迟（1-3 秒随机），请勿修改降低延迟
- 大量抓取时告知用户预估耗时，避免用户以为卡死
