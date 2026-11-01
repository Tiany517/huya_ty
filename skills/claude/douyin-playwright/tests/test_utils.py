import pytest
from unittest.mock import patch, AsyncMock
from cli.utils import random_delay, format_number, extract_video_id, extract_sec_user_id, parse_count


class TestRandomDelay:
    @pytest.mark.asyncio
    @patch("cli.utils.asyncio.sleep")
    @patch("cli.utils.random.uniform", return_value=1.5)
    async def test_random_delay_calls_sleep(self, mock_uniform, mock_sleep):
        await random_delay(1, 3)
        mock_uniform.assert_called_once_with(1, 3)
        mock_sleep.assert_called_once_with(1.5)


class TestParseCount:
    def test_w_suffix(self):
        assert parse_count("1.2w") == 12000

    def test_wan_suffix(self):
        assert parse_count("5.6万") == 56000

    def test_yi_suffix(self):
        assert parse_count("3.2亿") == 320000000

    def test_plain_number(self):
        assert parse_count("999") == 999

    def test_empty(self):
        assert parse_count("") == 0


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
