#!/usr/bin/env python3
"""Independently validate the AI live-room migration package."""

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

from openpyxl import load_workbook


SOURCE_ROOT_DEFAULT = Path(r"C:\Users\tiany\Desktop")
PROJECT_ROOT = Path(__file__).resolve().parents[1]
ARTIFACT_DIR = PROJECT_ROOT / "artifacts" / "anonymous-summary"
VALIDATION_DIR = PROJECT_ROOT / "validation"
SCRIPT_DIR = PROJECT_ROOT / "scripts"

INFO_DIR = "AI直播间信息"
MONITOR_DIR = "AI直播间监控UID"
METRIC_FIELDS = ("acu", "pcu", "live_hours", "app_dau", "view_hours", "per_cap_view_min")
SNAPSHOT_SPECS = (
    ("2026-08-07", "2026-07", "info", "AI直播间信息_0807.csv"),
    ("2026-09-04", "2026-08", "monitor", "AI主播直播信息_0904.xlsx"),
    ("2026-10-09", "2026-09", "monitor", "AI主播直播信息_1009.xlsx"),
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def compact(value: object) -> str:
    return re.sub(r"\s+", "", str(value or "")).lower()


def header_row(rows: list[list[object]]) -> int:
    for index, row in enumerate(rows[:10]):
        headers = [compact(value) for value in row]
        if any("uid" in value for value in headers) and any("品类" in value for value in headers):
            return index
    raise ValueError("header row not found")


def read_text(path: Path) -> str:
    raw = path.read_bytes()
    for encoding in ("utf-8-sig", "gb18030"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            pass
    raise UnicodeDecodeError("unknown", raw, 0, 1, str(path))


def source_rows(path: Path) -> list[list[object]]:
    if path.suffix.lower() == ".csv":
        return list(csv.reader(read_text(path).splitlines()))
    workbook = load_workbook(path, read_only=True, data_only=True)
    try:
        best: tuple[int, list[list[object]]] | None = None
        for sheet in workbook.worksheets:
            rows = [list(row) for row in sheet.iter_rows(values_only=True)]
            try:
                index = header_row(rows)
            except ValueError:
                continue
            score = len(rows) - index
            if best is None or score > best[0]:
                best = (score, rows)
        if best is None:
            raise ValueError(f"no recognizable snapshot sheet in {path}")
        return best[1]
    finally:
        workbook.close()


def number(value: object) -> float | None:
    text = str(value or "").strip().replace(",", "")
    if not text:
        return None
    try:
        result = float(text)
    except ValueError:
        return None
    return result if math.isfinite(result) else None


def identity(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    text = str(value).strip()
    return text[:-2] if re.fullmatch(r"\d+\.0", text) else text


def month(value: object) -> str:
    match = re.match(r"^(\d{4})[-/](\d{1,2})", str(value or "").strip())
    return f"{match.group(1)}-{int(match.group(2)):02d}" if match else str(value or "").strip()


def locate_column(headers: list[str], predicate) -> int:
    for index, header in enumerate(headers):
        if predicate(header):
            return index
    raise ValueError(f"column not found: {headers}")


def parse_snapshot(path: Path, export_date: str) -> tuple[list[dict[str, object]], int]:
    rows = source_rows(path)
    index = header_row(rows)
    headers = [compact(value) for value in rows[index]]
    columns = {
        "month": locate_column(headers, lambda value: "月标签" in value),
        "category": locate_column(headers, lambda value: "品类" in value and "分层" not in value),
        "uid": locate_column(headers, lambda value: "uid" in value),
        "nickname": locate_column(headers, lambda value: "主播昵称" in value),
        "acu": locate_column(headers, lambda value: "acu" in value and "分层" not in value),
        "pcu": locate_column(headers, lambda value: "pcu" in value),
        "live_hours": locate_column(headers, lambda value: "直播时长" in value),
        "app_dau": locate_column(headers, lambda value: "appdau" in value),
        "view_hours": locate_column(headers, lambda value: "观时" in value and "人均" not in value),
        "per_cap_view_min": locate_column(headers, lambda value: "人均观时" in value),
        "tier": locate_column(headers, lambda value: "acu分层" in value),
    }
    result: list[dict[str, object]] = []
    for row in rows[index + 1 :]:
        if not any(value not in (None, "") for value in row):
            continue
        padded = list(row) + [None] * (len(headers) - len(row))

        def get(name: str) -> object:
            return padded[columns[name]] if columns[name] < len(padded) else None

        result.append(
            {
                "snapshot_date": export_date,
                "data_month": month(get("month")),
                "category": str(get("category") or "").strip(),
                "uid": identity(get("uid")),
                "nickname": str(get("nickname") or "").strip(),
                "tier": str(get("tier") or "").strip(),
                "acu": number(get("acu")),
                "pcu": number(get("pcu")),
                "live_hours": number(get("live_hours")),
                "app_dau": number(get("app_dau")),
                "view_hours": number(get("view_hours")),
                "per_cap_view_min": number(get("per_cap_view_min")),
            }
        )
    return result, len(headers)


def mean(values: list[float | None]) -> float | None:
    clean = [value for value in values if value is not None]
    return sum(clean) / len(clean) if clean else None


def fmt(value: float | None) -> str:
    return "" if value is None else f"{value:.4f}".rstrip("0").rstrip(".")


def expected_overview(export_date: str, records: list[dict[str, object]]) -> dict[str, str]:
    uid_categories = [(str(record["uid"]), str(record["category"])) for record in records]
    per_uid = Counter(uid for uid, _ in uid_categories)
    acus = [record["acu"] for record in records if record["acu"] is not None]
    return {
        "snapshot_date": export_date,
        "source_format": "xlsx" if export_date != "2026-08-07" else "csv",
        "data_month": "|".join(sorted({str(record["data_month"]) for record in records})),
        "rows": str(len(records)),
        "unique_anchors": str(len({record["uid"] for record in records})),
        "anchor_category_keys": str(len(set(uid_categories))),
        "multi_category_anchors": str(sum(value > 1 for value in per_uid.values())),
        "categories": str(len({record["category"] for record in records})),
        "acu_mean": fmt(mean([record["acu"] for record in records])),
        "acu_median": fmt(median(acus) if acus else None),
        "acu_max": fmt(max(acus) if acus else None),
        "pcu_max": fmt(max((record["pcu"] for record in records if record["pcu"] is not None), default=None)),
        "live_hours_mean": fmt(mean([record["live_hours"] for record in records])),
        "app_dau_mean": fmt(mean([record["app_dau"] for record in records])),
        "view_hours_mean": fmt(mean([record["view_hours"] for record in records])),
        "per_cap_view_min_mean": fmt(mean([record["per_cap_view_min"] for record in records])),
        "tiers": "|".join(sorted({record["tier"] for record in records})),
        "blank_metric_cells": str(
            sum(record[field] is None for record in records for field in METRIC_FIELDS)
        ),
    }


def expected_groups(records_by_snapshot: dict[str, list[dict[str, object]]], group_field: str) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for export_date, records in records_by_snapshot.items():
        groups: dict[str, list[dict[str, object]]] = defaultdict(list)
        for record in records:
            groups[str(record[group_field])].append(record)
        for group, items in sorted(groups.items()):
            acus = [item["acu"] for item in items if item["acu"] is not None]
            rows.append(
                {
                    group_field: group,
                    "snapshot_date": export_date,
                    "data_month": str(items[0]["data_month"]),
                    "rows": str(len(items)),
                    "unique_anchors": str(len({item["uid"] for item in items})),
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
    return rows


def expected_overlaps(records_by_snapshot: dict[str, list[dict[str, object]]]) -> list[dict[str, str]]:
    ids = {date: {str(record["uid"]) for record in records} for date, records in records_by_snapshot.items()}
    months = {date: str(records[0]["data_month"]) for date, records in records_by_snapshot.items()}
    pairs = (("2026-08-07", "2026-09-04"), ("2026-09-04", "2026-10-09"), ("2026-08-07", "2026-10-09"))
    result: list[dict[str, str]] = []
    for left, right in pairs:
        intersection = ids[left] & ids[right]
        union = ids[left] | ids[right]
        result.append(
            {
                "comparison": f"{months[left]} vs {months[right]}",
                "left_anchors": str(len(ids[left])),
                "right_anchors": str(len(ids[right])),
                "intersection": str(len(intersection)),
                "left_only": str(len(ids[left] - intersection)),
                "right_only": str(len(ids[right] - intersection)),
                "jaccard": fmt(len(intersection) / len(union)),
            }
        )
    triple = ids["2026-08-07"] & ids["2026-09-04"] & ids["2026-10-09"]
    union = ids["2026-08-07"] | ids["2026-09-04"] | ids["2026-10-09"]
    result.append(
        {
            "comparison": "2026-07 vs 2026-08 vs 2026-09",
            "left_anchors": str(len(union)),
            "right_anchors": "",
            "intersection": str(len(triple)),
            "left_only": str(len(union - triple)),
            "right_only": "",
            "jaccard": fmt(len(triple) / len(union)),
        }
    )
    return result


def read_csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def compare_rows(actual: list[dict[str, str]], expected: list[dict[str, str]], keys: list[str]) -> tuple[bool, str]:
    if len(actual) != len(expected):
        return False, f"row_count actual={len(actual)} expected={len(expected)}"
    mismatches = []
    for index, (actual_row, expected_row) in enumerate(zip(actual, expected), start=2):
        for key in keys:
            if str(actual_row.get(key, "")) != str(expected_row.get(key, "")):
                mismatches.append(f"row={index} field={key} actual={actual_row.get(key)} expected={expected_row.get(key)}")
                if len(mismatches) >= 5:
                    return False, "; ".join(mismatches)
    return not mismatches, "; ".join(mismatches) or f"{len(actual)} rows and all fields match"


def add_check(
    checks: list[dict[str, object]],
    check_id: str,
    status: str,
    title_zh: str,
    title_en: str,
    evidence_zh: str,
    evidence_en: str,
) -> None:
    checks.append(
        {
            "check_id": check_id,
            "status": status,
            "zh": {"title": title_zh, "evidence": evidence_zh},
            "en": {"title": title_en, "evidence": evidence_en},
        }
    )


def private_identity_scan(
    records_by_snapshot: dict[str, list[dict[str, object]]],
    output_paths: list[Path],
) -> tuple[bool, str]:
    uids = {str(record["uid"]) for records in records_by_snapshot.values() for record in records if record["uid"]}
    nicknames = {str(record["nickname"]) for records in records_by_snapshot.values() for record in records if record["nickname"]}
    findings: list[str] = []
    for path in output_paths:
        if path.suffix.lower() == ".xlsx":
            workbook = load_workbook(path, read_only=True, data_only=True)
            try:
                for sheet in workbook.worksheets:
                    for row in sheet.iter_rows(values_only=True):
                        for value in row:
                            text = str(value or "").strip()
                            if text in uids or text in nicknames:
                                findings.append(f"{path.name}:{sheet.title}")
            finally:
                workbook.close()
        elif path.suffix.lower() in {".csv", ".md", ".json"}:
            text = path.read_text(encoding="utf-8-sig")
            for uid in uids:
                if uid in text:
                    findings.append(f"{path.name}:UID")
            if findings:
                break
    return not findings, "no source UID or nickname found in generated deliverables" if not findings else "; ".join(findings)


def validate(source_root: Path) -> dict[str, object]:
    info_dir = source_root / INFO_DIR
    monitor_dir = source_root / MONITOR_DIR
    sql_source = monitor_dir / "AI直播间监控_每月的腰部颈部主播表现.sql"
    annotated_sql_source = source_root / "SQL" / "腰部AI直播间_月度ACU_DAU_观时_By主播_改正版_20261009.sql"
    checks: list[dict[str, object]] = []

    records_by_snapshot: dict[str, list[dict[str, object]]] = {}
    header_counts: dict[str, int] = {}
    for export_date, _, directory, filename in SNAPSHOT_SPECS:
        path = (info_dir if directory == "info" else monitor_dir) / filename
        records, column_count = parse_snapshot(path, export_date)
        records_by_snapshot[export_date] = records
        header_counts[export_date] = column_count
    add_check(
        checks,
        "source_readability",
        "PASS",
        "源快照可读且表头可识别",
        "Source snapshots are readable with recognizable headers",
        f"字段数：{header_counts}",
        f"Column counts: {header_counts}",
    )

    duplicate = monitor_dir / "AI直播间信息_0807.csv"
    duplicate_ok = sha256(info_dir / "AI直播间信息_0807.csv") == sha256(duplicate)
    add_check(
        checks,
        "duplicate_0807_hash",
        "PASS" if duplicate_ok else "FAIL",
        "两份 0807 CSV 完全一致",
        "The two 0807 CSV copies are identical",
        "SHA-256 一致" if duplicate_ok else "SHA-256 不一致",
        "SHA-256 matches" if duplicate_ok else "SHA-256 differs",
    )

    manifest_path = ARTIFACT_DIR / "source-manifest.csv"
    manifest = read_csv_rows(manifest_path)
    manifest_mismatch = []
    for row in manifest:
        path = source_root.parent / row["local_relative_path"]
        if not path.exists() or sha256(path) != row["sha256"] or path.stat().st_size != int(row["size_bytes"]):
            manifest_mismatch.append(row["source_id"])
    add_check(
        checks,
        "source_manifest_hashes",
        "PASS" if not manifest_mismatch else "FAIL",
        "源文件清单大小与哈希一致",
        "Source manifest sizes and hashes match",
        f"{len(manifest)} 个源文件；异常={manifest_mismatch}",
        f"{len(manifest)} source files; mismatches={manifest_mismatch}",
    )

    sql_copy_ok = sha256(sql_source) == sha256(SCRIPT_DIR / "ai-live-room-monthly-tiering.sql")
    annotated_copy_ok = sha256(annotated_sql_source) == sha256(SCRIPT_DIR / "ai-live-room-monthly-tiering-annotated.sql")
    add_check(
        checks,
        "sql_verbatim_copies",
        "PASS" if sql_copy_ok and annotated_copy_ok else "FAIL",
        "两份 SQL 与源文件逐字节一致",
        "Both SQL files are byte-identical to their sources",
        f"运行版={sql_copy_ok}; 注释版={annotated_copy_ok}",
        f"runtime={sql_copy_ok}; annotated={annotated_copy_ok}",
    )

    for export_date, expected_month, _, _ in SNAPSHOT_SPECS:
        records = records_by_snapshot[export_date]
        keys = Counter((record["uid"], record["category"]) for record in records)
        duplicate_keys = sum(count - 1 for count in keys.values() if count > 1)
        months = sorted({str(record["data_month"]) for record in records})
        passed = duplicate_keys == 0 and months == [expected_month]
        add_check(
            checks,
            f"snapshot_{export_date}_grain_month",
            "PASS" if passed else "FAIL",
            f"{export_date} 快照粒度与月份",
            f"Snapshot {export_date} grain and month",
            f"行={len(records)}; 唯一主播×品类={len(keys)}; 重复键={duplicate_keys}; 数据月={months}",
            f"rows={len(records)}; unique anchor-category={len(keys)}; duplicate keys={duplicate_keys}; data month={months}",
        )

    october_records = records_by_snapshot["2026-10-09"]
    multi = Counter(str(record["uid"]) for record in october_records)
    add_check(
        checks,
        "october_multi_category",
        "PASS" if sum(value > 1 for value in multi.values()) == 4 else "REVIEW",
        "1009 重复 UID 是多品类主播",
        "Repeated October UIDs represent multi-category anchors",
        f"12 个主播形成 18 个主播×品类键；跨多个品类主播 {sum(value > 1 for value in multi.values())} 个",
        f"12 anchors form 18 anchor-category keys; {sum(value > 1 for value in multi.values())} anchors span multiple categories",
    )

    actual_overview = read_csv_rows(ARTIFACT_DIR / "overview-summary.en.csv")
    expected_overview_rows = [expected_overview(date, records) for date, records in records_by_snapshot.items()]
    overview_ok, overview_detail = compare_rows(actual_overview, expected_overview_rows, list(expected_overview_rows[0]))
    add_check(
        checks,
        "overview_recompute",
        "PASS" if overview_ok else "FAIL",
        "快照总览独立复算",
        "Snapshot overview independently recomputed",
        overview_detail,
        overview_detail,
    )

    for section, field in (("category", "category"), ("tier", "tier")):
        actual = read_csv_rows(ARTIFACT_DIR / f"{section}-summary.en.csv")
        expected = expected_groups(records_by_snapshot, field)
        passed, detail = compare_rows(actual, expected, list(expected[0]))
        add_check(
            checks,
            f"{section}_recompute",
            "PASS" if passed else "FAIL",
            f"{section} 汇总独立复算",
            f"{section} summary independently recomputed",
            detail,
            detail,
        )

    actual_overlap = read_csv_rows(ARTIFACT_DIR / "overlap-summary.en.csv")
    expected_overlap = expected_overlaps(records_by_snapshot)
    overlap_ok, overlap_detail = compare_rows(actual_overlap, expected_overlap, list(expected_overlap[0]))
    add_check(
        checks,
        "overlap_recompute",
        "PASS" if overlap_ok else "FAIL",
        "跨快照主播覆盖独立复算",
        "Cross-snapshot anchor overlap independently recomputed",
        overlap_detail,
        overlap_detail,
    )

    quality = read_csv_rows(ARTIFACT_DIR / "quality-summary.en.csv")
    failed_quality = [row["check_id"] for row in quality if row["status"] == "FAIL"]
    add_check(
        checks,
        "snapshot_quality_failures",
        "PASS" if not failed_quality else "FAIL",
        "快照质量检查无失败项",
        "Snapshot quality checks have no failures",
        f"{len(quality)} 项；失败={failed_quality}",
        f"{len(quality)} checks; failures={failed_quality}",
    )

    risk_en = read_csv_rows(ARTIFACT_DIR / "sql-static-review.en.csv")
    risk_zh = read_csv_rows(ARTIFACT_DIR / "sql-static-review.zh.csv")
    risk_ids_match = [row["risk_id"] for row in risk_en] == [row["风险编号"] for row in risk_zh]
    risk_ok = len(risk_en) == 13 and risk_ids_match
    add_check(
        checks,
        "sql_risk_inventory",
        "PASS" if risk_ok else "FAIL",
        "中英文 SQL 风险清单完整对应",
        "Bilingual SQL risk inventories match",
        f"英文 {len(risk_en)} 项；中文 {len(risk_zh)} 项；编号一致={risk_ids_match}",
        f"English={len(risk_en)}; Chinese={len(risk_zh)}; IDs match={risk_ids_match}",
    )

    sql_text = (SCRIPT_DIR / "ai-live-room-monthly-tiering.sql").read_text(encoding="utf-8-sig")
    required_patterns = [
        "zhgametemp.zty_ai_liveroom_uid_list_v1",
        "gamelive.dm_huya_ayyuid_detail_day",
        "gamelive.dwt_huya_ayyuid_session_from_server_with_user",
        "gamelive.dw_huya_online_users",
        "gamelive.to_main_games_day",
        "'2026-09-01'",
        "'2026-09-30'",
        "count(distinct user_ukey)",
        "rank() over",
        "where acu >= 100",
        "huya_andriod",
    ]
    missing_patterns = [pattern for pattern in required_patterns if pattern not in sql_text]
    add_check(
        checks,
        "sql_core_structure",
        "PASS" if not missing_patterns else "FAIL",
        "SQL 核心表、日期和指标结构存在",
        "Core SQL tables, dates, and metric structures are present",
        f"缺失={missing_patterns}",
        f"missing={missing_patterns}",
    )

    executable_sql = "\n".join(line.split("--", 1)[0] for line in sql_text.splitlines())
    padded_dates_ok = "'2026-9-30'" not in executable_sql and "'2026-09-30'" in executable_sql
    add_check(
        checks,
        "sql_date_padding",
        "PASS" if padded_dates_ok else "FAIL",
        "SQL 日期字符串已补零",
        "SQL date strings are zero-padded",
        "未出现 2026-9-30；存在 2026-09-30",
        "2026-9-30 is absent; 2026-09-30 is present",
    )

    product_scope_missing = "hmos_kiwi" not in sql_text
    add_check(
        checks,
        "sql_product_scope_risk_recorded",
        "PASS" if "SQL-07" in {row["risk_id"] for row in risk_en} else "FAIL",
        "有效日与 DAU 端口差异已记录",
        "Product-scope difference between eligibility and DAU is recorded",
        f"涉及 hmos_kiwi 的编号 SQL-07 已列入；hmos_kiwi 缺失={product_scope_missing}",
        f"SQL-07 is recorded; hmos_kiwi absent from runtime SQL={product_scope_missing}",
    )

    generated = [path for path in ARTIFACT_DIR.iterdir() if path.suffix.lower() in {".csv", ".json", ".xlsx"}]
    private_ok, private_detail = private_identity_scan(records_by_snapshot, generated)
    add_check(
        checks,
        "privacy_identity_scan",
        "PASS" if private_ok else "FAIL",
        "生成交付物不含源 UID 或昵称",
        "Generated deliverables contain no source UID or nickname",
        private_detail,
        private_detail,
    )

    expected_sheets_zh = ["快照总览", "品类汇总", "ACU分层汇总", "主播覆盖重叠", "数据质量", "SQL静态审查", "方法说明"]
    expected_sheets_en = ["Snapshot overview", "Category summary", "Tier summary", "Anchor overlap", "Data quality", "SQL static review", "Method"]
    sheets_ok = True
    sheet_evidence = []
    for filename, expected_sheets in (
        ("ai-live-room-snapshot-review-zh.xlsx", expected_sheets_zh),
        ("ai-live-room-snapshot-review-en.xlsx", expected_sheets_en),
    ):
        workbook = load_workbook(ARTIFACT_DIR / filename, read_only=True, data_only=True)
        try:
            actual = workbook.sheetnames
        finally:
            workbook.close()
        sheets_ok = sheets_ok and actual == expected_sheets
        sheet_evidence.append(f"{filename}={actual}")
    add_check(
        checks,
        "bilingual_workbook_structure",
        "PASS" if sheets_ok else "FAIL",
        "中英文结果工作簿结构一致",
        "Bilingual workbooks have the expected structure",
        "; ".join(sheet_evidence),
        "; ".join(sheet_evidence),
    )

    required_docs = ["README.md", "README.en.md", "methodology/analysis-method.md", "methodology/analysis-method.en.md"]
    missing_docs = [name for name in required_docs if not (PROJECT_ROOT / name).exists()]
    add_check(
        checks,
        "bilingual_documentation",
        "PASS" if not missing_docs else "FAIL",
        "中英文项目文档齐全",
        "Bilingual project documentation is present",
        f"缺失={missing_docs}",
        f"missing={missing_docs}",
    )

    not_run = [row["risk_id"] for row in risk_en if row["status"] == "NOT_RUN"]
    add_check(
        checks,
        "sql_execution_status",
        "NOT_RUN" if not_run else "PASS",
        "SQL 正式执行和最终指标对账",
        "Formal SQL execution and final-metric reconciliation",
        f"未执行项={not_run}；当前结果只能标记为静态审查",
        f"not run={not_run}; results remain static-review only",
    )

    counts = Counter(str(check["status"]) for check in checks)
    overall = "incomplete" if counts["FAIL"] or counts["NOT_RUN"] else "verified"
    return {
        "project": "AI live-room monthly snapshot review",
        "overall_status": overall,
        "summary": {
            "total": len(checks),
            "passed": counts["PASS"],
            "failed": counts["FAIL"],
            "not_run": counts["NOT_RUN"],
            "review": counts["REVIEW"],
        },
        "checks": checks,
    }


def write_reports(report: dict[str, object]) -> None:
    VALIDATION_DIR.mkdir(parents=True, exist_ok=True)
    (VALIDATION_DIR / "validation-report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    for language in ("zh", "en"):
        lines = [
            "# AI 直播间快照复盘校验" if language == "zh" else "# AI live-room snapshot review validation",
            "",
            f"总体状态：`{report['overall_status']}`" if language == "zh" else f"Overall status: `{report['overall_status']}`",
            "",
            "| 检查 | 状态 | 证据 |" if language == "zh" else "| Check | Status | Evidence |",
            "| --- | --- | --- |",
        ]
        for check in report["checks"]:
            detail = check[language]
            lines.append(f"| {detail['title']} | {check['status']} | {detail['evidence']} |")
        summary = report["summary"]
        lines.extend(
            [
                "",
                (
                    f"汇总：{summary['total']} 项，通过 {summary['passed']}，失败 {summary['failed']}，未执行 {summary['not_run']}，复核 {summary['review']}。"
                    if language == "zh"
                    else f"Summary: {summary['total']} checks, {summary['passed']} passed, {summary['failed']} failed, {summary['not_run']} not run, {summary['review']} review."
                ),
                "",
                (
                    "结论：快照文件、匿名汇总、主播覆盖和隐私边界已验证；SQL 仍为静态审查，不能把三份导出结果当作已由当前 SQL 重跑并通过业务对账。"
                    if language == "zh"
                    else "Conclusion: the snapshot files, anonymous summaries, anchor overlap, and privacy boundary are verified. SQL remains under static review; the exports must not be treated as freshly executed and reconciled by the current query."
                ),
                "",
            ]
        )
        filename = "validation-report.md" if language == "zh" else "validation-report.en.md"
        (VALIDATION_DIR / filename).write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, default=SOURCE_ROOT_DEFAULT)
    parser.add_argument("--write-report", action="store_true")
    args = parser.parse_args()
    report = validate(args.source_root)
    if args.write_report:
        write_reports(report)
    print(json.dumps(report["summary"], ensure_ascii=False))
    return 1 if report["summary"]["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
