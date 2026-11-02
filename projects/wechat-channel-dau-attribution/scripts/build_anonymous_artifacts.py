#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Build de-identified WeChat Channel DAU attribution artifacts.

The raw input is streamer x day, not user detail. This script removes streamer
names and platform IDs, assigns stable hash-based aliases, normalizes dates,
rebuilds the two-week comparison, and writes the committed artifacts.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter


W1_START = "2026-09-14"
W1_END = "2026-09-20"
W2_START = "2026-09-21"
W2_END = "2026-09-27"
W1 = {f"2026-09-{day:02d}" for day in range(14, 21)}
W2 = {f"2026-09-{day:02d}" for day in range(21, 28)}

NUMERIC_FIELDS = {
    "validonlinedaycnt": "valid_online_days",
    "onlinetimeduration": "online_hours",
    "validonlinetimeduration": "valid_online_hours",
    "audiencecnt": "audience_count",
    "rewardaudiencecnt": "reward_audience_count",
    "rewardcnt": "reward_count",
    "liveacu100times": "live_acu_100_times",
    "liveroomrewardcnt": "live_room_reward_count",
    "anchorrewardincome": "anchor_reward_income",
    "sharemicrewardincome": "share_mic_reward_income",
    "asmicaudiencerewardincome": "asmic_audience_reward_income",
    "findertotalincome": "finder_total_income",
}

GROUP_LABELS = {
    "persistent": "持续开播",
    "new_or_returning_w2": "W2新增/回流",
    "absent_w2": "W2未开播",
}

CONTENT_LABELS = {
    "mahjong": "麻将",
    "landlord": "斗地主",
    "poker_upgrade": "升级/扑克",
    "board_games": "棋类(象棋/军棋)",
    "tabletop_games": "棋牌向桌游",
    "boundary_sanguosha": "边界-三国杀",
    "boundary_hearthstone": "边界-炉石",
    "boundary_autochess": "边界-云顶之弈/金铲铲",
    "non_content_group": "非棋牌类",
}

QIPAI_SOURCE_LABELS = {
    "麻将": "mahjong",
    "斗地主": "landlord",
    "升级/扑克": "poker_upgrade",
    "棋类(象棋/军棋)": "board_games",
    "棋牌向桌游": "tabletop_games",
}
BOUNDARY_SOURCE_LABELS = {
    "三国杀": "boundary_sanguosha",
    "炉石": "boundary_hearthstone",
    "云顶之弈/金铲铲": "boundary_autochess",
}


def parse_number(value: Any, default: float = 0.0) -> float:
    try:
        if value is None or value == "":
            return default
        return float(value)
    except (TypeError, ValueError):
        return default


def normalize_date(value: str) -> str:
    value = value.strip()
    for fmt in ("%Y-%m-%d", "%Y/%m/%d"):
        try:
            return datetime.strptime(value, fmt).strftime("%Y-%m-%d")
        except ValueError:
            pass
    raise ValueError(f"Unsupported date: {value!r}")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def stable_alias(user_id: str) -> str:
    return "anchor_" + hashlib.sha256(user_id.encode("utf-8")).hexdigest()[:12]


def read_classification(path: Path) -> dict[str, str]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    result: dict[str, str] = {}
    for source_group, code in QIPAI_SOURCE_LABELS.items():
        for user_id, _nickname in payload.get("QIPAI", {}).get(source_group, []):
            if user_id in result:
                raise ValueError(f"Duplicate content classification: {user_id}")
            result[user_id] = code
    for source_group, code in BOUNDARY_SOURCE_LABELS.items():
        for user_id, _nickname in payload.get("BOUNDARY", {}).get(source_group, []):
            if user_id in result:
                raise ValueError(f"Duplicate content classification: {user_id}")
            result[user_id] = code
    return result


def load_source(path: Path, classification: dict[str, str]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    aliases = {user_id: stable_alias(user_id) for user_id in set(classification)}
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        required = {"dt", "userid", "usernickname", *NUMERIC_FIELDS}
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise ValueError(f"Missing source columns: {sorted(missing)}")
        for raw in reader:
            online_hours = parse_number(raw["onlinetimeduration"])
            if online_hours <= 0:
                continue
            user_id = raw["userid"].strip()
            alias = aliases.get(user_id) or stable_alias(user_id)
            aliases[user_id] = alias
            record: dict[str, Any] = {
                "dt": normalize_date(raw["dt"]),
                "anchor_alias": alias,
                "content_group_code": classification.get(user_id, "non_content_group"),
                "content_group_label_zh": CONTENT_LABELS[
                    classification.get(user_id, "non_content_group")
                ],
            }
            for source_name, output_name in NUMERIC_FIELDS.items():
                record[output_name] = parse_number(raw[source_name])
            rows.append(record)
    if len({(row["dt"], row["anchor_alias"]) for row in rows}) != len(rows):
        raise ValueError("Source is not unique at (dt, anchor_alias)")
    return rows


def aggregate_weeks(rows: Iterable[dict[str, Any]]) -> dict[tuple[str, int], dict[str, float]]:
    result: dict[tuple[str, int], dict[str, float]] = defaultdict(
        lambda: {"dau": 0.0, "days": 0.0, "hours": 0.0, "income": 0.0}
    )
    for row in rows:
        week = 1 if row["dt"] in W1 else 2 if row["dt"] in W2 else 0
        if not week:
            continue
        item = result[(row["anchor_alias"], week)]
        item["dau"] += row["audience_count"]
        item["days"] += 1
        item["hours"] += row["online_hours"]
        item["income"] += row["finder_total_income"]
    return result


def build_anchor_rows(
    rows: list[dict[str, Any]], weekly: dict[tuple[str, int], dict[str, float]]
) -> list[dict[str, Any]]:
    content_by_alias = {row["anchor_alias"]: row["content_group_code"] for row in rows}
    labels_by_alias = {row["anchor_alias"]: row["content_group_label_zh"] for row in rows}
    anchors: list[dict[str, Any]] = []
    for alias in sorted({key[0] for key in weekly}):
        w1 = weekly[(alias, 1)]
        w2 = weekly[(alias, 2)]
        if w1["days"] and w2["days"]:
            group = "persistent"
        elif w2["days"]:
            group = "new_or_returning_w2"
        else:
            group = "absent_w2"
        anchors.append(
            {
                "anchor_alias": alias,
                "activity_group_code": group,
                "activity_group_label_zh": GROUP_LABELS[group],
                "content_group_code": content_by_alias[alias],
                "content_group_label_zh": labels_by_alias[alias],
                "w1_live_days": int(w1["days"]),
                "w2_live_days": int(w2["days"]),
                "w1_week_audience_sum": w1["dau"],
                "w2_week_audience_sum": w2["dau"],
                "week_audience_change": w2["dau"] - w1["dau"],
                "w1_avg_audience_per_live_day": w1["dau"] / w1["days"] if w1["days"] else 0.0,
                "w2_avg_audience_per_live_day": w2["dau"] / w2["days"] if w2["days"] else 0.0,
                "w1_avg_online_hours": w1["hours"] / w1["days"] if w1["days"] else 0.0,
                "w2_avg_online_hours": w2["hours"] / w2["days"] if w2["days"] else 0.0,
                "w1_finder_total_income": w1["income"],
                "w2_finder_total_income": w2["income"],
            }
        )
    anchors.sort(key=lambda item: (-item["week_audience_change"], item["anchor_alias"]))
    return anchors


def sum_metric(items: Iterable[dict[str, Any]], key: str) -> float:
    return math.fsum(float(item[key]) for item in items)


def build_activity_summary(anchors: list[dict[str, Any]], net_week_change: float) -> list[dict[str, Any]]:
    output: list[dict[str, Any]] = []
    for code, label in GROUP_LABELS.items():
        subset = [row for row in anchors if row["activity_group_code"] == code]
        w1 = sum_metric(subset, "w1_week_audience_sum")
        w2 = sum_metric(subset, "w2_week_audience_sum")
        change = w2 - w1
        output.append(
            {
                "activity_group_code": code,
                "activity_group_label_zh": label,
                "anchor_count": len(subset),
                "w1_week_audience_sum": w1,
                "w2_week_audience_sum": w2,
                "week_audience_change": change,
                "daily_audience_change": change / 7,
                "share_of_net_change": change / net_week_change if net_week_change else None,
                "w1_live_days": sum(row["w1_live_days"] for row in subset),
                "w2_live_days": sum(row["w2_live_days"] for row in subset),
            }
        )
    return output


def build_content_summary(
    anchor_day: list[dict[str, Any]], aliases_by_code: dict[str, set[str]]
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    main: list[dict[str, Any]] = []
    subgroups: list[dict[str, Any]] = []
    qipai_codes = set(QIPAI_SOURCE_LABELS.values())
    boundary_codes = set(BOUNDARY_SOURCE_LABELS.values())
    non_qipai_codes = boundary_codes | {"non_content_group"}
    all_codes = ["mahjong", "landlord", "poker_upgrade", "board_games", "tabletop_games"]
    boundary_codes_ordered = [
        "boundary_sanguosha",
        "boundary_hearthstone",
        "boundary_autochess",
    ]
    totals: dict[str, dict[str, float]] = {}
    for group_code, group_label, codes in [
        ("qipai_main", "棋牌类(主口径)", qipai_codes),
        ("non_qipai", "非棋牌类", non_qipai_codes),
        ("all_source", "全部源主播", set(CONTENT_LABELS)),
    ]:
        selected_aliases = set().union(*(aliases_by_code.get(code, set()) for code in codes))
        selected = [row for row in anchor_day if row["anchor_alias"] in selected_aliases]
        w1 = sum(row["audience_count"] for row in selected if row["dt"] in W1)
        w2 = sum(row["audience_count"] for row in selected if row["dt"] in W2)
        totals[group_code] = {"w1": w1, "w2": w2, "anchors": len(selected_aliases)}
    net_day = (totals["all_source"]["w2"] - totals["all_source"]["w1"]) / 7
    for group_code, group_label in (
        ("qipai_main", "棋牌类(主口径)"),
        ("non_qipai", "非棋牌类"),
        ("all_source", "全部源主播"),
    ):
        item = totals[group_code]
        change_day = (item["w2"] - item["w1"]) / 7
        main.append(
            {
                "content_group_code": group_code,
                "content_group_label_zh": group_label,
                "anchor_count": item["anchors"],
                "w1_daily_audience_sum": item["w1"] / 7,
                "w2_daily_audience_sum": item["w2"] / 7,
                "daily_change": change_day,
                "change_rate": (item["w2"] / item["w1"] - 1) if item["w1"] else None,
                "share_of_all_net_change": change_day / net_day if net_day else None,
            }
        )
    qipai_change_day = (totals["qipai_main"]["w2"] - totals["qipai_main"]["w1"]) / 7
    for code in all_codes + boundary_codes_ordered:
        aliases = aliases_by_code.get(code, set())
        selected = [row for row in anchor_day if row["anchor_alias"] in aliases]
        w1 = sum(row["audience_count"] for row in selected if row["dt"] in W1)
        w2 = sum(row["audience_count"] for row in selected if row["dt"] in W2)
        change_day = (w2 - w1) / 7
        subgroups.append(
            {
                "content_group_code": code,
                "content_group_label_zh": CONTENT_LABELS[code],
                "is_main_qipai": code in qipai_codes,
                "anchor_count": len(aliases),
                "w1_daily_audience_sum": w1 / 7,
                "w2_daily_audience_sum": w2 / 7,
                "daily_change": change_day,
                "change_rate": (w2 / w1 - 1) if w1 else None,
                "share_of_qipai_change": change_day / qipai_change_day if code in qipai_codes and qipai_change_day else None,
            }
        )
    return main, subgroups


def three_factor(anchor_day: list[dict[str, Any]], aliases: set[str]) -> dict[str, float]:
    weekly: dict[tuple[str, int], dict[str, float]] = defaultdict(
        lambda: {"days": 0.0, "hours": 0.0, "dau": 0.0}
    )
    for row in anchor_day:
        if row["anchor_alias"] not in aliases:
            continue
        week = 1 if row["dt"] in W1 else 2 if row["dt"] in W2 else 0
        if not week:
            continue
        item = weekly[(row["anchor_alias"], week)]
        item["days"] += 1
        item["hours"] += row["online_hours"]
        item["dau"] += row["audience_count"]
    score = {"volume": 0.0, "duration": 0.0, "productivity": 0.0}
    for alias in aliases:
        first = weekly[(alias, 1)]
        second = weekly[(alias, 2)]
        h1 = first["hours"] / first["days"] if first["days"] else 0.0
        h2 = second["hours"] / second["days"] if second["days"] else 0.0
        p1 = first["dau"] / (first["days"] * h1) if first["days"] and h1 else 0.0
        p2 = second["dau"] / (second["days"] * h2) if second["days"] and h2 else 0.0
        score["volume"] += (second["days"] - first["days"]) * h1 * p1
        score["duration"] += second["days"] * (h2 - h1) * p1
        score["productivity"] += second["days"] * h2 * (p2 - p1)
    score["net"] = score["volume"] + score["duration"] + score["productivity"]
    return score


def write_csv(path: Path, rows: list[dict[str, Any]], fieldnames: list[str]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def add_sheet(wb: Workbook, title: str, headers: list[str], rows: list[list[Any]], widths: list[int]) -> None:
    ws = wb.create_sheet(title)
    ws.append(headers)
    for row in rows:
        ws.append(row)
    for index, width in enumerate(widths, 1):
        ws.column_dimensions[get_column_letter(index)].width = width
    fill = PatternFill("solid", fgColor="DCE6F1")
    for cell in ws[1]:
        cell.font = Font(name="楷体", bold=True, size=11)
        cell.fill = fill
        cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
    for row in ws.iter_rows(min_row=2):
        for cell in row:
            if isinstance(cell.value, (int, float)) and not isinstance(cell.value, bool):
                cell.font = Font(name="Calibri", size=11)
                cell.number_format = "#,##0.00" if isinstance(cell.value, float) else "#,##0"
            elif cell.value is not None:
                cell.font = Font(name="楷体", size=11)
                cell.alignment = Alignment(vertical="top", wrap_text=True)
    ws.freeze_panes = "A2"
    ws.auto_filter.ref = ws.dimensions


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--classification", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parents[1] / "artifacts")
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    classification_hash = sha256_file(args.classification)
    classification = read_classification(args.classification)
    anchor_day = load_source(args.source, classification)
    weekly = aggregate_weeks(anchor_day)
    anchors = build_anchor_rows(anchor_day, weekly)

    w1_sum = math.fsum(anchor["w1_week_audience_sum"] for anchor in anchors)
    w2_sum = math.fsum(anchor["w2_week_audience_sum"] for anchor in anchors)
    w1_days = sum(anchor["w1_live_days"] for anchor in anchors)
    w2_days = sum(anchor["w2_live_days"] for anchor in anchors)
    avg1 = w1_sum / w1_days
    avg2 = w2_sum / w2_days
    scale = (w2_days - w1_days) * avg1
    # Standard three-term decomposition: hold scale at W1 for the efficiency
    # term, then add the scale x efficiency interaction separately.
    efficiency = w1_days * (avg2 - avg1)
    interaction = (w2_days - w1_days) * (avg2 - avg1)
    net_week_change = w2_sum - w1_sum
    activity = build_activity_summary(anchors, net_week_change)

    aliases_by_code: dict[str, set[str]] = defaultdict(set)
    for row in anchor_day:
        aliases_by_code[row["content_group_code"]].add(row["anchor_alias"])
    content_main, content_subgroups = build_content_summary(anchor_day, aliases_by_code)
    qipai_aliases = set().union(
        *(aliases_by_code[code] for code in QIPAI_SOURCE_LABELS.values())
    )
    boundary_aliases = set().union(
        *(aliases_by_code[code] for code in BOUNDARY_SOURCE_LABELS.values())
    )
    all_aliases = {row["anchor_alias"] for row in anchor_day}
    non_qipai_aliases = all_aliases - qipai_aliases
    decomposition_rows: list[dict[str, Any]] = []
    for code, label, aliases in (
        ("all_source", "全部源主播", all_aliases),
        ("qipai_main", "棋牌类(主口径)", qipai_aliases),
        ("non_qipai", "非棋牌类", non_qipai_aliases),
        ("boundary", "边界项", boundary_aliases),
    ):
        score = three_factor(anchor_day, aliases)
        decomposition_rows.append(
            {
                "scope_code": code,
                "scope_label_zh": label,
                "weekly_volume_effect": score["volume"],
                "weekly_duration_effect": score["duration"],
                "weekly_productivity_effect": score["productivity"],
                "weekly_net_change": score["net"],
                "daily_volume_effect": score["volume"] / 7,
                "daily_duration_effect": score["duration"] / 7,
                "daily_productivity_effect": score["productivity"] / 7,
                "daily_net_change": score["net"] / 7,
            }
        )

    daily: list[dict[str, Any]] = []
    by_day: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in anchor_day:
        by_day[row["dt"]].append(row)
    for date in sorted(by_day):
        subset = by_day[date]
        audience = math.fsum(row["audience_count"] for row in subset)
        hours = math.fsum(row["online_hours"] for row in subset)
        daily.append(
            {
                "dt": date,
                "week_marker": "W1" if date in W1 else "W2" if date in W2 else "BASE_OR_OTHER",
                "active_anchor_count": len(subset),
                "audience_count_sum": audience,
                "avg_audience_per_anchor": audience / len(subset),
                "online_hours_sum": hours,
                "avg_online_hours_per_anchor": hours / len(subset),
                "finder_total_income": math.fsum(row["finder_total_income"] for row in subset),
            }
        )

    top_positive = anchors[:20]
    top_negative = list(reversed(anchors[-20:]))
    contribution_rows = [dict(row, direction="positive", rank=i) for i, row in enumerate(top_positive, 1)]
    contribution_rows += [dict(row, direction="negative", rank=i) for i, row in enumerate(top_negative, 1)]
    top3_aliases = {row["anchor_alias"] for row in top_positive[:3]}
    top3_w1 = math.fsum(row["w1_week_audience_sum"] for row in anchors if row["anchor_alias"] not in top3_aliases)
    top3_w2 = math.fsum(row["w2_week_audience_sum"] for row in anchors if row["anchor_alias"] not in top3_aliases)
    sensitivity = [
        {"scenario": "all_anchors", "removed_alias_count": 0, "w1_daily": w1_sum / 7, "w2_daily": w2_sum / 7, "daily_change": net_week_change / 7, "change_rate": w2_sum / w1_sum - 1},
        {"scenario": "exclude_top3_positive_contributors", "removed_alias_count": 3, "w1_daily": top3_w1 / 7, "w2_daily": top3_w2 / 7, "daily_change": (top3_w2 - top3_w1) / 7, "change_rate": top3_w2 / top3_w1 - 1},
    ]
    persistent = [
        row
        for row in anchors
        if row["w1_live_days"] >= 3 and row["w2_live_days"] >= 3
    ]
    persistent_changes = [
        row["w2_avg_audience_per_live_day"] / row["w1_avg_audience_per_live_day"] - 1
        for row in persistent
        if row["w1_avg_audience_per_live_day"]
    ]
    positive_week_change = math.fsum(max(row["week_audience_change"], 0.0) for row in anchors)
    negative_week_change = math.fsum(min(row["week_audience_change"], 0.0) for row in anchors)

    overall = [
        {"metric": "w1_daily_audience_sum", "value": w1_sum / 7, "unit": "audience_count sum / calendar day"},
        {"metric": "w2_daily_audience_sum", "value": w2_sum / 7, "unit": "audience_count sum / calendar day"},
        {"metric": "daily_audience_change", "value": net_week_change / 7, "unit": "audience_count sum / calendar day"},
        {"metric": "change_rate", "value": w2_sum / w1_sum - 1, "unit": "ratio"},
        {"metric": "w1_anchor_live_days", "value": w1_days, "unit": "anchor-day"},
        {"metric": "w2_anchor_live_days", "value": w2_days, "unit": "anchor-day"},
        {"metric": "avg_audience_per_anchor_live_day_w1", "value": avg1, "unit": "audience_count / anchor-day"},
        {"metric": "avg_audience_per_anchor_live_day_w2", "value": avg2, "unit": "audience_count / anchor-day"},
        {"metric": "two_factor_scale_daily", "value": scale / 7, "unit": "audience_count sum / calendar day"},
        {"metric": "two_factor_efficiency_daily", "value": efficiency / 7, "unit": "audience_count sum / calendar day"},
        {"metric": "two_factor_interaction_daily", "value": interaction / 7, "unit": "audience_count sum / calendar day"},
        {"metric": "positive_week_contribution", "value": positive_week_change, "unit": "week audience_count sum"},
        {"metric": "negative_week_contribution", "value": negative_week_change, "unit": "week audience_count sum"},
        {"metric": "persistent_anchor_count_ge3_days_each_week", "value": len(persistent), "unit": "anchor"},
        {"metric": "persistent_anchor_change_rate_median", "value": sorted(persistent_changes)[len(persistent_changes)//2], "unit": "ratio"},
    ]

    anchor_fields = list(anchors[0])
    content_main_fields = list(content_main[0])
    content_sub_fields = list(content_subgroups[0])
    decomposition_fields = list(decomposition_rows[0])
    activity_fields = list(activity[0])
    daily_fields = list(daily[0])
    contribution_fields = list(contribution_rows[0])
    sensitivity_fields = list(sensitivity[0])
    overall_fields = list(overall[0])

    write_csv(args.output_dir / "overall-summary.csv", overall, overall_fields)
    write_csv(args.output_dir / "daily-summary.csv", daily, daily_fields)
    write_csv(args.output_dir / "anchor-two-week-anonymous.csv", anchors, anchor_fields)
    write_csv(args.output_dir / "activity-group-summary.csv", activity, activity_fields)
    write_csv(args.output_dir / "content-group-summary.csv", content_main, content_main_fields)
    write_csv(args.output_dir / "content-subgroup-summary.csv", content_subgroups, content_sub_fields)
    write_csv(args.output_dir / "decomposition-summary.csv", decomposition_rows, decomposition_fields)
    write_csv(args.output_dir / "contribution-top20-anonymous.csv", contribution_rows, contribution_fields)
    write_csv(args.output_dir / "sensitivity-summary.csv", sensitivity, sensitivity_fields)

    anchor_day_fields = [
        "dt",
        "anchor_alias",
        "content_group_code",
        "content_group_label_zh",
        *NUMERIC_FIELDS.values(),
    ]
    write_csv(args.output_dir / "anchor-day-anonymous.csv", anchor_day, anchor_day_fields)

    source_manifest = [
        {
            "source_local_path": str(args.source),
            "source_file_name": args.source.name,
            "source_bytes": args.source.stat().st_size,
            "source_sha256": sha256_file(args.source),
            "classification_source_sha256": classification_hash,
            "raw_rows": sum(1 for _ in args.source.open("r", encoding="utf-8-sig")) - 1,
            "live_rows": len(anchor_day),
            "unique_date_count": len({row["dt"] for row in anchor_day}),
            "date_min": min(row["dt"] for row in anchor_day),
            "date_max": max(row["dt"] for row in anchor_day),
            "unique_anchor_count_all_dates": len(all_aliases),
            "unique_anchor_count_in_w1_or_w2": len(anchors),
            "unique_dt_anchor_rows": len({(row["dt"], row["anchor_alias"]) for row in anchor_day}),
            "privacy_transform": "Removed userid/usernickname/reportid/starttime/endtime; replaced userid with a SHA-256-based alias.",
        }
    ]
    write_csv(args.output_dir / "source-manifest.csv", source_manifest, list(source_manifest[0]))

    wb = Workbook()
    wb.remove(wb.active)
    summary_rows = [
        ["W1 daily audience sum", round(w1_sum / 7), round(avg1), w1_days],
        ["W2 daily audience sum", round(w2_sum / 7), round(avg2), w2_days],
        ["Daily change", round(net_week_change / 7), f"{(w2_sum / w1_sum - 1) * 100:+.1f}%", ""],
        ["Scale effect", round(scale / 7), "two-factor decomposition", ""],
        ["Efficiency effect", round(efficiency / 7), "two-factor decomposition", ""],
        ["Interaction", round(interaction / 7), "two-factor decomposition", ""],
        ["Top1 positive contribution / net change", f"{anchors[0]['week_audience_change'] / net_week_change * 100:.0f}%", anchors[0]["anchor_alias"], ""],
        ["Excluding top3 positive contributors", round((top3_w2 - top3_w1) / 7), f"{top3_w2 / top3_w1 * 100 - 100:+.1f}%", ""],
    ]
    add_sheet(wb, "summary", ["Metric", "W2 / change", "Detail", "Anchor-days"], summary_rows, [38, 22, 28, 14])
    add_sheet(wb, "daily", list(daily[0]), [[row[field] for field in daily_fields] for row in daily], [12, 14, 12, 18, 18, 16, 20, 18])
    add_sheet(
        wb,
        "anchor-two-week",
        anchor_fields,
        [[row[field] for field in anchor_fields] for row in anchors],
        [20, 20, 20, 12, 12, 18, 18, 18, 18, 18, 18, 18, 18, 18],
    )
    add_sheet(wb, "activity-groups", activity_fields, [[row[field] for field in activity_fields] for row in activity], [20, 20, 10, 18, 18, 18, 16, 14, 12, 12])
    add_sheet(wb, "content-groups", content_main_fields, [[row[field] for field in content_main_fields] for row in content_main], [20, 20, 12, 18, 18, 16, 12, 18])
    add_sheet(wb, "content-subgroups", content_sub_fields, [[row[field] for field in content_sub_fields] for row in content_subgroups], [20, 20, 12, 12, 18, 18, 16, 12, 18])
    add_sheet(wb, "three-factor", decomposition_fields, [[row[field] for field in decomposition_fields] for row in decomposition_rows], [16, 18, 18, 18, 20, 18, 18, 18, 20, 18])
    add_sheet(wb, "contrib-top20", contribution_fields, [[row[field] for field in contribution_fields] for row in contribution_rows], [12, 8, 20, 20, 20, 12, 12, 18, 18, 18, 18, 18, 18, 18, 18, 18])
    definition_rows = [
        ["Question", "Why did the two-week audience-count sum increase from 2026-09-14–20 to 2026-09-21–27?"],
        ["Input grain", "Anchor x day; unique on (dt, anchor_alias)."],
        ["Metric", "audiencecnt summed across anchors and calendar days; this is not deduplicated platform DAU."],
        ["W1", f"{W1_START} through {W1_END}."],
        ["W2", f"{W2_START} through {W2_END}."],
        ["Date handling", "Both YYYY-MM-DD and YYYY/M/D source formats are normalized before filtering."],
        ["Anonymization", "Streamer nickname, platform ID, report ID, and timestamps were removed; aliases are SHA-256 prefixes."],
        ["Content classification", "The original project assigned specified source IDs to qipai and boundary groups. This repository stores only the resulting category label on anonymous aliases."],
        ["Causality", "No user-level exposure, recommendation, campaign, or platform-change evidence is available; results are descriptive and compositional."],
        ["Known source-output drift", "A derived text file records 10 anchors in W2未开播, but current source and the final workbook both contain 7. The stale text file was not migrated."],
    ]
    add_sheet(wb, "definitions", ["Item", "Description"], definition_rows, [24, 120])
    workbook_path = args.output_dir / "wechat-channel-dau-two-week-anonymous-20260929.xlsx"
    wb.save(workbook_path)

    print(json.dumps({
        "workbook": str(workbook_path),
        "w1_daily": w1_sum / 7,
        "w2_daily": w2_sum / 7,
        "daily_change": net_week_change / 7,
        "change_rate": w2_sum / w1_sum - 1,
        "anchor_count_in_windows": len(anchors),
        "anchor_count_all_source": len(all_aliases),
        "activity_groups": {row["activity_group_code"]: row["anchor_count"] for row in activity},
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
