---
name: huya_zhubo_monitor
description: 虎牙/哔哩哔哩/抖音主播直播回放监控分析。触发条件：用户提到"监控XX主播"、"分析XX直播回放"、"帮我找XX的录播"、"查一下XX最近直播"等主播监控相关请求。自动搜索多平台直播回放、下载抽帧、AI分析画面内容、生成Word/PDF报告、更新Excel追踪表格。
---

# 虎牙主播监控分析系统 (huya_zhubo_monitor)

## 核心能力

对指定主播的直播回放进行全自动监控分析：
1. **多平台搜索** — 在虎牙、哔哩哔哩、抖音等平台搜索主播的直播回放/录播
2. **视频下载+抽帧** — 下载回放视频，按时间间隔提取采样帧
3. **AI画面分析** — 逐帧分析画面内容（游戏类型、弹幕、人物、节奏）
4. **报告生成** — 输出 Word (.docx) + PDF 结构化报告
5. **Excel追踪** — 创建/更新主播专属 Excel 监控表格，记录每次分析

## ⚠️ 模型要求（重要！）

**AI分析阶段必须有视觉能力。** 当前使用的 `deepseek-v4-pro` 是纯文本模型，无法读取截图。

处理方式：
- **所有阶段都可以用当前模型完成**，包括下载、抽帧、报告生成、Excel更新
- **唯独 AI 分析截图这一步**，如果当前模型无视觉能力，Claude Code 的 Read 工具读取图片时会失败
- **解决方案**：在调用 `claude` CLI 做分析时，通过 `--model` 参数临时切换到有视觉能力的模型（如 `claude-sonnet-4-6` 或 `claude-opus-4-8`），分析完成后再切回

```bash
# 分析阶段使用 vision 模型
claude -p "$(cat analysis-prompt.md)" --model claude-sonnet-4-6 --output-format text
```

> 如果用户已经配置了 Claude 模型作为默认模型，则无需切换。

## 触发条件

当用户表达以下意图时自动触发本 skill：
- "帮我监控/分析 XX 主播的直播回放"
- "找一下 XX 的录播/回放"
- "查一下 XX 最近在播什么"
- "帮我看看 XX 的直播内容"
- 指定平台："帮我在虎牙/B站/抖音找 XX 的直播"
- 直接给直播回放链接要求分析
- "更新 XX 的监控报告"

## 完整工作流程

```
用户请求 "监控XX主播"
    │
    ├─ 阶段0：搜索定位
    │   ├─ 如果用户给了具体回放链接 → 直接进入阶段1
    │   ├─ 如果只给了主播名 → 多平台搜索
    │   │   ├─ 虎牙: https://www.huya.com/search?hsk={name}
    │   │   ├─ B站: https://search.bilibili.com/all?keyword={name}+录播
    │   │   └─ 抖音: 通过 web-access skill 搜索
    │   └─ 列出找到的回放，让用户选择（或自动选最新）
    │
    ├─ 阶段1：数据收集
    │   ├─ 用 yt-dlp 获取视频信息（标题、时长、上传者）
    │   ├─ 用 ffmpeg 每20分钟提取一帧（最多18帧）
    │   ├─ 生成 raw-data.json（视频元信息+帧路径列表）
    │   └─ 生成 analysis-prompt.md（AI分析提示词）
    │
    ├─ 阶段2：AI分析（需要视觉模型！）
    │   ├─ 用 Read 工具逐帧读取截图
    │   ├─ 按三模块输出结构化报告：
    │   │   ├─ 模块1：主要人物（主播、配角、嘉宾、人员变动）
    │   │   ├─ 模块2：观众反馈（正向、疑问、调侃、负面、热度）
    │   │   └─ 模块3：直播节奏（开场→主体→收尾→整体总结）
    │   └─ 末尾输出 JSON 结构化摘要
    │
    ├─ 阶段3：报告生成
    │   ├─ 生成 Word (.docx)：封面 + 报告正文 + 附录截图
    │   ├─ 生成 PDF：HTML渲染 + Puppeteer打印
    │   └─ 文件命名：{主播名}直播回访总结_{YYYYMMDD}.docx/.pdf
    │
    └─ 阶段4：Excel更新
        ├─ 查找是否已有该主播的Excel文件
        ├─ 有 → 追加新行
        ├─ 无 → 新建文件
        └─ 7列数据写入
```

## 阶段详解

### 阶段0：多平台搜索主播回放

#### 虎牙 (huya.com)
```
搜索URL: https://www.huya.com/search?hsk={主播名}
回放链接格式: https://www.huya.com/video/play/{vid}.html
房间号格式: https://www.huya.com/{房间号}
```
- 用 `web_fetch` 抓取搜索结果页，解析出回放列表
- 或用 `yt-dlp --flat-playlist` 尝试获取房间回放列表
- 虎牙反爬较强，如果自动抓取失败，指导用户手动复制回放链接
- 注意区分"直播间"和"直播回放"：直播间URL不含 `/video/play/`

#### 哔哩哔哩 (bilibili.com)
```
搜索URL: https://search.bilibili.com/all?keyword={主播名}+录播&order=pubdate
视频链接格式: https://www.bilibili.com/video/{BV号}
```
- B站有大量主播录播（粉丝或官方上传）
- 搜索关键词："{主播名} 录播"、"{主播名} 直播录像"、"{主播名} 回放"
- 优先选择标题包含日期的最新视频
- B站视频 yt-dlp 支持良好，下载稳定

#### 抖音 (douyin.com)
- 抖音搜索需要 `web-access` skill（动态渲染）
- 搜索关键词："{主播名} 直播"、"{主播名} 回放"
- 抖音反爬极强，可能需要用户手动提供链接
- 如果用户没有指定平台且各平台都搜不到，告知用户

#### 搜索策略总结
| 优先级 | 平台 | 搜索方式 | 可靠性 |
|--------|------|----------|--------|
| 1 | 虎牙 | web_fetch + yt-dlp | 中等（反爬） |
| 2 | B站 | web_fetch + yt-dlp | 高 |
| 3 | 抖音 | web-access skill | 低（反爬强） |

> 如果用户说"不指定平台"，默认三个平台都搜，优先展示虎牙（官方回放最完整）和B站（最易下载）。

### 阶段1：数据收集

使用脚本 `C:\Users\tiany\wechat-claude-bot\huya-monitor.mjs`：

```bash
node huya-monitor.mjs "<回放URL>" "<工作目录>"
```

脚本自动完成：
1. 用 yt-dlp 获取视频元信息
2. 用 yt-dlp -g 获取真实视频流地址
3. 用 ffmpeg 每20分钟提取一帧 JPEG
4. 生成 `raw-data.json` 和 `analysis-prompt.md`

输出文件结构：
```
{工作目录}/
├── raw-data.json          # 视频信息 + 帧路径列表
├── analysis-prompt.md     # AI分析提示词
├── huya-monitor.log       # 运行日志
├── frame_00_000000.jpg    # 采样帧
├── frame_01_002000.jpg
└── ...
```

**重要**：如果视频超过1小时，yt-dlp下载可能触发 spawnSync 超时（~30-60秒限制）。此时应：
1. 直接在终端（非Claude Code内）运行 yt-dlp 下载视频
2. 或使用 `download-huya-replay.ps1` 脚本
3. 然后对本地文件执行抽帧

### 阶段2：AI分析

这是最核心的步骤。分析提示词已由阶段1自动生成在 `analysis-prompt.md` 中。

**分析流程：**
1. Read 每一帧截图（并行读取，Read工具支持JPEG渲染）
2. 观察画面内容：游戏界面、主播位置、弹幕文字、场景元素
3. 按三大模块输出结构化报告
4. 报告末尾必须包含 JSON 结构化摘要（见下方格式）

**JSON结构化摘要格式（必须输出）：**
```json
{
  "streamer": "主播昵称",
  "roomId": "主播房间号",
  "category": "直播品类（英雄联盟/王者荣耀/CS2/聊天杂谈/户外等）",
  "liveDate": "YYYY-MM-DD",
  "coreSummary": "200字以内的核心精简摘要",
  "keyScreenshots": [
    {"index": 0, "time": "HH:MM:SS", "description": "典型画面描述"},
    {"index": 3, "time": "HH:MM:SS", "description": "另一典型画面描述"}
  ]
}
```

**如果当前模型无视觉能力：**
调用 `claude` CLI 并指定 vision 模型来执行分析：
```bash
claude -p "$(cat analysis-prompt.md)" \
  --model claude-sonnet-4-6 \
  --output-format text \
  --max-turns 15 \
  --dangerously-skip-permissions
```

分析报告保存为 `{工作目录}/report.md`。

### 阶段3：报告生成

使用脚本 `C:\Users\tiany\wechat-claude-bot\report-generator.mjs`：

```bash
# 基本用法（输出到默认目录）
node report-generator.mjs "{工作目录}" "{工作目录}/report.md"

# 同主播多视频时加版本号避免覆盖
node report-generator.mjs "{工作目录}" "{工作目录}/report.md" "" "v2"
```

**输出路径（统一目录结构）：**
```
桌面/主机监/reports/{主播名}/{主播名}直播回访总结_{YYYYMMDD}[_vN].docx
桌面/主机监/reports/{主播名}/{主播名}直播回访总结_{YYYYMMDD}[_vN].pdf
```
- 报告按**主播名**自动分子目录
- 同一主播同一天多个视频时，用 `_v1`, `_v2` ... 后缀区分（第5参数）
- 不传版本号则不加后缀（向后兼容）

### 阶段4：Excel追踪表格更新

使用脚本 `C:\Users\tiany\.claude\skills\huya_zhubo_monitor\scripts\update_excel.py`：

```bash
python update_excel.py \
  --streamer "Letme严君泽" \
  --room-id "660137" \
  --category "英雄联盟" \
  --summary "report-summary.txt" \
  --screenshot "path/to/keyframe.jpg" \
  --live-date "2026-05-29"
  # --excel-dir 可选，默认为 桌面/主机监/excel/
```

**Excel输出路径：**
```
桌面/主机监/excel/{主播昵称}_监控.xlsx
```

**Excel文件规则：**
- 文件名：`{主播昵称}_监控.xlsx`（如 `Letme严君泽_监控.xlsx`）
- 每个主播一个独立文件，同主播的多次监控追加到同一文件
- 新建文件时自动写入表头

**7列结构：**
| 列 | 标题 | 内容 | 格式 |
|----|------|------|------|
| A | 检测时间 | 精确到 YYYY/MM/DD HH:MM | 文本 |
| B | 主播昵称 | 主播名称 | 文本 |
| C | 主播房间号 | 平台房间号 | 文本 |
| D | 主播归属游戏 | 直播游戏品类 | 文本 |
| E | 直播回放内容 | 报告精华（分点列举） | 文本（自动换行） |
| F | 直播间的截图 | 代表性截图 | 嵌入图片 |
| G | 直播间的日期 | 回放日期 YYYY-MM-DD | 文本 |

## 集成到微信 Bot

### 微信触发模式

当微信 Bot 收到以下消息时，自动路由到本 skill：
- `监控 {主播名}` — 搜索该主播最新回放并分析
- `监控 {主播名} {日期}` — 搜索指定日期的回放
- `分析 {链接}` — 直接分析指定回放链接
- `更新 {主播名} 监控` — 查找新回放并追加到 Excel
- `查看 {主播名} 监控` — 读取已有 Excel 返回摘要

### Bot 处理逻辑

在 `bot.mjs` 中，检测到上述模式后：
1. 构建 prompt：`/huya_zhubo_monitor 监控 {主播名} [平台] [日期]`
2. 调用 `claude -p "{prompt}"`（此时 Claude Code 会加载本 skill）
3. 将生成的报告摘要返回微信用户
4. 如果有 Word/PDF 文件生成，告知用户文件位置

### 终端直接使用

在终端直接和 Claude Code 对话即可触发，例如：
```
你：帮我监控Letme的直播回放
你：帮我在B站找Uzi的录播并分析
你：分析这个回放 https://www.huya.com/video/play/1111327536.html
你：更新卡尔的监控表格
```

## 依赖清单

| 工具 | 用途 | 安装方式 |
|------|------|----------|
| yt-dlp | 视频信息获取+下载 | `pip install yt-dlp` |
| ffmpeg | 视频抽帧 | `winget install ffmpeg` 或官网下载 |
| ffprobe | 视频时长探测 | 随 ffmpeg 一起安装 |
| Python 3.9+ | Excel生成脚本 | Windows Store 或官网 |
| openpyxl | Excel读写+图片嵌入 | `pip install openpyxl` |
| Pillow | 图片处理（缩略图） | `pip install Pillow` |
| node.js | 运行 .mjs 脚本 | 已安装 |
| docx (npm) | Word生成 | `npm install docx` |
| puppeteer-core | PDF生成 | `npm install puppeteer-core` |
| Chrome | PDF渲染引擎 | 已安装 |

## 脚本位置

| 脚本 | 路径 | 用途 |
|------|------|------|
| 数据收集 | `C:\Users\tiany\wechat-claude-bot\huya-monitor.mjs` | 下载+抽帧+生成提示词 |
| 完整流水线 | `C:\Users\tiany\wechat-claude-bot\huya-monitor-full.mjs` | 三阶段全自动 |
| 报告生成 | `C:\Users\tiany\wechat-claude-bot\report-generator.mjs` | Word+PDF生成 |
| 下载辅助 | `C:\Users\tiany\wechat-claude-bot\download-huya-replay.ps1` | PS下载脚本 |
| 备用流水线 | `C:\Users\tiany\wechat-claude-bot\huya_pipeline.py` | Python 4阶段 |
| Excel更新 | `C:\Users\tiany\.claude\skills\huya_zhubo_monitor\scripts\update_excel.py` | Excel追踪表格 |

## 统一目录结构规范

所有监控输出文件必须归入以下统一目录结构，**禁止直接输出到桌面根目录**：

```
C:\Users\tiany\Desktop\主机监\
├── reports/                    # Word/PDF 报告（按主播分子目录）
│   ├── 卡尔/
│   │   ├── 卡尔直播回访总结_20250529.docx
│   │   └── 卡尔直播回访总结_20250529.pdf
│   ├── Letme严君泽/
│   │   └── ...
│   ├── Chalice/                # 同主播多视频用 _v1, _v2 区分
│   │   ├── Chalice直播回访总结_20250529_v1.docx
│   │   ├── Chalice直播回访总结_20250529_v2.docx
│   │   └── ...
│   └── CSBOY/
│       └── ...
├── excel/                      # Excel 追踪表格（统一存放）
│   ├── 卡尔_监控.xlsx
│   ├── Letme严君泽_监控.xlsx
│   └── ...
└── archives/                   # 原始工作目录（按日期归档）
    └── 20250530/
        └── huya_monitor_20250530/  # 含各子目录 + report.md 等
```

**路径常量定义：**
- `MONITOR_ROOT` = `{USERPROFILE}/Desktop/主机监`
- `REPORTS_DIR` = `{MONITOR_ROOT}/reports`
- `EXCEL_DIR` = `{MONITOR_ROOT}/excel`
- `ARCHIVES_DIR` = `{MONITOR_ROOT}/archives`

## 常见问题

### Q: 虎牙回放需要登录怎么办？
A: 一般公开回放不需要登录。如果遇到需要登录的情况，用浏览器打开链接确认可访问性，然后把可访问的链接提供给脚本。yt-dlp 支持传 cookies：`yt-dlp --cookies-from-browser chrome`。

### Q: 视频下载太慢怎么办？
A: 可以限制分辨率 `-f "best[height<=720]"` ，或只下载音频+关键帧。对超长直播（>3小时），考虑只分析部分片段。

### Q: AI分析结果不准确？
A: 采样帧间隔可调整（默认20分钟）。减小间隔（如10分钟）能获得更多帧但增加token消耗。确认使用了视觉模型。

### Q: Excel中截图显示不正常？
A: openpyxl 嵌入的图片是锚定到单元格的，不是真正的"单元格内图片"。调整列宽和行高可以改善显示。截图会自动缩放到适合单元格的大小。

### Q: 多个平台都搜不到主播回放？
A: 告知用户可能的原因：主播没有公开回放、平台反爬限制、主播已注销等。建议用户手动提供回放链接。

## 执行注意事项

1. **始终先确认模型能力** — 如果当前会话模型是 `deepseek-v4-pro`，在分析阶段必须切换到 vision 模型
2. **长视频分段处理** — 超过3小时的直播，考虑分段分析避免token爆炸
3. **文件路径用绝对路径** — 所有脚本参数使用绝对路径
4. **错误处理** — 每个阶段失败时明确告知用户哪个环节出错，不要静默跳过
5. **Excel追加前检查** — 先检查是否已有同日期同主播的记录，避免重复
6. **截图保留** — 采样帧在报告生成后保留，方便后续查看
7. **微信回复精简** — 通过微信返回时，控制在1500字以内，核心摘要+文件位置即可
8. **统一输出目录** — 所有报告/Excel/归档文件必须输出到 `桌面/主机监/` 下对应子目录，禁止散落桌面根目录
9. **同主播多视频版本号** — 同一主播同一天有多个视频时，调用 report-generator.mjs 必须传入版本号（v1/v2/...），否则后生成的报告会覆盖先前的
