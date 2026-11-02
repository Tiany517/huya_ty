#!/usr/bin/env python3
"""Build a de-identified review of the AI live-room monthly snapshots.

The source snapshots contain streamer UIDs and nicknames. Those fields are
used only in memory to derive counts; no identity value is written to the
repository artifacts.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import re
from collections import Counter, defaultdict
from pathlib import Path
from statistics import median

from openpyxl import Workbook, load_workbook


SOURCE_ROOT_DEFAULT = Path(r"C:\Users\tiany\Desktop")
INFO_DIR = "AI直播间信息"
MONITOR_DIR = "AI直播间监控UID"
PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = PROJECT_ROOT / "artifacts" / "anonymous-summary"

SNAPSHOT_SPECS = (
    ("2026-08-07", "0807", "info", "AI直播间信息_0807.csv"),
    ("2026-09-04", "0904", "monitor", "AI主播直播信息_0904.xlsx"),
    ("2026-10-09", "1009", "monitor", "AI主播直播信息_1009.xlsx"),
)

EXPECTED_DATA_MONTHS = {
    "2026-08-07": "2026-07",
    "2026-09-04": "2026-08",
    "2026-10-09": "2026-09",
}

METRIC_FIELDS = (
    "acu",
    "pcu",
    "live_hours",
    "app_dau",
    "view_hours",
    "per_cap_view_min",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def text_from_path(path: Path) -> str:
    raw = path.read_bytes()
    for encoding in ("utf-8-sig", "gb18030"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            continue
    raise UnicodeDecodeError("unknown", raw, 0, 1, f"cannot decode {path.name}")


def read_csv_rows(path: Path) -> list[list[object]]:
    return list(csv.reader(text_from_path(path).splitlines()))


def read_excel_rows(path: Path) -> list[list[object]]:
    workbook = load_workbook(path, read_only=True, data_only=True)
    try:
        candidates: list[tuple[int, int, list[list[object]]]] = []
        for sheet_index, sheet in enumerate(workbook.worksheets):
            rows = [list(row) for row in sheet.iter_rows(values_only=True)]
            candidates.append((benchmark_header_index(rows), sheet_index, rows))
        _, _, rows = max(candidates, key=lambda item: item[0])
        return rows
    finally:
        workbook.close()


def compact_header(value: object) -> str:
    return re.sub(r"\s+", "", str(value or "")).lower()


def benchmark_header_index(rows: list[list[object]]) -> int:
    for index, row in enumerate(rows[:10]):
        headers = [compact_header(value) for value in row]
        if any("uid" in value for value in headers) and any("品类" in value for value in headers):
            return 100 - index
    return -1


def header_index(rows: list[list[object]]) -> int:
    result = benchmark_header_index(rows)
    if result < 0:
        raise ValueError("Unable to locate the UID/category header row")
    return 100 - result


def find_column(headers: list[str], predicate) -> int:
    for index, header in enumerate(headers):
        if predicate(header):
            return index
    raise ValueError(f"Required column not found in headers: {headers}")


def parse_number(value: object) -> float | None:
    if value is None:
        return None
    text = str(value).strip().replace(",", "")
    if not text:
        return None
    try:
        number = float(text)
    except ValueError:
        return None
    return number if math.isfinite(number) else None


def clean_identity(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    text = str(value).strip()
    if re.fullmatch(r"\d+\.0", text):
        return text[:-2]
    return text


def normalize_month(value: object) -> str:
    match = re.match(r"^(\d{4})[-/](\d{1,2})", str(value or "").strip())
    return f"{match.group(1)}-{int(match.group(2)):02d}" if match else str(value or "").strip()


def load_snapshot(path: Path, snapshot_date: str) -> tuple[list[dict[str, object]], dict[str, object]]:
    rows = read_excel_rows(path) if path.suffix.lower() == ".xlsx" else read_csv_rows(path)
    header_row_index = header_index(rows)
    headers = [compact_header(value) for value in rows[header_row_index]]

    columns = {
        "month": find_column(headers, lambda value: "月标签" in value),
        "category": find_column(headers, lambda value: "品类" in value and "分层" not in value),
        "uid": find_column(headers, lambda value: "uid" in value),
        "acu": find_column(headers, lambda value: "acu" in value and "分层" not in value),
        "pcu": find_column(headers, lambda value: "pcu" in value),
        "live_hours": find_column(headers, lambda value: "直播时长" in value),
        "app_dau": find_column(headers, lambda value: "appdau" in value),
        "view_hours": find_column(headers, lambda value: "观时" in value and "人均" not in value),
        "per_cap_view_min": find_column(headers, lambda value: "人均观时" in value),
        "tier": find_column(headers, lambda value: "acu分层" in value),
    }

    records: list[dict[str, object]] = []
    for source_row, row in enumerate(rows[header_row_index + 1 :], start=header_row_index + 2):
        if not any(value not in (None, "") for value in row):
            continue
        padded = list(row) + [None] * (len(headers) - len(row))

        def cell(name: str) -> object:
            return padded[columns[name]] if columns[name] < len(padded) else None

        records.append(
            {
                "source_row": source_row,
                "month": str(cell("month") or "").strip(),
                "data_month": normalize_month(cell("month")),
                "category": str(cell("category") or "").strip(),
                "uid": clean_identity(cell("uid")),
                "nickname": str(padded[find_column(headers, lambda value: "主播昵称" in value)] or "").strip(),
                "acu": parse_number(cell("acu")),
                "pcu": parse_number(cell("pcu")),
                "live_hours": parse_number(cell("live_hours")),
                "app_dau": parse_number(cell("app_dau")),
                "view_hours": parse_number(cell("view_hours")),
                "per_cap_view_min": parse_number(cell("per_cap_view_min")),
                "tier": str(cell("tier") or "").strip(),
            }
        )

    metadata = {
        "snapshot_date": snapshot_date,
        "header_row": header_row_index + 1,
        "columns": len(headers),
        "month_values": sorted(Counter(record["month"] for record in records)),
        "data_month": "|".join(sorted({str(record["data_month"]) for record in records})),
    }
    return records, metadata


def mean(values: list[float | None]) -> float | None:
    clean = [value for value in values if value is not None]
    return sum(clean) / len(clean) if clean else None


def fmt(value: float | None, digits: int = 4) -> str:
    if value is None:
        return ""
    return f"{value:.{digits}f}".rstrip("0").rstrip(".")


def overview(snapshot_date: str, source_format: str, records: list[dict[str, object]]) -> dict[str, object]:
    uids = [str(record["uid"]) for record in records]
    uid_categories = [(str(record["uid"]), str(record["category"])) for record in records]
    uid_category_counts = Counter(uid for uid, _ in uid_categories)
    missing_cells = sum(
        record[field] is None for record in records for field in METRIC_FIELDS
    )
    metrics = [record["acu"] for record in records if record["acu"] is not None]
    return {
        "snapshot_date": snapshot_date,
        "source_format": source_format,
        "data_month": "|".join(sorted({str(record["data_month"]) for record in records})),
        "rows": len(records),
        "unique_anchors": len(set(uids)),
        "anchor_category_keys": len(set(uid_categories)),
        "multi_category_anchors": sum(count > 1 for count in uid_category_counts.values()),
        "categories": len({str(record["category"]) for record in records}),
        "acu_mean": fmt(mean([record["acu"] for record in records])),
        "acu_median": fmt(median(metrics) if metrics else None),
        "acu_max": fmt(max(metrics) if metrics else None),
        "pcu_max": fmt(max((record["pcu"] for record in records if record["pcu"] is not None), default=None)),
        "live_hours_mean": fmt(mean([record["live_hours"] for record in records])),
        "app_dau_mean": fmt(mean([record["app_dau"] for record in records])),
        "view_hours_mean": fmt(mean([record["view_hours"] for record in records])),
        "per_cap_view_min_mean": fmt(mean([record["per_cap_view_min"] for record in records])),
        "tiers": "|".join(sorted({str(record["tier"]) for record in records})),
        "blank_metric_cells": missing_cells,
    }


def grouped_summary(records: list[dict[str, object]], group_field: str) -> list[dict[str, object]]:
    groups: dict[str, list[dict[str, object]]] = defaultdict(list)
    for record in records:
        groups[str(record[group_field])].append(record)
    result: list[dict[str, object]] = []
    for group, items in sorted(groups.items()):
        acus = [item["acu"] for item in items if item["acu"] is not None]
        result.append(
            {
                group_field: group,
                "snapshot_date": items[0]["snapshot_date"],
                "data_month": items[0]["data_month"],
                "rows": len(items),
                "unique_anchors": len({item["uid"] for item in items}),
                "acu_mean": fmt(mean(acus)),
                "acu_median": fmt(median(acus) if acus else None),
                "acu_min": fmt(min(acus) if acus else None),
                "acu_max": fmt(max(acus) if acus else None),
                "pcu_max": fmt(max((item["pcu"] for item in items if item["pcu"] is not None), default=None)),
                "live_hours_mean": fmt(mean([item["live_hours"] for item in items])),
                "app_dau_mean": fmt(mean([item["app_dau"] for item in items])),
                "view_hours_mean": fmt(mean([item["view_hours"] for item in items])),
                "per_cap_view_min_mean": fmt(mean([item["per_cap_view_min"] for item in items])),
            }
        )
    return result


def quality_rows(
    snapshot_date: str,
    records: list[dict[str, object]],
    metadata: dict[str, object],
) -> list[dict[str, object]]:
    uid_category = Counter((record["uid"], record["category"]) for record in records)
    duplicate_uid_category = sum(count - 1 for count in uid_category.values() if count > 1)
    blank_uid = sum(not record["uid"] for record in records)
    blank_category = sum(not record["category"] for record in records)
    negative_metric = sum(
        record[field] is not None and record[field] < 0
        for record in records
        for field in METRIC_FIELDS
    )
    unknown_tier = sum(record["tier"] not in {"头部", "颈部", "腰部", "尾部"} for record in records)
    month_values = metadata["month_values"]
    return [
        {
            "snapshot_date": snapshot_date,
            "check_id": "header_schema",
            "status": "PASS",
            "observed": f"{metadata['columns']} columns; header row {metadata['header_row']}",
            "expected": "UID, category, tier, and six metrics recognized",
        },
        {
            "snapshot_date": snapshot_date,
            "check_id": "blank_identity_or_category",
            "status": "PASS" if blank_uid + blank_category == 0 else "FAIL",
            "observed": f"blank_uid={blank_uid}; blank_category={blank_category}",
            "expected": "0",
        },
        {
            "snapshot_date": snapshot_date,
            "check_id": "duplicate_uid_category",
            "status": "PASS" if duplicate_uid_category == 0 else "FAIL",
            "observed": str(duplicate_uid_category),
            "expected": "0 under anchor x category grain",
        },
        {
            "snapshot_date": snapshot_date,
            "check_id": "negative_metric",
            "status": "PASS" if negative_metric == 0 else "REVIEW",
            "observed": str(negative_metric),
            "expected": "0",
        },
        {
            "snapshot_date": snapshot_date,
            "check_id": "tier_vocabulary",
            "status": "PASS" if unknown_tier == 0 else "REVIEW",
            "observed": str(unknown_tier),
            "expected": "all values in head/neck/waist/tail vocabulary",
        },
        {
            "snapshot_date": snapshot_date,
            "check_id": "month_label",
            "status": "PASS" if len(month_values) == 1 else "REVIEW",
            "observed": "|".join(sorted({str(record["data_month"]) for record in records})),
            "expected": "one monthly label per snapshot",
        },
        {
            "snapshot_date": snapshot_date,
            "check_id": "snapshot_month_alignment",
            "status": "PASS"
            if metadata["data_month"] == EXPECTED_DATA_MONTHS[snapshot_date]
            else "REVIEW",
            "observed": str(metadata["data_month"]),
            "expected": f"export {snapshot_date} contains {EXPECTED_DATA_MONTHS[snapshot_date]}",
        },
    ]


def overlap_rows(snapshots: dict[str, list[dict[str, object]]]) -> list[dict[str, object]]:
    ids = {snapshot: {str(record["uid"]) for record in records} for snapshot, records in snapshots.items()}
    data_months = {snapshot: sorted({str(record["data_month"]) for record in records}) for snapshot, records in snapshots.items()}
    pairs = (("2026-08-07", "2026-09-04"), ("2026-09-04", "2026-10-09"), ("2026-08-07", "2026-10-09"))
    result: list[dict[str, object]] = []
    for left, right in pairs:
        overlap = ids[left] & ids[right]
        union = ids[left] | ids[right]
        result.append(
            {
                "comparison": f"{data_months[left][0]} vs {data_months[right][0]}",
                "left_anchors": len(ids[left]),
                "right_anchors": len(ids[right]),
                "intersection": len(overlap),
                "left_only": len(ids[left] - overlap),
                "right_only": len(ids[right] - overlap),
                "jaccard": fmt(len(overlap) / len(union) if union else None),
            }
        )
    all_three = ids["2026-08-07"] & ids["2026-09-04"] & ids["2026-10-09"]
    union_three = ids["2026-08-07"] | ids["2026-09-04"] | ids["2026-10-09"]
    result.append(
        {
            "comparison": "2026-07 vs 2026-08 vs 2026-09",
            "left_anchors": len(union_three),
            "right_anchors": "",
            "intersection": len(all_three),
            "left_only": len(union_three - all_three),
            "right_only": "",
            "jaccard": fmt(len(all_three) / len(union_three) if union_three else None),
        }
    )
    return result


TRANSLATIONS = {
    "overview": {
        "zh": {
            "snapshot_date": "快照日期",
            "source_format": "源格式",
            "data_month": "数据月份",
            "rows": "数据行",
            "unique_anchors": "唯一主播",
            "anchor_category_keys": "主播×品类唯一键",
            "multi_category_anchors": "跨多个品类主播",
            "categories": "品类数",
            "acu_mean": "ACU均值",
            "acu_median": "ACU中位数",
            "acu_max": "ACU最大值",
            "pcu_max": "PCU最大值",
            "live_hours_mean": "日均直播时长均值_h",
            "app_dau_mean": "APP_DAU均值",
            "view_hours_mean": "观时均值_h",
            "per_cap_view_min_mean": "人均观时均值_min",
            "tiers": "ACU分层",
            "blank_metric_cells": "空指标单元格",
        },
        "en": {
            "snapshot_date": "snapshot_date",
            "source_format": "source_format",
            "data_month": "data_month",
            "rows": "rows",
            "unique_anchors": "unique_anchors",
            "anchor_category_keys": "anchor_category_keys",
            "multi_category_anchors": "multi_category_anchors",
            "categories": "categories",
            "acu_mean": "acu_mean",
            "acu_median": "acu_median",
            "acu_max": "acu_max",
            "pcu_max": "pcu_max",
            "live_hours_mean": "live_hours_mean",
            "app_dau_mean": "app_dau_mean",
            "view_hours_mean": "view_hours_mean",
            "per_cap_view_min_mean": "per_cap_view_min_mean",
            "tiers": "tiers",
            "blank_metric_cells": "blank_metric_cells",
        },
    },
    "category": {
        "zh": {
            "category": "品类",
            "snapshot_date": "快照日期",
            "data_month": "数据月份",
            "rows": "数据行",
            "unique_anchors": "唯一主播",
            "acu_mean": "ACU均值",
            "acu_median": "ACU中位数",
            "acu_min": "ACU最小值",
            "acu_max": "ACU最大值",
            "pcu_max": "PCU最大值",
            "live_hours_mean": "日均直播时长均值_h",
            "app_dau_mean": "APP_DAU均值",
            "view_hours_mean": "观时均值_h",
            "per_cap_view_min_mean": "人均观时均值_min",
        },
        "en": {},
    },
    "tier": {
        "zh": {
            "tier": "ACU分层",
            "snapshot_date": "快照日期",
            "data_month": "数据月份",
            "rows": "数据行",
            "unique_anchors": "唯一主播",
            "acu_mean": "ACU均值",
            "acu_median": "ACU中位数",
            "acu_min": "ACU最小值",
            "acu_max": "ACU最大值",
            "pcu_max": "PCU最大值",
            "live_hours_mean": "日均直播时长均值_h",
            "app_dau_mean": "APP_DAU均值",
            "view_hours_mean": "观时均值_h",
            "per_cap_view_min_mean": "人均观时均值_min",
        },
        "en": {},
    },
    "overlap": {
        "zh": {
            "comparison": "比较",
            "left_anchors": "左侧主播数",
            "right_anchors": "右侧主播数",
            "intersection": "交集主播数",
            "left_only": "仅左侧",
            "right_only": "仅右侧",
            "jaccard": "Jaccard",
        },
        "en": {},
    },
    "quality": {
        "zh": {
            "snapshot_date": "快照日期",
            "check_id": "检查项",
            "status": "状态",
            "observed": "实际值",
            "expected": "预期",
        },
        "en": {},
    },
}


def translated_rows(rows: list[dict[str, object]], section: str, language: str) -> tuple[list[str], list[list[object]]]:
    keys = list(rows[0]) if rows else []
    mapping = TRANSLATIONS[section][language]
    headers = [mapping.get(key, key) for key in keys]
    return headers, [[row[key] for key in keys] for row in rows]


def write_csv(path: Path, headers: list[str], rows: list[list[object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(headers)
        writer.writerows(rows)


def write_summary_csvs(data: dict[str, list[dict[str, object]]]) -> None:
    for section, rows in data.items():
        for language in ("zh", "en"):
            headers, values = translated_rows(rows, section, language)
            suffix = ".zh.csv" if language == "zh" else ".en.csv"
            write_csv(OUT_DIR / f"{section}-summary{suffix}", headers, values)


def write_workbook(
    language: str,
    data: dict[str, list[dict[str, object]]],
    project_summary: dict[str, object],
) -> Path:
    workbook = Workbook()
    workbook.remove(workbook.active)
    sheet_names = {
        "zh": ["快照总览", "品类汇总", "ACU分层汇总", "主播覆盖重叠", "数据质量", "SQL静态审查", "方法说明"],
        "en": ["Snapshot overview", "Category summary", "Tier summary", "Anchor overlap", "Data quality", "SQL static review", "Method"],
    }[language]
    section_order = ("overview", "category", "tier", "overlap", "quality")
    for sheet_name, section in zip(sheet_names[:5], section_order):
        sheet = workbook.create_sheet(sheet_name)
        headers, rows = translated_rows(data[section], section, language)
        sheet.append(headers)
        for row in rows:
            sheet.append(row)
        sheet.freeze_panes = "A2"
        sheet.auto_filter.ref = sheet.dimensions

    risk_sheet = workbook.create_sheet(sheet_names[5])
    risk_path = OUT_DIR / f"sql-static-review.{language}.csv"
    with risk_path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.reader(handle)
        for row in reader:
            risk_sheet.append(row)
    risk_sheet.freeze_panes = "A2"
    risk_sheet.auto_filter.ref = risk_sheet.dimensions

    method = workbook.create_sheet(sheet_names[-1])
    method.append(["项目", "说明"] if language == "zh" else ["Item", "Description"])
    notes = (
        [
            ("数据范围", "三份导出快照：2026-08-07 包含 2026-07 月数据，2026-09-04 包含 2026-08 月数据，2026-10-09 包含 2026-09 月数据。"),
            ("匿名化边界", "不输出主播 UID、昵称或原始快照；UID 仅在内存中用于统计。"),
            ("行粒度", "通过 UID+品类唯一键检查判断；同一 UID 覆盖多个品类时保留多行。"),
            ("指标边界", "只汇总源快照已有值，不重新执行 SQL，也不把 ACU 变化解释为因果。"),
            ("校验状态", f"数据快照校验与结构复盘；SQL 状态={project_summary['sql_validation_status']}。"),
        ]
        if language == "zh"
        else [
            ("Coverage", "Three exports: 2026-08-07 contains 2026-07, 2026-09-04 contains 2026-08, and 2026-10-09 contains 2026-09."),
            ("De-identification", "Anchor UIDs, nicknames, and source snapshots are not exported; UIDs are used in memory only."),
            ("Row grain", "UID+category uniqueness determines the candidate grain; one UID may legitimately span categories."),
            ("Metric boundary", "Only existing snapshot values are summarized. The SQL is not rerun and ACU changes are not causal."),
            ("Validation status", f"Snapshot and structure review; SQL status={project_summary['sql_validation_status']}."),
        ]
    )
    for row in notes:
        method.append(row)
    method.column_dimensions["A"].width = 24
    method.column_dimensions["B"].width = 100

    path = OUT_DIR / f"ai-live-room-snapshot-review-{language}.xlsx"
    workbook.save(path)
    return path


def build(source_root: Path) -> dict[str, object]:
    info_dir = source_root / INFO_DIR
    monitor_dir = source_root / MONITOR_DIR
    sql_source = monitor_dir / "AI直播间监控_每月的腰部颈部主播表现.sql"
    annotated_sql_source = (
        source_root
        / "SQL"
        / "腰部AI直播间_月度ACU_DAU_观时_By主播_改正版_20261009.sql"
    )
    duplicate_0807 = monitor_dir / "AI直播间信息_0807.csv"

    snapshot_sources = []
    snapshots: dict[str, list[dict[str, object]]] = {}
    metadata: dict[str, dict[str, object]] = {}
    overview_rows: list[dict[str, object]] = []
    category_rows: list[dict[str, object]] = []
    tier_rows: list[dict[str, object]] = []
    quality: list[dict[str, object]] = []

    for snapshot_date, label, directory, filename in SNAPSHOT_SPECS:
        path = (info_dir if directory == "info" else monitor_dir) / filename
        records, meta = load_snapshot(path, snapshot_date)
        for record in records:
            record["snapshot_date"] = snapshot_date
        snapshots[snapshot_date] = records
        metadata[snapshot_date] = meta
        snapshot_sources.append((snapshot_date, label, path))
        overview_rows.append(overview(snapshot_date, path.suffix.lower().lstrip("."), records))
        category_rows.extend(grouped_summary(records, "category"))
        tier_rows.extend(grouped_summary(records, "tier"))
        quality.extend(quality_rows(snapshot_date, records, meta))

    canonical_0807 = info_dir / "AI直播间信息_0807.csv"
    copies_identical = sha256(canonical_0807) == sha256(duplicate_0807)
    quality.append(
        {
            "snapshot_date": "2026-08-07",
            "check_id": "duplicate_0807_copies",
            "status": "PASS" if copies_identical else "FAIL",
            "observed": "identical SHA-256" if copies_identical else "different SHA-256",
            "expected": "the two 0807 copies are identical",
        }
    )

    overlap = overlap_rows(snapshots)
    data = {
        "overview": overview_rows,
        "category": category_rows,
        "tier": tier_rows,
        "overlap": overlap,
        "quality": quality,
    }

    project_summary = {
        "project": "AI live-room monthly snapshot review",
        "snapshot_count": len(SNAPSHOT_SPECS),
        "total_rows": sum(len(records) for records in snapshots.values()),
        "unique_anchor_snapshot_pairs": sum(
            len({record["uid"] for record in records}) for records in snapshots.values()
        ),
        "privacy": {
            "excluded": ["streamer UID", "streamer nickname", "raw CSV/XLSX snapshots"],
            "identity_values_used_in_memory_only": True,
        },
        "sql_validation_status": "incomplete-static-review-only",
        "sql_risk_count": 13,
    }

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    write_summary_csvs(data)
    write_workbook("zh", data, project_summary)
    write_workbook("en", data, project_summary)

    manifest_rows = []
    manifest_specs = [
        (*snapshot_sources[0], "canonical August snapshot", "parsed; identity fields excluded"),
        ("2026-08-07", "0807-copy", duplicate_0807, "duplicate August snapshot", "byte-identical copy; parsed only for hash check"),
        (*snapshot_sources[1], "canonical September snapshot", "parsed; identity fields excluded"),
        (*snapshot_sources[2], "canonical October snapshot", "parsed; identity fields excluded"),
        ("", "sql", sql_source, "monthly waist/neck anchor tiering SQL", "copied verbatim"),
        ("", "sql-annotated", annotated_sql_source, "annotated corrected SQL with validation queries", "copied verbatim"),
    ]
    for snapshot_date, label, path, role, status in manifest_specs:
        try:
            relative = path.relative_to(source_root.parent)
        except ValueError:
            relative = path
        manifest_rows.append(
            {
                "snapshot_date": snapshot_date,
                "source_id": label,
                "local_relative_path": str(relative).replace("\\", "/"),
                "size_bytes": path.stat().st_size,
                "sha256": sha256(path),
                "role": role,
                "inclusion": status,
            }
        )
    write_csv(
        OUT_DIR / "source-manifest.csv",
        ["snapshot_date", "source_id", "local_relative_path", "size_bytes", "sha256", "role", "inclusion"],
        [[row[key] for key in ("snapshot_date", "source_id", "local_relative_path", "size_bytes", "sha256", "role", "inclusion")] for row in manifest_rows],
    )

    project_summary["snapshots"] = {
        snapshot_date: {
            "rows": len(records),
            "unique_anchors": len({record["uid"] for record in records}),
            "anchor_category_keys": len({(record["uid"], record["category"]) for record in records}),
        }
        for snapshot_date, records in snapshots.items()
    }
    project_summary["overlaps"] = overlap
    (OUT_DIR / "project-summary.json").write_text(
        json.dumps(project_summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return project_summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, default=SOURCE_ROOT_DEFAULT)
    args = parser.parse_args()
    summary = build(args.source_root)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
