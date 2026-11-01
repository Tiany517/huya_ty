import json
import pytest
from pathlib import Path
from unittest.mock import Mock, patch, mock_open, AsyncMock
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
        mock_page.goto = AsyncMock()
        mock_page.wait_for_timeout = AsyncMock()
        mock_page.query_selector = AsyncMock(side_effect=[None, Mock()])  # 无登录按钮，有用户头像
        mock_page.close = AsyncMock()

        mock_context.new_page = AsyncMock(return_value=mock_page)

        result = await self.manager.validate_cookie(mock_context)
        assert result["valid"] is True

    @pytest.mark.asyncio
    async def test_validate_cookie_invalid(self):
        mock_context = Mock()
        mock_page = Mock()
        mock_page.url = "https://www.douyin.com/"
        mock_page.goto = AsyncMock()
        mock_page.wait_for_timeout = AsyncMock()
        mock_page.close = AsyncMock()
        # 模拟未登录状态：页面包含登录按钮
        mock_login_btn = Mock()
        mock_login_btn.is_visible = AsyncMock(return_value=True)
        mock_page.query_selector = AsyncMock(return_value=mock_login_btn)

        mock_context.new_page = AsyncMock(return_value=mock_page)

        result = await self.manager.validate_cookie(mock_context)
        assert result["valid"] is False
