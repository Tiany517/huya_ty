#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Independently validate the committed WeChat Channel DAU artifacts."""

from __future__ import annotations

import argparse
import csv
import json
import math
from collections import Counter, defaultdict
from pathlib import Path

from openpyxl import load_workbook


EXPECTED_SOURCE_SHA256 = "17d4e89ad0413fd705b93f63dc37b5aed4e8d0e579055fd44ef9bd2f87e3e261"


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def metric(rows: list[dict[str, str]], name: str) -> float:
    return float(next(row["value"] for row in rows if row["metric"] == name))


def close(left: float, right: float, tolerance: float = 1e-4) -> bool:
    return math.isclose(left, right, rel_tol=0.0, abs_tol=tolerance)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifacts", type=Path, default=Path(__file__).resolve().parents[1] / "artifacts")
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "validation" / "validation-summary.json")
    args = parser.parse_args()
    checks: list[dict[str, object]] = []

    def check(check_id: str, passed: bool, evidence: object) -> None:
        checks.append({"id": check_id, "status": "pass" if passed else "fail", "evidence": evidence})

    manifest = read_csv(args.artifacts / "source-manifest.csv")
    check("source_manifest_single_row", len(manifest) == 1, {"rows": len(manifest)})
    source = manifest[0]
    check("source_hash_matches_verified_snapshot", source["source_sha256"] == EXPECTED_SOURCE_SHA256, source["source_sha256"])
    check("source_live_row_count", int(source["live_rows"]) == 2067, int(source["live_rows"]))
    check("source_date_coverage", source["date_min"] == "2026-09-01" and source["date_max"] == "2026-09-28" and int(source["unique_date_count"]) == 28, {k: source[k] for k in ("date_min", "date_max", "unique_date_count")})

    anchor_day = read_csv(args.artifacts / "anchor-day-anonymous.csv")
    fieldnames = set(anchor_day[0]) if anchor_day else set()
    forbidden_fields = {"userid", "usernickname", "reportid", "starttime", "endtime"}
    check("anonymous_source_has_no_identity_columns", not (fieldnames & forbidden_fields), sorted(fieldnames & forbidden_fields))
    keys = Counter((row["dt"], row["anchor_alias"]) for row in anchor_day)
    check("anonymous_source_unique_dt_anchor", len(anchor_day) == 2067 and max(keys.values()) == 1, {"rows": len(anchor_day), "max_key_count": max(keys.values())})
    check("anonymous_alias_count", len({row["anchor_alias"] for row in anchor_day}) == 110, len({row["anchor_alias"] for row in anchor_day}))
    check("anonymous_source_unique_date_count", len({row["dt"] for row in anchor_day}) == 28, len({row["dt"] for row in anchor_day}))
    direct_w1 = sum(float(row["audience_count"]) for row in anchor_day if "2026-09-14" <= row["dt"] <= "2026-09-20")
    direct_w2 = sum(float(row["audience_count"]) for row in anchor_day if "2026-09-21" <= row["dt"] <= "2026-09-27")
    direct_w1_days = sum(1 for row in anchor_day if "2026-09-14" <= row["dt"] <= "2026-09-20")
    direct_w2_days = sum(1 for row in anchor_day if "2026-09-21" <= row["dt"] <= "2026-09-27")
    check(
        "anchor_day_headline_recompute",
        close(direct_w1 / 7, 6760166.0, 0.01)
        and close(direct_w2 / 7, 7163321.428571428, 0.01)
        and direct_w1_days == 534
        and direct_w2_days == 510,
        {"w1_daily": direct_w1 / 7, "w2_daily": direct_w2 / 7, "w1_days": direct_w1_days, "w2_days": direct_w2_days},
    )
    check("all_values_finite", all(math.isfinite(float(row["audience_count"])) and math.isfinite(float(row["online_hours"])) for row in anchor_day), "audience_count and online_hours are finite")

    overall = read_csv(args.artifacts / "overall-summary.csv")
    w1_daily = metric(overall, "w1_daily_audience_sum")
    w2_daily = metric(overall, "w2_daily_audience_sum")
    daily_change = metric(overall, "daily_audience_change")
    scale = metric(overall, "two_factor_scale_daily")
    efficiency = metric(overall, "two_factor_efficiency_daily")
    interaction = metric(overall, "two_factor_interaction_daily")
    check("headline_w1", close(w1_daily, 6760166.0, 0.01), w1_daily)
    check("headline_w2", close(w2_daily, 7163321.428571428, 0.01), w2_daily)
    check("headline_change", close(daily_change, 403155.4285714286, 0.01), daily_change)
    check("two_factor_closure", close(scale + efficiency + interaction, daily_change, 0.01), {"components": [scale, efficiency, interaction], "sum": scale + efficiency + interaction, "reported": daily_change})

    activity = read_csv(args.artifacts / "activity-group-summary.csv")
    activity_map = {row["activity_group_code"]: row for row in activity}
    check("activity_anchor_count", sum(int(row["anchor_count"]) for row in activity) == 107, sum(int(row["anchor_count"]) for row in activity))
    check("activity_counts_final", {key: int(value["anchor_count"]) for key, value in activity_map.items()} == {"persistent": 97, "new_or_returning_w2": 3, "absent_w2": 7}, {key: int(value["anchor_count"]) for key, value in activity_map.items()})
    days_by_alias_week: dict[tuple[str, int], int] = defaultdict(int)
    for row in anchor_day:
        if "2026-09-14" <= row["dt"] <= "2026-09-20":
            days_by_alias_week[(row["anchor_alias"], 1)] += 1
        elif "2026-09-21" <= row["dt"] <= "2026-09-27":
            days_by_alias_week[(row["anchor_alias"], 2)] += 1
    aliases_in_windows = sorted({alias for alias, _week in days_by_alias_week})
    direct_groups = Counter()
    for alias in aliases_in_windows:
        w1_days = days_by_alias_week[(alias, 1)]
        w2_days = days_by_alias_week[(alias, 2)]
        direct_groups["persistent" if w1_days and w2_days else "new_or_returning_w2" if w2_days else "absent_w2"] += 1
    check("anchor_day_activity_recompute", dict(direct_groups) == {key: int(value["anchor_count"]) for key, value in activity_map.items()}, dict(direct_groups))
    check("activity_w1_closure", close(sum(float(row["w1_week_audience_sum"]) for row in activity), w1_daily * 7, 0.01), sum(float(row["w1_week_audience_sum"]) for row in activity))
    check("activity_w2_closure", close(sum(float(row["w2_week_audience_sum"]) for row in activity), w2_daily * 7, 0.01), sum(float(row["w2_week_audience_sum"]) for row in activity))

    content = read_csv(args.artifacts / "content-group-summary.csv")
    content_map = {row["content_group_code"]: row for row in content}
    check("content_anchor_closure", int(content_map["qipai_main"]["anchor_count"]) + int(content_map["non_qipai"]["anchor_count"]) == 110 and int(content_map["all_source"]["anchor_count"]) == 110, {key: int(value["anchor_count"]) for key, value in content_map.items()})
    check("content_daily_change_closure", close(float(content_map["qipai_main"]["daily_change"]) + float(content_map["non_qipai"]["daily_change"]), daily_change, 0.01), float(content_map["qipai_main"]["daily_change"]) + float(content_map["non_qipai"]["daily_change"]))
    check("content_w1_closure", close(float(content_map["qipai_main"]["w1_daily_audience_sum"]) + float(content_map["non_qipai"]["w1_daily_audience_sum"]), w1_daily, 0.01), w1_daily)
    check("content_w2_closure", close(float(content_map["qipai_main"]["w2_daily_audience_sum"]) + float(content_map["non_qipai"]["w2_daily_audience_sum"]), w2_daily, 0.01), w2_daily)

    subgroups = read_csv(args.artifacts / "content-subgroup-summary.csv")
    qipai_subgroups = [row for row in subgroups if row["is_main_qipai"] == "True"]
    qipai_sub_change = sum(float(row["daily_change"]) for row in qipai_subgroups)
    check("qipai_subgroup_closure", close(qipai_sub_change, float(content_map["qipai_main"]["daily_change"]), 0.01), {"subgroup_sum": qipai_sub_change, "reported": float(content_map["qipai_main"]["daily_change"])})
    qipai_codes = {"mahjong", "landlord", "poker_upgrade", "board_games", "tabletop_games"}
    qipai_rows = [row for row in anchor_day if row["content_group_code"] in qipai_codes]
    direct_qipai_w1 = sum(float(row["audience_count"]) for row in qipai_rows if "2026-09-14" <= row["dt"] <= "2026-09-20")
    direct_qipai_w2 = sum(float(row["audience_count"]) for row in qipai_rows if "2026-09-21" <= row["dt"] <= "2026-09-27")
    check(
        "anchor_day_content_recompute",
        close((direct_qipai_w2 - direct_qipai_w1) / 7, float(content_map["qipai_main"]["daily_change"]), 0.01),
        {"qipai_daily_change": (direct_qipai_w2 - direct_qipai_w1) / 7},
    )

    decomposition = read_csv(args.artifacts / "decomposition-summary.csv")
    decomposition_map = {row["scope_code"]: row for row in decomposition}
    for scope in ("all_source", "qipai_main", "non_qipai"):
        row = decomposition_map[scope]
        total = sum(float(row[field]) for field in ("weekly_volume_effect", "weekly_duration_effect", "weekly_productivity_effect"))
        check(f"three_factor_closure_{scope}", close(total, float(row["weekly_net_change"]), 0.01), {"components_sum": total, "reported": float(row["weekly_net_change"])})
    check("decomposition_all_matches_headline", close(float(decomposition_map["all_source"]["daily_net_change"]), daily_change, 0.01), float(decomposition_map["all_source"]["daily_net_change"]))
    check("decomposition_qipai_matches_content", close(float(decomposition_map["qipai_main"]["daily_net_change"]), float(content_map["qipai_main"]["daily_change"]), 0.01), float(decomposition_map["qipai_main"]["daily_net_change"]))
    check("decomposition_non_qipai_matches_content", close(float(decomposition_map["non_qipai"]["daily_net_change"]), float(content_map["non_qipai"]["daily_change"]), 0.01), float(decomposition_map["non_qipai"]["daily_net_change"]))

    sensitivity = read_csv(args.artifacts / "sensitivity-summary.csv")
    sensitivity_map = {row["scenario"]: row for row in sensitivity}
    excluded_top3 = sensitivity_map["exclude_top3_positive_contributors"]
    check("top3_sensitivity", close(float(excluded_top3["change_rate"]), -0.21184747930971115, 1e-9), excluded_top3["change_rate"])
    persistent_count = metric(overall, "persistent_anchor_count_ge3_days_each_week")
    persistent_median = metric(overall, "persistent_anchor_change_rate_median")
    check("persistent_sample", int(persistent_count) == 83, persistent_count)
    check("persistent_median", close(persistent_median, 0.0013966928881039564, 1e-12), persistent_median)

    workbook_path = args.artifacts / "wechat-channel-dau-two-week-anonymous-20260929.xlsx"
    wb = load_workbook(workbook_path, read_only=True, data_only=True)
    expected_sheets = {"summary", "daily", "anchor-two-week", "activity-groups", "content-groups", "content-subgroups", "three-factor", "contrib-top20", "definitions"}
    check("workbook_sheets", set(wb.sheetnames) == expected_sheets, wb.sheetnames)
    check("workbook_daily_rows", wb["daily"].max_row == 29, wb["daily"].max_row)
    check("workbook_anchor_rows", wb["anchor-two-week"].max_row == 108, wb["anchor-two-week"].max_row)
    summary_rows = {row[0]: row for row in wb["summary"].iter_rows(min_row=2, values_only=True)}
    check(
        "workbook_summary_matches_csv",
        summary_rows["W1 daily audience sum"][1] == round(w1_daily)
        and summary_rows["W2 daily audience sum"][1] == round(w2_daily)
        and summary_rows["Daily change"][1] == round(daily_change),
        {
            "w1": summary_rows["W1 daily audience sum"][1],
            "w2": summary_rows["W2 daily audience sum"][1],
            "daily_change": summary_rows["Daily change"][1],
        },
    )
    workbook_content = {row[0]: row for row in wb["content-groups"].iter_rows(min_row=2, values_only=True)}
    check(
        "workbook_content_matches_csv",
        close(float(workbook_content["qipai_main"][5]), float(content_map["qipai_main"]["daily_change"]), 0.01)
        and float(workbook_content["non_qipai"][5]) < 0,
        {"qipai_change": workbook_content["qipai_main"][5], "non_qipai_change": workbook_content["non_qipai"][5]},
    )
    workbook_activity = {row[0]: row for row in wb["activity-groups"].iter_rows(min_row=2, values_only=True)}
    check(
        "workbook_activity_matches_csv",
        workbook_activity["absent_w2"][2] == 7 and workbook_activity["persistent"][2] == 97,
        {"persistent": workbook_activity["persistent"][2], "absent_w2": workbook_activity["absent_w2"][2]},
    )
    wb.close()

    failures = [row for row in checks if row["status"] == "fail"]
    result = {
        "status": "pass_with_known_issues" if not failures else "fail",
        "checked_at_local_timezone": "Asia/Shanghai",
        "check_count": len(checks),
        "passed": len(checks) - len(failures),
        "failed": len(failures),
        "known_issues": [
            {
                "id": "stale_derived_text_and_old_script_date_filter",
                "detail": "The historical text result says ten W2-absent anchors, while the current source and final workbook have seven. The historical scripts also compare ISO dates and fail against the current slash-formatted source unless dates are normalized.",
                "handling": "The stale text result was excluded. The migrated build normalizes both date formats and independently reproduces seven W2-absent anchors.",
            },
            {
                "id": "summed_audience_not_platform_unique_dau",
                "detail": "audiencecnt is summed across anchors, so the same viewer can be counted in more than one room.",
                "handling": "Artifacts and documentation call this an audience-count sum, not unique cross-anchor DAU.",
            },
            {
                "id": "manual_content_classification",
                "detail": "The qipai and boundary groups came from an explicit source-project streamer classification, not a platform content taxonomy.",
                "handling": "Only the anonymous category assignment is committed; classification results are treated as a scenario, not an official taxonomy.",
            },
            {
                "id": "legacy_two_factor_components_do_not_close",
                "detail": "The historical workbook printed scale -303,828, efficiency 706,983, and interaction -33,270 per day, but those three values sum to 369,885 rather than the reported 403,155 change.",
                "handling": "The migrated calculation uses efficiency at fixed W1 anchor-days, so scale, efficiency, and interaction sum exactly to the reported change.",
            },
        ],
        "checks": checks,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: result[key] for key in ("status", "check_count", "passed", "failed")}, ensure_ascii=False, indent=2))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
