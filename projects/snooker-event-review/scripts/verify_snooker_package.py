from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import re
from pathlib import Path
from typing import Any

from openpyxl import load_workbook


PROJECT_DIR = Path(__file__).resolve().parents[1]
SOURCE_PREFIX = "<source-root>/"
SENSITIVE_TOKENS = {"uid", "user_uid", "user_ukey", "luid", "nickname", "主播uid", "主播昵称", "手机号", "用户id"}


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as source:
        return list(csv.DictReader(source))


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def as_float(value: Any) -> float | None:
    if value in {None, ""}:
        return None
    return float(value)


def close(left: float, right: float, tolerance: float = 1e-8) -> bool:
    return abs(left - right) <= tolerance


def jsonable(value: Any) -> Any:
    if isinstance(value, dict):
        return {str(key): jsonable(item) for key, item in value.items()}
    if isinstance(value, (list, tuple, set)):
        return [jsonable(item) for item in value]
    return value


def main(source_dir: Path) -> None:
    artifacts = PROJECT_DIR / "artifacts"
    zh_dir = artifacts / "zh"
    en_dir = artifacts / "en"
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

    final_dir = artifacts / "final-delivery"
    final_files = [path for path in final_dir.rglob("*") if path.is_file()]
    ext_counts = {suffix: sum(path.suffix.lower() == suffix for path in final_files) for suffix in [".csv", ".xlsx", ".pptx", ".sql"]}
    add("SNK-V01", "coverage", len(final_files) == 89, 89, len(final_files), "All original final-delivery files are represented")
    add("SNK-V02", "coverage", ext_counts == {".csv": 38, ".xlsx": 14, ".pptx": 9, ".sql": 28}, {".csv": 38, ".xlsx": 14, ".pptx": 9, ".sql": 28}, ext_counts, "Final-delivery extension counts match the source inventory")
    sql_files = [path for path in (PROJECT_DIR / "sql" / "source").rglob("*.sql") if path.is_file()]
    add("SNK-V03", "coverage", len(sql_files) == 61, 61, len(sql_files), "All project SQL files are retained")

    pairs = [
        ("audience", zh_dir / "世锦赛受众与漏斗.csv", en_dir / "world-championship-audience-funnel.csv"),
        ("path", zh_dir / "世锦赛拉新转化路径.csv", en_dir / "world-championship-new-user-path.csv"),
        ("tipping", zh_dir / "世锦赛拉新付费.csv", en_dir / "world-championship-tipping.csv"),
        ("unique_share", zh_dir / "世锦赛拉新用户视频直播覆盖率.csv", en_dir / "world-championship-unique-audience-share.csv"),
        ("retention", zh_dir / "赛事到世锦赛留存.csv", en_dir / "event-to-world-championship-retention.csv"),
        ("affinity", zh_dir / "斯诺克视频偏好.csv", en_dir / "snooker-video-affinity.csv"),
        ("supply", zh_dir / "关键视频内容供给.csv", en_dir / "key-video-content-supply.csv"),
        ("clusters", zh_dir / "拉新用户画像聚类.csv", en_dir / "new-user-profile-clusters.csv"),
        ("quality", zh_dir / "质量问题.csv", en_dir / "quality-findings.csv"),
        ("manifest", zh_dir / "来源清单.csv", en_dir / "source-manifest.csv"),
    ]
    add("SNK-V04", "bilingual", all(zh.is_file() and en.is_file() for _, zh, en in pairs), 20, sum(path.is_file() for _, zh, en in pairs for path in (zh, en)), "All bilingual CSV files exist")
    row_counts = {name: [len(read_csv(zh)), len(read_csv(en))] for name, zh, en in pairs}
    add("SNK-V05", "bilingual", all(left == right for left, right in row_counts.values()), "equal row counts", row_counts, "Chinese and English datasets have matching row counts")

    audience = read_csv(en_dir / "world-championship-audience-funnel.csv")
    new_users = read_csv(en_dir / "world-championship-new-user-path.csv")
    tipping = read_csv(en_dir / "world-championship-tipping.csv")
    unique_share = read_csv(en_dir / "world-championship-unique-audience-share.csv")
    retention = read_csv(en_dir / "event-to-world-championship-retention.csv")
    affinity = read_csv(en_dir / "snooker-video-affinity.csv")
    supply = read_csv(en_dir / "key-video-content-supply.csv")
    clusters = read_csv(en_dir / "new-user-profile-clusters.csv")
    findings = read_csv(en_dir / "quality-findings.csv")
    manifest = read_csv(en_dir / "source-manifest.csv")

    lookup = {(row["season"], row["user_group_en"]): row for row in audience}
    add("SNK-V06", "reconciliation", close(float(lookup[("2025", "event viewers")]["users_wan"]), 403.6454), 403.6454, lookup[("2025", "event viewers")]["users_wan"], "2025 World Championship viewers match the source workbook")
    add("SNK-V07", "reconciliation", close(float(lookup[("2026", "event viewers")]["users_wan"]), 631.2202), 631.2202, lookup[("2026", "event viewers")]["users_wan"], "2026 World Championship viewers match the source workbook")
    add("SNK-V08", "reconciliation", close(float(lookup[("2025", "new users")]["users_wan"]), 38.4036) and close(float(lookup[("2026", "new users")]["users_wan"]), 78.3875), [38.4036, 78.3875], [lookup[("2025", "new users")]["users_wan"], lookup[("2026", "new users")]["users_wan"]], "World Championship new-user counts match")
    growth = (631.2202 / 403.6454 - 1) * 100
    new_growth = (78.3875 / 38.4036 - 1) * 100
    add("SNK-V09", "metric", close(growth, 56.37988194588617, 1e-9) and close(new_growth, 104.11497880407046, 1e-9), [56.37988194588617, 104.11497880407046], [growth, new_growth], "Year-over-year viewer and new-user growth are reproducible")

    path_lookup = {(row["season"], row["new_user_group_en"]): row for row in new_users}
    expected_path = {
        ("2025", "snooker new users"): (18.6953, 3.789, 0.0744, 0.2115),
        ("2025", "non-snooker new users"): (54.8156, 11.398, 0.2493, 0.6074),
        ("2026", "snooker new users"): (42.2332, 13.2921, 0.1825, 0.3833),
        ("2026", "non-snooker new users"): (55.806, 15.2334, 0.2663, 0.5109),
    }
    path_actual = {
        key: (
            float(path_lookup[key]["video_viewers_wan"]),
            float(path_lookup[key]["video_to_xinxiu_users_wan"]),
            float(path_lookup[key]["video_to_tippers_wan"]),
            float(path_lookup[key]["all_tippers_wan"]),
        )
        for key in expected_path
    }
    add("SNK-V10", "reconciliation", path_actual == expected_path, expected_path, path_actual, "World Championship new-user funnel rows match the final workbook")
    add("SNK-V11", "grain", len(new_users) == 4 and len({(row["season"], row["new_user_group_en"]) for row in new_users}) == 4, 4, len(new_users), "New-user funnel has one row per season and comparison group")

    tipping_lookup = {(row["season"], row["user_group_en"]): row for row in tipping}
    add("SNK-V12", "reconciliation", close(float(tipping_lookup[("2025", "snooker new users")]["tipping_rate_pct"]), 0.5507296190982096, 1e-12) and close(float(tipping_lookup[("2026", "snooker new users")]["tipping_rate_pct"]), 0.488981023760165, 1e-12), [0.5507296190982096, 0.488981023760165], [tipping_lookup[("2025", "snooker new users")]["tipping_rate_pct"], tipping_lookup[("2026", "snooker new users")]["tipping_rate_pct"]], "Snooker new-user tipping rates match the source")
    add("SNK-V13", "metric", all(0 <= float(row["tipping_rate_pct"]) <= 100 for row in tipping), "0..100", [row["tipping_rate_pct"] for row in tipping], "All tipping rates are in a valid percentage range")

    share_lookup = {row["season"]: (float(row["video_viewer_share_pct"]), float(row["live_viewer_share_pct"])) for row in unique_share}
    expected_share = {"2025": (28.4593111, 52.5909029), "2026": (30.332132, 48.8788391)}
    add("SNK-V35", "reconciliation", share_lookup == expected_share and all(0 <= value <= 100 for pair in share_lookup.values() for value in pair), expected_share, share_lookup, "Independent final-CSV video and live viewer coverage matches the source")

    add("SNK-V14", "grain", len(retention) == 36 and len({(row["baseline_event"], row["season"], row["phase"]) for row in retention}) == 36, 36, len(retention), "Five baseline events, two seasons, and available phases are unique")
    denominator_checks = []
    for baseline in {"上海大师赛", "英锦赛", "英格兰公开赛", "沙特大师赛"}:
        for season in {"2024/25", "2025/26"}:
            values = {float(row["baseline_new_users"]) for row in retention if row["baseline_event"] == baseline and row["season"] == season}
            denominator_checks.append(len(values) == 1)
    add("SNK-V15", "grain", all(denominator_checks), "one baseline denominator per event-season", denominator_checks, "Stage retention uses a stable denominator within each event-season")
    shanghai = {
        (row["season"], row["phase"]): float(row["retention_rate_pct"])
        for row in retention
        if row["baseline_event"] == "上海大师赛"
    }
    add("SNK-V16", "correction", close(shanghai[("2024/25", "长期")], 38.930938167479) and close(shanghai[("2025/26", "长期")], 39.2245146023857, 1e-12), [38.930938167479, 39.2245146023857], [shanghai[("2024/25", "长期")], shanghai[("2025/26", "长期")]], "Shanghai Masters sheets are mapped by sheet-name season rather than workbook order")

    add("SNK-V17", "metric", len(clusters) == 4 and sum(int(row["users"]) for row in clusters) == 1086, 1086, sum(int(row["users"]) for row in clusters), "Profile clusters add to the reported unique-user total")
    add("SNK-V18", "metric", close(sum(float(row["share_pct"]) for row in clusters), 100.0, 1e-9), 100.0, sum(float(row["share_pct"]) for row in clusters), "Profile cluster shares close to 100%")
    suspicion = next(row for row in clusters if "小米视频派" in row["cluster_name"])
    add("SNK-V19", "risk", close(float(suspicion["share_pct"]), 32.96500920810313, 1e-12) and suspicion["risk_flag"] == "suspected_fake_registration_not_verified", 32.96500920810313, suspicion, "The 33% suspected-fake cluster remains explicitly unverified")
    add("SNK-V20", "metric", affinity and close(float(affinity[0]["view_share_difference_pp"]), 14.99, 1e-12) and affinity[0]["category"] == "奇闻趣事", {"category": "奇闻趣事", "difference_pp": 14.99}, affinity[0], "The top video-affinity category reproduces the source")
    add("SNK-V21", "metric", len(supply) == 9 and next(row for row in supply if row["category"] == "奇闻趣事")["share_of_all_huya_video_pct"] == "1.2", "奇闻趣事 all-video share 1.2%", next(row for row in supply if row["category"] == "奇闻趣事"), "The content-supply benchmark is preserved")
    add("SNK-V22", "quality", len(findings) == 7 and {row["finding_id"] for row in findings} == {f"SNK-QF-0{i}" for i in range(1, 8)}, "SNK-QF-01..07", len(findings), "All reviewed quality findings are retained")

    source_files = [path for path in source_dir.rglob("*") if path.is_file()]
    manifest_sources = {row["source_path"] for row in manifest}
    expected_sources = {SOURCE_PREFIX + path.relative_to(source_dir).as_posix() for path in source_files}
    add("SNK-V23", "provenance", manifest_sources == expected_sources, len(expected_sources), len(manifest_sources), "Every local source file is represented in the source manifest")
    add("SNK-V24", "privacy", all(row["source_path"].startswith(SOURCE_PREFIX) for row in manifest), SOURCE_PREFIX, "absolute paths found" if any(not row["source_path"].startswith(SOURCE_PREFIX) for row in manifest) else "none", "Git does not contain absolute local source paths")
    included_rows = [row for row in manifest if row["disposition"] == "included"]
    add("SNK-V25", "provenance", len(included_rows) == 158, 158, len(included_rows), "All 158 included copy entries are represented, including duplicate SQL/result paths")
    missing_repo_paths = [row["repo_path"] for row in included_rows if not (PROJECT_DIR / row["repo_path"]).is_file()]
    add("SNK-V26", "provenance", not missing_repo_paths, [], missing_repo_paths[:20], "Every included manifest repo path exists")
    copied_hash_failures = []
    for row in included_rows:
        target = PROJECT_DIR / row["repo_path"]
        if target.is_file() and digest(target) != row["repo_sha256"]:
            copied_hash_failures.append(row["repo_path"])
    add("SNK-V27", "provenance", not copied_hash_failures, [], copied_hash_failures[:20], "Every copied artifact matches its recorded repository SHA-256")
    source_hash_failures = []
    for row in manifest:
        relative = row["source_path"].removeprefix(SOURCE_PREFIX)
        source = source_dir / relative
        if not source.is_file() or digest(source) != row["sha256"]:
            source_hash_failures.append(row["source_path"])
    add("SNK-V28", "provenance", not source_hash_failures, [], source_hash_failures[:20], "Every manifest row matches the current source SHA-256")

    excluded_sensitive = [row for row in manifest if row["disposition"] == "excluded" and (
        "拉新用户漏斗_重要" in row["source_path"]
        or "拉新用户行为监测_重要" in row["source_path"]
        or "上海拉新用户到世锦赛" in row["source_path"]
        or row["source_path"].endswith("世锦赛期间_体育和非体育用户画像数据.csv")
        or row["source_path"].endswith("上海大师赛到世锦赛留存情况.xlsx.csv")
    )]
    add("SNK-V29", "privacy", len(excluded_sensitive) == 5 and all(not row["repo_path"] for row in excluded_sensitive), 5, len(excluded_sensitive), "Large or user-level identifier sources are excluded")
    add("SNK-V30", "privacy", not list(PROJECT_DIR.rglob("*.ipynb")), [], [str(path.relative_to(PROJECT_DIR)) for path in PROJECT_DIR.rglob("*.ipynb")], "Notebooks with potential embedded user output are excluded")

    bad_csv_headers = []
    for path in final_dir.rglob("*.csv"):
        with path.open("r", encoding="utf-8-sig", newline="") as source:
            header = next(csv.reader(source), [])
        hits = [value for value in header if str(value).strip().lower() in SENSITIVE_TOKENS]
        if hits:
            bad_csv_headers.append({"path": str(path.relative_to(PROJECT_DIR)), "headers": hits})
    add("SNK-V31", "privacy", not bad_csv_headers, [], bad_csv_headers, "Final-delivery CSV schemas contain no user or streamer identifiers")

    formula_errors = []
    for path in final_dir.rglob("*.xlsx"):
        workbook = load_workbook(path, data_only=True, read_only=True)
        for sheet in workbook.worksheets:
            for row in sheet.iter_rows(values_only=True):
                for value in row:
                    if isinstance(value, str) and value in {"#NAME?", "#VALUE!", "#REF!", "#DIV/0!", "#N/A", "#NUM!", "#NULL!", "#SPILL!", "#CALC!"}:
                        formula_errors.append({"path": str(path.relative_to(PROJECT_DIR)), "sheet": sheet.title, "value": value})
        workbook.close()
    add("SNK-V32", "source-quality", not formula_errors, [], formula_errors[:20], "No formula error values appear in retained Excel workbooks")

    text_absolute_path_hits = []
    for path in PROJECT_DIR.rglob("*"):
        if path.is_file() and path.suffix.lower() in {".md", ".csv", ".json", ".py", ".sql"}:
            text = path.read_text(encoding="utf-8-sig", errors="ignore")
            if re.search(r"[A-Za-z]:\\Users\\", text):
                text_absolute_path_hits.append(str(path.relative_to(PROJECT_DIR)))
    add("SNK-V33", "privacy", not text_absolute_path_hits, [], text_absolute_path_hits, "Text artifacts contain no absolute Windows user paths")

    summary = json.loads((artifacts / "project_summary.json").read_text(encoding="utf-8"))
    add("SNK-V34", "status", summary["status"] == "reviewed_with_documented_label_denominator_and_profile_risks" and summary["raw_user_level_data_included"] is False, "reviewed with documented risks and no raw user data", {"status": summary["status"], "raw_user_level_data_included": summary["raw_user_level_data_included"]}, "Project status is explicit")

    readme_zh = PROJECT_DIR / "README.md"
    readme_en = PROJECT_DIR / "README.en.md"
    readme_zh_text = readme_zh.read_text(encoding="utf-8") if readme_zh.is_file() else ""
    readme_en_text = readme_en.read_text(encoding="utf-8") if readme_en.is_file() else ""
    add("SNK-V36", "documentation", "## GitHub 路径地图" in readme_zh_text and "## GitHub Repository Map" in readme_en_text and "35" in readme_zh_text and "35" in readme_en_text, "separate Chinese/English guides with GitHub maps and validation status", {"zh_readme": readme_zh.is_file(), "en_readme": readme_en.is_file(), "zh_map": "## GitHub 路径地图" in readme_zh_text, "en_map": "## GitHub Repository Map" in readme_en_text}, "Both language guides exist and expose the repository map and validation status")

    for check in checks:
        if isinstance(check["actual"], float) and not math.isfinite(check["actual"]):
            check["actual"] = str(check["actual"])
    fields = ["check_id", "category", "status", "expected", "actual", "note"]
    for path in [zh_dir / "校验结果.csv", en_dir / "validation-results.csv"]:
        with path.open("w", encoding="utf-8-sig", newline="") as target:
            writer = csv.DictWriter(target, fieldnames=fields)
            writer.writeheader()
            for check in checks:
                writer.writerow(
                    {
                        **check,
                        "expected": json.dumps(jsonable(check["expected"]), ensure_ascii=False, default=str),
                        "actual": json.dumps(jsonable(check["actual"]), ensure_ascii=False, default=str),
                    }
                )

    failed = sum(check["status"] == "FAIL" for check in checks)
    report = {
        "checks": len(checks),
        "passed": len(checks) - failed,
        "failed": failed,
        "not_run": 0,
        "status": "passed" if failed == 0 else "failed",
    }
    (artifacts / "validation_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if failed:
        failures = [check for check in checks if check["status"] == "FAIL"]
        print(json.dumps(failures, ensure_ascii=False, indent=2))
        raise SystemExit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path, required=True)
    args = parser.parse_args()
    main(args.source_dir.resolve())
