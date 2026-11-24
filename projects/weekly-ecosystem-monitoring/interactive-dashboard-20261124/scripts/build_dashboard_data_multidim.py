from __future__ import annotations

import argparse
import csv
import json
from collections import Counter, defaultdict
from datetime import date, timedelta
from pathlib import Path


ROOT = Path(__file__).resolve().parent
DEFAULT_CATEGORY_CSV = ROOT / "category_daily_all_20261123.csv"
DEFAULT_ANCHOR_CSV = ROOT / "anchor_weekly_guild_20261012_20261122.csv"
DEFAULT_ANCHOR_DAILY_CSV = ROOT / "anchor_daily_focus_20261012_20261122.csv"
DEFAULT_EVENT_CSV = ROOT / "event_user_revenue_20261012_20261122.csv"
DEFAULT_OUTPUT = ROOT / "dashboard_data_multidim_20261123.json"
DEFAULT_SOURCE_LATEST_PARTITION = "2026-11-23"

CATEGORY_CSV = DEFAULT_CATEGORY_CSV
ANCHOR_CSV = DEFAULT_ANCHOR_CSV
ANCHOR_DAILY_CSV = DEFAULT_ANCHOR_DAILY_CSV
EVENT_CSV = DEFAULT_EVENT_CSV
OUTPUT = DEFAULT_OUTPUT
SOURCE_LATEST_PARTITION = DEFAULT_SOURCE_LATEST_PARTITION

GROUPS = ["游戏", "娱乐（秀场）", "娱乐（非秀场）", "未匹配"]
GROUP_ORDER = {name: i for i, name in enumerate(GROUPS)}
DEFAULT_WEEK_STARTS = [
    "2026-10-12",
    "2026-10-19",
    "2026-10-26",
    "2026-11-02",
    "2026-11-09",
    "2026-11-16",
]
WEEK_STARTS = DEFAULT_WEEK_STARTS.copy()


def configure(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Build ecology dashboard multidimensional JSON from CSV inputs.")
    parser.add_argument("--category-csv", type=Path, default=DEFAULT_CATEGORY_CSV)
    parser.add_argument("--anchor-weekly-csv", type=Path, default=DEFAULT_ANCHOR_CSV)
    parser.add_argument("--anchor-daily-csv", type=Path, default=DEFAULT_ANCHOR_DAILY_CSV)
    parser.add_argument("--event-csv", type=Path, default=DEFAULT_EVENT_CSV)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--week-start",
        default=",".join(DEFAULT_WEEK_STARTS),
        help="Comma-separated Monday/week-start dates, in ascending order.",
    )
    parser.add_argument("--source-latest-partition", default=DEFAULT_SOURCE_LATEST_PARTITION)
    args = parser.parse_args(argv)

    global CATEGORY_CSV, ANCHOR_CSV, ANCHOR_DAILY_CSV, EVENT_CSV, OUTPUT
    global SOURCE_LATEST_PARTITION, WEEK_STARTS
    CATEGORY_CSV = args.category_csv.resolve()
    ANCHOR_CSV = args.anchor_weekly_csv.resolve()
    ANCHOR_DAILY_CSV = args.anchor_daily_csv.resolve()
    EVENT_CSV = args.event_csv.resolve()
    OUTPUT = args.output.resolve()
    SOURCE_LATEST_PARTITION = str(args.source_latest_partition)

    week_starts = [item.strip() for item in args.week_start.split(",") if item.strip()]
    if not week_starts:
        raise ValueError("--week-start must contain at least one date")
    parsed = [date.fromisoformat(item) for item in week_starts]
    for prev, current in zip(parsed, parsed[1:]):
        if current <= prev:
            raise ValueError("--week-start dates must be strictly ascending")
        if (current - prev).days != 7:
            raise ValueError("--week-start dates must be consecutive 7-day intervals")
    WEEK_STARTS = week_starts


def number(value, default=0.0) -> float:
    if value is None or value == "":
        return default
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def integer(value, default=0) -> int:
    return int(round(number(value, default)))


def compact(value: float, digits: int = 4):
    rounded = round(float(value), digits)
    if abs(rounded - round(rounded)) < 1e-9:
        return int(round(rounded))
    return rounded


def week_label(day: date) -> str:
    iso = day.isocalendar()
    return f"{iso.year}W{iso.week:02d}"


def build_week_meta() -> tuple[list[str], dict[str, dict[str, str]]]:
    weeks = []
    ranges = {}
    for value in WEEK_STARTS:
        start = date.fromisoformat(value)
        end = start + timedelta(days=6)
        label = week_label(start)
        weeks.append(label)
        ranges[label] = {
            "start": start.isoformat(),
            "end": end.isoformat(),
            "short": f"{start.strftime('%m.%d')}-{end.strftime('%m.%d')}",
        }
    return weeks, ranges


def read_category_rows() -> tuple[list[list], list[dict], dict[str, int]]:
    raw_rows = []
    latest_name = {}
    latest_group = {}
    with CATEGORY_CSV.open(encoding="utf-8-sig", newline="") as fh:
        for row in csv.DictReader(fh):
            gameid = (row.get("gameid") or "").strip()
            name = (row.get("game_name") or "").strip()
            group = (row.get("content_group") or "未匹配").strip()
            if not gameid or not name:
                continue
            latest_name[gameid] = name
            latest_group[gameid] = group if group in GROUP_ORDER else "未匹配"
            raw_rows.append(row)

    category_ids = sorted(
        latest_name,
        key=lambda gameid: (
            GROUP_ORDER.get(latest_group[gameid], 99),
            latest_name[gameid],
            gameid,
        ),
    )
    category_index = {gameid: i for i, gameid in enumerate(category_ids)}
    categories = [
        {
            "id": gameid,
            "name": latest_name[gameid],
            "group": GROUP_ORDER[latest_group[gameid]],
        }
        for gameid in category_ids
    ]

    rows = []
    for row in raw_rows:
        gameid = (row.get("gameid") or "").strip()
        if gameid not in category_index:
            continue
        group = latest_group[gameid]
        rows.append([
            row["dt"],
            category_index[gameid],
            GROUP_ORDER[group],
            compact(number(row.get("dau"))),
            compact(number(row.get("daily_revenue"))),
            compact(number(row.get("daily_pay_user_cnt"))),
            compact(number(row.get("arppu"))),
            compact(number(row.get("avg_view_mins"))),
            compact(number(row.get("attribution_user_cnt"))),
            integer(row.get("live_anchor_cnt")),
            integer(row.get("group_live_anchor_cnt")),
            integer(row.get("total_live_anchor_cnt")),
        ])
    rows.sort(key=lambda r: (r[0], r[2], r[1]))
    return rows, categories, category_index


def read_anchor_rows(
    category_index: dict[str, int],
    weeks: list[str],
) -> tuple[list[list], list[list], list[str], list[dict]]:
    week_index = {start: i for i, start in enumerate(WEEK_STARTS)}
    guild_index: dict[str, int] = {}
    guilds: list[str] = []
    anchor_index: dict[str, int] = {}
    anchors: list[list] = []
    anchor_latest_week: dict[str, int] = {}
    rows = []

    def get_guild(name: str) -> int:
        nonlocal guilds
        name = name.strip() or "无公会"
        if name not in guild_index:
            guild_index[name] = len(guilds)
            guilds.append(name)
        return guild_index[name]

    def get_anchor(uid: str, nickname: str, roomid: str, week_idx: int) -> int:
        if uid not in anchor_index:
            anchor_index[uid] = len(anchors)
            anchors.append([uid, nickname or "未知主播", roomid or ""])
            anchor_latest_week[uid] = week_idx
        elif week_idx >= anchor_latest_week[uid]:
            anchor_latest_week[uid] = week_idx
            anchor = anchors[anchor_index[uid]]
            if nickname:
                anchor[1] = nickname
            if roomid:
                anchor[2] = roomid
        return anchor_index[uid]

    with ANCHOR_CSV.open(encoding="utf-8-sig", newline="") as fh:
        for row in csv.DictReader(fh):
            week = (row.get("week_start") or "").strip()
            gameid = (row.get("gameid") or "").strip()
            uid = (row.get("luid") or "").strip()
            nickname = (row.get("snick") or "").strip()
            if week not in week_index or gameid not in category_index or not uid:
                continue
            if not nickname or nickname.startswith("#") or nickname == "未归属主播":
                continue
            week_idx = week_index[week]
            guild_idx = get_guild(row.get("guild_name") or "")
            roomid = (row.get("roomid") or "").strip()
            anchor_idx = get_anchor(uid, nickname, roomid, week_idx)
            category_idx = category_index[gameid]
            group_name = (row.get("content_group") or "未匹配").strip()
            rows.append([
                week_idx,
                category_idx,
                GROUP_ORDER.get(group_name, 3),
                guild_idx,
                anchor_idx,
                compact(number(row.get("dau_sum"))),
                compact(number(row.get("revenue_sum"))),
                compact(number(row.get("pay_sum"))),
                compact(number(row.get("live_sum"))),
                compact(number(row.get("acu_sum"))),
                integer(row.get("acu_days")),
                compact(number(row.get("view_sum"))),
                integer(row.get("view_days")),
                compact(number(row.get("attribution_sum"))),
                compact(number(row.get("interaction_cnt_sum"))),
                compact(number(row.get("interaction_user_sum"))),
                integer(row.get("live_days")),
            ])
    rows.sort(key=lambda r: (r[0], r[2], r[1], -float(r[13]), -float(r[6]), r[4]))
    return rows, anchors, guilds, [
        {"id": uid, "name": name, "roomid": room}
        for uid, name, room in anchors
    ]


def read_event_rows(
    category_index: dict[str, int],
    guilds: list[str],
    anchors: list[list],
    weeks: list[str],
) -> tuple[list[list], str]:
    if not EVENT_CSV.exists() or EVENT_CSV.stat().st_size == 0:
        return [], "pending"
    week_index = {start: i for i, start in enumerate(WEEK_STARTS)}
    guild_index = {name: i for i, name in enumerate(guilds)}
    anchor_index = {row[0]: i for i, row in enumerate(anchors)}
    rows = []
    with EVENT_CSV.open(encoding="utf-8-sig", newline="") as fh:
        reader = csv.DictReader(fh)
        if not reader.fieldnames or "revenue" not in reader.fieldnames:
            return [], "failed"
        for row in reader:
            week = (row.get("week_start") or "").strip()
            gameid = (row.get("gameid") or "").strip()
            uid = (row.get("luid") or "").strip()
            if week not in week_index or gameid not in category_index or uid not in anchor_index:
                continue
            guild = (row.get("guild_name") or "无公会").strip() or "无公会"
            if guild not in guild_index:
                guild_index[guild] = len(guilds)
                guilds.append(guild)
            event_type = 1 if (row.get("user_event_type") or "") == "赛事用户" else 0
            rows.append([
                row["dt"],
                week_index[week],
                category_index[gameid],
                guild_index[guild],
                anchor_index[uid],
                event_type,
                compact(number(row.get("revenue"))),
                compact(number(row.get("pay_user_cnt"))),
            ])
    rows.sort(key=lambda r: (r[0], r[2], r[5], r[4]))
    return rows, "ready"


def read_anchor_daily_rows(
    category_index: dict[str, int],
    guilds: list[str],
    anchors: list[list],
    allowed_anchor_indices: set[int],
) -> tuple[list[list], str]:
    if not ANCHOR_DAILY_CSV.exists() or ANCHOR_DAILY_CSV.stat().st_size == 0:
        return [], "pending"
    anchor_index = {row[0]: i for i, row in enumerate(anchors)}
    aggregated: dict[tuple[str, int], list] = {}
    with ANCHOR_DAILY_CSV.open(encoding="utf-8-sig", newline="") as fh:
        reader = csv.DictReader(fh)
        if not reader.fieldnames or "roomid" not in reader.fieldnames:
            return [], "failed"
        for row in reader:
            gameid = (row.get("gameid") or "").strip()
            uid = (row.get("luid") or "").strip()
            if gameid not in category_index or uid not in anchor_index:
                continue
            anchor_idx = anchor_index[uid]
            if anchor_idx not in allowed_anchor_indices:
                continue
            key = (row["dt"], anchor_idx)
            if key not in aggregated:
                aggregated[key] = [row["dt"], anchor_idx, 0, 0, 0, 0, 0, 0, 0, 0]
            target = aggregated[key]
            target[2] += number(row.get("dau"))
            target[3] += number(row.get("daily_revenue"))
            target[4] += number(row.get("daily_pay_user_cnt"))
            target[5] += number(row.get("avg_view_mins"))
            target[6] += number(row.get("attribution_user_cnt"))
            target[7] += number(row.get("interaction_cnt"))
            target[8] += number(row.get("interaction_user_cnt"))
            target[9] = max(
                target[9],
                1 if integer(row.get("is_live")) == 1 or number(row.get("live_mins")) > 0 else 0,
            )
    rows = [[r[0], r[1], *[compact(v) for v in r[2:]]] for r in aggregated.values()]
    rows.sort(key=lambda r: (r[0], r[1]))
    return rows, "ready"


def main(argv: list[str] | None = None) -> None:
    configure(argv)
    category_rows, categories, category_index = read_category_rows()
    weeks, week_ranges = build_week_meta()
    anchor_rows, anchors, guilds, anchor_meta = read_anchor_rows(category_index, weeks)
    activity = defaultdict(lambda: [0.0, 0.0, 0.0])
    for row in anchor_rows:
        item = activity[row[4]]
        item[0] += number(row[13])
        item[1] += number(row[6])
        item[2] += number(row[15])
    active_anchor_indices = {
        anchor_idx for anchor_idx, (attr, revenue, interaction_users) in activity.items()
        if attr >= 10 or revenue >= 1 or interaction_users >= 10
    }
    anchor_daily_rows, anchor_daily_status = read_anchor_daily_rows(
        category_index, guilds, anchors, active_anchor_indices
    )
    event_rows, event_status = read_event_rows(category_index, guilds, anchors, weeks)

    group_counts = Counter(item["group"] for item in categories)
    anchor_end_date = (date.fromisoformat(WEEK_STARTS[-1]) + timedelta(days=6)).isoformat()
    payload = {
        "meta": {
            "source": "zhgametemp.zty_category_ecology_health_daily_d_i_0827_v1",
            "guildSource": "gamelive.dm_huya_ayyuid_detail_day",
            "sourceLatestPartition": SOURCE_LATEST_PARTITION,
            "aggregateStartDate": min(r[0] for r in category_rows),
            "aggregateEndDate": max(r[0] for r in category_rows),
            "anchorStartDate": WEEK_STARTS[0],
            "anchorEndDate": anchor_end_date,
            "contentGroups": GROUPS,
            "groupCounts": {GROUPS[i]: group_counts[i] for i in range(len(GROUPS))},
            "weeks": weeks,
            "weekRanges": week_ranges,
            "guilds": guilds,
            "categories": categories,
            "anchors": anchor_meta,
            "eventStatus": event_status,
            "anchorDailyStatus": anchor_daily_status,
            "anchorDailyCoverage": f"{weeks[0]}-{weeks[-1]}期间归属DAU>=10或流水>=1元或互动人数>=10的主播",
            "eventMethod": "支付用户前90天赛事主播观时占比>=70%",
            "eventCoverage": f"{WEEK_STARTS[0]} 至 {anchor_end_date}（仅游戏支付指标）",
            "interactionMethod": "com_ucnt / dau；跨主播汇总人数可能重叠，仅用于相对监控",
            "tierMethod": "头部ACU>=2000；腰部100<=ACU<2000；尾部ACU<100",
            "categoryColumns": [
                "date", "category", "group", "dau", "revenue", "payUsers",
                "arppu", "viewMinutes", "attributionUsers", "liveAnchors",
                "groupLiveAnchors", "totalLiveAnchors",
            ],
            "anchorColumns": [
                "week", "category", "group", "guild", "anchor", "dau", "revenue",
                "payUsers", "live", "acuSum", "acuDays", "viewMinutes", "viewDays",
                "attributionUsers", "interactionCount", "interactionUsers", "liveDays",
            ],
            "anchorDailyColumns": [
                "date", "anchor", "dau", "revenue", "payUsers", "viewMinutes",
                "attributionUsers", "interactionCount", "interactionUsers", "isLive",
            ],
            "eventColumns": [
                "date", "week", "category", "guild", "anchor", "eventUser",
                "revenue", "payUsers",
            ],
            "diagnostics": {
                "categoryDailyRows": len(category_rows),
                "categoryCount": len(categories),
                "anchorWeeklyRows": len(anchor_rows),
                "anchorCount": len(anchors),
                "guildCount": len(guilds),
                "anchorDailyRows": len(anchor_daily_rows),
                "eventDailyRows": len(event_rows),
            },
        },
        "categoryDaily": category_rows,
        "anchorWeekly": anchor_rows,
        "anchorDaily": anchor_daily_rows,
        "eventRevenueDaily": event_rows,
    }
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(json.dumps({
        "output": str(OUTPUT),
        "bytes": OUTPUT.stat().st_size,
        **payload["meta"]["diagnostics"],
        "eventStatus": event_status,
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
