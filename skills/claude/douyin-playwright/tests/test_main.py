import pytest
from unittest.mock import Mock, patch, AsyncMock
import json
from cli.main import main


class TestMain:
    @pytest.mark.asyncio
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

    @pytest.mark.asyncio
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
