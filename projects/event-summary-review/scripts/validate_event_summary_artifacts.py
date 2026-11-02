from __future__ import annotations

import csv
import hashlib
import json
import math
import re
from collections import defaultdict
from pathlib import Path
from typing import Any

from openpyxl import load_workbook


PROJECT_DIR = Path(__file__).resolve().parents[1]
DATE_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as source:
        return list(csv.DictReader(source))


def as_float(value: Any) -> float | None:
    if value in {None, ""}:
        return None
    return float(value)


def as_iso_date(value: Any) -> str | None:
    text = value.strftime("%Y-%m-%d") if hasattr(value, "strftime") else str(value).strip()
    return text if DATE_PATTERN.fullmatch(text) else None


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(source_dir: Path) -> None:
    artifacts = PROJECT_DIR / "artifacts"
    checks: list[dict[str, Any]] = []

    def add(check_id: str, category: str, condition: bool, expected: Any, actual: Any, note: str) -> None:
        checks.append(
            {
                "check_id": check_id,
                "category": category,
                "status": "PASS" if condition else "FAIL",
                "expected": expected,
                "actual": actual,
                "note": note,
            }
        )

    zh_files = {
        "event_dau": artifacts / "zh" / "赛事DAU汇总.csv",
        "comparison": artifacts / "zh" / "赛事DAU对比.csv",
        "share": artifacts / "zh" / "平台份额汇总.csv",
        "duplicate": artifacts / "zh" / "重复审计.csv",
        "quality": artifacts / "zh" / "质量问题.csv",
        "manifest": artifacts / "zh" / "来源清单.csv",
    }
    en_files = {
        "event_dau": artifacts / "en" / "event-dau-summary.csv",
        "comparison": artifacts / "en" / "event-dau-comparisons.csv",
        "share": artifacts / "en" / "platform-share-summary.csv",
        "duplicate": artifacts / "en" / "duplication-audit.csv",
        "quality": artifacts / "en" / "quality-findings.csv",
        "manifest": artifacts / "en" / "source-manifest.csv",
    }
    add("EVENT-V01", "files", all(path.is_file() for path in [*zh_files.values(), *en_files.values()]), 12, sum(path.is_file() for path in [*zh_files.values(), *en_files.values()]), "All bilingual CSV artifacts exist")

    zh_data = {name: read_csv(path) for name, path in zh_files.items()}
    en_data = {name: read_csv(path) for name, path in en_files.items()}
    add("EVENT-V02", "bilingual", all(len(zh_data[name]) == len(en_data[name]) for name in zh_data), "equal row counts", {name: [len(zh_data[name]), len(en_data[name])] for name in zh_data}, "Chinese and English data editions have matching row counts")

    event_rows = en_data["event_dau"]
    event_names = {row["event_name"] for row in event_rows}
    required_events = {
        "2026LPL第一赛段",
        "2026LPL第二赛段",
        "2026LPL第三赛段",
        "2026KPL春季赛",
        "2026KPL夏季赛",
        "FISSURE裂变天地3苏州",
        "FISSURE裂变天地S1",
        "FISSURE裂变天地S2",
        "2026BLAST赏金赛S2",
        "BLAST波尔图公开赛2026",
    }
    add("EVENT-V03", "coverage", len(event_rows) == 16, 16, len(event_rows), "All date-valid event groups are represented")
    add("EVENT-V04", "coverage", required_events <= event_names, sorted(required_events), sorted(required_events & event_names), "Required LPL, KPL, FISSURE, and BLAST events are present")
    add("EVENT-V05", "grain", all(int(row["duplicate_event_date_rows"]) == 0 for row in event_rows), 0, max(int(row["duplicate_event_date_rows"]) for row in event_rows), "No duplicate event/date rows in DAU source rows")
    add("EVENT-V06", "metric", all(as_float(row["dau"]) is not None and as_float(row["dau"]) > 0 for row in event_rows), "> 0", min(as_float(row["dau"]) for row in event_rows), "Every event has a positive DAU average")

    summary_workbook = load_workbook(source_dir / "0914_赛事总结_汇总.xlsx", data_only=True, read_only=True)
    summary_sheet = summary_workbook["Sheet1"]
    event_lookup = {row["event_name"]: row for row in event_rows}

    def workbook_value(sheet, cell: str) -> float:
        return float(sheet[cell].value)

    dau_cells = {
        "2026LPL第一赛段": "C8",
        "2026LPL第二赛段": "C9",
        "2026LPL第三赛段": "C10",
        "2026KPL春季赛": "J9",
        "2026KPL夏季赛": "J10",
        "BLAST波尔图公开赛2026": "T9",
    }
    dau_differences = {
        name: abs(float(event_lookup[name]["dau"]) - workbook_value(summary_sheet, cell))
        for name, cell in dau_cells.items()
    }
    add("EVENT-V07", "reconciliation", all(value <= 1e-6 for value in dau_differences.values()), "all <= 1e-6", dau_differences, "Aggregated event DAU independently matches the consolidated workbook")

    comparison_lookup = {(row["comparison_id"], row["metric"]): row for row in en_data["comparison"]}
    comparison_cells = {
        "lpl_q1_yoy": "C17",
        "lpl_q2_yoy": "C18",
        "lpl_q3_yoy": "C19",
        "lpl_q2_q1": "C26",
        "lpl_q3_q2": "C27",
        "kpl_spring_yoy": "J17",
        "kpl_summer_yoy": "J18",
        "kpl_summer_spring": "J19",
        "blast_porto_yoy": "T17",
    }
    comparison_differences = {
        comparison_id: abs(float(comparison_lookup[(comparison_id, "dau")]["percent_change"]) - workbook_value(summary_sheet, cell))
        for comparison_id, cell in comparison_cells.items()
    }
    summary_workbook.close()
    add("EVENT-V08", "reconciliation", all(value <= 1e-8 for value in comparison_differences.values()), "all <= 1e-8", comparison_differences, "DAU YoY and phase comparisons match the consolidated workbook")

    share_rows = en_data["share"]
    totals = [row for row in share_rows if row["platform"] == "TOTAL"]
    share_sum_differences = {}
    for row in totals:
        key = (row["event_name"], row["figure_type"])
        platform_sum = sum(float(item["platform_share"]) for item in share_rows if (item["event_name"], item["figure_type"]) == key and item["platform"] != "TOTAL")
        share_sum_differences[str(key)] = abs(platform_sum - 1.0)
    add("EVENT-V09", "metric", all(value <= 1e-9 for value in share_sum_differences.values()), "all <= 1e-9", share_sum_differences, "Each event/figure-type platform share set closes to 100%")

    published_lpl_first = next(row for row in share_rows if row["event_name"] == "2026LPL第一赛段" and row["figure_type"] == "published_rows" and row["platform"] == "huya")
    corrected_lpl_first = next(row for row in share_rows if row["event_name"] == "2026LPL第一赛段" and row["figure_type"] == "deduplicated" and row["platform"] == "huya")
    add("EVENT-V10", "correction", abs(float(published_lpl_first["platform_share_pct"]) - 54.59620842474645) <= 1e-6, 54.59620842474645, float(published_lpl_first["platform_share_pct"]), "Published LPL first-segment Huya share is retained as source evidence")
    add("EVENT-V11", "correction", abs(float(corrected_lpl_first["platform_share_pct"]) - 54.30902191696139) <= 1e-6, 54.30902191696139, float(corrected_lpl_first["platform_share_pct"]), "Deduplicated LPL first-segment Huya share is available as the corrected view")

    kpl_published = next(row for row in share_rows if row["event_name"] == "2026KPL夏季赛" and row["figure_type"] == "published_rows" and row["platform"] == "TOTAL")
    kpl_corrected = next(row for row in share_rows if row["event_name"] == "2026KPL夏季赛" and row["figure_type"] == "deduplicated" and row["platform"] == "TOTAL")
    add("EVENT-V12", "correction", abs(float(kpl_published["streamer_acu_sum"]) - 4_202_229.3382343585) <= 1e-6, 4_202_229.3382343585, float(kpl_published["streamer_acu_sum"]), "Published KPL summer total is retained as source evidence")
    add("EVENT-V13", "correction", abs(float(kpl_corrected["streamer_acu_sum"]) - 4_122_499.5718171434) <= 1e-6, 4_122_499.5718171434, float(kpl_corrected["streamer_acu_sum"]), "Deduplicated KPL summer total is available as the corrected view")

    duplicate_lookup = {row["source_group"]: row for row in en_data["duplicate"]}
    duplicate_expectations = {"LPL": (2, 2), "KPL": (16, 16), "BLAST": (2, 2)}
    duplicate_actual = {
        group: (int(duplicate_lookup[group]["duplicate_groups"]), int(duplicate_lookup[group]["exact_duplicate_groups"]))
        for group in duplicate_expectations
    }
    add("EVENT-V14", "duplication", duplicate_actual == duplicate_expectations, duplicate_expectations, duplicate_actual, "Duplicate counts are exact and fully documented")
    add("EVENT-V15", "duplication", all(int(row["differing_metric_groups"]) == 0 for row in duplicate_lookup.values()), 0, {key: row["differing_metric_groups"] for key, row in duplicate_lookup.items()}, "Every duplicate key is an exact duplicate, not a conflicting metric")

    main_workbook = load_workbook(source_dir / "0914_赛事总结.xlsx", data_only=True, read_only=True)
    kpl_summary = main_workbook["KPL_赛事份额_汇总"]
    formula_errors = {
        cell: kpl_summary[cell].value
        for cell in ["I242", "J242"]
        if isinstance(kpl_summary[cell].value, str) and kpl_summary[cell].value.startswith("#")
    }
    add("EVENT-V16", "source-quality", formula_errors == {"I242": "#DIV/0!", "J242": "#DIV/0!"}, {"I242": "#DIV/0!", "J242": "#DIV/0!"}, formula_errors, "Known spreadsheet errors are located only in the documented secondary streamer block")

    share_workbook = main_workbook
    independent_share: dict[tuple[str, str, str], float] = defaultdict(float)
    duplicate_acu: dict[str, float] = defaultdict(float)
    key_specs = [
        ("LPL", "LPL份额数据源"),
        ("KPL", "KPL_赛事份额_by主播"),
        ("BLAST", "BLAST波尔图份额数据"),
    ]
    independent_counts = {}
    for group, sheet_name in key_specs:
        rows = share_workbook[sheet_name].iter_rows(values_only=True)
        headers = list(next(rows))
        index = {value: position for position, value in enumerate(headers) if value is not None}
        raw_totals: dict[str, defaultdict[str, float]] = defaultdict(lambda: defaultdict(float))
        dedup_totals: dict[str, defaultdict[str, float]] = defaultdict(lambda: defaultdict(float))
        groups: dict[tuple[Any, ...], list[tuple[Any, ...]]] = defaultdict(list)
        for row in rows:
            date = as_iso_date(row[index["赛事日期"]])
            if date is None:
                continue
            event = str(row[index["赛事名称"]]).strip()
            platform = str(row[index["竞品平台"]]).strip().lower()
            acu = float(row[index["主播ACU"]] or 0)
            raw_totals[event][platform] += acu
            key = tuple(row[index[field]] for field in ["赛事日期", "赛程ID", "赛事名称", "竞品平台", "主播UID"])
            groups[key].append((acu, event, platform))
        for metric_rows in groups.values():
            dedup_totals[metric_rows[0][1]][metric_rows[0][2]] += metric_rows[0][0]
            if len(metric_rows) > 1:
                duplicate_acu[group] += sum(item[0] for item in metric_rows[1:])
        independent_counts[group] = {
            "published_rows": {event: sum(values.values()) for event, values in raw_totals.items()},
            "deduplicated": {event: sum(values.values()) for event, values in dedup_totals.items()},
        }
        for event in raw_totals:
            for figure_type, source in [("published_rows", raw_totals), ("deduplicated", dedup_totals)]:
                total = sum(source[event].values())
                for platform, value in source[event].items():
                    independent_share[(event, figure_type, platform)] = value / total
    share_workbook.close()

    artifact_share_differences = {}
    for row in share_rows:
        if row["platform"] == "TOTAL":
            continue
        expected = independent_share.get((row["event_name"], row["figure_type"], row["platform"]), 0.0)
        artifact_share_differences[f"{row['event_name']}|{row['figure_type']}|{row['platform']}"] = abs(float(row["platform_share"]) - expected)
    add("EVENT-V17", "independent-recompute", all(value <= 1e-9 for value in artifact_share_differences.values()), "all <= 1e-9", max(artifact_share_differences.values()), "Platform shares are independently rebuilt from source rows")
    add("EVENT-V18", "independent-recompute", abs(duplicate_acu["LPL"] - 45_013.102500125715) <= 1e-6 and abs(duplicate_acu["KPL"] - 79_729.7664172151) <= 1e-6 and abs(duplicate_acu["BLAST"] - 115_422.89285859547) <= 1e-6, {"LPL": 45_013.102500125715, "KPL": 79_729.7664172151, "BLAST": 115_422.89285859547}, dict(duplicate_acu), "Excess summed streamer ACU from duplicate rows is independently reproduced")
    add("EVENT-V19", "independent-recompute", all(abs(independent_counts[group][figure][event] - next(float(row["event_total_streamer_acu"]) for row in share_rows if row["source_group"] == group and row["event_name"] == event and row["figure_type"] == figure and row["platform"] == "TOTAL")) <= 1e-6 for group in independent_counts for figure, event_totals in independent_counts[group].items() for event in event_totals), "all <= 1e-6", "reconciled", "Every event total recomputes from the source sheet")

    manifest_lookup = {row["source_artifact"]: row for row in en_data["manifest"]}
    hash_matches = {
        name: digest(source_dir / name) == row["sha256"]
        and (source_dir / name).stat().st_size == int(row["bytes"])
        and row["hash_matches_recorded"] == "True"
        for name, row in manifest_lookup.items()
    }
    add("EVENT-V20", "provenance", all(hash_matches.values()), "all true", hash_matches, "All source sizes and SHA-256 values match the recorded manifest")
    add("EVENT-V21", "privacy", manifest_lookup["版权赛事V1_0921.pptx"]["disposition"] == "exclude", "exclude", manifest_lookup["版权赛事V1_0921.pptx"]["disposition"], "Presentation is excluded as documented")

    prohibited = list(PROJECT_DIR.rglob("*.xlsx")) + list(PROJECT_DIR.rglob("*.pptx"))
    add("EVENT-V22", "privacy", not prohibited, [], [str(path.relative_to(PROJECT_DIR)) for path in prohibited], "No raw workbook or presentation is stored in the project")
    sensitive_headers = {"主播UID", "昵称", "uid", "nickname"}
    observed_headers = set()
    for path in [*zh_files.values(), *en_files.values()]:
        observed_headers.update(read_csv(path)[0].keys() if read_csv(path) else [])
    add("EVENT-V23", "privacy", not (sensitive_headers & observed_headers), [], sorted(sensitive_headers & observed_headers), "Artifact schemas contain no UID or nickname fields")

    summary_path = artifacts / "project_summary.json"
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    add("EVENT-V24", "status", summary["status"] == "reviewed_with_documented_source_quality_issues" and summary["raw_workbooks_included"] is False and summary["presentation_included"] is False, "reviewed with exclusions", summary, "Project status and exclusions are explicit")
    add("EVENT-V25", "quality", len(en_data["quality"]) == 6 and {row["finding_id"] for row in en_data["quality"]} == {f"EVENT-QF-0{index}" for index in range(1, 7)}, "EVENT-QF-01..06", len(en_data["quality"]), "All reviewed quality findings remain documented")

    # Make unbounded differences JSON-safe before writing.
    for check in checks:
        if isinstance(check["actual"], dict):
            check["actual"] = {key: (value if not isinstance(value, float) or math.isfinite(value) else str(value)) for key, value in check["actual"].items()}
        elif isinstance(check["actual"], float) and not math.isfinite(check["actual"]):
            check["actual"] = str(check["actual"])

    columns = ["check_id", "category", "status", "expected", "actual", "note"]
    for path in [artifacts / "zh" / "校验结果.csv", artifacts / "en" / "validation-results.csv"]:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("w", encoding="utf-8-sig", newline="") as target:
            writer = csv.DictWriter(target, fieldnames=columns)
            writer.writeheader()
            for check in checks:
                writer.writerow(
                    {
                        **check,
                        "expected": json.dumps(check["expected"], ensure_ascii=False, default=str),
                        "actual": json.dumps(check["actual"], ensure_ascii=False, default=str),
                    }
                )

    fail_count = sum(row["status"] == "FAIL" for row in checks)
    report = {
        "checks": len(checks),
        "passed": len(checks) - fail_count,
        "failed": fail_count,
        "not_run": 0,
        "status": "passed" if fail_count == 0 else "failed",
    }
    (artifacts / "validation_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if fail_count:
        raise SystemExit(1)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path, required=True)
    args = parser.parse_args()
    main(args.source_dir.resolve())
