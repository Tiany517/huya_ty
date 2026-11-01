# CDP 模式操作参考

> 使用 web-access skill 的 CDP Proxy 操作用户本地 Chrome

## 前置条件

```bash
node "C:/Users/tiany/.claude/skills/web-access/scripts/check-deps.mjs"
```

需要 Node.js 22+ 和 Chrome 开启远程调试（`chrome://inspect/#remote-debugging` → 勾选 "Allow remote debugging"）。

## 常用操作

### 创建新 tab 并导航
```bash
curl -s "http://localhost:3456/new?url=https://www.douyin.com/user/MS4wLjABAAAA..."
```

### 提取页面数据（eval）
```bash
curl -s -X POST "http://localhost:3456/eval?target=<ID>" -d 'document.title'
```

### 点击元素
```bash
curl -s -X POST "http://localhost:3456/click?target=<ID>" -d '[data-e2e="comment-entry"]'
```

### 精确坐标点击（用于验证码点击）
```bash
# /clickAt 使用 CDP Input.dispatchMouseEvent，模拟真实鼠标点击
# 传入 CSS 选择器，自动定位元素中心点击
curl -s -X POST "http://localhost:3456/clickAt?target=<ID>" -d '<CSS选择器>'
```

### 滚动加载
```bash
curl -s "http://localhost:3456/scroll?target=<ID>&direction=bottom"
curl -s "http://localhost:3456/scroll?target=<ID>&y=3000"
```

### 截图
```bash
curl -s "http://localhost:3456/screenshot?target=<ID>&file=/tmp/shot.png"
```

### 关闭 tab
```bash
curl -s "http://localhost:3456/close?target=<ID>"
```

## 抖音专用操作模式

### 博主主页抓取流程

1. 创建 tab 打开博主主页
2. 等待 3 秒加载
3. 滚动到底部多次，提取视频卡片数据
4. 对 Top N 视频，逐个创建新 tab 打开详情页
5. 提取详情页数据（点赞/评论/收藏/转发/发布时间）
6. 关闭详情页 tab

### 视频详情页数据提取 JS

```javascript
// 一次性提取所有数据
JSON.stringify({
    title: document.querySelector('h1[class*="title"]')?.innerText?.trim() || '',
    likes: document.querySelector('[data-e2e="video-player-digg"]')?.innerText?.trim() || '',
    comments: document.querySelector('[data-e2e="feed-comment-icon"]')?.innerText?.trim() || '',
    collects: document.querySelector('[data-e2e="video-player-collect"]')?.innerText?.trim() || '',
    shares: document.querySelector('[data-e2e="video-player-share"]')?.innerText?.trim() || '',
    publishTime: document.querySelector('[data-e2e="detail-video-publish-time"]')?.innerText?.trim() || '',
})
```

### 评论区展开 + 提取 JS

```javascript
// 1. 点击展开评论区
const entry = document.querySelector('[data-e2e="comment-entry"]');
if (entry) entry.click();

// 2. 等待后提取
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
JSON.stringify(results);
```

## 注意事项

- CDP 模式天然携带用户登录态，无需单独处理 Cookie
- 同一 Chrome 实例可同时操作多个 tab（不同 targetId），无竞态
- 短时间密集打开大量页面可能触发反爬风控，建议每页间隔 3-5 秒
- 子 Agent 可各自创建/关闭 tab，互不干扰

## 验证码/反爬处理（CDP 模式）

### 检测验证码

每次页面加载后，**必须先执行验证码检测**，再进行数据提取：

```bash
# 检测当前页面是否存在验证码
curl -s -X POST "http://localhost:3456/eval?target=<ID>" -d '(() => {
    const checks = [
        {sel: "#captcha_container, [class*=\"captcha-slider\"], [class*=\"captcha_verify\"], [class*=\"verify-wrap\"], [class*=\"nc_wrapper\"], #nc_1_wrapper, [class*=\"sm-pop-btn\"]", type: "slider"},
        {sel: "[class*=\"captcha-click\"], [class*=\"click-verify\"], [class*=\"select-text\"], [class*=\"word-verify\"]", type: "click_text"},
        {sel: "[class*=\"captcha-image\"], [class*=\"image-verify\"], [class*=\"pic-verify\"]", type: "image_select"},
    ];
    for (const c of checks) {
        if (document.querySelector(c.sel)) return JSON.stringify({detected: true, type: c.type});
    }
    const body = document.body.innerText || "";
    for (const kw of ["操作频繁", "请求过于频繁", "请稍后再试", "访问受限"]) {
        if (body.includes(kw)) return JSON.stringify({detected: true, type: "rate_limit"});
    }
    for (const kw of ["登录已过期", "请先登录", "重新登录"]) {
        if (body.includes(kw)) return JSON.stringify({detected: true, type: "login_expired"});
    }
    if (location.href.includes("captcha") || location.href.includes("verify")) {
        return JSON.stringify({detected: true, type: "unknown"});
    }
    return JSON.stringify({detected: false, type: "none"});
})()'
```

### 验证码处理流程

```
检测到验证码
├── 滑块验证码 (slider)
│   ├── 方案1: 截图识别滑块位置 → 用 clickAt + 拖拽自动完成（难度高，推荐方案2）
│   └── 方案2: 通知用户手动拖动滑块 → 轮询等待验证码消失（每3秒检测1次，最多120秒）
│
├── 点击文字验证码 (click_text) ← AI 自动处理
│   └── 截图 → 识别提示文字和待点击字符 → 依次 clickAt 正确字符
│
├── 图片选择验证码 (image_select) ← AI 自动处理
│   └── 截图 → 识别提示文字和候选图片 → 依次 clickAt 正确图片
│
├── 频率限制 (rate_limit)
│   └── 自动等待30秒 → 刷新页面 → 重新检测
│       └── 仍然限制？ → 通知用户，等待60秒后重试
│
├── 登录过期 (login_expired)
│   └── 通知用户在 Chrome 中重新登录 → 等待用户确认后继续
│
└── 未知验证类型 (unknown)
    └── 截图 → 识别验证码类型 → 按对应策略处理
```

### AI 自动处理点击类验证码（核心流程）

当检测到 `click_text` 或 `image_select` 类型验证码时，执行以下流程：

#### 步骤 1：截图

```bash
curl -s "http://localhost:3456/screenshot?target=<ID>&file=C:/Users/tiany/AppData/Local/Temp/captcha_screenshot.png"
```

#### 步骤 2：读取截图，识别验证码内容

用 Read 工具读取截图（支持 PNG/JPG），AI 视觉识别：
- 验证码的提示文字（如"请依次点击：人、山、水"）
- 待点击目标的位置（字符/图片在屏幕上的坐标）
- 点击顺序

#### 步骤 3：定位目标元素坐标

用 eval 获取验证码区域中各可点击元素的精确坐标：

```bash
# 获取验证码容器内所有可点击字符/图片的位置和内容
curl -s -X POST "http://localhost:3456/eval?target=<ID>" -d '(() => {
    const container = document.querySelector(
        "[class*=\"captcha-click\"], [class*=\"click-verify\"], " +
        "[class*=\"select-text\"], [class*=\"word-verify\"], " +
        "[class*=\"captcha-image\"], [class*=\"image-verify\"], " +
        "[class*=\"pic-verify\"], " +
        "#captcha_container, [class*=\"captcha_verify\"], [class*=\"verify-wrap\"]"
    );
    if (!container) return JSON.stringify({error: "no captcha container found"});

    // 获取提示文字
    const promptEl = container.querySelector("[class*=\"prompt\"], [class*=\"title\"], [class*=\"desc\"]");
    const prompt = promptEl ? promptEl.innerText.trim() : "";

    // 获取所有可点击子元素
    const items = container.querySelectorAll(
        "[class*=\"click-item\"], [class*=\"char\"], [class*=\"word\"], " +
        "[class*=\"img-item\"], [class*=\"pic-item\"], [class*=\"select-item\"], " +
        "img, canvas"
    );

    const targets = [];
    items.forEach((el, i) => {
        const rect = el.getBoundingClientRect();
        targets.push({
            index: i,
            x: Math.round(rect.left + rect.width / 2),
            y: Math.round(rect.top + rect.height / 2),
            width: Math.round(rect.width),
            height: Math.round(rect.height),
            text: el.innerText?.trim() || "",
            tag: el.tagName,
        });
    });

    return JSON.stringify({prompt, targets, containerRect: {
        x: container.getBoundingClientRect().left,
        y: container.getBoundingClientRect().top,
        width: container.getBoundingClientRect().width,
        height: container.getBoundingClientRect().height,
    }});
})()'
```

#### 步骤 4：AI 判断并点击

根据截图识别 + DOM 坐标信息，AI 判断正确的点击顺序，然后：

```bash
# 方式1：如果目标有 CSS 选择器，用 clickAt（模拟真实鼠标事件）
curl -s -X POST "http://localhost:3456/clickAt?target=<ID>" -d '<选择器>'

# 方式2：如果需要精确坐标点击，用 eval + CDP 命令
curl -s -X POST "http://localhost:3456/eval?target=<ID>" -d '(() => {
    // 在坐标 (x, y) 处模拟点击
    const el = document.elementFromPoint(X, Y);
    if (el) el.click();
    return "clicked";
})()'
```

**点击策略**：逐个点击，每次点击后等待 0.5-1 秒再点下一个，模拟人类操作节奏。

#### 步骤 5：验证结果

点击完成后，等待 2 秒重新检测验证码：

```bash
# 等待后重新检测
sleep 2
curl -s -X POST "http://localhost:3456/eval?target=<ID>" -d '<验证码检测JS>'
```

- 验证码消失 → 继续抓取
- 验证码仍在 → 可能点击错误，重新截图识别（最多重试 3 次）
- 刷新出新的验证码 → 重新执行步骤 1-4

#### 完整自动处理伪代码

```
retry_count = 0
while retry_count < 3:
    1. 截图 → 读取识别
    2. 获取验证码元素坐标
    3. AI 判断点击顺序
    4. 依次点击目标（每个间隔 0.5-1 秒）
    5. 等待 2 秒
    6. 检测验证码是否消失
       - 消失 → 成功，继续抓取
       - 仍在 → retry_count++，重新识别
如果 3 次都失败 → 通知用户手动完成，轮询等待
```

### 滑块验证码处理

滑块验证码难度较高（需要精确拖拽），推荐优先让用户手动完成。

**自动尝试方案**（可选，成功率约 60-70%）：

```bash
# 1. 截图识别滑块和缺口位置
curl -s "http://localhost:3456/screenshot?target=<ID>&file=C:/Users/tiany/AppData/Local/Temp/slider_captcha.png"

# 2. 获取滑块按钮位置
curl -s -X POST "http://localhost:3456/eval?target=<ID>" -d '(() => {
    const slider = document.querySelector(
        "[class*=\"slider-btn\"], [class*=\"drag-btn\"], " +
        "[class*=\"nc_iconfont\"], [class*=\"btn_slide\"], " +
        "#nc_1__scale_text span"
    );
    if (!slider) return JSON.stringify({error: "no slider found"});
    const rect = slider.getBoundingClientRect();
    return JSON.stringify({
        x: Math.round(rect.left + rect.width / 2),
        y: Math.round(rect.top + rect.height / 2),
    });
})()'

# 3. 用 left_click_drag 拖拽滑块
# 从滑块位置向右拖拽到缺口位置
# 需要截图识别缺口位置后计算拖拽距离
```

**注意**：滑块验证码自动通过率不高，如果自动失败应立即通知用户手动完成，不要反复重试浪费机会（多次失败可能触发更严格的验证）。

### 轮询等待验证码消失

```bash
# 每3秒检测1次，直到验证码消失
for i in $(seq 1 40); do
    result=$(curl -s -X POST "http://localhost:3456/eval?target=<ID>" -d '<检测JS>')
    if echo "$result" | grep -q '"detected":false'; then
        echo "验证码已消失，继续操作"
        break
    fi
    echo "等待验证码完成... ($i/40)"
    sleep 3
done
```

### 频率限制自动恢复

```bash
# 检测到"操作频繁"时的处理
# 1. 等待30秒
sleep 30

# 2. 刷新页面
curl -s "http://localhost:3456/navigate?target=<ID>&url=<SAME_URL>"

# 3. 等待加载后重新检测
sleep 3

# 4. 如果仍然限制，等待更长时间
# sleep 60
```

### 反爬预防措施

1. **页面间隔 3-5 秒** — 不要密集打开页面，每个详情页之间至少等待 3 秒
2. **随机化延迟** — 使用 3-8 秒的随机延迟，而非固定间隔
3. **分批操作** — 超过 10 个视频时，每 5 个暂停 15-20 秒
4. **避免重复访问** — 同一页面不要在短时间内反复打开
5. **模拟人类行为** — 滚动时使用渐进式滚动（每次 300-800px），不要一次到底
6. **验证码后冷却** — 通过验证码后，额外等待 5-10 秒再继续操作，避免连续触发
