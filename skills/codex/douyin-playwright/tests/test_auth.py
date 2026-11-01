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

        mock_browser.close = AsyncMock()
        mock_context.close = AsyncMock()
        mock_page.goto = AsyncMock()
        mock_page.wait_for_timeout = AsyncMock()

        with patch("builtins.input", return_value=""):
            result = await self.auth.login()

        assert result["success"] is True
        self.mock_cookie_manager.save_cookie.assert_called_once()
        mock_browser.close.assert_called_once()
