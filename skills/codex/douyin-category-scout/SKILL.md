---
name: douyin-category-scout
description: 抖音类目博主搜索工具。给定关键词，自动搜索并抓取 Top 100 博主的名称、粉丝数、获赞数、主页链接（调用搜索API分页，不需DOM滚动），生成极简Excel（4列）。不进主页，1-3分钟完成。
---

# Douyin Category Scout — 抖音类目博主搜索

按关键词搜索抖音博主类目，通过搜索 API 分页获取 Top 100 博主。

## 项目位置

- Skill 目录: `C:\Users\tiany\.claude\skills\douyin-category-scout\`
- 脚本目录: `C:\Users\tiany\.claude\skills\douyin-category-scout\scripts\`
- CLI 入口: `C:\Users\tiany\.claude\skills\douyin-category-scout\scripts\main.py`
- Cookie 共享: `C:\Users\tiany\Desktop\douyin-playwright\data\cookie.json`
- Excel 输出: `C:\Users\tiany\.claude\skills\douyin-category-scout\output\`

## 触发词

"类目搜索"、"抖音类目"、"category scout"、"搜XXX博主"、"搜索XXX类目"、"帮我找XXX的博主"、"XXX类目有哪些博主"、"搞笑幽默博主"、"美妆博主粉丝" 等。

## 使用方式

### 一键搜索

```bash
cd C:\Users\tiany\.claude\skills\douyin-category-scout
python scripts/main.py scout "搞笑幽默"
```

### 自定义数量

```bash
python scripts/main.py scout "短剧" --max 50
```

## 执行流程

### Step 0: 环境预检

```bash
cd C:\Users\tiany\.claude\skills\douyin-category-scout

python --version
python -c "import playwright; import pydantic; import openpyxl; print('deps OK')"
python -c "from playwright.sync_api import sync_playwright; p = sync_playwright().start(); b = p.chromium.launch(headless=True); b.close(); p.stop(); print('browser OK')"
```

如果 Playwright Chromium 不可用，降级为 CDP 模式（使用用户本地 Chrome）。

### Step 1: 确认登录态

CDP 模式天然携带用户 Chrome 登录态。Playwright 模式下确认 Cookie 存在：

```bash
dir "C:\Users\tiany\Desktop\douyin-playwright\data\cookie.json"
```

如果文件不存在，先运行 `douyin-playwright` 的 auth 登录。

### Step 2: 执行搜索

```bash
python scripts/main.py scout "关键词"
```

内部流程：
1. 浏览器打开 `https://www.douyin.com/search/{关键词}?type=user` 建立 cookie 上下文
2. 在页面内调用搜索 API 逐页获取用户列表（`/aweme/v1/web/discover/search/`）
3. API 返回结构化 JSON：`user_info.nickname` / `follower_count` / `total_favorited` / `sec_uid`
4. 无需 DOM 解析和滚动——API 直接分页
5. 去重 → 按粉丝数降序 → 截 Top 100 → 生成 4 列 Excel

### Step 3: 交付结果

输出 JSON 包含：keyword, total_found, top_count, excel_path

**Excel 4 列**: 博主名称 | 粉丝数 | 获赞数 | 博主主页链接

文件名格式: `YYYY-MM-DD_关键词_抖音博主Top100.xlsx`

## 耗时预估

| 搜索结果规模 | API 分页 | 预估耗时 |
|------------|---------|---------|
| <100 个结果 | 3-7 页 | ~30-60 秒 |
| 100-300 个结果 | 7-20 页 | ~1-3 分钟 |
| 300+ 个结果 | 20+ 页 | ~3-5 分钟 |

## 实战经验（重要！先读）

### 1. 搜索页 ≠ 博主主页——API 分页而非 DOM 滚动

**关键教训**：抖音搜索页的搜索结果通过 XHR API 分页加载，DOM 滚动（包括 `WheelEvent`、`scrollTop`、`.route-scroll-container` 等）**完全无效**。无论怎么滚，scrollHeight 始终不增长，user card 数量不变。

正确做法：在浏览器 context 中 `fetch()` 调用搜索 API：
```
https://www.douyin.com/aweme/v1/web/discover/search/
  ?device_platform=webapp&aid=6383&channel=channel_pc_web
  &search_channel=aweme_user_web
  &keyword={关键词}
  &search_source=normal_search&query_correct_type=1&is_filter_search=0
  &offset={游标}&count=15
  &pc_client_type=1&version_code=170400&version_name=17.4.0
  &cookie_enabled=true&screen_width=1920&screen_height=1080
```

API 返回结构化 JSON：
```json
{
  "user_list": [{
    "user_info": {
      "nickname": "磁力短剧",
      "follower_count": 6993000,
      "total_favorited": 85031000,
      "sec_uid": "MS4wLjAB..."
    }
  }],
  "cursor": 15,
  "has_more": 1
}
```

### 2. API 参数的坑

- `count` 必须用 15（与实际页面请求一致），用 50/30/10 会触发 `invalid_count` 返回空
- 必须带完整的设备指纹参数（`cookie_enabled=true&screen_width=1920&screen_height=1080` 等）
- `offset=0` 不带 `count` → 返回空；不带 `cookie_enabled=true` → 可能返回空
- API 只能从搜索页 context 调用（需先在搜索页建立 cookie 上下文），不能裸调

### 3. CDP eval 异步超时

CDP `Runtime.evaluate` 有超时限制。单次 eval 不能循环多页——会被 kill。正确做法：逐页 eval，shell 层串行循环，每页等 1.5s 反爬延迟。

### 4. Windows 控制台编码

Windows 终端默认 GBK 编码。CLI 输出中避免使用 emoji，只输出 ASCII 和中文。必要时设置 `PYTHONIOENCODING=utf-8`。

## Excel 说明

- 仅 1 个 Sheet，无 AI 分析
- 按粉丝数降序排列
- 粉丝数/获赞数保留原始格式（如"183.5万"、"8503.1万"）
- 缺失字段填入 "—"，不阻塞流程

## 降级策略

| 优先级 | 方式 | 适用场景 |
|--------|------|----------|
| 1 | Playwright + fetch API | Chromium 可用，Cookie 有效（首选） |
| 2 | CDP Proxy + eval fetch | Chromium 不可用（**最常用**） |
| 3 | 截图 + OCR | 完全兜底 |

## 错误处理

| 错误场景 | 处理方式 |
|----------|----------|
| Cookie 不存在/过期 | 引导运行 auth 登录 |
| API 返回空列表 | 返回空结果，提示用户换关键词 |
| 验证码 | 等待手动完成（页面不关，120s 超时） |
| API 单页超时 | 停止当页，返回已收集数据 |
| 抓取字段为空 | Excel 中填入 "—" |

## 注意事项

- 本工具仅用于合法的数据采集和研究用途
- 遵守抖音平台使用条款
- Cookie 文件本地存储，不上传任何服务器
- 抓取频率已内置反爬延迟（1.5s/页），不可降低
- 不进任何博主主页，所有数据来自搜索 API
