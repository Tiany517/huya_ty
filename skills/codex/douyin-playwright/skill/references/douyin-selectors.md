# 抖音 DOM 选择器参考（已验证）

> 最后验证日期: 2026-06-25
> 注意：抖音 DOM 结构频繁变动，以下选择器按优先级排列，使用时逐个尝试。

## 视频详情页选择器

| 字段 | 首选选择器 | 备选选择器 | 备注 |
|------|-----------|-----------|------|
| 视频标题 | `h1[class*='title']` | `[data-e2e='video-title']` | — |
| 视频描述 | `[class*='desc']` | `[data-e2e='video-desc']` | — |
| 点赞数 | `[data-e2e='video-player-digg']` | `[data-e2e='like-count']`, `[class*='like-count']` | ✅ 已验证 |
| 评论数 | `[data-e2e='feed-comment-icon']` | `[data-e2e='comment-count']`, `[class*='comment-count']` | ✅ 已验证（图标区域含数字） |
| 收藏数 | `[data-e2e='video-player-collect']` | `[class*='collect-count']` | ✅ 已验证 |
| 转发数 | `[data-e2e='video-player-share']` | `[class*='share-count']` | ✅ 已验证 |
| 发布时间 | `[data-e2e='detail-video-publish-time']` | `[class*='publish-time']`, `[class*='time']` | ✅ 已验证 |

## 博主主页选择器

| 字段 | 选择器 | 备注 |
|------|--------|------|
| 视频列表容器 | `[data-e2e='user-post-list']` | — |
| 视频卡片 | `[data-e2e='user-post-list'] a` 或 `a[href*='/video/']` | — |
| 博主名 | `h1[class*='title']` | — |
| 粉丝数 | `[data-e2e='user-info'] [class*='fan']` | — |

## 评论区选择器

| 字段 | 首选选择器 | 备选选择器 | 备注 |
|------|-----------|-----------|------|
| 评论列表 | `[data-e2e='comment-list']` | `[class*='comment-list']` | — |
| 评论条目 | `[data-e2e='comment-item']` | `[class*='comment-item']` | — |
| 用户名 | `a[href*='/user/']` | `[class*='user-name']` | ✅ 已验证：用户名在 a 标签内 |
| 评论内容 | `.Pmn4RZdg` | `[data-e2e='comment-content']`, `[class*='comment-text']` | ✅ 已验证（2026-06） |
| 点赞数 | `.ormFoAZF` | `[data-e2e='comment-like-count']`, `[class*='digg']` | ✅ 已验证（2026-06） |
| 展开评论区 | `[data-e2e='comment-entry']` | `[class*='comment-entry']` | — |

## JS 降级提取脚本

当 CSS 选择器全部失效时，用 JavaScript 直接遍历 DOM：

```javascript
// 提取评论区
const results = [];
document.querySelectorAll('[data-e2e="comment-item"]').forEach(item => {
    const userLink = item.querySelector('a[href*="/user/"]');
    const user = userLink ? userLink.innerText.split('\n')[0].trim() : '';
    const textEl = item.querySelector('.Pmn4RZdg, [class*="comment-text"]');
    const text = textEl ? textEl.innerText.trim() : '';
    const likeEl = item.querySelector('.ormFoAZF, [class*="like-count"]');
    const likes = likeEl ? likeEl.innerText.trim().split('\n')[0] : '0';
    if (text) results.push({user, text, likes});
});
return JSON.stringify(results);
```

## 选择器维护原则

1. **优先使用 `data-e2e` 属性** — 这类属性是抖音的端到端测试锚点，比 class 名更稳定
2. **`[class*='xxx']` 模糊匹配作备选** — class 名经常变，但关键词通常保留
3. **JS 遍历是终极兜底** — 直接用 `document.querySelectorAll` + 属性/文本匹配
4. **验证日期标注** — 每个选择器标注最后验证日期，超过 3 个月的需重新验证

## 验证码/反爬检测选择器

> 最后验证日期: 2026-06-25

### 滑块验证码

| 选择器 | 来源 | 备注 |
|--------|------|------|
| `#captcha_container` | 抖音原生 | 最常见 |
| `[class*='captcha-slider']` | 抖音原生 | 滑块容器 |
| `[class*='captcha_verify']` | 抖音原生 | 验证弹窗 |
| `[class*='verify-wrap']` | 抖音原生 | 验证外层 |
| `[class*='nc_wrapper']` | 阿里 NoCaptcha | 第三方滑块 |
| `#nc_1_wrapper` | 阿里 NoCaptcha | 阿里滑块容器 |
| `[class*='sm-pop-btn']` | 数美 | 第三方验证 |

### 点击文字验证码

| 选择器 | 来源 | 备注 |
|--------|------|------|
| `[class*='captcha-click']` | 抖音原生 | 点击类验证 |
| `[class*='click-verify']` | 抖音原生 | 点击验证容器 |
| `[class*='select-text']` | 抖音原生 | 文字选择 |
| `[class*='word-verify']` | 抖音原生 | 文字验证 |

### 图片选择验证码

| 选择器 | 来源 | 备注 |
|--------|------|------|
| `[class*='captcha-image']` | 抖音原生 | 图片验证 |
| `[class*='image-verify']` | 抖音原生 | 图片选择验证 |
| `[class*='pic-verify']` | 抖音原生 | 图片识别验证 |

### 频率限制/登录过期（文本检测）

| 关键词 | 含义 |
|--------|------|
| "操作频繁" | 频率限制 |
| "请求过于频繁" | 频率限制 |
| "请稍后再试" | 频率限制 |
| "访问受限" | IP/账号限制 |
| "登录已过期" | 需重新登录 |
| "请先登录" | 未登录/登录失效 |
| "重新登录" | 登录过期 |

### URL 级别检测

页面 URL 包含 `captcha` 或 `verify` 时，视为进入验证流程。

### CDP 模式下验证码检测 JS

```javascript
// 一键检测当前页面是否存在验证码
(() => {
    const checks = [
        // 滑块
        {sel: '#captcha_container, [class*="captcha-slider"], [class*="captcha_verify"], [class*="verify-wrap"], [class*="nc_wrapper"], #nc_1_wrapper, [class*="sm-pop-btn"]', type: 'slider', msg: '检测到滑块验证码'},
        // 点击文字
        {sel: '[class*="captcha-click"], [class*="click-verify"], [class*="select-text"], [class*="word-verify"]', type: 'click_text', msg: '检测到点击文字验证码'},
        // 图片选择
        {sel: '[class*="captcha-image"], [class*="image-verify"], [class*="pic-verify"]', type: 'image_select', msg: '检测到图片选择验证码'},
    ];
    for (const c of checks) {
        if (document.querySelector(c.sel)) return JSON.stringify({detected: true, type: c.type, message: c.msg});
    }
    const body = document.body.innerText || '';
    for (const kw of ['操作频繁', '请求过于频繁', '请稍后再试', '访问受限']) {
        if (body.includes(kw)) return JSON.stringify({detected: true, type: 'rate_limit', message: '频率限制: ' + kw});
    }
    for (const kw of ['登录已过期', '请先登录', '重新登录']) {
        if (body.includes(kw)) return JSON.stringify({detected: true, type: 'login_expired', message: kw});
    }
    if (location.href.includes('captcha') || location.href.includes('verify')) {
        return JSON.stringify({detected: true, type: 'unknown', message: '页面跳转到验证页'});
    }
    return JSON.stringify({detected: false, type: 'none', message: ''});
})()
```
