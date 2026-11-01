---
name: comprehensive-douyin-scapper
description: 抖音博主全量视频点赞排名快速采集工具。给定博主名称，自动搜索并爬取其所有视频的点赞量，生成极简Excel（6列）。不进详情页，2-5分钟完成。触发词："全量视频"、"所有视频点赞"、"博主全部视频"、"comprehensive douyin"、"comprehensive-douyin-scapper"、"爬取全部视频"、"博主点赞排名"。
---

# Comprehensive Douyin Scapper — 博主全量视频点赞排名

快速爬取抖音博主全部视频的点赞排名，仅取主页可见数据（不进详情页），2-8分钟完成。

## 项目位置

- 项目根目录: `C:\Users\tiany\Desktop\comprehensive-douyin-scapper`
- CLI 入口: `C:\Users\tiany\Desktop\comprehensive-douyin-scapper\cli\main.py`
- Cookie 文件: 共享 `C:\Users\tiany\Desktop\douyin-playwright\data\cookie.json`（或项目自有 `data/cookie.json`）
- Excel 输出: `C:\Users\tiany\Desktop\comprehensive-douyin-scapper\data\output\`

## 核心功能

给博主名称 → 自动搜索 → 抓取全部视频（仅主页数据） → 生成极简Excel

## 使用方式

### 一键执行（推荐）

```bash
cd C:\Users\tiany\Desktop\comprehensive-douyin-scapper
python cli/main.py blogger-by-name "博主名称"
```

内部自动完成：搜索博主 → 取粉丝最高者 → 全量滚动主页 → 按点赞排序 → 生成Excel

### 分步执行

**1. 搜索博主**:
```bash
python cli/main.py search "博主名称"
```

**2. 全量抓取（需URL）**:
```bash
python cli/main.py blogger "https://www.douyin.com/user/XXX" --all
```

**3. 仅 Top N（原有功能）**:
```bash
python cli/main.py blogger "https://www.douyin.com/user/XXX" --top 20
```

## 执行流程

### Step 0: 环境预检

```bash
cd C:\Users\tiany\Desktop\comprehensive-douyin-scapper

python --version
python -c "import playwright; import pydantic; import openpyxl; print('deps OK')"
python -c "from playwright.sync_api import sync_playwright; p = sync_playwright().start(); b = p.chromium.launch(headless=True); b.close(); p.stop(); print('browser OK')"
```

如果 Playwright Chromium 不可用，降级为 CDP 模式（使用用户本地 Chrome）。

### Step 1: 确认登录态

CDP 模式天然携带用户 Chrome 登录态，只需确认 Chrome 远程调试已开启：

```bash
node "C:\Users\tiany\.claude\skills\web-access\scripts\check-deps.mjs"
```

需要看到 `chrome: ok (port 9222)` 和 `proxy: ready`。

如果显示 `chrome: not connected`，引导用户在 Chrome 中访问 `chrome://inspect/#remote-debugging` 开启远程调试。

Playwright 模式下运行：

```bash
python cli/main.py check-auth
```

### Step 2: 一键执行

```bash
python cli/main.py blogger-by-name "博主名称"
```

### Step 3: 交付结果

输出 JSON 包含：blogger_name, fans_count, total_videos, excel_path

**Excel 6列**: 博主名称 | 博主粉丝数 | 视频排名 | 视频标题 | 点赞数 | 视频链接

文件名格式: `YYYY-MM-DD_博主名_全量视频点赞排名.xlsx`

## 实战经验（重要！先读）

这些是从真实抓取中总结的教训，直接影响执行策略：

### 1. 抖音的滚动容器不是 `window`，而是 `.route-scroll-container`

抖音使用 react-router，页面有一个内部滚动容器：
- CSS class: `parent-route-container AGITGpbK route-scroll-container fnucI`
- `window.scrollBy()` / `window.scrollTo()` 对这个容器完全无效
- 必须找到该容器，对其设置 `scrollTop` 或调用 `scrollBy()`
- 此外还有一个内层视频列表容器 `.ulxic5B4.NnMU21s2`，也需要滚动

### 2. 必须 dispatch WheelEvent 才能触发懒加载

仅仅修改 `scrollTop` 值不会触发抖音的懒加载逻辑。必须在容器上同时 dispatch `WheelEvent`：

```javascript
var rc = document.querySelector('.route-scroll-container');
rc.scrollTop = rc.scrollHeight;  // 跳到最底
rc.dispatchEvent(new WheelEvent('wheel', {deltaY: 800, deltaMode: 0, bubbles: true, cancelable: true}));
rc.dispatchEvent(new Event('scroll', {bubbles: true}));
```

每次滚动后等 2-4 秒让新内容加载（`scrollHeight` 会增长）。重复直到 `scrollHeight` 不再增长。

### 3. 大量视频需要多轮滚动到底

实测数据（黄士铨看世界，1905个视频）：
- scrollHeight 从初始 5478 → 15000 → 50000 → 116790
- 每次跳到底 + wheel event 加载约 50-60 个视频
- 总共需要 40+ 轮滚动才能到底
- 每轮等 3-4 秒，total ~5-8 分钟（含页面解析和Excel生成）

### 4. 页面尾部会混入抖音推荐流内容

滚到底后，页面会塞入非本博主的推荐视频（如 CAD教学、汉服妆容等，点赞都是 0）。这些可以从标题内容识别出来 — 与本博主领域（财经/宏观经济）完全无关的就是混入的。

### 5. 粉丝数和博主名从搜索页获取更可靠

博主主页的 `innerText` 中粉丝数正则可能匹配失败（取决于 DOM 结构）。从搜索页提取更可靠 — 搜索结果显示 "183.7万粉丝" 等结构化文本。

### 6. Windows 控制台编码问题

Windows 终端默认 GBK 编码，`print("✅")` 会报 `UnicodeEncodeError`。所有 emoji 输出需避免，或设置 `PYTHONIOENCODING=utf-8`。最安全的做法是只用 ASCII 字符输出状态信息。

### 7. 视频标题提取 — 行模式解析

主页视频卡片的 `a` 标签 `innerText` 是多行的，结构通常是：
```
置顶
4.5万

沃什议息首秀！加息还是缩表? #美联储 #美元
```
解析策略：遍历每一行，匹配点赞数字正则 `^[0-9.]+[万亿w]?$` 的行作为点赞数，跳过点赞行之后的行拼接为标题。注意有些视频没有置顶标记但结构相同。

### 8. 搜索时自动取粉丝最高的匹配者

搜索页可能返回多个同名/相似名博主。代码会自动解析粉丝量（支持"万"/"亿"后缀），选粉丝量最高的作为 `selected`。在搜索结果页的 `innerText` 中就能看到粉丝数。

## Excel 说明

- 仅1个 Sheet，无 AI 分析
- 按点赞数降序排列，排名1=点赞最高
- 点赞数保留原始格式（如"4.5万"）
- 缺失字段填入"—"，不阻塞流程

## 耗时预估

| 视频数量 | 预估耗时 |
|----------|----------|
| <50个 | 约2-3分钟 |
| 50-200个 | 约3-5分钟 |
| 200-1000个 | 约5-8分钟 |
| 1000-2000个 | 约8-12分钟 |

## 与原 douyin-playwright 的区别

| | comprehensive-douyin-scapper | douyin-playwright |
|---|---|---|
| 输入 | 博主名称 | 博主URL |
| 视频范围 | 全部 | Top N |
| 数据来源 | 仅主页 | 主页+详情页 |
| 详情页数据 | 不进 | 进（评论/收藏/转发/时长/标签） |
| Excel列 | 6列极简 | 多Sheet含AI分析 |
| AI摘要 | 无 | 有 |
| 速度 | 快（2-12分钟） | 慢（10分钟+） |
| 滚动方式 | CDP 直接操作 scroll container | Playwright page.evaluate |

## 降级策略

| 优先级 | 方式 | 适用场景 |
|--------|------|----------|
| 1 | Playwright CLI | Chromium 可用，Cookie 有效 |
| 2 | CDP Proxy + 用户 Chrome | Chromium 不可用或 Cookie 失效（**最常用**） |
| 3 | 截图 + OCR | DOM 解析完全失败 |

## CDP 模式操作要点

当使用 CDP Proxy（`http://localhost:3456`）时：

1. 打开页面：`curl -s "http://localhost:3456/new?url=<URL>"`
2. 执行 JS：`curl -s -X POST "http://localhost:3456/eval?target=<TARGET_ID>" -d "<JS_CODE>"`
3. 找滚动容器：`document.querySelector('.route-scroll-container')`
4. 滚动+触发懒加载：设置 `scrollTop` + dispatch `WheelEvent` + dispatch `scroll` event
5. 提取视频：`document.querySelectorAll('a[href*="/video/"]')`

## 错误处理

| 错误场景 | 处理方式 |
|----------|----------|
| Cookie 不存在/过期 | 引导运行 auth 登录 |
| CDP Proxy 未就绪 | 引导用户开启 Chrome 远程调试 |
| 搜不到博主 | 返回 NO_MATCH 错误 |
| 验证码 | 自动检测+截图识别+等待手动完成（120秒超时） |
| 页面加载超时 | 重试1次，仍失败则跳过 |
| 抓取字段为空 | Excel 中填入 "—" |
| 滚动无新内容 | 连续 8 轮 `scrollHeight` 不增长则停止 |
| emoji 编码错误 | 避免使用 emoji 字符，只用 ASCII |

## 注意事项

- 本工具仅用于合法的数据采集和研究用途
- 遵守抖音平台使用条款
- Cookie 文件本地存储，不上传任何服务器
- 抓取频率已内置反爬延迟（1-3秒随机），请勿修改降低延迟
- CDP 模式下用户 Chrome 天然携带登录态，无需额外处理 Cookie
- 视频量 >500 时告知用户预估耗时，避免用户以为卡死
