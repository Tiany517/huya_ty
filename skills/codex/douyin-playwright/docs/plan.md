# 抖音 Playwright 数据采集 Skill - 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建一个基于 Playwright 的抖音数据采集 CLI 工具 + Claude Skill，支持博主主页 Top N 高赞视频分析和单个视频摘要，输出 AI 文字总结 + Excel 表格。

**Architecture:** 纯 CLI 架构。CLI 层（Playwright）负责浏览器自动化抓取，输出结构化 JSON；Skill 层负责调用 CLI、AI 生成摘要、调用 xlsx skill 生成 Excel。Cookie 手动登录后复用。

**Tech Stack:** Python 3.10+, Playwright, Pydantic, pytest

## Global Constraints

- Python >= 3.10
- Playwright >= 1.40.0
- Pydantic >= 2.0.0
- 项目根目录: `C:\Users\tiany\Desktop\douyin-playwright`
- Cookie 文件: `data/cookie.json`（Playwright storage_state 格式）
- 所有 CLI 输出为 JSON 到 stdout
- 错误输出为 `{"error": "CODE", "message": "..."}` 格式
- 反爬延迟: 操作间 1-3 秒随机延迟
- 失败重试: 2 次
- Excel 输出路径: `data/output/YYYY-MM-DD_名称.xlsx`

---

## File Structure

```
douyin-playwright/
├── cli/
│   ├── __init__.py
│   ├── models.py              # Pydantic 数据模型（Video, BloggerResult, VideoResult）
│   ├── utils.py               # 工具函数（random_delay, format_number, extract_id_from_url）
│   ├── cookie_manager.py      # Cookie 加载/保存/验证
│   ├── auth.py                # 登录流程（headed 浏览器，扫码/短信）
│   ├── scraper.py             # Playwright 核心抓取（博主主页 + 单个视频）
│   └── main.py                # CLI 入口（argparse，路由到各子命令）
├── skill/
│   └── SKILL.md               # Claude Skill 定义
├── data/
│   ├── output/                # Excel 输出目录
│   └── .gitignore             # 忽略 cookie.json 和 output/*
├── tests/
│   ├── test_models.py
│   ├── test_utils.py
│   ├── test_cookie_manager.py
│   ├── test_auth.py
│   └── test_main.py
├── scripts/
│   └── setup.ps1              # Windows 一键安装
├── docs/
│   ├── design.md
│   └── plan.md                # 本文件
├── requirements.txt
├── README.md
└── .gitignore
```

---

### Task 1: 项目脚手架

**Files:**
- Create: `requirements.txt`
- Create: `.gitignore`
- Create: `data/.gitignore`
- Create: `cli/__init__.py`
- Create: `tests/__init__.py`
- Create: `skill/.gitkeep`
- Modify: 初始化 git 仓库

**Interfaces:**
- Produces: 项目目录结构，无代码接口

- [ ] **Step 1: 初始化 git 仓库**

```bash
cd C:\Users\tiany\Desktop\douyin-playwright
git init
git branch -m main
```

- [ ] **Step 2: 创建 requirements.txt**

```text
playwright>=1.40.0
pydantic>=2.0.0
pytest>=7.0.0
pytest-asyncio>=0.21.0
```

- [ ] **Step 3: 创建 .gitignore**

```text
__pycache__/
*.pyc
*.pyo
.env
data/cookie.json
data/output/
.pytest_cache/
.vscode/
.idea/
```

- [ ] **Step 4: 创建 data/.gitignore**

```text
cookie.json
output/*
!.gitkeep
```

- [ ] **Step 5: 创建空 __init__.py 文件**

```bash
touch cli/__init__.py tests/__init__.py
touch data/output/.gitkeep
```

- [ ] **Step 6: 安装依赖并验证**

```bash
cd C:\Users\tiany\Desktop\douyin-playwright
pip install -r requirements.txt
playwright install chromium
python -c "import playwright; print('playwright ok')"
python -c "import pydantic; print('pydantic ok')"
```

Expected: 所有导入成功

- [ ] **Step 7: Commit**

```bash
git add .
git commit -m "chore: project scaffolding"
```

---

### Task 2: 数据模型

**Files:**
- Create: `cli/models.py`
- Create: `tests/test_models.py`

**Interfaces:**
- Produces: `Comment`, `Video`, `BloggerResult`, `VideoResult` Pydantic 模型
- Produces: `CliError` 错误模型

- [ ] **Step 1: 写测试**

Create `tests/test_models.py`:

```python
import pytest
from cli.models import Comment, Video, BloggerResult, VideoResult, CliError


class TestComment:
    def test_comment_creation(self):
        c = Comment(user="用户A", text="评论内容", likes=1200)
        assert c.user == "用户A"
        assert c.text == "评论内容"
        assert c.likes == 1200

    def test_comment_defaults(self):
        c = Comment(user="用户B", text="test")
        assert c.likes == 0


class TestVideo:
    def test_video_creation(self):
        v = Video(
            rank=1,
            title="视频标题",
            desc="视频描述",
            url="https://www.douyin.com/video/123",
            like_count=1000,
            play_count=5000,
            comment_count=100,
            publish_time="2024-06-15",
            top_comments=[Comment(user="A", text="nice", likes=10)]
        )
        assert v.rank == 1
        assert v.like_count == 1000
        assert len(v.top_comments) == 1


class TestBloggerResult:
    def test_blogger_result_creation(self):
        result = BloggerResult(
            blogger_name="测试博主",
            blogger_id="MS4wLjABAAAA",
            total_videos=100,
            top_videos=[Video(rank=1, title="t", desc="d", url="https://x", like_count=1, play_count=1, comment_count=1)]
        )
        assert result.blogger_name == "测试博主"
        assert len(result.top_videos) == 1

    def test_blogger_result_json(self):
        result = BloggerResult(
            blogger_name="测试博主",
            blogger_id="id",
            total_videos=10,
            top_videos=[]
        )
        data = result.model_dump()
        assert data["blogger_name"] == "测试博主"
        assert "scrape_time" in data


class TestVideoResult:
    def test_video_result_creation(self):
        result = VideoResult(
            title="标题",
            desc="描述",
            like_count=100,
            play_count=500,
            comment_count=10,
            blogger_name="博主",
            blogger_id="id"
        )
        assert result.title == "标题"


class TestCliError:
    def test_error_json(self):
        err = CliError(code="TEST_ERROR", message="测试错误")
        data = err.model_dump()
        assert data["error"] == "TEST_ERROR"
        assert data["message"] == "测试错误"
```

- [ ] **Step 2: 运行测试（期望失败）**

```bash
cd C:\Users\tiany\Desktop\douyin-playwright
pytest tests/test_models.py -v
```

Expected: `ModuleNotFoundError: No module named 'cli.models'`

- [ ] **Step 3: 实现数据模型**

Create `cli/models.py`:

```python
from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, Field


class Comment(BaseModel):
    """评论模型"""
    user: str
    text: str
    likes: int = 0


class Video(BaseModel):
    """视频模型"""
    rank: int
    title: str
    desc: str = ""
    url: str
    like_count: int = 0
    play_count: int = 0
    comment_count: int = 0
    publish_time: str = ""
    top_comments: List[Comment] = Field(default_factory=list)


class BloggerResult(BaseModel):
    """博主抓取结果"""
    blogger_name: str
    blogger_id: str
    total_videos: int = 0
    scrape_time: str = Field(default_factory=lambda: datetime.now().isoformat())
    top_videos: List[Video] = Field(default_factory=list)


class VideoResult(BaseModel):
    """单个视频抓取结果"""
    title: str
    desc: str = ""
    like_count: int = 0
    play_count: int = 0
    comment_count: int = 0
    publish_time: str = ""
    blogger_name: str = ""
    blogger_id: str = ""
    top_comments: List[Comment] = Field(default_factory=list)


class CliError(BaseModel):
    """CLI 错误输出模型"""
    error: str
    message: str

    def model_dump(self, **kwargs):
        return {"error": self.error, "message": self.message}
```

- [ ] **Step 4: 运行测试（期望通过）**

```bash
pytest tests/test_models.py -v
```

Expected: 所有 7 个测试 PASS

- [ ] **Step 5: Commit**

```bash
git add tests/test_models.py cli/models.py
git commit -m "feat: add pydantic data models"
```

---

### Task 3: 工具函数

**Files:**
- Create: `cli/utils.py`
- Create: `tests/test_utils.py`

**Interfaces:**
- Produces: `random_delay()`, `format_number()`, `extract_video_id()`, `extract_sec_user_id()`
- Consumes: 无

- [ ] **Step 1: 写测试**

Create `tests/test_utils.py`:

```python
import pytest
from unittest.mock import patch
from cli.utils import random_delay, format_number, extract_video_id, extract_sec_user_id


class TestRandomDelay:
    @patch("cli.utils.time.sleep")
    @patch("cli.utils.random.uniform", return_value=1.5)
    def test_random_delay_calls_sleep(self, mock_uniform, mock_sleep):
        random_delay(1, 3)
        mock_uniform.assert_called_once_with(1, 3)
        mock_sleep.assert_called_once_with(1.5)


class TestFormatNumber:
    def test_format_thousands(self):
        assert format_number(1250000) == "1,250,000"

    def test_format_small(self):
        assert format_number(100) == "100"

    def test_format_none(self):
        assert format_number(None) == "N/A"


class TestExtractVideoId:
    def test_extract_from_full_url(self):
        assert extract_video_id("https://www.douyin.com/video/1234567890") == "1234567890"

    def test_extract_from_short_url(self):
        # 短链接需要额外解析，这里返回 None
        assert extract_video_id("https://v.douyin.com/xxxxx") is None

    def test_extract_invalid(self):
        assert extract_video_id("not-a-url") is None


class TestExtractSecUserId:
    def test_extract_from_user_url(self):
        assert extract_sec_user_id("https://www.douyin.com/user/MS4wLjABAAAAxxx") == "MS4wLjABAAAAxxx"

    def test_extract_invalid(self):
        assert extract_sec_user_id("not-a-url") is None
```

- [ ] **Step 2: 运行测试（期望失败）**

```bash
pytest tests/test_utils.py -v
```

Expected: `ModuleNotFoundError: No module named 'cli.utils'`

- [ ] **Step 3: 实现工具函数**

Create `cli/utils.py`:

```python
import random
import time
import re
from typing import Optional


def random_delay(min_seconds: float = 1.0, max_seconds: float = 3.0) -> None:
    """随机延迟，用于反爬"""
    delay = random.uniform(min_seconds, max_seconds)
    time.sleep(delay)


def format_number(num: Optional[int]) -> str:
    """格式化数字，千分位"""
    if num is None:
        return "N/A"
    return f"{num:,}"


def extract_video_id(url: str) -> Optional[str]:
    """从抖音视频链接提取视频 ID"""
    # 完整链接: https://www.douyin.com/video/1234567890
    match = re.search(r"/video/(\d+)", url)
    if match:
        return match.group(1)
    return None


def extract_sec_user_id(url: str) -> Optional[str]:
    """从抖音用户主页链接提取 sec_user_id"""
    # 链接: https://www.douyin.com/user/MS4wLjABAAAAxxx
    match = re.search(r"/user/([^/?#]+)", url)
    if match:
        return match.group(1)
    return None
```

- [ ] **Step 4: 运行测试（期望通过）**

```bash
pytest tests/test_utils.py -v
```

Expected: 所有 7 个测试 PASS

- [ ] **Step 5: Commit**

```bash
git add cli/utils.py tests/test_utils.py
git commit -m "feat: add utility functions"
```

---

### Task 4: Cookie 管理器

**Files:**
- Create: `cli/cookie_manager.py`
- Create: `tests/test_cookie_manager.py`

**Interfaces:**
- Produces: `CookieManager` 类，方法：`save_cookie()`, `load_cookie()`, `has_cookie()`, `validate_cookie()`
- Consumes: 无

- [ ] **Step 1: 写测试**

Create `tests/test_cookie_manager.py`:

```python
import json
import pytest
from pathlib import Path
from unittest.mock import Mock, patch, mock_open
from cli.cookie_manager import CookieManager


class TestCookieManager:
    def setup_method(self):
        self.manager = CookieManager(cookie_path="test_cookie.json")

    def teardown_method(self):
        # 清理测试文件
        if Path("test_cookie.json").exists():
            Path("test_cookie.json").unlink()

    def test_has_cookie_no_file(self):
        assert self.manager.has_cookie() is False

    def test_save_and_load_cookie(self, tmp_path):
        cookie_path = tmp_path / "cookie.json"
        manager = CookieManager(cookie_path=str(cookie_path))
        
        test_cookie = {"cookies": [{"name": "session", "value": "abc123"}]}
        manager.save_cookie(test_cookie)
        
        assert manager.has_cookie() is True
        loaded = manager.load_cookie()
        assert loaded == test_cookie

    def test_load_cookie_no_file(self):
        result = self.manager.load_cookie()
        assert result is None

    @pytest.mark.asyncio
    async def test_validate_cookie_valid(self):
        # mock browser context
        mock_context = Mock()
        mock_page = Mock()
        mock_page.url = "https://www.douyin.com/"
        mock_page.query_selector = Mock(return_value=Mock())  # 已登录，有用户头像
        
        mock_context.new_page = Mock(return_value=mock_page)
        
        result = await self.manager.validate_cookie(mock_context)
        assert result["valid"] is True

    @pytest.mark.asyncio
    async def test_validate_cookie_invalid(self):
        mock_context = Mock()
        mock_page = Mock()
        mock_page.url = "https://www.douyin.com/"
        # 模拟未登录状态：页面包含登录按钮
        mock_login_btn = Mock()
        mock_login_btn.is_visible = Mock(return_value=True)
        mock_page.query_selector = Mock(return_value=mock_login_btn)
        
        mock_context.new_page = Mock(return_value=mock_page)
        
        result = await self.manager.validate_cookie(mock_context)
        assert result["valid"] is False
```

- [ ] **Step 2: 运行测试（期望失败）**

```bash
pytest tests/test_cookie_manager.py -v
```

Expected: `ModuleNotFoundError: No module named 'cli.cookie_manager'`

- [ ] **Step 3: 实现 Cookie 管理器**

Create `cli/cookie_manager.py`:

```python
import json
import os
from pathlib import Path
from typing import Optional, Dict, Any


class CookieManager:
    """Cookie 管理器：保存、加载、验证 Cookie"""
    
    def __init__(self, cookie_path: str = "data/cookie.json"):
        self.cookie_path = Path(cookie_path)
    
    def has_cookie(self) -> bool:
        """检查 Cookie 文件是否存在"""
        return self.cookie_path.exists() and self.cookie_path.stat().st_size > 0
    
    def save_cookie(self, storage_state: Dict[str, Any]) -> None:
        """保存 Playwright storage_state 到文件"""
        self.cookie_path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.cookie_path, "w", encoding="utf-8") as f:
            json.dump(storage_state, f, ensure_ascii=False, indent=2)
    
    def load_cookie(self) -> Optional[Dict[str, Any]]:
        """加载 Cookie 文件"""
        if not self.has_cookie():
            return None
        with open(self.cookie_path, "r", encoding="utf-8") as f:
            return json.load(f)
    
    async def validate_cookie(self, browser_context) -> Dict[str, Any]:
        """验证 Cookie 是否有效
        
        打开抖音首页，检查是否已登录。
        返回 {"valid": bool, "message": str}
        """
        page = await browser_context.new_page()
        try:
            await page.goto("https://www.douyin.com/", wait_until="domcontentloaded", timeout=15000)
            await page.wait_for_timeout(2000)
            
            # 检查是否有登录按钮（未登录标志）
            login_btn = await page.query_selector('a[href*="login"]')
            if login_btn:
                is_visible = await login_btn.is_visible()
                if is_visible:
                    return {"valid": False, "message": "Cookie 已过期，请重新登录"}
            
            # 检查是否有用户头像（已登录标志）
            avatar = await page.query_selector('[data-e2e="user-avatar"]')
            if avatar:
                return {"valid": True, "message": "Cookie 有效"}
            
            # 兜底：检查 URL 是否被重定向到登录页
            if "login" in page.url:
                return {"valid": False, "message": "Cookie 已过期，请重新登录"}
            
            return {"valid": True, "message": "Cookie 看起来有效"}
        except Exception as e:
            return {"valid": False, "message": f"验证失败: {str(e)}"}
        finally:
            await page.close()
```

- [ ] **Step 4: 运行测试（期望通过）**

```bash
pytest tests/test_cookie_manager.py -v
```

Expected: 所有 5 个测试 PASS

- [ ] **Step 5: Commit**

```bash
git add cli/cookie_manager.py tests/test_cookie_manager.py
git commit -m "feat: add cookie manager"
```

---

### Task 5: 登录认证模块

**Files:**
- Create: `cli/auth.py`
- Create: `tests/test_auth.py`

**Interfaces:**
- Produces: `AuthManager` 类，方法：`login()`
- Consumes: `CookieManager.save_cookie()`, `CookieManager.has_cookie()`

- [ ] **Step 1: 写测试**

Create `tests/test_auth.py`:

```python
import pytest
from unittest.mock import Mock, patch, AsyncMock
from cli.auth import AuthManager


class TestAuthManager:
    def setup_method(self):
        self.mock_cookie_manager = Mock()
        self.auth = AuthManager(self.mock_cookie_manager)

    @pytest.mark.asyncio
    @patch("cli.auth.async_playwright")
    async def test_login_already_has_cookie(self, mock_playwright):
        self.mock_cookie_manager.has_cookie.return_value = True
        
        result = await self.auth.login()
        
        assert result["success"] is True
        assert "已存在" in result["message"]
        mock_playwright.assert_not_called()

    @pytest.mark.asyncio
    @patch("cli.auth.async_playwright")
    async def test_login_success(self, mock_playwright):
        self.mock_cookie_manager.has_cookie.return_value = False
        
        # Mock Playwright 链
        mock_pw = Mock()
        mock_browser = Mock()
        mock_context = Mock()
        mock_page = Mock()
        
        mock_playwright.return_value.__aenter__ = AsyncMock(return_value=mock_pw)
        mock_pw.chromium.launch = AsyncMock(return_value=mock_browser)
        mock_browser.new_context = AsyncMock(return_value=mock_context)
        mock_context.new_page = AsyncMock(return_value=mock_page)
        mock_context.storage_state = AsyncMock(return_value={"cookies": [{"name": "test"}]})
        
        mock_page.goto = AsyncMock()
        mock_page.wait_for_timeout = AsyncMock()
        
        result = await self.auth.login()
        
        assert result["success"] is True
        self.mock_cookie_manager.save_cookie.assert_called_once()
```

- [ ] **Step 2: 运行测试（期望失败）**

```bash
pytest tests/test_auth.py -v
```

Expected: `ModuleNotFoundError: No module named 'cli.auth'`

- [ ] **Step 3: 实现登录模块**

Create `cli/auth.py`:

```python
from typing import Dict, Any
from playwright.async_api import async_playwright
from cli.cookie_manager import CookieManager


class AuthManager:
    """登录管理器：处理扫码/短信登录"""
    
    def __init__(self, cookie_manager: CookieManager):
        self.cookie_manager = cookie_manager
    
    async def login(self) -> Dict[str, Any]:
        """启动 headed 浏览器，让用户手动登录，保存 Cookie
        
        返回 {"success": bool, "message": str}
        """
        if self.cookie_manager.has_cookie():
            return {
                "success": True,
                "message": "Cookie 已存在，如需重新登录请先删除 data/cookie.json"
            }
        
        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=False)
            context = await browser.new_context(
                viewport={"width": 1280, "height": 800},
                user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.0"
            )
            page = await context.new_page()
            
            try:
                print("正在打开抖音登录页面...")
                await page.goto("https://www.douyin.com/", wait_until="networkidle")
                
                # 等待用户登录（手动扫码或短信）
                print("请在浏览器中完成登录（扫码或短信）...")
                print("登录完成后按 Enter 键继续...")
                input()  # 等待用户按回车
                
                # 保存 Cookie
                storage_state = await context.storage_state()
                self.cookie_manager.save_cookie(storage_state)
                
                return {
                    "success": True,
                    "message": "登录成功，Cookie 已保存"
                }
            except Exception as e:
                return {
                    "success": False,
                    "message": f"登录失败: {str(e)}"
                }
            finally:
                await browser.close()
```

- [ ] **Step 4: 运行测试（期望通过）**

```bash
pytest tests/test_auth.py -v
```

Expected: 2 个测试 PASS

- [ ] **Step 5: Commit**

```bash
git add cli/auth.py tests/test_auth.py
git commit -m "feat: add auth module for manual login"
```

---

### Task 6: 核心抓取器 - 博主主页

**Files:**
- Create: `cli/scraper.py`
- Create: `tests/test_scraper.py`

**Interfaces:**
- Produces: `DouyinScraper` 类，方法：`scrape_blogger()`, `scrape_video()`
- Consumes: `CookieManager.load_cookie()`, `utils.random_delay()`, `models.*`

- [ ] **Step 1: 写测试**

Create `tests/test_scraper.py`:

```python
import pytest
from unittest.mock import Mock, AsyncMock, patch
from cli.scraper import DouyinScraper
from cli.cookie_manager import CookieManager


class TestDouyinScraper:
    def setup_method(self):
        self.mock_cookie_manager = Mock(spec=CookieManager)
        self.scraper = DouyinScraper(self.mock_cookie_manager)

    @pytest.mark.asyncio
    @patch("cli.scraper.async_playwright")
    async def test_scrape_blogger_no_cookie(self, mock_playwright):
        self.mock_cookie_manager.has_cookie.return_value = False
        
        result = await self.scraper.scrape_blogger("https://www.douyin.com/user/xxx", top_n=10)
        
        assert result["error"] == "COOKIE_NOT_FOUND"

    @pytest.mark.asyncio
    @patch("cli.scraper.async_playwright")
    async def test_scrape_video_no_cookie(self, mock_playwright):
        self.mock_cookie_manager.has_cookie.return_value = False
        
        result = await self.scraper.scrape_video("https://www.douyin.com/video/xxx")
        
        assert result["error"] == "COOKIE_NOT_FOUND"

    def test_parse_like_count(self):
        assert self.scraper._parse_count("1.2w") == 12000
        assert self.scraper._parse_count("5.6万") == 56000
        assert self.scraper._parse_count("999") == 999
        assert self.scraper._parse_count("") == 0
```

- [ ] **Step 2: 运行测试（期望失败）**

```bash
pytest tests/test_scraper.py -v
```

Expected: `ModuleNotFoundError: No module named 'cli.scraper'`

- [ ] **Step 3: 实现抓取器**

Create `cli/scraper.py`:

```python
import re
from typing import Dict, Any, List, Optional
from playwright.async_api import async_playwright
from cli.cookie_manager import CookieManager
from cli.models import BloggerResult, VideoResult, Video, Comment
from cli.utils import random_delay


class DouyinScraper:
    """抖音核心抓取器"""
    
    def __init__(self, cookie_manager: CookieManager):
        self.cookie_manager = cookie_manager
    
    def _parse_count(self, text: str) -> int:
        """解析数字（支持 w/万 后缀）"""
        if not text:
            return 0
        text = text.strip()
        if "w" in text.lower() or "万" in text:
            num = re.sub(r"[^\d.]", "", text)
            return int(float(num) * 10000) if num else 0
        num = re.sub(r"[^\d]", "", text)
        return int(num) if num else 0
    
    async def _create_context(self, browser):
        """创建带 Cookie 的浏览器上下文"""
        cookie = self.cookie_manager.load_cookie()
        if cookie:
            return await browser.new_context(storage_state=cookie)
        return await browser.new_context()
    
    async def scrape_blogger(self, url: str, top_n: int = 10) -> Dict[str, Any]:
        """抓取博主主页，返回 Top N 高赞视频"""
        if not self.cookie_manager.has_cookie():
            return {"error": "COOKIE_NOT_FOUND", "message": "请先运行 `python cli/main.py auth` 扫码登录"}
        
        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            context = await self._create_context(browser)
            page = await context.new_page()
            
            try:
                # 打开博主主页
                await page.goto(url, wait_until="domcontentloaded", timeout=30000)
                await page.wait_for_timeout(3000)
                
                # 获取博主名称
                name_elem = await page.query_selector("h1[class*='title']")
                blogger_name = await name_elem.inner_text() if name_elem else "未知博主"
                
                # 获取博主 ID
                sec_user_id = url.split("/user/")[-1].split("?")[0] if "/user/" in url else ""
                
                videos = []
                scroll_attempts = 0
                max_scrolls = 50
                
                while len(videos) < top_n * 2 and scroll_attempts < max_scrolls:  # 多抓一些用于排序
                    # 提取当前可见视频
                    video_cards = await page.query_selector_all("[data-e2e='user-post-list'] a")
                    
                    for card in video_cards:
                        try:
                            href = await card.get_attribute("href") or ""
                            if "/video/" not in href:
                                continue
                            
                            video_id = href.split("/video/")[-1].split("?")[0]
                            if any(v.get("video_id") == video_id for v in videos):
                                continue  # 去重
                            
                            # 提取点赞数
                            like_elem = await card.query_selector("[class*='like']")
                            like_text = await like_elem.inner_text() if like_elem else "0"
                            like_count = self._parse_count(like_text)
                            
                            videos.append({
                                "video_id": video_id,
                                "url": f"https://www.douyin.com/video/{video_id}",
                                "like_count": like_count,
                            })
                        except Exception:
                            continue
                    
                    # 滚动加载更多
                    await page.evaluate("window.scrollBy(0, 800)")
                    await random_delay(1, 2)
                    scroll_attempts += 1
                
                # 按点赞排序，取 Top N
                videos.sort(key=lambda x: x["like_count"], reverse=True)
                top_videos = videos[:top_n]
                
                # 抓取每个视频的详细信息
                video_models = []
                for i, v in enumerate(top_videos, 1):
                    video_detail = await self._scrape_video_detail(page, v["url"])
                    video_detail.rank = i
                    video_models.append(video_detail)
                    await random_delay(1, 3)
                
                result = BloggerResult(
                    blogger_name=blogger_name.strip(),
                    blogger_id=sec_user_id,
                    total_videos=len(videos),
                    top_videos=video_models
                )
                return result.model_dump()
                
            except Exception as e:
                return {"error": "SCRAPE_ERROR", "message": f"抓取失败: {str(e)}"}
            finally:
                await browser.close()
    
    async def _scrape_video_detail(self, page, url: str) -> Video:
        """抓取单个视频的详细信息"""
        await page.goto(url, wait_until="domcontentloaded", timeout=30000)
        await page.wait_for_timeout(2000)
        
        # 标题
        title_elem = await page.query_selector("h1[class*='title']")
        title = await title_elem.inner_text() if title_elem else ""
        
        # 描述/文案
        desc_elem = await page.query_selector("[class*='desc']")
        desc = await desc_elem.inner_text() if desc_elem else ""
        
        # 点赞数
        like_elem = await page.query_selector("[data-e2e='like-count']")
        like_text = await like_elem.inner_text() if like_elem else "0"
        like_count = self._parse_count(like_text)
        
        # 评论数
        comment_elem = await page.query_selector("[data-e2e='comment-count']")
        comment_text = await comment_elem.inner_text() if comment_elem else "0"
        comment_count = self._parse_count(comment_text)
        
        # 播放量（可能没有精确数字）
        play_elem = await page.query_selector("[class*='play-count']")
        play_text = await play_elem.inner_text() if play_elem else "0"
        play_count = self._parse_count(play_text)
        
        # 发布时间
        time_elem = await page.query_selector("[class*='time']")
        publish_time = await time_elem.inner_text() if time_elem else ""
        
        # 热门评论
        comments = await self._scrape_comments(page)
        
        return Video(
            rank=0,
            title=title.strip(),
            desc=desc.strip(),
            url=url,
            like_count=like_count,
            play_count=play_count,
            comment_count=comment_count,
            publish_time=publish_time.strip(),
            top_comments=comments
        )
    
    async def _scrape_comments(self, page, max_comments: int = 10) -> List[Comment]:
        """抓取热门评论"""
        comments = []
        try:
            # 等待评论区加载
            await page.wait_for_selector("[class*='comment']", timeout=5000)
            
            comment_items = await page.query_selector_all("[class*='comment-item']")[:max_comments]
            for item in comment_items:
                user_elem = await item.query_selector("[class*='user-name']")
                user = await user_elem.inner_text() if user_elem else ""
                
                text_elem = await item.query_selector("[class*='text']")
                text = await text_elem.inner_text() if text_elem else ""
                
                like_elem = await item.query_selector("[class*='comment-like']")
                like_text = await like_elem.inner_text() if like_elem else "0"
                likes = self._parse_count(like_text)
                
                if user and text:
                    comments.append(Comment(user=user.strip(), text=text.strip(), likes=likes))
        except Exception:
            pass  # 评论抓取失败不影响主流程
        
        return comments
    
    async def scrape_video(self, url: str) -> Dict[str, Any]:
        """抓取单个视频"""
        if not self.cookie_manager.has_cookie():
            return {"error": "COOKIE_NOT_FOUND", "message": "请先运行 `python cli/main.py auth` 扫码登录"}
        
        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            context = await self._create_context(browser)
            page = await context.new_page()
            
            try:
                video = await self._scrape_video_detail(page, url)
                
                # 获取博主名称
                blogger_elem = await page.query_selector("[class*='blogger-name']")
                blogger_name = await blogger_elem.inner_text() if blogger_elem else ""
                
                result = VideoResult(
                    title=video.title,
                    desc=video.desc,
                    like_count=video.like_count,
                    play_count=video.play_count,
                    comment_count=video.comment_count,
                    publish_time=video.publish_time,
                    blogger_name=blogger_name.strip(),
                    top_comments=video.top_comments
                )
                return result.model_dump()
                
            except Exception as e:
                return {"error": "SCRAPE_ERROR", "message": f"抓取失败: {str(e)}"}
            finally:
                await browser.close()
```

- [ ] **Step 4: 运行测试（期望通过）**

```bash
pytest tests/test_scraper.py -v
```

Expected: 3 个测试 PASS

- [ ] **Step 5: Commit**

```bash
git add cli/scraper.py tests/test_scraper.py
git commit -m "feat: add douyin scraper for blogger and video"
```

---

### Task 7: CLI 入口

**Files:**
- Create: `cli/main.py`
- Create: `tests/test_main.py`

**Interfaces:**
- Produces: CLI 入口，支持 `auth`, `check-auth`, `blogger`, `video` 子命令
- Consumes: `AuthManager`, `CookieManager`, `DouyinScraper`

- [ ] **Step 1: 写测试**

Create `tests/test_main.py`:

```python
import pytest
from unittest.mock import Mock, patch, AsyncMock
import json
from cli.main import main


class TestMain:
    @patch("cli.main.AuthManager")
    @patch("cli.main.CookieManager")
    @patch("cli.main.sys.argv", ["main.py", "auth"])
    @patch("builtins.print")
    async def test_auth_command(self, mock_print, mock_cookie_cls, mock_auth_cls):
        mock_cookie = Mock()
        mock_cookie_cls.return_value = mock_cookie
        mock_auth = Mock()
        mock_auth.login = AsyncMock(return_value={"success": True, "message": "ok"})
        mock_auth_cls.return_value = mock_auth
        
        await main()
        mock_auth.login.assert_called_once()

    @patch("cli.main.CookieManager")
    @patch("cli.main.sys.argv", ["main.py", "check-auth"])
    @patch("builtins.print")
    async def test_check_auth_no_cookie(self, mock_print, mock_cookie_cls):
        mock_cookie = Mock()
        mock_cookie.has_cookie.return_value = False
        mock_cookie_cls.return_value = mock_cookie
        
        await main()
        output = mock_print.call_args[0][0]
        assert "COOKIE_NOT_FOUND" in output
```

- [ ] **Step 2: 运行测试（期望失败）**

```bash
pytest tests/test_main.py -v
```

Expected: `ModuleNotFoundError: No module named 'cli.main'`

- [ ] **Step 3: 实现 CLI 入口**

Create `cli/main.py`:

```python
import argparse
import asyncio
import json
import sys
from pathlib import Path

# 添加项目根目录到路径
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

from cli.cookie_manager import CookieManager
from cli.auth import AuthManager
from cli.scraper import DouyinScraper


def print_json(data: dict) -> None:
    """输出 JSON 到 stdout"""
    print(json.dumps(data, ensure_ascii=False, indent=2))


async def handle_auth(args):
    """处理登录命令"""
    cookie_manager = CookieManager()
    auth = AuthManager(cookie_manager)
    result = await auth.login()
    print_json(result)


async def handle_check_auth(args):
    """处理验证 Cookie 命令"""
    cookie_manager = CookieManager()
    
    if not cookie_manager.has_cookie():
        print_json({"error": "COOKIE_NOT_FOUND", "message": "Cookie 不存在，请先运行 auth 登录"})
        return
    
    from playwright.async_api import async_playwright
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        cookie = cookie_manager.load_cookie()
        context = await browser.new_context(storage_state=cookie)
        result = await cookie_manager.validate_cookie(context)
        await browser.close()
    
    print_json(result)


async def handle_blogger(args):
    """处理博主抓取命令"""
    cookie_manager = CookieManager()
    scraper = DouyinScraper(cookie_manager)
    result = await scraper.scrape_blogger(args.url, top_n=args.top)
    print_json(result)


async def handle_video(args):
    """处理视频抓取命令"""
    cookie_manager = CookieManager()
    scraper = DouyinScraper(cookie_manager)
    result = await scraper.scrape_video(args.url)
    print_json(result)


async def main():
    parser = argparse.ArgumentParser(description="抖音 Playwright 数据采集工具")
    subparsers = parser.add_subparsers(dest="command", help="可用命令")
    
    # auth 命令
    auth_parser = subparsers.add_parser("auth", help="扫码登录并保存 Cookie")
    
    # check-auth 命令
    check_parser = subparsers.add_parser("check-auth", help="验证 Cookie 是否有效")
    
    # blogger 命令
    blogger_parser = subparsers.add_parser("blogger", help="抓取博主主页 Top N 高赞视频")
    blogger_parser.add_argument("url", help="博主主页 URL")
    blogger_parser.add_argument("--top", type=int, default=10, help="取前 N 个高赞视频 (默认: 10)")
    
    # video 命令
    video_parser = subparsers.add_parser("video", help="抓取单个视频")
    video_parser.add_argument("url", help="视频 URL")
    
    args = parser.parse_args()
    
    if args.command == "auth":
        await handle_auth(args)
    elif args.command == "check-auth":
        await handle_check_auth(args)
    elif args.command == "blogger":
        await handle_blogger(args)
    elif args.command == "video":
        await handle_video(args)
    else:
        parser.print_help()


if __name__ == "__main__":
    asyncio.run(main())
```

- [ ] **Step 4: 运行测试（期望通过）**

```bash
pytest tests/test_main.py -v
```

Expected: 2 个测试 PASS

- [ ] **Step 5: 手动验证 CLI**

```bash
cd C:\Users\tiany\Desktop\douyin-playwright
python cli/main.py --help
python cli/main.py auth --help
python cli/main.py blogger --help
python cli/main.py video --help
```

Expected: 显示各命令的帮助信息

- [ ] **Step 6: Commit**

```bash
git add cli/main.py tests/test_main.py
git commit -m "feat: add CLI entry point with argparse routing"
```

---

### Task 8: Skill 文件

**Files:**
- Create: `skill/SKILL.md`

**Interfaces:**
- Produces: Claude Skill 定义，触发词、执行流程、Excel 生成

- [ ] **Step 1: 写 SKILL.md**

Create `skill/SKILL.md`:

```markdown
---
name: douyin-playwright
description: 抖音数据采集与内容总结 Skill。基于 Playwright 抓取抖音博主主页或单个视频的数据，生成 AI 文字摘要 + Excel 表格。触发场景：用户提到"抖音总结"、"分析抖音博主"、"视频摘要"、"总结这个抖音"、"博主高赞视频"、"抖音数据导出"等。
---

# 抖音 Playwright 数据采集 Skill

基于 Playwright 的抖音数据采集工具，支持两种核心场景：
1. **博主主页分析** → Top N 高赞视频的文字摘要 + Excel 表格
2. **单个视频分析** → 标题+文案+热评的摘要 + Excel 表格

## 项目位置

- 项目根目录: `C:\Users\tiany\Desktop\douyin-playwright`
- CLI 入口: `C:\Users\tiany\Desktop\douyin-playwright\cli\main.py`
- Cookie 文件: `C:\Users\tiany\Desktop\douyin-playwright\data\cookie.json`
- Excel 输出: `C:\Users\tiany\Desktop\douyin-playwright\data\output\`

## 依赖检查

首次使用前确保已安装：
```bash
cd C:\Users\tiany\Desktop\douyin-playwright
pip install -r requirements.txt
playwright install chromium
```

## 使用流程

### 1. 检查 Cookie

```bash
cd C:\Users\tiany\Desktop\douyin-playwright
python cli/main.py check-auth
```

- 返回 `{"valid": true}` → 继续下一步
- 返回 `COOKIE_NOT_FOUND` 或 `COOKIE_EXPIRED` → 引导用户登录

### 2. 登录（如需要）

```bash
python cli/main.py auth
```

- 会弹出 headed 浏览器，打开抖音首页
- 用户手动扫码或短信登录
- 登录完成后按 Enter 键，Cookie 自动保存

### 3. 根据用户需求调用 CLI

**场景 A：博主主页分析**

```bash
python cli/main.py blogger <博主主页URL> --top 10
```

**场景 B：单个视频分析**

```bash
python cli/main.py video <视频URL>
```

### 4. 解析 JSON 输出

CLI 输出结构化 JSON 到 stdout，Skill 层读取并解析。

**博主输出格式**：
```json
{
  "blogger_name": "博主名",
  "blogger_id": "...",
  "total_videos": 156,
  "top_videos": [
    {
      "rank": 1,
      "title": "视频标题",
      "desc": "视频描述",
      "url": "https://www.douyin.com/video/xxx",
      "like_count": 1250000,
      "play_count": 8500000,
      "comment_count": 3200,
      "publish_time": "2024-06-15",
      "top_comments": [{"user": "...", "text": "...", "likes": 1200}]
    }
  ]
}
```

**视频输出格式**：
```json
{
  "title": "视频标题",
  "desc": "视频描述",
  "like_count": 1250000,
  "play_count": 8500000,
  "comment_count": 3200,
  "publish_time": "2024-06-15",
  "blogger_name": "博主名",
  "top_comments": [...]
}
```

### 5. AI 生成文字摘要

基于 JSON 数据，生成结构化的文字摘要：

**博主摘要示例**：
```
## 博主「xxx」Top 10 高赞视频分析

该博主共发布 156 个视频，以下是点赞量最高的 10 个视频总结：

### Top 1: 视频标题（点赞 125万）
- **内容摘要**: [AI 根据 desc 和评论生成的摘要]
- **热门评论**: 用户A: "..."; 用户B: "..."
- **链接**: https://www.douyin.com/video/xxx

### Top 2: ...
...
```

**视频摘要示例**：
```
## 视频「xxx」内容分析

- **博主**: xxx
- **点赞**: 125万 | **播放**: 850万 | **评论**: 3200
- **发布时间**: 2024-06-15

### 内容摘要
[AI 根据标题+文案+热评生成的摘要]

### 热门评论 Top 5
1. 用户A: "..." (1200赞)
2. ...
```

### 6. 生成 Excel 表格（调用 xlsx skill）

根据用户请求决定是否生成 Excel：

| 用户说法 | 输出 |
|----------|------|
| "帮我总结这个博主" | 文字摘要 + Excel |
| "导出 Excel" / "生成表格" | Excel 文件 |
| "视频内容是什么" | 仅文字摘要 |

**Excel 文件路径**: `data/output/YYYY-MM-DD_博主名.xlsx`

**博主 Excel 表格列**：
| 排名 | 视频标题 | 点赞数 | 播放量 | 评论数 | 发布日期 | 内容摘要 | 热门评论 | 视频链接 |

**视频 Excel 表格行**：
| 字段 | 内容 |
|------|------|
| 视频标题 | xxx |
| 博主名称 | xxx |
| 点赞数 | xxx |
| 播放量 | xxx |
| 评论数 | xxx |
| 发布日期 | xxx |
| 视频文案 | xxx |
| 内容摘要 | xxx |
| 热门评论 Top 5 | xxx |

调用 xlsx skill 生成 Excel 后，告知用户文件保存路径。

## 错误处理

| 错误场景 | 处理方式 |
|----------|----------|
| Cookie 不存在 | 提示用户运行 `python cli/main.py auth` 登录 |
| Cookie 过期 | 提示用户重新登录 |
| 页面加载超时 | 提示网络问题，建议重试 |
| 博主主页无法访问 | 检查 URL 或账号是否私密 |
| 抓取字段为空 | 在摘要中标注"未能获取" |

## 注意事项

- 本工具仅用于合法的数据采集和研究用途
- 遵守抖音平台使用条款
- Cookie 文件本地存储，不上传任何服务器
- 首次登录后 Cookie 可复用，无需每次登录
- 抓取频率已内置反爬延迟，请勿修改降低延迟
```

- [ ] **Step 2: Commit**

```bash
git add skill/SKILL.md
git commit -m "feat: add Claude skill definition"
```

---

### Task 9: 安装脚本和文档

**Files:**
- Create: `scripts/setup.ps1`
- Create: `README.md`

**Interfaces:**
- Produces: Windows PowerShell 安装脚本 + 项目 README

- [ ] **Step 1: 创建 setup.ps1**

Create `scripts/setup.ps1`:

```powershell
# 抖音 Playwright 数据采集工具 - Windows 安装脚本
# 使用方法: 右键 → 使用 PowerShell 运行

$ErrorActionPreference = "Stop"

Write-Host "=== 抖音 Playwright 数据采集工具 安装 ===" -ForegroundColor Cyan

# 检查 Python
$pythonVersion = python --version 2>$null
if (-not $pythonVersion) {
    Write-Host "错误: 未找到 Python，请先安装 Python 3.10+" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Python: $pythonVersion"

# 检查 Node.js
$nodeVersion = node --version 2>$null
if (-not $nodeVersion) {
    Write-Host "错误: 未找到 Node.js，请先安装 Node.js 18+" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Node.js: $nodeVersion"

# 安装 Python 依赖
Write-Host "`n正在安装 Python 依赖..." -ForegroundColor Yellow
pip install -r requirements.txt

# 安装 Playwright 浏览器
Write-Host "`n正在安装 Playwright Chromium..." -ForegroundColor Yellow
playwright install chromium

# 创建数据目录
New-Item -ItemType Directory -Force -Path "data\output" >$null

Write-Host "`n=== 安装完成 ===" -ForegroundColor Green
Write-Host "使用方法:" -ForegroundColor Cyan
Write-Host "  1. 登录: python cli/main.py auth"
Write-Host "  2. 验证: python cli/main.py check-auth"
Write-Host "  3. 抓取博主: python cli/main.py blogger <URL> --top 10"
Write-Host "  4. 抓取视频: python cli/main.py video <URL>"
```

- [ ] **Step 2: 创建 README.md**

Create `README.md`:

```markdown
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
```

- [ ] **Step 3: Commit**

```bash
git add scripts/setup.ps1 README.md
git commit -m "docs: add setup script and README"
```

---

## Self-Review

**1. Spec coverage:**

| 设计文档章节 | 实现任务 |
|-------------|---------|
| 项目结构 | Task 1 |
| 数据模型 | Task 2 |
| Cookie 管理 | Task 4 |
| 登录认证 | Task 5 |
| 核心抓取 | Task 6 |
| CLI 入口 | Task 7 |
| Skill 定义 | Task 8 |
| Excel 输出 | Task 8 (SKILL.md 中定义，由 xlsx skill 实现) |
| 反爬策略 | Task 6 (scraper.py 中实现) |
| 错误处理 | Task 4-8 各任务中包含 |

**2. Placeholder scan:**
- ✅ 无 TBD、TODO
- ✅ 所有步骤包含实际代码
- ✅ 无 "similar to Task N"

**3. Type consistency:**
- ✅ `BloggerResult`, `VideoResult`, `Video`, `Comment` 模型在 Task 2 定义，Task 6 scraper 中使用一致
- ✅ `CookieManager` 在 Task 4 定义，Task 5-7 中使用一致
- ✅ CLI 错误输出格式 `"error": "CODE", "message": "..."` 全项目一致

---

**Plan complete and saved to `docs/plan.md`.**

**Two execution options:**

**1. Subagent-Driven (recommended)** - 每个 Task 分配一个子代理，任务间审查，快速迭代

**2. Inline Execution** - 在本会话中使用 executing-plans 批量执行任务，带检查点

**Which approach?**
