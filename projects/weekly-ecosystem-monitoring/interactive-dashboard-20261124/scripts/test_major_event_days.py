from __future__ import annotations

import csv
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_daily_v12 import load_major_event_days
from build_major_event_days import classify_cycles, load_event_days, load_official_events, merge_official_events


class MajorEventSelectionTest(unittest.TestCase):
    def test_cf_keeps_november_event_and_drops_tiny_event(self) -> None:
        cycles = classify_cycles([
            self.cycle("4", "9029603", "CFPL夏季赛", 46, 135202.15),
            self.cycle("4", "9029609", "CFPL全明星", 2, 136163.5),
            self.cycle("4", "9029611", "CFS中国区预选赛", 8, 89442.25),
            self.cycle("4", "9029612", "百城联赛秋季嘉年华", 7, 56568.0),
            self.cycle("4", "9029608", "CF百城", 3, 867.33),
            self.cycle("4", "9031116", "EWC穿越火线", 5, 193365.6),
        ])
        status = {row["match_id"]: row["status"] for row in cycles}
        self.assertEqual(status["9029611"], "selected")
        self.assertEqual(status["9029612"], "selected")
        self.assertEqual(status["9029608"], "excluded_low_scale")

    def test_low_scale_filter_is_category_relative_and_single_event_is_kept(self) -> None:
        cycles = classify_cycles([
            self.cycle("A", "1", "最大赛事", 2, 1000),
            self.cycle("A", "2", "中档赛事", 2, 80),
            self.cycle("A", "3", "极小赛事", 1, 20),
            self.cycle("B", "4", "小品类唯一赛事", 1, 20),
        ])
        status = {(row["gameid"], row["match_id"]): row["status"] for row in cycles}
        self.assertEqual(status[("A", "1")], "selected")
        self.assertEqual(status[("A", "2")], "selected")
        self.assertEqual(status[("A", "3")], "excluded_low_scale")
        self.assertEqual(status[("B", "4")], "selected")

    def test_event_days_are_filtered_deduplicated_and_aliases_are_normalized(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "days.csv"
            with path.open("w", encoding="utf-8-sig", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=["dt", "gameid", "match_id", "match_name"])
                writer.writeheader()
                writer.writerows([
                    {"dt": "2026-11-07", "gameid": "4", "match_id": "9029612", "match_name": "百城联赛秋季嘉年华"},
                    {"dt": "2026-11-07", "gameid": "4", "match_id": "9029612", "match_name": "百城联赛秋季嘉年华"},
                    {"dt": "2026-07-08", "gameid": "4", "match_id": "9029608", "match_name": "CF百城"},
                    {"dt": "2026-07-20", "gameid": "无畏契约", "match_id": "9029807", "match_name": "VCTCN"},
                ])
            cycles = classify_cycles([
                self.cycle("4", "9029612", "百城联赛秋季嘉年华", 7, 56568),
                self.cycle("4", "9029608", "CF百城", 3, 867),
                self.cycle("5937", "9029807", "VCTCN", 7, 399042),
            ])
            rows, stats = load_event_days(path, cycles)
        self.assertEqual(len(rows), 2)
        self.assertEqual({row["gameid"] for row in rows}, {"4", "5937"})
        self.assertEqual(stats["rawEventDayRows"], 4)
        self.assertEqual(stats["selectedEventDayRows"], 2)

    def test_verified_official_schedule_supplements_copyright_gap(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "official.csv"
            with path.open("w", encoding="utf-8-sig", newline="") as handle:
                writer = csv.DictWriter(
                    handle,
                    fieldnames=["gameid", "match_id", "match_name", "start_day", "end_day", "source", "source_url", "note"],
                )
                writer.writeheader()
                writer.writerow({
                    "gameid": "4",
                    "match_id": "official-cfs-world-finals-2026",
                    "match_name": "2026CFS世界总决赛",
                    "start_day": "2026-11-24",
                    "end_day": "2026-11-26",
                    "source": "虎牙站内赛事页",
                    "source_url": "",
                    "note": "版权表未覆盖",
                })
            official = load_official_events(path)
            cycles = classify_cycles([self.cycle("4", "9029612", "百城联赛秋季嘉年华", 7, 56568)])
            cycles, days, stats = merge_official_events(cycles, [], official)
        self.assertEqual(stats["officialEventDayRows"], 3)
        self.assertEqual([row["dt"] for row in days], ["2026-11-24", "2026-11-25", "2026-11-26"])
        official_cycle = next(row for row in cycles if row["match_id"] == "official-cfs-world-finals-2026")
        self.assertEqual(official_cycle["status"], "selected_official")
        self.assertEqual(official_cycle["selection_source"], "official_schedule")

    def test_builder_preserves_major_event_provenance(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            days_path = root / "days.csv"
            meta_path = root / "meta.json"
            with days_path.open("w", encoding="utf-8-sig", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=["dt", "gameid", "match_id", "match_name"])
                writer.writeheader()
                writer.writerows([
                    {"dt": "2026-11-07", "gameid": "4", "match_id": "9029612", "match_name": "百城联赛秋季嘉年华"},
                    {"dt": "2026-11-08", "gameid": "4", "match_id": "9029612", "match_name": "百城联赛秋季嘉年华"},
                ])
            meta_path.write_text(
                '{"rule":"test rule","categories":{"4":{"selectedEvents":[{"matchId":"9029612","matchName":"百城联赛秋季嘉年华"}],"excludedLowEvents":[{"matchId":"9029608","matchName":"CF百城"}],"selectionThreshold":20223.08}}}',
                encoding="utf-8",
            )
            days, meta = load_major_event_days(days_path, meta_path)
        self.assertEqual(days["4"], ["2026-11-07", "2026-11-08"])
        self.assertEqual(meta["4"]["rule"], "test rule")
        self.assertEqual(meta["4"]["excludedLowEvents"][0]["matchId"], "9029608")

    @staticmethod
    def cycle(gameid: str, match_id: str, name: str, days: int, mean: float) -> dict:
        return {
            "gameid": gameid,
            "match_id": match_id,
            "match_name": name,
            "mapped_start": "2026-01-01",
            "mapped_end": "2026-01-01",
            "observed_days": days,
            "mean_event_dau": mean,
        }


if __name__ == "__main__":
    unittest.main()
