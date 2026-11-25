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
    def test_zero_baseline_change_rate_is_not_infinite(self):
        self.assertIsNone(MODULE.pct_change(10, 0))
        self.assertIsNone(MODULE.pct_change(0, 0))

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

    def test_anchor_level_uses_its_own_four_week_history(self):
        row = {"_key": (0, 0, 0), "currentDau": 20_000}
        weekly = {
            "anchorHistoryWeekIdxs": [0, 1, 2, 3],
            "anchorDauHistory": {(0, 0, 0): {0: 10_000, 1: 10_000, 2: 10_000, 3: 10_000}},
        }
        MODULE.apply_anchor_history_severity(row, weekly)
        self.assertEqual(row["severityLabel"], "高")
        self.assertEqual(row["severityConfidence"], "high")
        self.assertEqual(row["historyWeeksAvailable"], 4)
        self.assertGreater(abs(row["severityRobustZ"]), 3)

    def test_anchor_level_missing_history_does_not_fill_zero(self):
        row = {"_key": (0, 0, 0), "currentDau": 20_000}
        weekly = {
            "anchorHistoryWeekIdxs": [0, 1, 2, 3],
            "anchorDauHistory": {(0, 0, 0): {0: 10_000, 1: 10_000}},
        }
        MODULE.apply_anchor_history_severity(row, weekly)
        self.assertEqual(row["historyWeeksAvailable"], 2)
        self.assertEqual(row["severityBaseline"], 10_000)
        self.assertEqual(row["severityConfidence"], "low")
        self.assertEqual(row["severityLabel"], "中")

    def test_guild_live_anchors_are_deduplicated_across_categories(self):
        columns = [
            "week", "category", "group", "guild", "anchor", "dau", "revenue",
            "payUsers", "live", "acuSum", "acuDays", "viewMinutes", "viewDays",
            "attributionUsers", "interactionCount", "interactionUsers", "liveDays",
        ]

        def row(week, category, anchor, live_days, dau):
            return [week, category, 0, 0, anchor, dau, 0, 0, 1, 1_000, live_days, 0, 0, 0, 0, 0, live_days]

        data = {
            "meta": {
                "weeks": [
                    "2026-10-12",
                    "2026-10-19",
                    "2026-10-26",
                    "2026-11-02",
                    "2026-11-09",
                    "2026-11-16",
                ],
                "anchorColumns": columns,
            },
            "anchorWeekly": [
                row(1, 0, 0, 7, 200),
                row(1, 1, 0, 7, 180),
                row(1, 0, 1, 2, 90),
                row(2, 0, 0, 7, 210),
                row(3, 0, 0, 7, 215),
                row(3, 1, 0, 4, 170),
                row(3, 0, 1, 2, 85),
                row(4, 0, 0, 6, 200),
                row(4, 0, 1, 1, 80),
                row(5, 0, 0, 7, 220),
                row(5, 1, 0, 7, 180),
                row(5, 0, 1, 3, 90),
            ],
        }
        weekly = MODULE.aggregate_weekly_rows(data)
        current = weekly["guild"][weekly["currentWeekIdx"]][0]
        self.assertEqual(current["liveDays"], 10)
        history = weekly["guildLiveAnchorHistory"][0]
        self.assertAlmostEqual(history[1], 9 / 7)
        self.assertAlmostEqual(history[2], 7 / 7)
        self.assertAlmostEqual(history[3], 9 / 7)
        self.assertAlmostEqual(history[4], 7 / 7)
        rows = MODULE.weekly_rows_for(
            weekly,
            "guild",
            weekly["currentWeekIdx"],
            weekly["previousWeekIdx"],
            {},
            lambda key: key,
            lambda key, _: "测试公会",
        )
        self.assertAlmostEqual(rows[0]["currentLiveAnchors"], 10 / 7)

    def test_guild_level_uses_its_own_four_week_live_anchor_history(self):
        row = {"_key": 0, "currentLiveAnchors": 140}
        weekly = {
            "anchorHistoryWeekIdxs": [0, 1, 2, 3],
            "guildLiveAnchorHistory": {0: {0: 100, 1: 100, 2: 100, 3: 100}},
        }
        MODULE.apply_guild_history_severity(row, weekly)
        self.assertEqual(row["severityLabel"], "高")
        self.assertEqual(row["severityConfidence"], "high")
        self.assertEqual(row["historyWeeksAvailable"], 4)
        self.assertGreater(abs(row["severityRobustZ"]), 3)

    def test_guild_level_missing_history_does_not_fill_zero(self):
        row = {"_key": 0, "currentLiveAnchors": 140}
        weekly = {
            "anchorHistoryWeekIdxs": [0, 1, 2, 3],
            "guildLiveAnchorHistory": {0: {0: 100, 1: 100}},
        }
        MODULE.apply_guild_history_severity(row, weekly)
        self.assertEqual(row["historyWeeksAvailable"], 2)
        self.assertEqual(row["severityBaseline"], 100)
        self.assertEqual(row["severityConfidence"], "low")
        self.assertEqual(row["severityLabel"], "中")


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
        self.assertIn('id="visualizationDimension"', html_text)
        self.assertIn('id="visualizationDrillValue"', html_text)
        self.assertIn('id="visualizationTooltip"', html_text)
        self.assertIn('data-chart-type="line"', html_text)
        self.assertIn('data-chart-type="bar"', html_text)
        self.assertIn('data-chart-type="stack"', html_text)
        self.assertIn("品类 Top10", html_text)
        self.assertIn('id="categoryTopLimit"', html_text)
        self.assertIn('id="categoryTable"', html_text)
        self.assertIn('id="guildTopLimit"', html_text)
        self.assertIn('id="guildTable"', html_text)
        self.assertIn("级别按公会自身前 4 个完整周异常分判定", html_text)
        self.assertIn("最新完整周 开播主播数（日均）", html_text)
        self.assertIn("头部：周平均 ACU ≥ 2,000；腰部：100–1,999；尾部：&lt;100", html_text)
        self.assertIn('id="anchorTopLimit"', html_text)
        self.assertIn('id="anchorTopTitle">主播 Top10</h2>', html_text)
        self.assertIn("级别按该行主播自身前 4 个完整周异常分判定", html_text)
        self.assertIn("主播</th>", html_text)
        self.assertLess(html_text.index('id="anchorTable"'), html_text.index('id="methodNotesTitle"'))


if __name__ == "__main__":
    unittest.main()
