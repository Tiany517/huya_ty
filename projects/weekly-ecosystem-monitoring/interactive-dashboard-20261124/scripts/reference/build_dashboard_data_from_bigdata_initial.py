from __future__ import annotations

import csv
import json
from datetime import date, timedelta
from pathlib import Path


ROOT = Path(__file__).resolve().parent
AGGREGATE_CSV = ROOT / "ecology_aggregate_20261123.csv"
ANCHOR_CSV = ROOT / "ecology_anchor_weekly_20261012_20261122.csv"
OUTPUT = ROOT / "dashboard_data_bigdata_20261123.json"

CATEGORY_ORDER = ["CS2", "体育", "户外", "无畏契约", "王者荣耀", "英雄联盟"]
WEEK_STARTS = [
    "2026-10-12",
    "2026-10-19",
    "2026-10-26",
    "2026-11-02",
    "2026-11-09",
    "2026-11-16",
]


def number(value, default=0.0) -> float:
    if value is None or value == "":
        return default
    try:
        return float(value)
    except ValueError:
        return default


def compact(value: float, digits: int = 4):
    rounded = round(float(value), digits)
    if abs(rounded - round(rounded)) < 1e-9:
        return int(round(rounded))
    return rounded


def week_label(day: date) -> str:
    iso = day.isocalendar()
    return f"{iso.year}W{iso.week:02d}"


def week_ranges() -> dict[str, dict[str, str]]:
    out = {}
    for week_start in WEEK_STARTS:
        start = date.fromisoformat(week_start)
        end = start + timedelta(days=6)
        label = week_label(start)
        out[label] = {
            "start": start.isoformat(),
            "end": end.isoformat(),
            "short": f"{start.strftime('%m.%d')}-{end.strftime('%m.%d')}",
        }
    return out


def main() -> None:
    aggregate = []
    with AGGREGATE_CSV.open(encoding="utf-8-sig", newline="") as fh:
        for row in csv.DictReader(fh):
            aggregate.append({
                "d": row["dt"],
                "c": row["game_name"],
                "dau": compact(number(row["dau"])),
                "rev": compact(number(row["daily_revenue"])),
                "pay": compact(number(row["daily_pay_user_cnt"])),
                "arppu": compact(number(row["arppu"])),
                "view": compact(number(row["avg_view_mins"])),
                "attr": compact(number(row["attribution_user_cnt"])),
            })

    anchors = []
    week_index = {week_start: i for i, week_start in enumerate(WEEK_STARTS)}
    with ANCHOR_CSV.open(encoding="utf-8-sig", newline="") as fh:
        for row in csv.DictReader(fh):
            week_start = row["week_start"]
            if week_start not in week_index:
                continue
            nickname = (row.get("snick") or "").strip()
            if not nickname or nickname.startswith("#") or nickname == "未归属主播":
                continue
            anchors.append([
                row["game_name"],
                week_index[week_start],
                row["luid"],
                nickname,
                compact(number(row["dau_sum"])),
                compact(number(row["revenue_sum"])),
                compact(number(row["pay_sum"])),
                compact(number(row["live_sum"])),
                compact(number(row["acu_sum"])),
                int(number(row["acu_days"])),
                compact(number(row["view_sum"])),
                int(number(row["view_days"])),
                compact(number(row["attribution_sum"])),
            ])

    aggregate.sort(key=lambda x: (x["d"], CATEGORY_ORDER.index(x["c"]) if x["c"] in CATEGORY_ORDER else 99))
    anchors.sort(key=lambda x: (x[1], x[0], -float(x[5]), -float(x[12]), x[2]))
    weeks = list(week_ranges())
    payload = {
        "meta": {
            "source": "zhgametemp.zty_category_ecology_health_daily_d_i_0827_v1",
            "sourceLatestPartition": "2026-11-23",
            "aggregateStartDate": "2026-01-01",
            "aggregateEndDate": "2026-11-23",
            "startDate": WEEK_STARTS[0],
            "endDate": "2026-11-22",
            "weeks": weeks,
            "weekRanges": week_ranges(),
            "categories": CATEGORY_ORDER,
            "categoryColumns": ["d", "c", "dau", "rev", "pay", "arppu", "view", "attr"],
            "anchorColumns": ["category", "weekIndex", "uid", "nickname", "dauSum", "revenueSum", "payUsersSum", "liveHoursSum", "acuSum", "acuDays", "viewMinsSum", "viewDays", "attributionSum"],
            "diagnostics": {
                "aggregateRows": len(aggregate),
                "anchorWeeklyRows": len(anchors),
                "anchorSourceCsvRows": sum(1 for _ in ANCHOR_CSV.open(encoding="utf-8-sig")) - 1,
            },
        },
        "aggregate": aggregate,
        "anchors": anchors,
    }
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(json.dumps({
        "output": str(OUTPUT),
        "bytes": OUTPUT.stat().st_size,
        "aggregateRows": len(aggregate),
        "anchorWeeklyRows": len(anchors),
        "weeks": weeks,
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
