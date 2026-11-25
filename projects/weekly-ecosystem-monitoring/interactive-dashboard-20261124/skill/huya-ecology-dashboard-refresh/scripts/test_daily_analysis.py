import unittest
from datetime import date, timedelta
from daily_analysis import build_analysis, revenue_bridge
from build_daily_alert_report import classify_change


class AnalysisTest(unittest.TestCase):
    def test_revenue_bridge_closes_even_with_opposite_drivers(self):
        result = revenue_bridge(900, 1000, 150, 100)
        self.assertGreater(result['payEffect'], 0)
        self.assertLess(result['arppuEffect'], 0)
        self.assertAlmostEqual(result['payEffect'] + result['arppuEffect'], -100)
        self.assertIsNone(revenue_bridge(10, 20, 0, 2))

    def test_missing_record_breaks_streak_and_is_not_zero(self):
        today = date(2026, 11, 24)
        history = {}
        for offset in range(65):
            value = 100000 if offset > 2 else 50000
            history[(today-timedelta(days=offset)).isoformat()] = {0:dict(dau=value,revenue=value,payUsers=100,attributionUsers=value,liveAnchors=100)}
        dimensions = dict(categories=[dict(name='测试',group=0)],groups=['游戏'])
        records = build_analysis(today, history, dimensions, classify_change)
        self.assertEqual(next(r for r in records if r['metric']=='dau')['streak'], 3)
        del history[(today-timedelta(days=1)).isoformat()]
        records = build_analysis(today, history, dimensions, classify_change)
        self.assertEqual(next(r for r in records if r['metric']=='dau')['streak'], 1)
        del history[(today-timedelta(days=7)).isoformat()]
        self.assertEqual(build_analysis(today, history, dimensions, classify_change), [])

if __name__ == '__main__':
    unittest.main()
