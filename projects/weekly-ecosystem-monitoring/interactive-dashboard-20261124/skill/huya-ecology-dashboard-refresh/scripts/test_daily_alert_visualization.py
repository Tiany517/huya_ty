from __future__ import annotations

import importlib.util
import json
import sys
import unittest
from datetime import date
from pathlib import Path


SCRIPT = Path(__file__).with_name("build_daily_alert_report.py")
SPEC = importlib.util.spec_from_file_location("build_daily_alert_report", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def sample_data() -> dict:
    return {
        "meta": {
            "categoryColumns": [
                "date",
                "category",
                "group",
                "dau",
                "revenue",
                "payUsers",
                "arppu",
                "viewMinutes",
                "attributionUsers",
                "liveAnchors",
                "groupLiveAnchors",
                "totalLiveAnchors",
            ],
            "contentGroups": ["游戏", "娱乐（秀场）", "娱乐（非秀场）", "未匹配"],
            "categories": [
                {"id": "1", "name": "英雄联盟", "group": 0},
                {"id": "2", "name": "王者荣耀", "group": 0},
                {"id": "3", "name": "星秀", "group": 1},
            ],
        },
        "categoryDaily": [
            ["2026-11-17", 0, 0, 100, 0, 0, 0, 0, 0, 1, 1, 1],
            ["2026-11-17", 1, 0, 50, 0, 0, 0, 0, 0, 1, 1, 1],
            ["2026-11-17", 2, 1, 20, 0, 0, 0, 0, 0, 1, 1, 1],
            ["2026-11-18", 0, 0, 120, 0, 0, 0, 0, 0, 1, 1, 1],
            ["2026-11-18", 1, 0, 60, 0, 0, 0, 0, 0, 1, 1, 1],
            ["2026-11-18", 2, 1, 30, 0, 0, 0, 0, 0, 1, 1, 1],
            ["2026-11-24", 0, 0, 150, 0, 0, 0, 0, 0, 1, 1, 1],
            ["2026-11-24", 1, 0, 80, 0, 0, 0, 0, 0, 1, 1, 1],
            ["2026-11-24", 2, 1, 40, 0, 0, 0, 0, 0, 1, 1, 1],
        ],
    }


class VisualizationPayloadTest(unittest.TestCase):
    def test_payload_keeps_daily_values_and_dimension_hierarchy(self):
        payload = MODULE.build_visualization_payload(
            sample_data(),
            {"2026-11-23": 5_600_000, "2026-11-24": 5_700_000},
            date(2026, 11, 24),
        )

        self.assertEqual(payload["defaultScope"], "platform")
        self.assertEqual(payload["granularities"], ["day", "week", "month", "quarter"])
        self.assertEqual(payload["groups"][0]["name"], "游戏")
        self.assertEqual(payload["categories"][0]["name"], "英雄联盟")
        self.assertEqual(payload["platform"], [["2026-11-23", 5_600_000], ["2026-11-24", 5_700_000]])
        self.assertEqual(payload["rows"][0][-1], 100)


class VisualizationRenderTest(unittest.TestCase):
    def test_report_labels_periods_and_renders_free_chart_controls(self):
        report_path = Path(
            r"C:\Users\Huya\Desktop\生态监控看板_最新版_2026-11-24\日报\daily_alert_report_2026-11-23.json"
        )
        report = json.loads(report_path.read_text(encoding="utf-8"))
        payload = MODULE.build_visualization_payload(
            sample_data(),
            {"2026-11-23": 5_600_000, "2026-11-24": 5_700_000},
            date(2026, 11, 23),
        )
        html_text = MODULE.render_html(report, payload)

        self.assertIn("报告日 DAU（日）", html_text)
        self.assertIn("过去 4 个同星期中位数（日）", html_text)
        self.assertIn("最新完整周 DAU（7 日求和）", html_text)
        self.assertNotIn("本期 DAU", html_text)
        self.assertIn("自由分析画布", html_text)
        self.assertIn('data-visualization-canvas="true"', html_text)
        self.assertIn('id="visualizationGranularity"', html_text)
        self.assertIn('id="visualizationChartType"', html_text)
        self.assertIn('id="visualizationScope"', html_text)
        self.assertIn('data-chart-type="line"', html_text)
        self.assertIn('data-chart-type="bar"', html_text)
        self.assertIn('data-chart-type="stack"', html_text)


if __name__ == "__main__":
    unittest.main()
