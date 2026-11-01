---
name: douyin-playwright
description: 抖音数据采集与AI分析 Skill。使用 Playwright 抓取抖音博主主页或单个视频的数据，生成 AI 文字摘要 + Excel 表格。当用户提到"抖音"、"分析博主"、"视频摘要"、"总结这个抖音"、"博主高赞视频"、"抖音数据导出"、"抖音数据分析"、"抖音视频分析"时使用此 Skill。即使用户只说"帮我看看这个抖音博主"或"这个抖音视频讲了什么"，也应触发。当用户提供博主名而非 URL 时，同样触发并先搜索找到主页。
---

# 抖音 Playwright 数据采集 Skill

基于 Playwright 的抖音数据采集工具，支持两种核心场景：
1. **博主主页分析** → Top N 高赞视频的文字摘要 + Excel 表格
2. **单个视频分析** → 标题+文案+热评的摘要 + Excel 表格

## 项目位置

- 项目根目录: `C:\Users\tiany\Desktop\douyin-playwright`
- CLI 入口: `C:\Users\tiany\Desktop\douyin-playwright\cli\main.py`
- Excel 生成器: `C:\Users\tiany\Desktop\douyin-playwright\scripts\generate_excel.py`
- Cookie 文件: `C:\Users\tiany\Desktop\douyin-playwright\data\cookie.json`
- Excel 输出: `C:\Users\tiany\Desktop\douyin-playwright\data\output\`
- 选择器参考: `C:\Users\tiany\Desktop\douyin-playwright\skill\references\douyin-selectors.md`
- CDP 操作参考: `C:\Users\tiany\Desktop\douyin-playwright\skill\references\cdp-patterns.md`

## 实战经验（重要！先读）

1. **抖音主页不直接显示播放量和评论数** — 主页视频卡片只展示点赞数、标题和视频ID。播放量、评论数、收藏数、转发数需要进入视频详情页才能获取。**博主分析场景下，进详情页是必选步骤，不是可选步骤。**
2. **CSS 选择器极不稳定** — 抖音 DOM 结构频繁变动，深层 CSS 选择器随时可能失效。优先使用 URL 模式匹配（`/video/xxx`）、文本内容匹配和 `data-e2e` 属性，而非类名选择器。选择器参考见 `references/douyin-selectors.md`。
3. **Playwright Chromium 可能下载失败** — 在中国大陆网络环境下，`playwright install chromium` 经常失败。此时应降级为 CDP 模式（使用用户本地 Chrome）。
4. **Windows 环境注意** — `python3` 命令通常不可用，用 `python`；`/tmp` 映射到 `C:\Users\...\AppData\Local\Temp`；路径分隔符用 `\` 或 `/` 均可。
5. **中文编码统一 UTF-8** — 所有文件读写强制指定 `encoding='utf-8'`，避免跨系统乱码。
6. **CDP 模式下逐页操作耗时** — 每个页面跳转 2-3 秒硬开销，10 个视频累积 30 秒+。应在 Skill 执行时告知用户预估耗时。
7. **"—"兜底 ≠ 跳过获取** — 历史踩坑：曾因"阶段二可选"的表述，对评论/收藏/转发直接填"—"没去获取。"—"只能表示"尽力获取后失败"，不能表示"跳过了获取"。生成输出前必须过必检清单（Step 5.5）。
8. **做新功能时容易遗漏已有功能** — 历史踩坑：加了评论区话题分析后，忘记了 Sheet 3 脚本分析。解法：Step 5.5 必检清单强制检查所有输出项，不凭记忆假设"都做了"。
9. **验证码随时可能出现** — 抖音反爬会弹出滑块、点击文字、图片选择等验证码，尤其是在连续访问多个页面时。**每次页面加载后必须先检测验证码再提取数据**，检测到后暂停等待用户手动完成。详见 Step 2.5。

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
- 改用 web-access Skill 的 CDP Proxy 操作用户本地 Chrome
- CDP 模式天然携带用户登录态，无需单独处理 Cookie
- CDP 操作参考见 `references/cdp-patterns.md`
- 告知用户："Playwright 浏览器不可用，将使用你的本地 Chrome 浏览器操作（需要 Chrome 已开启远程调试）"

**如果 Step 2 失败**（依赖缺失），先安装：
```bash
pip install -r requirements.txt
```

### Step 0.5: 解析用户输入（URL 或博主名）

根据用户提供的输入判断入口类型：

| 输入类型 | 示例 | 处理方式 |
|----------|------|----------|
| 抖音用户主页 URL | `https://www.douyin.com/user/MS4wLjABAAAA...` | 直接使用，进入 Step 1 |
| 抖音视频 URL | `https://www.douyin.com/video/7650453...` | 直接使用，进入 Step 2 的视频场景 |
| 博主名（非 URL） | "帮我分析小Lin说" | **先搜索找到主页 URL**，再进入 Step 1 |

**博主名搜索流程**（当输入是博主名而非 URL 时）：

1. 使用 CDP 模式打开抖音搜索页：`https://www.douyin.com/search/博主名?type=user`
2. 从搜索结果中提取第一个匹配用户的链接（`a[href*='/user/']`）
3. 确认用户名匹配后，获取主页 URL
4. 进入 Step 1 继续执行

**备选搜索方式**（CDP 不可用时）：
- 使用 WebSearch 搜索 `site:douyin.com 博主名`，从结果中提取用户主页 URL
- 告知用户："无法自动搜索博主，请提供博主主页 URL"

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

**博主主页分析 — 两阶段策略（关键优化）**：

1. **阶段一：批量获取主页数据**（快） — 滚动加载主页，获取所有可见视频的标题+点赞数+视频ID
2. **阶段二：逐个访问详情页补全数据**（慢，但**必选**） — 对 Top N 视频逐个访问详情页，获取评论数、收藏数、转发数、发布时间等

**告知用户预估耗时**：
- 阶段一（仅点赞排名）：约 1-2 分钟
- 阶段一 + 阶段二（Top 10 完整数据）：约 3-5 分钟
- 阶段一 + 阶段二 + 评论区分析：约 4-7 分钟

**CDP 模式替代方案**：详见 `references/cdp-patterns.md`

### Step 2.5: 验证码/反爬检测与处理（每次页面加载后必须执行）

抖音的反爬机制会在检测到自动化操作后弹出验证码。**每次打开新页面或导航后，必须先检测验证码再提取数据。**

**验证码类型与处理策略**：

| 验证码类型 | 检测方式 | 处理策略 |
|-----------|---------|---------|
| 滑块验证码 | `#captcha_container`, `[class*='captcha-slider']`, `[class*='nc_wrapper']` | 通知用户手动拖动滑块，轮询等待完成 |
| 点击文字验证 | `[class*='captcha-click']`, `[class*='word-verify']` | 通知用户按顺序点击文字，轮询等待完成 |
| 图片选择验证 | `[class*='captcha-image']`, `[class*='image-verify']` | 通知用户选择正确图片，轮询等待完成 |
| 频率限制 | 页面文本含"操作频繁"等关键词 | 自动等待 30 秒后刷新页面重试 |
| 登录过期 | 页面文本含"登录已过期"等 | 通知用户在浏览器中重新登录 |

**检测流程**（CDP 模式）：

```bash
# 每次页面加载后执行
curl -s -X POST "http://localhost:3456/eval?target=<ID>" -d '<验证码检测JS（见 references/douyin-selectors.md 末尾）>'
```

**处理流程**：

1. **检测到滑块/点击/图片验证码**：
   - **点击文字验证码** → AI 自动处理：截图 → 识别提示文字和目标字符 → 获取坐标 → 依次点击正确字符（最多重试 3 次，失败后通知用户手动完成）
   - **图片选择验证码** → AI 自动处理：截图 → 识别提示文字和候选图片 → 获取坐标 → 依次点击正确图片（最多重试 3 次）
   - **滑块验证码** → 优先通知用户手动拖动（自动拖拽成功率约 60-70%），轮询等待验证码消失（最多 120 秒）
   - 所有验证码通过后额外等待 5-10 秒再继续，避免连续触发

2. **检测到频率限制**：
   - 自动等待 30 秒
   - 刷新页面重新加载
   - 如果仍然限制，等待 60 秒后重试
   - 连续 3 次仍然限制 → 通知用户稍后再试

3. **检测到登录过期**：
   - 通知用户："登录已过期，请在 Chrome 中重新登录抖音"
   - 等待用户确认登录完成后继续

**反爬预防措施**（比事后处理更重要）：

| 措施 | 说明 |
|------|------|
| 页面间隔 3-5 秒 | 不要密集打开页面 |
| 随机化延迟 | 3-8 秒随机延迟，不用固定间隔 |
| 分批操作 | 超过 10 个视频时，每 5 个暂停 15-20 秒 |
| 渐进式滚动 | 每次 300-800px，不要一次滚到底 |
| 避免重复访问 | 同一页面不要短时间内反复打开 |

**Playwright 模式下**：scraper.py 已内置 `detect_captcha()` 和 `wait_for_captcha_resolve()` 方法，会自动检测并等待用户处理。使用 headed 模式（有界面）时用户可以直接看到并操作验证码。

**完整选择器参考**：`references/douyin-selectors.md` 末尾的"验证码/反爬检测选择器"章节
**CDP 操作参考**：`references/cdp-patterns.md` 的"验证码/反爬处理"章节

### Step 3: 解析输出

CLI 输出结构化 JSON 到 stdout，Skill 层读取并解析。

**博主输出**：
```json
{
  "blogger_name": "博主名",
  "blogger_id": "MS4wLjABAAAA...",
  "profile": {
    "blogger_name": "博主名",
    "douyin_id": "xxx",
    "fans_count": "762.9万",
    "total_likes": "—",
    "certification": "财经自媒体",
    "description": "简介..."
  },
  "total_videos": 156,
  "scrape_time": "2026-06-25T14:30:00",
  "top_videos": [
    {
      "rank": 1,
      "title": "视频标题",
      "desc": "视频描述",
      "url": "https://www.douyin.com/video/xxx",
      "video_id": "7650453...",
      "like_count": 45000,
      "comment_count": 14000,
      "collect_count": 140000,
      "share_count": 147000,
      "publish_time": "2024-09-13",
      "duration": "约20分钟",
      "tags": "#迪拜 #掘金计划2024",
      "comment_topic": "",
      "top_comments": []
    }
  ]
}
```

**视频输出**：
```json
{
  "title": "视频标题",
  "desc": "视频描述",
  "like_count": 45000,
  "play_count": 8500000,
  "comment_count": 3200,
  "collect_count": 22000,
  "share_count": 9272,
  "publish_time": "2026-06-12",
  "blogger_name": "博主名",
  "top_comments": [{"user": "...", "text": "...", "likes": 1200}]
}
```

### Step 3.5: 评论区深度抓取（博主分析时默认执行）

当用户要求评论区舆论分析时，使用深度抓取：

**命令**：
```bash
# 单个视频评论区
python cli/main.py comments --url <VIDEO_URL> --max 20 --scrolls 3

# 批量视频评论区（博主 Top N 视频时用这个）
python cli/main.py comments --urls <URL1> <URL2> ... --max 20 --scrolls 3
```

**评论区输出**：
```json
{
  "videos": [
    {
      "video_url": "https://www.douyin.com/video/xxx",
      "comments": [{"user": "用户名", "text": "评论内容", "likes": 120}],
      "comment_count_total": 3200,
      "topic_summary": ""
    }
  ],
  "total": 10
}
```

注意：`topic_summary` 字段由 Step 4.5 的 subagent 填充，初始为空字符串。

**CDP 模式替代方案**：详见 `references/cdp-patterns.md`

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
- 评论区话题: {topic_summary}  ← 来自 Step 4.5
- 链接: {url}

...
```

**视频摘要模板**：
```markdown
## 视频「{title}」内容分析

- 博主: {blogger_name}
- 点赞: {likes} | 播放: {plays} | 评论: {comments} | 收藏: {collects} | 转发: {shares}
- 发布时间: {date}

### 内容摘要
[AI 基于标题+文案+热评生成的摘要]

### 评论区话题
{topic_summary}

### 热门评论 Top 5
1. {user}: "{text}" ({likes} 赞)
2. ...
```

### Step 4.5: 评论区话题分析（Subagent 并行）

当 Step 3.5 的评论数据可用时，对每个视频的评论做话题聚类。

**执行方式**：对每个有评论数据的视频 spawn 一个 subagent，所有 subagent 并行运行。

**Subagent Prompt 模板**：
```
你是一个评论区分析助手。以下是视频「{title}」的 Top 20 热门评论：

{comments 列表，每条格式：用户名: "评论文本" (xxx赞)}

请从这些评论中提取 2-4 个主要话题/观点方向，输出一段 100 字以内的中文总结。
格式示例："话题1(xxx%)：核心观点描述；话题2(xxx%)：核心观点描述"
不要输出其他内容。
```

**兜底规则**：
| 场景 | 处理 |
|------|------|
| 某视频评论为空 | 话题列填 "—" |
| Subagent 返回超 100 字 | 截断到 100 字 |
| Subagent 失败/超时 | 话题列填 "（分析失败）" |
| 所有视频都失败 | 不阻塞，继续生成摘要和 Excel |

### Step 4.6: AI 脚本制作深度分析（Subagent 并行）

对博主分析场景，为每个 Top N 视频 spawn 一个 subagent 生成脚本分析，用于 Excel Sheet 3。

**Subagent Prompt 模板**：
```
你是一个短视频脚本分析师。请基于以下视频信息，从脚本制作角度进行深度分析：

视频标题：{title}
视频描述/文案：{desc}
点赞数：{likes}  评论数：{comments}  收藏数：{collects}  转发数：{shares}
标签：{tags}

请输出以下维度的分析（每个维度一段话，50-80字）：
- 核心主题：这个视频在讲什么
- 脚本结构分析：开头-中段-结尾的结构设计
- 叙事手法：用了什么叙事技巧
- 信息呈现方式：如何把信息呈现给观众
- 互动设计：如何引导观众互动
- 话题策略：标签和话题的选择逻辑
- 爆款因素：为什么能火
- 数据洞察：转发率、收藏率、评论互动率等数据洞察

以 JSON 格式输出。
```

### Step 5: 生成 Excel 表格

**使用标准化生成器**（不再手写 Excel 脚本）：

```bash
# 先将数据保存为 JSON
python -c "import json; json.dump(data, open('data/output/temp_data.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=2)"

# 调用生成器
python scripts/generate_excel.py data/output/temp_data.json
```

生成器位置：`scripts/generate_excel.py`，接收 JSON 文件自动生成 3-Sheet Excel。

**Excel 文件路径**: `data/output/YYYY-MM-DD_博主名_Top10视频分析.xlsx`

**Excel 结构**：

Sheet 1 — 博主信息：
| 字段 | 内容 |
|------|------|
| 博主名称 | xxx |
| 抖音号 | xxx |
| 粉丝数 | xxx |
| ... | ... |

Sheet 2 — Top N 视频数据：
| 排名 | 视频标题 | 点赞数 | 评论数 | 收藏数 | 转发数 | 发布日期 | 时长 | 标签 | 评论区话题 | 视频链接 |

注意：
- "评论区话题"列内容为 Step 4.5 生成的话题摘要（≤100字）
- **评论数、收藏数、转发数、发布日期必须从视频详情页获取，禁止从主页数据直接填"—"跳过**（见"数据获取铁律"）

Sheet 3 — AI 脚本制作深度分析（必选）：
| 排名 | 视频标题 | 核心主题 | 脚本结构分析 | 叙事手法 | 信息呈现方式 | 互动设计 | 话题策略 | 爆款因素 | 数据洞察 |

**数据兜底规则**：
- 当某个字段**尽力获取后仍失败**时，在 Excel 中填入 "—" 而非留空
- **禁止"没去获取就填—"** ——"—" 只能表示"获取失败"，不能表示"跳过了获取步骤"
- 不因单个字段缺失而阻塞整个流程

**⚠️ 数据获取铁律（踩坑总结 2026-06-25）**：

主页视频卡片只展示点赞数。评论数、收藏数、转发数、发布日期**必须逐个进入视频详情页获取**。博主分析场景下，阶段二（详情页补全）是必选步骤，不是可选步骤。只有用户明确说"只要点赞排名"时才能跳过。

### Step 5.5: 输出前必检清单（生成 Excel / 摘要前必须逐项检查）

在生成最终输出前，对照以下清单逐项确认。**任何一项不通过都必须返回补全，不能带"—"输出**：

**Sheet 2 数据完整性**：
- [ ] 每个视频的评论数、收藏数、转发数是否有值（非"—"）？
  - 如果是"—"：说明没进详情页获取 → **必须补执行阶段二**
- [ ] 每个视频的发布日期是否有值？
- [ ] 评论区话题列是否已填充（非空）？

**Sheet 3 存在性**：
- [ ] Sheet 3 "AI 脚本制作深度分析" 是否已生成？
  - 如果缺失 → **必须 spawn subagent 并行生成**

**文字摘要完整性**：
- [ ] 每个视频摘要是否包含"评论区话题"行？
- [ ] 博主信息是否完整（粉丝数、获赞数等）？

**自检原则**：当你在做新功能时，特别容易遗漏已有功能。生成输出前**强制过一遍清单**，不要凭记忆假设"都做了"。

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
| DOM 选择器失效 | 尝试备选选择器，最终降级到 JS eval 或截图 |
| Windows python3 不可用 | 使用 `python` 代替 |
| **滑块验证码** | 通知用户手动拖动滑块，轮询等待（最多120秒） |
| **点击文字验证码** | 通知用户按顺序点击文字，轮询等待（最多120秒） |
| **图片选择验证码** | 通知用户选择正确图片，轮询等待（最多120秒） |
| **频率限制（操作频繁）** | 自动等待30秒后刷新重试，连续3次失败则通知用户 |
| **登录过期** | 通知用户在浏览器中重新登录抖音 |

## 注意事项

- 本工具仅用于合法的数据采集和研究用途
- 遵守抖音平台使用条款
- Cookie 文件本地存储，不上传任何服务器
- 首次登录后 Cookie 可复用，无需每次登录
- 抓取频率已内置反爬延迟（3-5 秒随机），请勿修改降低延迟
- 连续访问多个页面时，每 5 个视频暂停 15-20 秒，避免触发频率限制
- 大量抓取时告知用户预估耗时，避免用户以为卡死
