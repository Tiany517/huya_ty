from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import re
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable

from openpyxl import load_workbook


PROJECT_DIR = Path(__file__).resolve().parents[1]
DATE_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}$")

EVENT_SOURCES = [
    ("LPL", "LPL数据源", "日期", "赛事名称"),
    ("KPL", "KPL_数据源", "日期", "赛事名称"),
    ("FISSURE", "FISSURE裂变天地S3数据源", "日期", "赛事名称"),
    ("BLAST", "BLAST波尔图数据源", "日期", "赛事名称"),
]

SHARE_SOURCES = [
    ("LPL", "LPL份额数据源"),
    ("KPL", "KPL_赛事份额_by主播"),
    ("BLAST", "BLAST波尔图份额数据"),
]

PLATFORMS = {
    "LPL": ["bilibili", "huya", "douyu"],
    "KPL": ["bilibili", "douyin", "douyu", "huya", "kuaishou"],
    "BLAST": ["bilibili", "douyin", "douyu", "huya"],
}

METRICS = [
    ("dau", "全量聚合APPDAU"),
    ("app_dau_increment", "APP端DAU增量"),
    ("content_acquisition", "APP端内容拉新增量"),
    ("content_return", "APP端内容回流增量"),
]

COMPARISONS = [
    ("lpl_q1_yoy", "2026LPL第一赛段 vs 2025LPL第一赛段", "2026LPL第一赛段", "2025LPL第一赛段"),
    ("lpl_q2_yoy", "2026LPL第二赛段 vs 2025LPL第二赛段", "2026LPL第二赛段", "2025LPL第二赛段"),
    ("lpl_q3_yoy", "2026LPL第三赛段 vs 2025LPL第三赛段", "2026LPL第三赛段", "2025LPL第三赛段"),
    ("lpl_q2_q1", "2026LPL第二赛段 vs 2026LPL第一赛段", "2026LPL第二赛段", "2026LPL第一赛段"),
    ("lpl_q3_q2", "2026LPL第三赛段 vs 2026LPL第二赛段", "2026LPL第三赛段", "2026LPL第二赛段"),
    ("kpl_spring_yoy", "2026KPL春季赛 vs 2025KPL春季赛", "2026KPL春季赛", "2025KPL春季赛"),
    ("kpl_summer_yoy", "2026KPL夏季赛 vs 2025KPL夏季赛", "2026KPL夏季赛", "2025KPL夏季赛"),
    ("kpl_summer_spring", "2026KPL夏季赛 vs 2026KPL春季赛", "2026KPL夏季赛", "2026KPL春季赛"),
    ("blast_porto_yoy", "BLAST波尔图公开赛2026 vs BLAST伦敦公开赛", "BLAST波尔图公开赛2026", "BLAST伦敦公开赛"),
]

EXPECTED_SOURCES = {
    "0914_赛事总结.xlsx": {
        "bytes": 1_315_505,
        "sha256": "8fa1c7c2f3d8c21582c76413729423302f22030184097ab8eb583c220b066b6e",
    },
    "0914_赛事总结_汇总.xlsx": {
        "bytes": 16_983,
        "sha256": "01fc2b36ee2ec9aa4b46daa5ae5999656f7f5ebb5b43a9ca50d20a2eb3408b00",
    },
    "版权赛事V1_0921.pptx": {
        "bytes": 516_263,
        "sha256": "218809bb42a13796fad2745d80c8bef48ef624ca08d9305265f0bb6bf3860e56",
    },
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def number(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    result = float(value)
    return result if math.isfinite(result) else None


def iso_date(value: Any) -> str | None:
    text = value.strftime("%Y-%m-%d") if hasattr(value, "strftime") else str(value).strip()
    return text if DATE_PATTERN.fullmatch(text) else None


def write_csv(path: Path, rows: Iterable[dict[str, Any]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as target:
        writer = csv.DictWriter(target, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def audit_event_dau(workbook, source_group: str, sheet: str, date_header: str, event_header: str):
    rows = workbook[sheet].iter_rows(values_only=True)
    headers = list(next(rows))
    index = {value: position for position, value in enumerate(headers) if value is not None}
    required = [date_header, event_header, *(header for _, header in METRICS)]
    missing = [header for header in required if header not in index]
    if missing:
        raise ValueError(f"{sheet}: missing headers {missing}")

    values: dict[str, dict[str, list[float]]] = defaultdict(lambda: defaultdict(list))
    dates: dict[str, set[str]] = defaultdict(set)
    rows_by_event: Counter[str] = Counter()
    keys: Counter[tuple[str, str]] = Counter()
    for row in rows:
        date = iso_date(row[index[date_header]])
        event_value = row[index[event_header]]
        if date is None or event_value is None:
            continue
        event = str(event_value).strip()
        if not event:
            continue
        rows_by_event[event] += 1
        dates[event].add(date)
        keys[(event, date)] += 1
        for output_name, header in METRICS:
            value = number(row[index[header]])
            if value is not None:
                values[event][output_name].append(value)

    output = []
    for event in sorted(rows_by_event):
        averages = {
            metric: (sum(values[event][metric]) / len(values[event][metric]) if values[event][metric] else None)
            for metric, _ in METRICS
        }
        duplicate_event_dates = sum(count - 1 for (item, _), count in keys.items() if item == event and count > 1)
        output.append(
            {
                "source_group": source_group,
                "source_sheet": sheet,
                "event_name": event,
                "date_min": min(dates[event]),
                "date_max": max(dates[event]),
                "distinct_dates": len(dates[event]),
                "valid_day_rows": rows_by_event[event],
                "duplicate_event_date_rows": duplicate_event_dates,
                **averages,
            }
        )
    return output


def audit_share_sheet(workbook, source_group: str, sheet: str):
    rows = workbook[sheet].iter_rows(values_only=True)
    headers = list(next(rows))
    index = {value: position for position, value in enumerate(headers) if value is not None}
    key_fields = ["赛事日期", "赛程ID", "赛事名称", "竞品平台", "主播UID"]
    required = [*key_fields, "主播ACU"]
    missing = [header for header in required if header not in index]
    if missing:
        raise ValueError(f"{sheet}: missing headers {missing}")

    groups: dict[tuple[Any, ...], list[tuple[float, float, tuple[Any, ...]]]] = defaultdict(list)
    event_platform_total_raw: dict[str, defaultdict[str, float]] = defaultdict(lambda: defaultdict(float))
    event_platform_total_dedup: dict[str, defaultdict[str, float]] = defaultdict(lambda: defaultdict(float))
    streamers: dict[str, set[Any]] = defaultdict(set)
    for row in rows:
        date = iso_date(row[index["赛事日期"]])
        event_value = row[index["赛事名称"]]
        platform_value = row[index["竞品平台"]]
        if date is None or event_value is None or platform_value is None:
            continue
        event = str(event_value).strip()
        platform = str(platform_value).strip().lower()
        key = tuple(row[index[field]] for field in key_fields)
        effective_acu = number(row[index.get("有效ACU")]) if "有效ACU" in index else None
        streamer_acu = number(row[index["主播ACU"]])
        if streamer_acu is None:
            continue
        groups[key].append((effective_acu or 0.0, streamer_acu, tuple(row)))
        event_platform_total_raw[event][platform] += streamer_acu
        streamers[event].add(row[index["主播UID"]])

    seen: set[tuple[Any, ...]] = set()
    duplicate_groups = 0
    exact_duplicate_groups = 0
    differing_metric_groups = 0
    extra_streamer_acu = 0.0
    extra_effective_acu = 0.0
    for key, metric_rows in groups.items():
        if len(metric_rows) == 1:
            continue
        seen.add(key)
        duplicate_groups += 1
        exact_duplicate_groups += int(len({item[2] for item in metric_rows}) == 1)
        differing_metric_groups += int(len({(item[0], item[1]) for item in metric_rows}) > 1)
        extra_streamer_acu += sum(value[1] for value in metric_rows[1:])
        extra_effective_acu += sum(value[0] for value in metric_rows[1:])
        event = str(key[2]).strip()
        platform = str(key[3]).strip().lower()
        event_platform_total_dedup[event][platform] += metric_rows[0][1]

    for key, metric_rows in groups.items():
        if key in seen:
            continue
        event = str(key[2]).strip()
        platform = str(key[3]).strip().lower()
        event_platform_total_dedup[event][platform] += metric_rows[0][1]

    all_events = sorted(event_platform_total_raw)
    share_rows = []
    for event in all_events:
        for figure_type, totals in [
            ("published_rows", event_platform_total_raw[event]),
            ("deduplicated", event_platform_total_dedup[event]),
        ]:
            event_total = sum(totals.values())
            for platform in PLATFORMS[source_group]:
                value = totals.get(platform, 0.0)
                share_rows.append(
                    {
                        "source_group": source_group,
                        "source_sheet": sheet,
                        "event_name": event,
                        "figure_type": figure_type,
                        "platform": platform,
                        "streamer_acu_sum": value,
                        "event_total_streamer_acu": event_total,
                        "platform_share": value / event_total if event_total else None,
                        "platform_share_pct": value / event_total * 100 if event_total else None,
                        "unique_streamers": len(streamers[event]),
                    }
                )
            share_rows.append(
                {
                    "source_group": source_group,
                    "source_sheet": sheet,
                    "event_name": event,
                    "figure_type": figure_type,
                    "platform": "TOTAL",
                    "streamer_acu_sum": event_total,
                    "event_total_streamer_acu": event_total,
                    "platform_share": 1.0 if event_total else None,
                    "platform_share_pct": 100.0 if event_total else None,
                    "unique_streamers": len(streamers[event]),
                }
            )

    duplicate_audit = {
        "source_group": source_group,
        "source_sheet": sheet,
        "valid_rows": sum(len(metric_rows) for metric_rows in groups.values()),
        "unique_keys": len(groups),
        "duplicate_groups": duplicate_groups,
        "extra_rows": sum(len(metric_rows) - 1 for metric_rows in groups.values()),
        "exact_duplicate_groups": exact_duplicate_groups,
        "differing_metric_groups": differing_metric_groups,
        "extra_effective_acu": extra_effective_acu,
        "extra_streamer_acu": extra_streamer_acu,
    }
    return share_rows, duplicate_audit


def comparison_rows(event_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_event = {row["event_name"]: row for row in event_rows}
    output = []
    for comparison_id, label, current_name, baseline_name in COMPARISONS:
        if current_name not in by_event or baseline_name not in by_event:
            raise ValueError(f"Missing comparison event for {comparison_id}")
        current = by_event[current_name]
        baseline = by_event[baseline_name]
        for metric, _ in METRICS:
            current_value = current[metric]
            baseline_value = baseline[metric]
            absolute = None
            percent = None
            if current_value is not None and baseline_value is not None:
                absolute = current_value - baseline_value
                percent = (current_value / baseline_value - 1) if baseline_value else None
            output.append(
                {
                    "comparison_id": comparison_id,
                    "comparison": label,
                    "metric": metric,
                    "baseline_event": baseline_name,
                    "current_event": current_name,
                    "baseline_value": baseline_value,
                    "current_value": current_value,
                    "absolute_change": absolute,
                    "percent_change": percent,
                    "percent_change_pct": percent * 100 if percent is not None else None,
                }
            )
    return output


def source_manifest(source_dir: Path) -> list[dict[str, Any]]:
    dispositions = {
        "0914_赛事总结.xlsx": ("retain-derived-only", "Main workbook contains UID, nickname, and streamer-level ACU rows; raw workbook excluded, anonymous aggregates retained"),
        "0914_赛事总结_汇总.xlsx": ("retain-derived-only", "Consolidated workbook contains named streamer contribution blocks; raw workbook excluded, anonymous aggregates retained"),
        "版权赛事V1_0921.pptx": ("exclude", "Two-slide deck contains named broadcasters and streamer-level narratives; excluded from Git"),
    }
    output = []
    for filename, expected in EXPECTED_SOURCES.items():
        path = source_dir / filename
        actual_hash = sha256(path)
        disposition, reason = dispositions[filename]
        output.append(
            {
                "source_artifact": filename,
                "bytes": path.stat().st_size,
                "sha256": actual_hash,
                "expected_sha256": expected["sha256"],
                "hash_matches_recorded": actual_hash == expected["sha256"],
                "disposition": disposition,
                "reason": reason,
            }
        )
    return output


def quality_findings(duplicates: list[dict[str, Any]]) -> list[dict[str, Any]]:
    dup = {row["source_group"]: row for row in duplicates}
    return [
        {
            "finding_id": "EVENT-QF-01",
            "severity": "high",
            "area": "LPL platform share",
            "finding": "LPL_份额汇总_Final reverses the Bilibili and Huya labels in the first segment: the source recomputation gives Bilibili 3,251,602.817 and Huya 3,909,919.831, while the final sheet places 3,909,919.831 under Bilibili and 3,251,602.817 under Huya.",
            "status": "corrected_in_derived_artifacts",
        },
        {
            "finding_id": "EVENT-QF-02",
            "severity": "high",
            "area": "Platform share source grain",
            "finding": f"Exact duplicate rows exist at date/schedule/event/platform/UID grain: LPL {dup['LPL']['extra_rows']} extra rows, KPL {dup['KPL']['extra_rows']}, BLAST {dup['BLAST']['extra_rows']}. Published shares are inflated; deduplicated shares are the corrected analytical view.",
            "status": "corrected_in_derived_artifacts",
        },
        {
            "finding_id": "EVENT-QF-03",
            "severity": "medium",
            "area": "KPL summary block",
            "finding": "KPL_赛事份额_汇总 contains #DIV/0! in I242 and J242 inside a secondary streamer-contribution block. The top-level platform totals and shares independently reconcile; the affected named-streamer row should not be reused.",
            "status": "open_but_not_material_to_top_level_totals",
        },
        {
            "finding_id": "EVENT-QF-04",
            "severity": "medium",
            "area": "Date-row parsing",
            "finding": "FISSURE and BLAST event sheets include labels and total blocks below the raw rows. Any recomputation must accept only YYYY-MM-DD date rows or those summary blocks will be misclassified as events.",
            "status": "controlled_in_build_script",
        },
        {
            "finding_id": "EVENT-QF-05",
            "severity": "medium",
            "area": "Reproducibility",
            "finding": "The raw workbooks contain UID, nickname, and streamer-level ACU data and are intentionally absent from GitHub. Aggregate CSV artifacts and their hashes are the portable evidence; rerunning requires access to the original files.",
            "status": "documented_limitation",
        },
        {
            "finding_id": "EVENT-QF-06",
            "severity": "medium",
            "area": "Presentation privacy",
            "finding": "版权赛事V1_0921.pptx contains named broadcasters and streamer-level narratives. It is excluded even though the repository is private; only this exclusion record and the anonymized workbook-derived aggregates are retained.",
            "status": "excluded_by_policy",
        },
    ]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path, required=True)
    args = parser.parse_args()
    source_dir = args.source_dir.resolve()

    main_workbook = source_dir / "0914_赛事总结.xlsx"
    workbook = load_workbook(main_workbook, data_only=True, read_only=True)
    event_rows = []
    for source_group, sheet, date_header, event_header in EVENT_SOURCES:
        event_rows.extend(audit_event_dau(workbook, source_group, sheet, date_header, event_header))
    event_rows.sort(key=lambda row: (row["source_group"], row["date_min"], row["event_name"]))

    share_rows = []
    duplicates = []
    for source_group, sheet in SHARE_SOURCES:
        group_rows, duplicate_row = audit_share_sheet(workbook, source_group, sheet)
        share_rows.extend(group_rows)
        duplicates.append(duplicate_row)
    workbook.close()

    comparisons = comparison_rows(event_rows)
    findings = quality_findings(duplicates)
    manifest = source_manifest(source_dir)

    zh = PROJECT_DIR / "artifacts" / "zh"
    en = PROJECT_DIR / "artifacts" / "en"
    write_csv(
        zh / "赛事DAU汇总.csv",
        event_rows,
        ["source_group", "source_sheet", "event_name", "date_min", "date_max", "distinct_dates", "valid_day_rows", "duplicate_event_date_rows", "dau", "app_dau_increment", "content_acquisition", "content_return"],
    )
    write_csv(
        en / "event-dau-summary.csv",
        event_rows,
        ["source_group", "source_sheet", "event_name", "date_min", "date_max", "distinct_dates", "valid_day_rows", "duplicate_event_date_rows", "dau", "app_dau_increment", "content_acquisition", "content_return"],
    )
    comparison_columns = ["comparison_id", "comparison", "metric", "baseline_event", "current_event", "baseline_value", "current_value", "absolute_change", "percent_change", "percent_change_pct"]
    write_csv(zh / "赛事DAU对比.csv", comparisons, comparison_columns)
    write_csv(en / "event-dau-comparisons.csv", comparisons, comparison_columns)
    share_columns = ["source_group", "source_sheet", "event_name", "figure_type", "platform", "streamer_acu_sum", "event_total_streamer_acu", "platform_share", "platform_share_pct", "unique_streamers"]
    write_csv(zh / "平台份额汇总.csv", share_rows, share_columns)
    write_csv(en / "platform-share-summary.csv", share_rows, share_columns)
    duplicate_columns = ["source_group", "source_sheet", "valid_rows", "unique_keys", "duplicate_groups", "extra_rows", "exact_duplicate_groups", "differing_metric_groups", "extra_effective_acu", "extra_streamer_acu"]
    write_csv(zh / "重复审计.csv", duplicates, duplicate_columns)
    write_csv(en / "duplication-audit.csv", duplicates, duplicate_columns)
    quality_columns = ["finding_id", "severity", "area", "finding", "status"]
    write_csv(zh / "质量问题.csv", findings, quality_columns)
    write_csv(en / "quality-findings.csv", findings, quality_columns)
    manifest_columns = ["source_artifact", "bytes", "sha256", "expected_sha256", "hash_matches_recorded", "disposition", "reason"]
    write_csv(zh / "来源清单.csv", manifest, manifest_columns)
    write_csv(en / "source-manifest.csv", manifest, manifest_columns)

    summary = {
        "project": "event-summary-review",
        "source_package_date": "2026-09-14",
        "source_cutoff": max(row["date_max"] for row in event_rows),
        "event_count": len(event_rows),
        "event_groups": sorted({row["source_group"] for row in event_rows}),
        "platform_share_events": len({row["event_name"] for row in share_rows}),
        "duplicate_extra_rows": sum(row["extra_rows"] for row in duplicates),
        "quality_findings": len(findings),
        "raw_workbooks_included": False,
        "presentation_included": False,
        "status": "reviewed_with_documented_source_quality_issues",
    }
    (PROJECT_DIR / "artifacts" / "project_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
