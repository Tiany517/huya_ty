from __future__ import annotations

import argparse
import json
import math
from datetime import date
from pathlib import Path


REQUIRED_KEYS = {
    "meta",
    "categoryDaily",
    "anchorWeekly",
    "anchorDaily",
    "eventRevenueDaily",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate a generated ecology dashboard data package.")
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    return parser.parse_args()


def unique(values) -> bool:
    seen = set()
    for value in values:
        if value in seen:
            return False
        seen.add(value)
    return True


def finite_numbers(rows: list[list], first_numeric: int) -> bool:
    for row in rows:
        for value in row[first_numeric:]:
            if isinstance(value, (int, float)) and not math.isfinite(float(value)):
                return False
    return True


def main() -> int:
    args = parse_args()
    data = json.loads(args.data.read_text(encoding="utf-8"))
    missing = sorted(REQUIRED_KEYS - set(data))
    if missing:
        raise SystemExit(f"missing top-level keys: {', '.join(missing)}")

    meta = data["meta"]
    categories = meta.get("categories", [])
    anchors = meta.get("anchors", [])
    weeks = meta.get("weeks", [])
    week_ranges = meta.get("weekRanges", {})
    category_rows = data["categoryDaily"]
    anchor_rows = data["anchorWeekly"]
    anchor_daily_rows = data["anchorDaily"]
    event_rows = data["eventRevenueDaily"]

    category_keys = [(row[0], row[1]) for row in category_rows]
    anchor_keys = [(row[0], row[1], row[3], row[4]) for row in anchor_rows]
    anchor_daily_keys = [(row[0], row[1]) for row in anchor_daily_rows]

    date_format_ok = True
    try:
        for value in [
            meta.get("aggregateStartDate"),
            meta.get("aggregateEndDate"),
            meta.get("anchorStartDate"),
            meta.get("anchorEndDate"),
            meta.get("sourceLatestPartition"),
        ]:
            date.fromisoformat(value)
        for week in weeks:
            date.fromisoformat(week_ranges[week]["start"])
            date.fromisoformat(week_ranges[week]["end"])
    except (TypeError, ValueError, KeyError):
        date_format_ok = False

    week_continuity = True
    parsed_starts = []
    for week in weeks:
        try:
            parsed_starts.append(date.fromisoformat(week_ranges[week]["start"]))
        except (TypeError, ValueError, KeyError):
            week_continuity = False
            break
    if parsed_starts:
        week_continuity = week_continuity and all(
            (current - previous).days == 7
            for previous, current in zip(parsed_starts, parsed_starts[1:])
        )

    index_ranges_ok = True
    for row in category_rows:
        index_ranges_ok = index_ranges_ok and 0 <= row[1] < len(categories) and 0 <= row[2] <= 3
    for row in anchor_rows:
        index_ranges_ok = index_ranges_ok and (
            0 <= row[0] < len(weeks)
            and 0 <= row[1] < len(categories)
            and 0 <= row[3] < len(meta.get("guilds", []))
            and 0 <= row[4] < len(anchors)
        )
    for row in anchor_daily_rows:
        index_ranges_ok = index_ranges_ok and 0 <= row[1] < len(anchors)

    diagnostics = meta.get("diagnostics", {})
    counts_match = (
        diagnostics.get("categoryDailyRows") == len(category_rows)
        and diagnostics.get("categoryCount") == len(categories)
        and diagnostics.get("anchorWeeklyRows") == len(anchor_rows)
        and diagnostics.get("anchorCount") == len(anchors)
        and diagnostics.get("anchorDailyRows") == len(anchor_daily_rows)
        and diagnostics.get("eventDailyRows") == len(event_rows)
    )

    roomid_coverage = sum(1 for item in anchors if item.get("roomid")) / max(len(anchors), 1)
    nickname_coverage = sum(1 for item in anchors if item.get("name")) / max(len(anchors), 1)
    event_status = meta.get("eventStatus")
    event_status_ok = event_status in {"ready", "pending"}
    if event_status == "pending":
        event_status_ok = event_status_ok and len(event_rows) == 0
    elif event_status == "ready":
        event_status_ok = event_status_ok and len(event_rows) > 0

    interaction_over_dau = sum(1 for row in anchor_rows if row[5] > 0 and row[15] > row[5])
    live_anchor_counts_valid = all(
        0 <= row[9] <= row[10] <= row[11]
        for row in category_rows
    ) and all(0 <= row[16] <= 7 for row in anchor_rows) and all(
        row[9] in (0, 1) for row in anchor_daily_rows
    )
    checks = {
        "topLevelSchema": True,
        "dateFormat": date_format_ok,
        "consecutiveWeeks": week_continuity,
        "categoryUniqueKeys": unique(category_keys),
        "anchorWeeklyUniqueKeys": unique(anchor_keys),
        "anchorDailyUniqueKeys": unique(anchor_daily_keys),
        "indexRanges": index_ranges_ok,
        "diagnosticCountsMatch": counts_match,
        "searchCoverage": nickname_coverage >= 0.99 and roomid_coverage >= 0.90,
        "finiteNumbers": finite_numbers(category_rows, 3)
        and finite_numbers(anchor_rows, 5)
        and finite_numbers(anchor_daily_rows, 2)
        and finite_numbers(event_rows, 6),
        "eventStatusConsistent": event_status_ok,
        "liveAnchorCountsValid": live_anchor_counts_valid,
        "nonEmptyCoreData": len(category_rows) > 0 and len(anchor_rows) > 0 and len(anchor_daily_rows) > 0,
    }
    report = {
        "status": "passed" if all(checks.values()) else "failed",
        "data": str(args.data),
        "bytes": args.data.stat().st_size,
        "checks": checks,
        "diagnostics": {
            "categoryDailyRows": len(category_rows),
            "categoryCount": len(categories),
            "anchorWeeklyRows": len(anchor_rows),
            "anchorCount": len(anchors),
            "guildCount": len(meta.get("guilds", [])),
            "anchorDailyRows": len(anchor_daily_rows),
            "eventDailyRows": len(event_rows),
            "eventStatus": event_status,
            "anchorDailyStatus": meta.get("anchorDailyStatus"),
            "nicknameCoverage": round(nickname_coverage, 6),
            "roomidCoverage": round(roomid_coverage, 6),
            "interactionOverDauRows": interaction_over_dau,
            "liveAnchorCountCoverage": "category/group/total daily counts and weekly live-days present",
            "aggregateStartDate": meta.get("aggregateStartDate"),
            "aggregateEndDate": meta.get("aggregateEndDate"),
            "anchorStartDate": meta.get("anchorStartDate"),
            "anchorEndDate": meta.get("anchorEndDate"),
        },
        "warnings": [],
    }
    if interaction_over_dau:
        report["warnings"].append(
            "互动人数大于主播 DAU 的记录存在；跨场次/跨主播人数未去重，只能用于相对趋势。"
        )
    if event_status == "pending":
        report["warnings"].append("赛事支付属性尚未回刷，赛事筛选不可用于 DAU/归属/互动对比。")

    text = json.dumps(report, ensure_ascii=False, indent=2)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
