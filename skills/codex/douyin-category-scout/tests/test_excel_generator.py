# -*- coding: utf-8 -*-
"""测试 excel_generator.py"""
import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))
import pytest
from excel_generator import generate_category_excel


class TestCategoryExcelGenerator:
    def test_generate_excel(self):
        result = {
            "keyword": "短剧",
            "total_found": 3,
            "scrape_time": "2026-06-26T14:30:00",
            "top_100": [
                {
                    "blogger_name": "磁力短剧",
                    "fans_count": "699.3万粉丝",
                    "fans_count_int": 6993000,
                    "total_likes": "8503.1万获赞",
                    "total_likes_int": 85031000,
                    "profile_url": "https://www.douyin.com/user/300653550958",
                },
                {
                    "blogger_name": "久悦短剧",
                    "fans_count": "200.6万粉丝",
                    "fans_count_int": 2006000,
                    "total_likes": "1468.4万获赞",
                    "total_likes_int": 14684000,
                    "profile_url": "https://www.douyin.com/user/251628108641",
                },
                {
                    "blogger_name": "白鹿短剧",
                    "fans_count": "288.4万粉丝",
                    "fans_count_int": 2884000,
                    "total_likes": "6836.8万获赞",
                    "total_likes_int": 68368000,
                    "profile_url": "https://www.douyin.com/user/753990979573",
                },
            ],
        }
        output_dir = os.path.join(os.path.dirname(__file__), "..", "output")
        filepath = generate_category_excel(result, output_dir)

        assert os.path.exists(filepath)
        assert filepath.endswith(".xlsx")
        assert "短剧" in filepath
        assert "2026-06-26" in filepath

        # 清理
        os.remove(filepath)

    def test_generate_excel_empty(self):
        result = {
            "keyword": "空搜索",
            "total_found": 0,
            "scrape_time": "2026-06-26T14:30:00",
            "top_100": [],
        }
        output_dir = os.path.join(os.path.dirname(__file__), "..", "output")
        filepath = generate_category_excel(result, output_dir)
        assert os.path.exists(filepath)
        os.remove(filepath)

    def test_generate_excel_missing_fields(self):
        """缺失字段应填入 '—'"""
        result = {
            "keyword": "测试",
            "total_found": 1,
            "scrape_time": "2026-06-26T14:30:00",
            "top_100": [
                {
                    "blogger_name": "博主X",
                    "fans_count": "",
                    "fans_count_int": 0,
                    "total_likes": "",
                    "total_likes_int": 0,
                    "profile_url": "",
                },
            ],
        }
        output_dir = os.path.join(os.path.dirname(__file__), "..", "output")
        filepath = generate_category_excel(result, output_dir)
        assert os.path.exists(filepath)
        os.remove(filepath)
