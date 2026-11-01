# 评论区话题聚类分析 — 功能设计规格

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在抖音博主 Top N 视频分析中，增加评论区话题聚类分析，每个视频输出 100 字以内的话题摘要

**Architecture:** Python 抓取层零改动，在 SKILL.md 层新增 Step 4.5（评论话题分析），通过 spawn 并行 subagent 对每个视频的评论做 AI 话题聚类，结果写入 Excel 新列和文字摘要

**Tech Stack:** Claude subagent（Skill 层并行）+ 现有 Python 抓取流程 + openpyxl

## Global Constraints

- Python 抓取层（cli/scraper.py, cli/models.py, cli/main.py）不做任何改动
- 每个视频的话题摘要严格 ≤ 100 字
- 话题分析必须在 AI 文字摘要（Step 4）之前完成
- 分析失败不阻塞主流程，填"（分析失败）"兜底
- 不需要用户配置任何 API Key
- CDP 模式下行为一致

---

## 1. 数据流变更

### 现有流程

```
Step 0: 环境预检
Step 1: 确认登录态
Step 2: 判断场景并执行抓取 → JSON 输出（含 top_comments）
Step 3: 解析 JSON
Step 4: AI 生成文字摘要
Step 5: 生成 Excel
```

### 新流程

```
Step 0: 环境预检
Step 1: 确认登录态
Step 2: 判断场景并执行抓取 → JSON 输出（含 top_comments）
Step 3: 解析 JSON
Step 4.5: 评论话题分析 ← 新增
Step 4: AI 生成文字摘要（现在可引用话题数据）
Step 5: 生成 Excel（增加"评论区话题"列）
```

### 为什么 4.5 在 4 之前

AI 摘要和 Excel 都需要引用话题分析结果，因此话题分析必须先完成。

## 2. Subagent 并行分析机制

### 触发条件

当抓取结果中 `top_comments` 非空时，自动触发话题分析。仅博主主页分析场景涉及（单视频场景也可用，但只有一个视频无需并行）。

### 执行方式

Skill 读取 JSON 后，对每个有评论的视频 spawn 一个 subagent，所有 subagent 并行运行。

### Subagent Prompt 模板

```
你是一个评论区分析助手。以下是视频「{title}」的 Top 10 热门评论：

{comments 列表，每条格式：用户名: "评论文本" (xxx赞)}

请从这些评论中提取 2-4 个主要话题/观点方向，输出一段 100 字以内的中文总结。
格式示例："话题1(xxx%)：核心观点描述；话题2(xxx%)：核心观点描述"
不要输出其他内容。
```

### 输出格式

每个 subagent 返回一段 ≤ 100 字的中文文本。

### 兜底规则

| 场景 | 处理 |
|------|------|
| 某视频评论为空 | 话题列填 "—" |
| Subagent 返回超 100 字 | 截断到 100 字 |
| Subagent 失败/超时 | 话题列填 "（分析失败）" |
| 所有视频都失败 | 不阻塞，继续生成摘要和 Excel |

### 耗时预估

10 个 subagent 并行 ≈ 3-5 秒。

## 3. 输出变更

### Excel Sheet 2（Top N 视频数据）

现有列顺序：排名 | 视频标题 | 点赞数 | 评论数 | 收藏数 | 转发数 | 发布日期 | 时长 | 标签 | 视频链接

新增列：**评论区话题**（插在"视频链接"之前）

变更后：排名 | 视频标题 | 点赞数 | 评论数 | 收藏数 | 转发数 | 发布日期 | 时长 | 标签 | **评论区话题** | 视频链接

- 列宽：30（与"标签"列一致）
- 对齐：wrap_text=True, vertical="top"
- 空值填 "—"

### 文字摘要（Step 4 博主摘要模板）

在每个视频的摘要段落中增加一行：

```
- 评论区话题: {话题分析结果}
```

位置：在"关键话题"行之后、"链接"行之前。

### Sheet 3（AI 脚本制作深度分析）

不变。评论话题属于数据层，放 Sheet 2 即可。

### 单视频场景

文字摘要中同样增加"评论区话题"行，不生成 Excel 时也生效。

## 4. SKILL.md 改动清单

在 SKILL.md 中需要修改的部分：

1. **Step 3 与 Step 4 之间**：新增 Step 4.5 完整描述，包含触发条件、subagent prompt 模板、兜底规则
2. **Step 4 博主摘要模板**：视频摘要段落增加"评论区话题"行
3. **Step 4 视频摘要模板**：增加"评论区话题"行
4. **Step 5 Excel 结构**：Sheet 2 列定义增加"评论区话题"列
5. **Step 2 耗时预估**：更新为"阶段一 + 阶段二 + 评论分析：约 3-6 分钟"（增加 3-5 秒几乎无感，但应提及）

## 5. 不改动的部分

- `cli/scraper.py` — 抓取逻辑不变
- `cli/models.py` — Comment/Video 模型不变
- `cli/main.py` — CLI 入口不变
- `data/output/generate_excel_v2.py` — 参考模板，运行时由 Skill 动态生成 Excel
- Sheet 1（博主信息）— 不变
- Sheet 3（AI 脚本制作深度分析）— 不变
- 降级策略 — 不变（分析在 Skill 层，与抓取方式无关）
- 错误处理 — 不变（增加评论分析失败的兜底即可）
