"""测试 models.py 中的数据模型"""
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))
import pytest
from models import BloggerItem, CategoryScoutResult


class TestBloggerItem:
    def test_minimal_creation(self):
        item = BloggerItem(
            blogger_name="测试博主",
            fans_count="699.3万",
            fans_count_int=6993000,
            total_likes="8503.1万",
            total_likes_int=85031000,
            profile_url="https://www.douyin.com/user/MS4wLjABAAAA",
        )
        assert item.blogger_name == "测试博主"
        assert item.fans_count == "699.3万"
        assert item.fans_count_int == 6993000
        assert item.total_likes == "8503.1万"
        assert item.total_likes_int == 85031000
        assert item.profile_url == "https://www.douyin.com/user/MS4wLjABAAAA"

    def test_defaults(self):
        item = BloggerItem()
        assert item.blogger_name == ""
        assert item.fans_count == ""
        assert item.fans_count_int == 0
        assert item.total_likes == ""
        assert item.total_likes_int == 0
        assert item.profile_url == ""


class TestCategoryScoutResult:
    def test_empty_result(self):
        result = CategoryScoutResult(keyword="搞笑幽默")
        assert result.keyword == "搞笑幽默"
        assert result.total_found == 0
        assert result.top_100 == []
        assert result.scrape_time != ""

    def test_with_bloggers(self):
        bloggers = [
            BloggerItem(
                blogger_name="博主A",
                fans_count="699.3万",
                fans_count_int=6993000,
                total_likes="8503.1万",
                total_likes_int=85031000,
                profile_url="https://www.douyin.com/user/a",
            ),
            BloggerItem(
                blogger_name="博主B",
                fans_count="200.6万",
                fans_count_int=2006000,
                total_likes="1468.4万",
                total_likes_int=14684000,
                profile_url="https://www.douyin.com/user/b",
            ),
        ]
        result = CategoryScoutResult(
            keyword="短剧",
            total_found=2,
            top_100=bloggers,
        )
        assert result.total_found == 2
        assert result.top_100[0].blogger_name == "博主A"
        # 验证默认按粉丝数降序
        assert result.top_100[0].fans_count_int > result.top_100[1].fans_count_int
