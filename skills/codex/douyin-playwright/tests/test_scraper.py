import pytest
from unittest.mock import Mock, AsyncMock, patch
from cli.scraper import DouyinScraper
from cli.cookie_manager import CookieManager
from cli.utils import parse_count


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
        # _parse_count 已移至 utils.parse_count
        assert parse_count("1.2w") == 12000
        assert parse_count("5.6万") == 56000
        assert parse_count("999") == 999
        assert parse_count("") == 0
        assert parse_count("3.2亿") == 320000000
