# 抖音 Playwright 数据采集工具

基于 Playwright 的抖音数据采集 CLI 工具 + Claude Skill，支持博主主页 Top N 高赞视频分析和单个视频摘要，输出 AI 文字总结 + Excel 表格。

## 功能

- ✅ 博主主页 Top N 高赞视频抓取（标题、点赞、播放、评论、文案、热评）
- ✅ 单个视频详情抓取
- ✅ AI 文字摘要生成（Claude Skill 层）
- ✅ Excel 表格导出（调用 xlsx skill）
- ✅ Cookie 手动登录 + 复用
- ✅ Cookie 过期自动检测

## 安装

### 方式 1：一键安装（Windows）

右键运行 `scripts/setup.ps1`

### 方式 2：手动安装

```bash
pip install -r requirements.txt
playwright install chromium
```

## 使用

### 1. 登录

```bash
python cli/main.py auth
```

弹出浏览器，手动扫码或短信登录抖音，完成后按 Enter 保存 Cookie。

### 2. 验证 Cookie

```bash
python cli/main.py check-auth
```

### 3. 抓取博主主页

```bash
python cli/main.py blogger "https://www.douyin.com/user/MS4wLjABAAAAxxx" --top 10
```

### 4. 抓取单个视频

```bash
python cli/main.py video "https://www.douyin.com/video/1234567890"
```

## Claude Skill

将 `skill/SKILL.md` 复制到 Claude Code skills 目录即可使用：

```bash
cp -r skill/douyin-playwright ~/.claude/skills/
```

或在 Claude Code 对话中直接调用。

## 项目结构

```
douyin-playwright/
├── cli/           # CLI 工具
├── skill/         # Claude Skill
├── data/          # Cookie + Excel 输出
├── tests/         # 测试
└── scripts/       # 安装脚本
```

## 测试

```bash
pytest tests/ -v
```

## 注意事项

- 本工具仅用于合法的数据采集和研究用途
- 遵守抖音平台使用条款
- Cookie 文件本地存储，不上传任何服务器
