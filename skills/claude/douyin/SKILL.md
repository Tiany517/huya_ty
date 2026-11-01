---
name: douyin
description: 抖音/TikTok数据爬取与下载工具。通过 DouK-Downloader (TikTokDownloader) 项目提供抖音和TikTok的数据采集能力。触发场景：用户提到"下载抖音视频"、"爬抖音评论"、"抖音搜索"、"采集抖音数据"、"下载TikTok视频"、"抖音账号数据"、"抖音热榜"、"直播拉流"、"抖音合集"等抖音/TikTok数据采集相关请求时使用此skill。也适用于用户想要批量下载某人的抖音作品、获取视频评论、搜索抖音内容、导出抖音数据为CSV/XLSX等场景。
---

# 抖音/TikTok 数据爬取 Skill

基于 [DouK-Downloader](https://github.com/JoeanAmier/TikTokDownloader) (V5.8 Beta) 项目，提供抖音和 TikTok 的数据采集与下载能力。

## 项目位置

- 项目根目录: `C:\Users\tiany\TikTokDownloader`
- 配置文件: `C:\Users\tiany\TikTokDownloader\settings.json`
- 入口脚本: `C:\Users\tiany\TikTokDownloader\main.py`

## 工作方式

本 skill 通过启动 DouK-Downloader 的 **Web API 服务模式** 来工作。服务基于 FastAPI，启动后提供 RESTful API 接口，skill 通过 httpx 调用这些接口完成数据采集。

### 启动 API 服务

```bash
cd C:\Users\tiany\TikTokDownloader && python main.py --server
```

服务默认监听 `http://127.0.0.1:5555`，启动后访问 `http://127.0.0.1:5555/docs` 可查看完整 API 文档。

如果服务已在运行，直接使用即可。每次使用 skill 时，先检查服务是否已运行：

```bash
curl -s http://127.0.0.1:5555/docs > /dev/null 2>&1 && echo "running" || echo "not_running"
```

若未运行则启动它（后台运行）。

## Cookie 配置

抖音和 TikTok 的多数功能需要登录 Cookie。Cookie 在 `settings.json` 的 `cookie` 和 `cookie_tiktok` 字段配置。

获取 Cookie 的方法：
1. 用浏览器登录抖音网页版 (douyin.com) 或 TikTok 网页版 (tiktok.com)
2. 打开开发者工具 (F12) → Network → 刷新页面 → 找到任意请求的 Cookie 头
3. 复制完整 Cookie 字符串写入 settings.json

如果用户未配置 Cookie，skill 应提醒用户先配置，否则部分功能可能无法正常使用。

写入 Cookie 的方法：通过 API 更新配置，或直接修改 settings.json 文件。

## TikTok 代理检查（重要）

TikTok 在中国大陆无法直接访问，需要代理。**所有 TikTok 操作前必须先检查代理是否可用。**

### 检查流程

在执行任何 TikTok 相关操作之前，运行 `scripts/check_proxy.py` 检测本地代理：

```bash
python C:\Users\tiany\.claude\skills\douyin\scripts\check_proxy.py
```

脚本会检测以下常见代理端口：
- Clash: 7890 (HTTP), 7891 (SOCKS5)
- V2Ray/Xray: 10808 (SOCKS5), 10809 (HTTP)
- Shadowsocks: 1080 (SOCKS5)

脚本返回 JSON 结果：
- `{"proxy_available": true, "proxy_url": "http://127.0.0.1:7890"}` → 代理可用，自动写入 settings.json 的 proxy_tiktok 字段
- `{"proxy_available": false}` → 代理不可用，**停止 TikTok 操作**，提示用户

提示语：
> TikTok 需要代理才能访问，请先开启 Clash/V2Ray 等代理软件，然后重试。如果代理已开启但仍检测失败，请手动在 settings.json 中配置 proxy_tiktok 字段。

**抖音功能不受此限制**，无需代理即可使用。

## 核心功能与 API 调用

所有 API 调用使用 httpx POST，请求头需携带 `token`（默认无需令牌，公开部署需设置）。

### 1. 下载单个作品（抖音）

```
POST /douyin/detail
Body: {"detail_id": "<作品ID>", "cookie": "<可选>", "source": false}
```

作品 ID 可从分享链接中提取，或先通过 `/douyin/share` 解析分享链接获取。

### 2. 下载账号作品（抖音）

```
POST /douyin/account
Body: {
  "sec_user_id": "<账号sec_uid>",
  "tab": "post",        // post/favorite/collection
  "earliest": "",       // 最早日期
  "latest": "",         // 最晚日期
  "pages": 10,          // 最大页数
  "cookie": "<可选>",
  "source": false
}
```

### 3. 爬取评论数据（抖音）

```
POST /douyin/comment
Body: {
  "detail_id": "<作品ID>",
  "pages": 5,           // 评论页数
  "cookie": "<可选>",
  "source": false
}
```

评论数据会保存为 CSV/XLSX 文件，取决于 settings.json 的 storage_format 设置。

### 4. 爬取评论回复（抖音）

```
POST /douyin/reply
Body: {
  "detail_id": "<作品ID>",
  "comment_id": "<评论ID>",
  "pages": 3,
  "cookie": "<可选>",
  "source": false
}
```

### 5. 搜索数据（抖音）

```
POST /douyin/search/general  // 综合搜索
POST /douyin/search/video    // 视频搜索
POST /douyin/search/user     // 用户搜索
POST /douyin/search/live     // 直播搜索

Body: {
  "keyword": "<关键词>",
  "pages": 3,
  "cookie": "<可选>",
  "source": false,
  ... (其他可选参数见 API 文档)
}
```

### 6. 合集数据（抖音）

```
POST /douyin/mix
Body: {
  "mix_id": "<合集ID>",     // 或 detail_id
  "cookie": "<可选>",
  "source": false
}
```

### 7. 直播数据（抖音）

```
POST /douyin/live
Body: {
  "web_rid": "<直播间web_rid>",
  "cookie": "<可选>",
  "source": false
}
```

### 8. 分享链接解析

```
POST /douyin/share
Body: {"text": "<分享文本/短链接>", "proxy": "<可选>"}
```

### 9. TikTok 功能

所有 TikTok API 端点路径以 `/tiktok/` 替换 `/douyin/`，如：
- `/tiktok/detail` — TikTok 单个作品
- `/tiktok/account` — TikTok 账号作品
- `/tiktok/mix` — TikTok 合辑
- `/tiktok/live` — TikTok 直播

**TikTok 操作前必须检查代理**（见上方代理检查流程）。

### 10. 更新配置

```
POST /settings
Body: {<需要更新的配置字段>}
```

可用于动态更新 cookie、proxy 等配置。

```
GET /settings
```

获取当前完整配置。

## 数据导出

采集的数据默认保存到 `C:\Users\tiany\TikTokDownloader\Download\` 目录下。

存储格式由 settings.json 的 `storage_format` 字段决定：
- `csv` — CSV 文件
- `xlsx` — Excel 文件
- `sqlite` — SQLite 数据库
- `text` — 纯文本

视频文件默认下载到 Download 目录，文件夹命名由 `folder_mode` 和 `name_format` 控制。

## 从分享链接提取 ID

用户提供的抖音分享链接通常是短链接格式，需要先解析：

```python
import httpx
response = httpx.post("http://127.0.0.1:5555/douyin/share",
    json={"text": "7.47 EHi:/ 复制打开抖音，看看... https://v.douyin.com/xxxxx/"})
```

返回的 URL 中包含作品 ID 或 sec_user_id，可用于后续 API 调用。

## 常见使用场景

| 场景 | 操作流程 |
|------|----------|
| 用户说"下载这个抖音视频" | 1. 解析分享链接获取 detail_id → 2. 调用 /douyin/detail 下载 |
| 用户说"下载某人的全部抖音作品" | 1. 解析账号链接获取 sec_user_id → 2. 调用 /douyin/account 下载 |
| 用户说"爬这个视频的评论" | 1. 获取 detail_id → 2. 调用 /douyin/comment 采集 → 3. 告知数据保存路径 |
| 用户说"搜索抖音上的XX" | 1. 调用 /douyin/search/general → 2. 展示搜索结果 |
| 用户说"下载TikTok视频" | 1. **检查代理** → 2. 有代理则继续 → 3. 调用 /tiktok/detail |
| 用户说"抖音热榜数据" | 调用 /douyin/hot（需 Cookie） |
| 用户说"导出抖音数据为Excel" | 先设置 storage_format=xlsx → 再执行采集操作 |

## 错误处理

- Cookie 未配置：提醒用户配置 Cookie，部分功能仍可使用（如公开视频下载）
- 服务未启动：先启动服务再操作
- TikTok 代理不可用：停止操作，提示用户开启代理
- API 返回失败：检查 Cookie 是否有效，或参数是否正确，给用户明确反馈

## 注意事项

- 本工具仅用于合法的数据采集和研究用途，请遵守抖音/TikTok 平台使用条款
- 不要采集付费内容（项目本身不支持付费作品下载）
- 私密账号需要使用已关注该账号的登录 Cookie
- Cookie 影响下载视频的分辨率质量，登录 Cookie 能获取更高清晰度
