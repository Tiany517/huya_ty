#!/usr/bin/env python3
"""Validate the migrated user-profile project against repository artifacts.

Without --source-dir, the script validates the committed aggregate package and
marks source-dependent checks as not_run. With --source-dir, it also verifies
hashes, source row counts, workbook samples, report defects, and SQL copies.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import zipfile
from pathlib import Path

import pandas as pd
from docx import Document
from openpyxl import load_workbook


PROJECT_ROOT = Path(__file__).resolve().parents[1]
ARTIFACT_ROOT = PROJECT_ROOT / "artifacts" / "anonymous-summary"
REPORT_JSON = PROJECT_ROOT / "artifacts" / "validation-report.json"


TGI_SPECS = {
    "tgi/device-all-pairs.csv": {
        "pcols": ["鸿蒙%", "苹果%"],
        "ncols": ["鸿蒙人数", "苹果人数"],
        "totals": [172312, 145179],
    },
    "tgi/device-harmony-vs-ios.csv": {
        "pcols": ["鸿蒙%", "苹果%"],
        "ncols": ["鸿蒙人数", "苹果人数"],
        "totals": [172312, 145179],
    },
    "tgi/device-harmony-vs-android.csv": {
        "pcols": ["鸿蒙%", "安卓%"],
        "ncols": ["鸿蒙人数", "安卓人数"],
        "totals": [172312, 390718],
    },
    "tgi/device-android-vs-ios.csv": {
        "pcols": ["安卓%", "苹果%"],
        "ncols": ["安卓人数", "苹果人数"],
        "totals": [390718, 145179],
    },
    "tgi/snooker-watchers-v2.csv": {
        "pcols": ["目标组%", "对照组%"],
        "ncols": ["目标组人数", "对照组人数"],
        "totals": [1072, 2676],
    },
    "tgi/world-championship-watchers.csv": {
        "pcols": ["目标组%", "对照组%"],
        "ncols": ["目标组人数", "对照组人数"],
        "totals": [208206, 366543],
    },
    "tgi/world-championship-viewers-10min.csv": {
        "pcols": ["目标组%", "对照组%"],
        "ncols": ["目标组人数", "对照组人数"],
        "totals": [192764, 395788],
    },
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def check(checks: list[dict[str, object]], name: str, status: str, details: str) -> None:
    if status not in {"pass", "fail", "known_issue", "not_run"}:
        raise ValueError(status)
    checks.append({"check": name, "status": status, "details": details})


def validate_tgi(checks: list[dict[str, object]]) -> None:
    for relative, spec in TGI_SPECS.items():
        path = ARTIFACT_ROOT / relative
        if not path.exists():
            check(checks, f"TGI artifact exists: {relative}", "fail", "File is missing")
            continue
        frame = pd.read_csv(path, encoding="utf-8-sig")
        group_ok = True
        max_pct_error = 0.0
        max_tgi_error = 0.0
        if relative == "tgi/device-all-pairs.csv":
            comparison_specs = {
                "鸿蒙 vs 苹果": ([172312, 145179], ["鸿蒙%", "苹果%"], ["鸿蒙人数", "苹果人数"]),
                "鸿蒙 vs 安卓": ([172312, 390718], ["鸿蒙%", "安卓%"], ["鸿蒙人数", "安卓人数"]),
                "安卓 vs 苹果": ([390718, 145179], ["安卓%", "苹果%"], ["安卓人数", "苹果人数"]),
            }
            for comparison, comparison_frame in frame.groupby("对比", sort=False):
                totals, pcols, ncols = comparison_specs[comparison]
                for _, group in comparison_frame.groupby("维度", sort=False):
                    total_1 = int(pd.to_numeric(group[ncols[0]], errors="coerce").fillna(0).sum())
                    total_2 = int(pd.to_numeric(group[ncols[1]], errors="coerce").fillna(0).sum())
                    if (total_1, total_2) != tuple(totals):
                        group_ok = False
                    max_pct_error = max(
                        max_pct_error,
                        abs(float(group[pcols[0]].fillna(0).sum()) - 100.0),
                        abs(float(group[pcols[1]].fillna(0).sum()) - 100.0),
                    )
                pct_1 = pd.to_numeric(comparison_frame[pcols[0]], errors="coerce")
                pct_2 = pd.to_numeric(comparison_frame[pcols[1]], errors="coerce")
                actual_tgi = pd.to_numeric(comparison_frame["TGI"], errors="coerce")
                comparable = actual_tgi.notna() & pct_2.gt(0)
                calculated = pct_1 / pct_2 * 100
                if comparable.any():
                    max_tgi_error = max(
                        max_tgi_error,
                        float((actual_tgi[comparable] - calculated[comparable]).abs().max()),
                    )
            denominator_label = "three pairwise denominators"
        else:
            pc1, pc2 = spec["pcols"]
            nc1, nc2 = spec["ncols"]
            expected_total_1, expected_total_2 = spec["totals"]
            for _, group in frame.groupby("维度", sort=False):
                total_1 = int(pd.to_numeric(group[nc1], errors="coerce").fillna(0).sum())
                total_2 = int(pd.to_numeric(group[nc2], errors="coerce").fillna(0).sum())
                if total_1 != expected_total_1 or total_2 != expected_total_2:
                    group_ok = False
                pct_errors = [
                    abs(float(group[pc1].fillna(0).sum()) - 100.0),
                    abs(float(group[pc2].fillna(0).sum()) - 100.0),
                ]
                max_pct_error = max(max_pct_error, *pct_errors)
            pct_1 = pd.to_numeric(frame[pc1], errors="coerce")
            pct_2 = pd.to_numeric(frame[pc2], errors="coerce")
            actual_tgi = pd.to_numeric(frame["TGI"], errors="coerce")
            comparable = actual_tgi.notna() & pct_2.gt(0)
            calculated = pct_1 / pct_2 * 100
            max_tgi_error = float((actual_tgi[comparable] - calculated[comparable]).abs().max())
            denominator_label = f"{expected_total_1:,}/{expected_total_2:,}"
        check(
            checks,
            f"TGI dimension denominators: {relative}",
            "pass" if group_ok else "fail",
            f"Every dimension sums to {denominator_label}: {group_ok}",
        )
        check(
            checks,
            f"TGI percentage closure: {relative}",
            "pass" if max_pct_error <= 0.10 else "fail",
            f"Maximum per-dimension 100% closure error is {max_pct_error:.4f} pp",
        )
        check(
            checks,
            f"TGI arithmetic: {relative}",
            "pass" if max_tgi_error <= 0.16 else "fail",
            f"Maximum rounded-percentage arithmetic difference is {max_tgi_error:.4f}",
        )

    for cn_path in sorted((ARTIFACT_ROOT / "tgi").glob("*.csv")):
        if cn_path.name.endswith(".en.csv"):
            continue
        en_path = cn_path.with_name(cn_path.stem + ".en.csv")
        if not en_path.exists():
            check(checks, f"Bilingual TGI pair: {cn_path.name}", "fail", "English CSV is missing")
            continue
        cn = pd.read_csv(cn_path, encoding="utf-8-sig")
        en = pd.read_csv(en_path, encoding="utf-8-sig")
        same_shape = cn.shape == en.shape
        check(
            checks,
            f"Bilingual TGI pair: {cn_path.name}",
            "pass" if same_shape else "fail",
            f"Chinese {cn.shape}; English {en.shape}",
        )


def validate_clusters(checks: list[dict[str, object]]) -> None:
    device = pd.read_csv(ARTIFACT_ROOT / "clusters/device-groups.csv", encoding="utf-8-sig")
    check(
        checks,
        "Device cluster sample shares",
        "pass"
        if len(device) == 12
        and device.groupby("用户组")["聚类人数"].sum().eq(50000).all()
        and device.groupby("用户组")["组内占比%"].sum().sub(100).abs().max() <= 0.011
        else "fail",
        "Three groups, four clusters each, 50,000 sampled users per group",
    )

    world = pd.read_csv(ARTIFACT_ROOT / "clusters/world-championship-10min.csv", encoding="utf-8-sig")
    check(
        checks,
        "World-championship 10-minute cluster sample shares",
        "pass"
        if len(world) == 4
        and int(world["聚类人数"].sum()) == 50000
        and abs(float(world["组内占比%"].sum()) - 100.0) <= 0.01
        else "fail",
        f"Cluster total {int(world['聚类人数'].sum()):,}; share sum {world['组内占比%'].sum():.2f}%",
    )

    processed = pd.read_csv(
        ARTIFACT_ROOT / "clusters/snooker-unreconciled-cluster-generation.csv",
        encoding="utf-8-sig",
    )
    check(
        checks,
        "Unreconciled snooker cluster generation is labelled",
        "pass"
        if len(processed) == 4
        and int(processed["行数"].sum()) == 1086
        and processed["可复现状态"].eq("与报告聚类不可勾稽").all()
        else "fail",
        "1,086 rows, 1,074 unique identifiers, separate from the report's 1,072-user clustering",
    )
    check(
        checks,
        "Snooker report clustering reproducible from retained files",
        "known_issue",
        "The retained processed sample has 1,086 rows and 1,074 unique identifiers, while the report says n=1,072; cluster labels also differ",
    )

    kmeans = pd.read_csv(
        ARTIFACT_ROOT / "clusters/world-championship-10min-kmeans.csv",
        encoding="utf-8-sig",
    )
    kmeans_k4 = kmeans.loc[pd.to_numeric(kmeans["K"], errors="coerce").eq(4)].iloc[0]
    check(
        checks,
        "World-championship 10-minute K=4 evaluation",
        "pass" if abs(float(kmeans_k4["轮廓系数"]) - 0.1434) < 1e-12 else "fail",
        f"K=4 silhouette coefficient is {kmeans_k4['轮廓系数']} (weak structure)",
    )

    price = pd.read_csv(
        ARTIFACT_ROOT / "clusters/world-championship-10min-device-price-tiers.csv",
        encoding="utf-8-sig",
    )
    target_total = int(pd.to_numeric(price["目标组人数"], errors="coerce").sum())
    control_total = int(pd.to_numeric(price["对照组人数"], errors="coerce").sum())
    check(
        checks,
        "World-championship device-price tier denominators",
        "pass" if (target_total, control_total) == (192764, 395788) else "fail",
        f"Tier totals reconcile to {target_total:,}/{control_total:,}",
    )


def validate_privacy(checks: list[dict[str, object]]) -> None:
    identifier_pattern = re.compile(r"mobile/[0-9a-fA-F]{16,}")
    violations: list[str] = []
    for suffix in ("*.csv", "*.json", "*.md"):
        for path in PROJECT_ROOT.rglob(suffix):
            if ".git" in path.parts:
                continue
            text = path.read_text(encoding="utf-8-sig", errors="ignore")
            if identifier_pattern.search(text):
                violations.append(str(path.relative_to(PROJECT_ROOT)))
            if suffix == "*.csv" and "user_ukey" in text.splitlines()[0]:
                violations.append(str(path.relative_to(PROJECT_ROOT)))
    check(
        checks,
        "No user identifier values in committed text artifacts",
        "pass" if not violations else "fail",
        "No identifier-like values or user_ukey CSV headers found" if not violations else "; ".join(violations),
    )

    docx_violations: list[str] = []
    for path in (PROJECT_ROOT / "reports").glob("*.docx"):
        with zipfile.ZipFile(path) as bundle:
            for name in bundle.namelist():
                if not name.endswith(".xml"):
                    continue
                payload = bundle.read(name).decode("utf-8", errors="ignore")
                if identifier_pattern.search(payload):
                    docx_violations.append(f"{path.name}:{name}")
    check(
        checks,
        "No user identifier values embedded in retained DOCX files",
        "pass" if not docx_violations else "fail",
        "No mobile/hash user identifiers found in report XML" if not docx_violations else "; ".join(docx_violations),
    )


def validate_sql_audit(checks: list[dict[str, object]]) -> None:
    path = ARTIFACT_ROOT / "sql-static-audit.csv"
    frame = pd.read_csv(path, encoding="utf-8-sig")
    check(
        checks,
        "Static SQL audit coverage",
        "pass" if len(frame) == 8 and frame["状态"].eq("失败").sum() == 7 and frame["状态"].eq("未执行").sum() == 1 else "fail",
        f"{len(frame)} checks: {(frame['状态'] == '失败').sum()} expected defects and {(frame['状态'] == '未执行').sum()} unit-semantic check",
    )
    required_checks = {
        "产品枚举拼写",
        "用户级画像归属",
        "比较窗口",
        "CTE 定义",
        "指标定义",
        "分组标签",
    }
    present = set(frame["检查项"])
    check(
        checks,
        "Critical SQL defect patterns are explicitly recorded",
        "pass" if required_checks.issubset(present) else "fail",
        f"Present: {', '.join(sorted(required_checks & present))}",
    )
    check(
        checks,
        "watch_duration unit and event source semantics confirmed",
        "not_run",
        "The source table lacks a retained field dictionary; no size, product-day sum or unit rule is assumed",
    )


def validate_source(source_dir: Path, checks: list[dict[str, object]]) -> None:
    manifest_path = ARTIFACT_ROOT / "source-manifest.csv"
    manifest = pd.read_csv(manifest_path, encoding="utf-8-sig")
    missing: list[str] = []
    hash_mismatch: list[str] = []
    for row in manifest.itertuples(index=False):
        source_path = source_dir / row.来源相对路径
        if not source_path.exists():
            missing.append(row.来源相对路径)
            continue
        if sha256(source_path) != row.SHA256:
            hash_mismatch.append(row.来源相对路径)
    check(
        checks,
        "Source-manifest coverage and hashes",
        "pass" if len(manifest) == 151 and not missing and not hash_mismatch else "fail",
        f"Manifest rows {len(manifest)}; missing {len(missing)}; hash mismatches {len(hash_mismatch)}",
    )
    classifications = manifest["分类"].value_counts().to_dict()
    expected = {
        "included_sql": 3,
        "included_report": 4,
        "included_aggregate": 7,
        "excluded_user_level": 2,
        "excluded_workbook": 2,
        "excluded_generated_chart": 132,
        "excluded_duplicate": 1,
    }
    check(
        checks,
        "Source classification counts",
        "pass" if classifications == expected else "fail",
        json.dumps(classifications, ensure_ascii=False, sort_keys=True),
    )

    copied_sql = {path.name: path for path in (PROJECT_ROOT / "sql").glob("*.sql")}
    sql_ok = True
    for name, copied in copied_sql.items():
        source = source_dir / "用户画像取数" / name
        if not source.exists() or sha256(source) != sha256(copied):
            sql_ok = False
    check(
        checks,
        "SQL copies match source files",
        "pass" if sql_ok and len(copied_sql) == 3 else "fail",
        f"Retained SQL files: {', '.join(sorted(copied_sql))}",
    )

    raw_device_path = source_dir / "苹果安卓鸿蒙用户用户画像" / "各设备用户画像数据.csv"
    raw_device = pd.read_csv(raw_device_path, encoding="utf-8-sig", dtype=str, keep_default_na=False)
    os_counts = raw_device["device_os"].value_counts().to_dict()
    device_facts = {
        "rows": len(raw_device),
        "unique_users": int(raw_device["user_ukey"].nunique()),
        "duplicate_rows": len(raw_device) - int(raw_device["user_ukey"].nunique()),
        "os_counts": os_counts,
    }
    check(
        checks,
        "Raw device CSV cannot reproduce the three-group source snapshot",
        "known_issue"
        if device_facts["rows"] == 178432
        and device_facts["unique_users"] == 178244
        and os_counts == {"IOS": 178412, "Android": 20}
        else "fail",
        json.dumps(device_facts, ensure_ascii=False, sort_keys=True),
    )

    processed = pd.read_csv(
        source_dir / "snooker_charts_V2" / "processed_data_v2.csv",
        encoding="utf-8-sig",
    )
    processed_identifier = processed.columns[0]
    check(
        checks,
        "Snooker processed sample grain differs from report",
        "known_issue"
        if len(processed) == 1086
        and processed[processed_identifier].nunique() == 1074
        else "fail",
        f"1,086 rows, 1,074 unique identifiers, 12 duplicate identifier rows; report n=1,072",
    )

    device_book = source_dir / "苹果安卓鸿蒙用户用户画像" / "鸿蒙安卓苹果三组用户画像对比分析数据.xlsx"
    wc_book = source_dir / "wc_10min_user_profile_analysis" / "世锦赛10分钟以上观看用户画像分析数据.xlsx"
    sample_counts: dict[str, int] = {}
    duplicate_counts: dict[str, int] = {}
    for sheet in ("鸿蒙聚类标签", "安卓聚类标签", "苹果聚类标签", "目标组聚类标签"):
        book = wc_book if sheet == "目标组聚类标签" else device_book
        workbook = load_workbook(book, read_only=True, data_only=True)
        worksheet = workbook[sheet]
        identifiers = set()
        rows = 0
        for row_no, row in enumerate(worksheet.iter_rows(min_row=2, values_only=True), start=2):
            if not row or row[0] in (None, ""):
                continue
            rows += 1
            identifiers.add(str(row[0]))
        workbook.close()
        sample_counts[sheet] = rows
        duplicate_counts[sheet] = rows - len(identifiers)
    check(
        checks,
        "Cluster-label sample uniqueness",
        "pass"
        if sample_counts == {
            "鸿蒙聚类标签": 50000,
            "安卓聚类标签": 50000,
            "苹果聚类标签": 50000,
            "目标组聚类标签": 50000,
        }
        and not any(duplicate_counts.values())
        else "fail",
        f"Rows {sample_counts}; duplicate identifier rows {duplicate_counts}",
    )

    legacy_text = "\n".join(p.text for p in Document(PROJECT_ROOT / "reports/device-profile-three-groups-legacy.docx").paragraphs)
    root_text = "\n".join(p.text for p in Document(PROJECT_ROOT / "reports/snooker-world-championship-tgi.docx").paragraphs)
    wc_text = "\n".join(p.text for p in Document(PROJECT_ROOT / "reports/world-championship-viewers-10min.docx").paragraphs)
    legacy_100_count = len(re.findall(r"\(100\.0%\)", legacy_text))
    check(
        checks,
        "Legacy device report cluster-share defect detected",
        "known_issue" if legacy_100_count == 12 else "fail",
        f"Twelve sampled clusters are printed as 100.0%; corrected shares are retained in the anonymous cluster table",
    )
    root_cohort_arithmetic = 1072 + 2676
    check(
        checks,
        "Snooker report record-count inconsistency detected",
        "known_issue"
        if "3,767条用户记录" in root_text and root_cohort_arithmetic == 3748
        else "fail",
        "Report says 3,767 records, while retained TGI denominators total 3,748 users",
    )
    check(
        checks,
        "Snooker report App-share inconsistency detected",
        "known_issue" if "63.1%" in root_text and "56.2%" in root_text else "fail",
        "The retained TGI table shows music 56.25%; another report narrative says 63.1%",
    )
    check(
        checks,
        "World-championship report confuses 10-minute viewers with new users",
        "known_issue"
        if "世锦赛作为拉新渠道有效吸引了192,764名用户" in wc_text
        else "fail",
        "192,764 is the 10-minute-viewer cohort, not a new-user cohort",
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path)
    parser.add_argument("--write-report", action="store_true")
    args = parser.parse_args()

    checks: list[dict[str, object]] = []
    validate_tgi(checks)
    validate_clusters(checks)
    validate_privacy(checks)
    validate_sql_audit(checks)

    if args.source_dir:
        source_dir = args.source_dir.resolve()
        if not source_dir.is_dir():
            raise SystemExit(f"Source directory does not exist: {source_dir}")
        validate_source(source_dir, checks)
    else:
        for name in (
            "Source-manifest coverage and hashes",
            "Source classification counts",
            "SQL copies match source files",
            "Raw device CSV cannot reproduce the three-group source snapshot",
            "Snooker processed sample grain differs from report",
            "Cluster-label sample uniqueness",
            "Legacy device report cluster-share defect detected",
            "Snooker report record-count inconsistency detected",
            "Snooker report app-share inconsistency detected",
            "World-championship report confuses 10-minute viewers with new users",
        ):
            check(checks, name, "not_run", "No --source-dir was supplied")

    failures = sum(item["status"] == "fail" for item in checks)
    not_run = sum(item["status"] == "not_run" for item in checks)
    known_issues = sum(item["status"] == "known_issue" for item in checks)
    passes = sum(item["status"] == "pass" for item in checks)
    overall = "failed" if failures else ("incomplete" if not_run else "complete_with_known_issues")
    report = {
        "project": "user-profile-analysis",
        "overall_status": overall,
        "summary": {
            "checks": len(checks),
            "passed": passes,
            "known_issues": known_issues,
            "not_run": not_run,
            "failed": failures,
        },
        "checks": checks,
    }
    output = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.write_report:
        REPORT_JSON.parent.mkdir(parents=True, exist_ok=True)
        REPORT_JSON.write_text(output, encoding="utf-8")
    print(output)
    raise SystemExit(1 if failures else 0)


if __name__ == "__main__":
    main()
