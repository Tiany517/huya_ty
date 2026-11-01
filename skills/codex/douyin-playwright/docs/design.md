# 抖音 Playwright 数据采集 Skill 设计文档

**日期**: 2026-06-25
**版本**: 2.0
**作者**: Claude + 用户协作

---

## 1. 项目概述

基于 Playwright 构建一个抖音数据采集工具，支持两种核心场景：
1. **博主主页分析** → 抓取所有视频，按点赞排序，输出 Top N 高赞视频的文字摘要 + Excel 表格（3-Sheet）
2. **单个视频分析** → 抓取视频标题、文案、点赞、播放、评论、收藏、转发等数据，输出摘要 + Excel 表格

**架构模式**: CLI 工具 + Skill AI 总结层 + CDP 降级模式

---

## 2. 项目结构

```
C:\Users\tiany\Desktop\douyin-playwright/
├── cli/                          # CLI 工具（Playwright 抓取层）
│   ├── __init__.py
│   ├── main.py                   # CLI 入口（auth / check-auth / blogger / video / comments）
│   ├── auth.py                   # 登录流程：扫码/短信 + Cookie 保存
│   ├── cookie_manager.py         # Cookie 加载/验证/过期检测
│   ├── scraper.py                # Playwright 核心抓取逻辑（v1+v2 合并版）
│   ├── models.py                 # 数据模型（Pydantic，含完整字段）
│   └── utils.py                  # 辅助函数（异步延迟、数字解析、ID提取）
├── scripts/
│   └── generate_excel.py         # 标准化 Excel 生成器（3-Sheet，从 JSON 输入）
├── skill/
│   ├── SKILL.md                  # Claude Skill 定义文件
│   ├── evals/
│   │   └── evals.json            # 测试用例
│   └── references/
│       ├── douyin-selectors.md   # 已验证的 DOM 选择器参考
│       └── cdp-patterns.md       # CDP 模式操作参考
├── data/                         # 运行时数据
│   ├── cookie.json               # Playwright storage_state（Cookie）
│   └── output/                   # Excel 输出目录
├── tests/                        # 测试
│   ├── test_models.py
│   ├── test_utils.py
│   └── test_cookie_manager.py
├── docs/
│   └── design.md                 # 本设计文档
├── requirements.txt
├── README.md
└── .gitignore
```

**核心依赖**: `playwright`, `pydantic`, `openpyxl`

---

## 3. CLI 命令

```bash
# 登录
python cli/main.py auth

# 验证 Cookie
python cli/main.py check-auth

# 博主主页分析（两阶段：主页列表 + 详情页补全）
python cli/main.py blogger <URL> --top 10

# 单个视频分析
python cli/main.py video <URL>

# 评论区深度抓取
python cli/main.py comments --url <VIDEO_URL> --max 20 --scrolls 3
python cli/main.py comments --urls <URL1> <URL2> ... --max 20 --scrolls 3
```

---

## 4. 数据模型

### Video 模型（完整字段）

| 字段 | 类型 | 说明 | 来源 |
|------|------|------|------|
| rank | int | 排名 | Skill 层赋值 |
| title | str | 标题 | 详情页 |
| desc | str | 描述/文案 | 详情页 |
| url | str | 链接 | 主页/详情页 |
| video_id | str | 视频ID | URL 提取 |
| like_count | int | 点赞数 | 主页/详情页 |
| play_count | int | 播放量 | 详情页 |
| comment_count | int | 评论数 | 详情页 |
| collect_count | int | 收藏数 | 详情页 |
| share_count | int | 转发数 | 详情页 |
| publish_time | str | 发布日期 | 详情页 |
| duration | str | 时长 | 详情页 |
| tags | str | 标签 | 详情页 |
| comment_topic | str | 评论区话题 | Subagent 填充 |
| top_comments | List[Comment] | 热门评论 | 详情页 |

### BloggerProfile 模型

| 字段 | 类型 | 说明 |
|------|------|------|
| blogger_name | str | 博主名 |
| douyin_id | str | 抖音号 |
| fans_count | str | 粉丝数 |
| total_likes | str | 获赞数 |
| total_videos | str | 作品数 |
| certification | str | 认证 |
| description | str | 简介 |
| ip_location | str | IP属地 |
| sec_user_id | str | sec_user_id |
| profile_url | str | 主页链接 |

---

## 5. 两阶段抓取策略

### 阶段一：主页列表（快）

1. 打开博主主页
2. 滚动加载视频列表
3. 提取每个视频的：视频ID、标题、点赞数
4. 按点赞排序取 Top N

### 阶段二：详情页补全（慢，**必选**）

1. 对 Top N 每个视频打开详情页
2. 提取：评论数、收藏数、转发数、发布时间、时长、标签、热门评论
3. 反爬延迟 1-3 秒

**铁律**：博主分析场景下阶段二是必选步骤，除非用户明确说"只要点赞排名"。

---

## 6. Excel 输出格式（3-Sheet）

### Sheet 1: 博主信息

键值对格式，包含博主名、抖音号、粉丝数、获赞数、认证、简介、主页链接、抓取时间等。

### Sheet 2: Top N 视频数据

| 排名 | 视频标题 | 点赞数 | 评论数 | 收藏数 | 转发数 | 发布日期 | 时长 | 标签 | 评论区话题 | 视频链接 |

### Sheet 3: AI 脚本制作深度分析

| 排名 | 视频标题 | 核心主题 | 脚本结构分析 | 叙事手法 | 信息呈现方式 | 互动设计 | 话题策略 | 爆款因素 | 数据洞察 |

**生成方式**：使用 `scripts/generate_excel.py`，接收 JSON 文件自动生成。

---

## 7. CDP 降级模式

当 Playwright Chromium 不可用时，使用 web-access Skill 的 CDP Proxy 操作用户本地 Chrome。

**优势**：
- 天然携带用户登录态
- 真实 Chrome 环境不容易被检测

**劣势**：
- 需要 Chrome 开启远程调试
- 逐页操作耗时较长

**详细操作参考**: `skill/references/cdp-patterns.md`

---

## 8. AI 分析层

### 评论区话题分析（Step 4.5）

- 对每个有评论数据的视频 spawn 一个 subagent
- Prompt 要求提取 2-4 个主要话题/观点方向
- 输出 ≤100 字的话题摘要
- Subagent 使用 Haiku 模型（快、便宜）

### 脚本制作深度分析（Step 4.6）

- 对每个 Top N 视频 spawn 一个 subagent
- 从脚本制作角度分析 8 个维度
- Subagent 使用 Sonnet 模型（深度分析需要）

---

## 9. 博主名搜索

当用户提供博主名而非 URL 时：

1. CDP 模式打开 `https://www.douyin.com/search/博主名?type=user`
2. 提取搜索结果中第一个匹配的用户链接
3. 确认用户名匹配后获取主页 URL
4. 进入正常抓取流程

---

## 10. 安全与合规

- 本工具仅用于合法的数据采集和研究用途
- 遵守抖音平台使用条款，不采集付费/私密内容
- 控制抓取频率，避免对平台造成压力
- Cookie 文件本地存储，不上传任何服务器

---

**设计状态**: ✅ v2.0 已完成
