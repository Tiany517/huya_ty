#!/usr/bin/env python3
"""Validate the identifier-free reverse-poaching migration package."""

from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path

import pandas as pd


PROJECT_ROOT = Path(__file__).resolve().parents[1]
ARTIFACT_DIR = PROJECT_ROOT / "artifacts" / "anonymous-summary"
SCRIPT_DIR = PROJECT_ROOT / "scripts"
EXPECTED_ROWS = 34_309
EXPECTED_UNIQUE_ANCHORS = 26_015
EXPECTED_PLATFORM_ROWS = {"bilibili": 29_975, "douyu": 4_334}


def check(condition: bool, name_zh: str, name_en: str, value: object, expected: object = "constraint") -> dict[str, object]:
    return {
        "check_zh": name_zh,
        "check_en": name_en,
        "status": "pass" if condition else "fail",
        "value": value,
        "expected": expected,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write-report", action="store_true")
    parser.add_argument("--source-dir", type=Path, default=None)
    args = parser.parse_args()

    checks: list[dict[str, object]] = []
    profile_path = ARTIFACT_DIR / "summary-profile.json"
    profile = json.loads(profile_path.read_text(encoding="utf-8"))
    checks.append(check(profile["source_rows"] == EXPECTED_ROWS, "源记录数", "Source row count", profile["source_rows"], EXPECTED_ROWS))
    checks.append(check(profile["unique_anchor_ids"] == EXPECTED_UNIQUE_ANCHORS, "唯一主播ID数", "Unique anchor count", profile["unique_anchor_ids"], EXPECTED_UNIQUE_ANCHORS))
    checks.append(check(profile["platforms"] == EXPECTED_PLATFORM_ROWS, "平台记录数", "Platform row counts", profile["platforms"], EXPECTED_PLATFORM_ROWS))
    checks.append(check(profile["duplicate_uid_platform_category_rows"] == 0, "平台/品类主播键唯一", "Platform-category anchor-key uniqueness", profile["duplicate_uid_platform_category_rows"], 0))
    checks.append(check(not profile["raw_identifiers_exported"], "未导出原始标识", "No raw identifiers exported", profile["raw_identifiers_exported"], False))
    checks.append(check(not profile["raw_anchor_names_exported"], "未导出主播昵称", "No anchor names exported", profile["raw_anchor_names_exported"], False))
    checks.append(check(not profile["raw_user_level_rows_exported"], "未导出用户级明细", "No raw user-level rows exported", profile["raw_user_level_rows_exported"], False))

    required = [
        "platform-summary.csv",
        "platform-summary.en.csv",
        "platform-category-summary.csv",
        "platform-category-summary.en.csv",
        "huya-anchor-market-monthly.csv",
        "huya-anchor-market-monthly.en.csv",
        "summary-profile.json",
    ]
    missing = [name for name in required if not (ARTIFACT_DIR / name).is_file()]
    checks.append(check(not missing, "必需匿名输出存在", "Required anonymized artifacts exist", missing, []))

    platform = pd.read_csv(ARTIFACT_DIR / "platform-summary.csv")
    checks.append(check(int(platform["记录数"].sum()) == EXPECTED_ROWS, "平台汇总记录数合计", "Platform summary rows sum", int(platform["记录数"].sum()), EXPECTED_ROWS))
    checks.append(check(platform["预测ACU_P50"].ge(0).all(), "预测ACU中位数非负", "Predicted ACU medians are nonnegative", True, True))

    benchmark = pd.read_csv(ARTIFACT_DIR / "huya-anchor-market-monthly.csv")
    checks.append(check(len(benchmark) == 15, "虎牙基准月份数", "Huya benchmark month count", len(benchmark), 15))
    checks.append(check(benchmark["自然日观测数"].sum() == 438, "虎牙基准观测日数", "Huya benchmark day count", int(benchmark["自然日观测数"].sum()), 438))
    checks.append(check(benchmark["日均主播数"].gt(0).all(), "虎牙日均主播数为正", "Huya daily anchor counts are positive", True, True))

    reproducibility = pd.read_csv(ARTIFACT_DIR / "model-reproducibility.csv")
    status_counts = {str(key): int(value) for key, value in reproducibility["status"].value_counts().to_dict().items()}
    checks.append(check(len(reproducibility) == 10, "模型复现检查行数", "Model-reproducibility row count", len(reproducibility), 10))
    checks.append(check(int(status_counts.get("warning_version_drift", 0)) == 3, "记录三类版本漂移警告", "Three version-drift warnings recorded", status_counts, {"warning_version_drift": 3}))
    bili_laxin = reproducibility[
        (reproducibility["platform"] == "bilibili") & (reproducibility["metric"] == "predict_laxin")
    ].iloc[0]
    checks.append(check(int(bili_laxin["matching_rows"]) == 23_262, "B站拉新历史复现行数", "Bilibili acquisition historical matches", int(bili_laxin["matching_rows"]), 23_262))

    banned_columns = {"r_owner", "uid", "主播名称", "主播昵称", "邮箱", "email"}
    exported_user_data: list[str] = []
    for path in ARTIFACT_DIR.glob("*.csv"):
        columns = set(pd.read_csv(path, nrows=0).columns)
        if columns & banned_columns:
            exported_user_data.append(path.name)
    checks.append(check(not exported_user_data, "匿名CSV不含标识字段", "Anonymized CSVs contain no identifier fields", exported_user_data, []))

    script_text = "\n".join(path.read_text(encoding="utf-8") for path in SCRIPT_DIR.glob("*.py"))
    hardcoded_hadoop_identity = bool(re.search(r"HADOOP_USER_NAME\s*=\s*[^\s'\"]+", script_text))
    hardcoded_email = bool(re.search(r"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}", script_text, re.I))
    checks.append(check(not hardcoded_hadoop_identity, "脚本无硬编码Hadoop身份", "Scripts contain no hard-coded Hadoop identity", hardcoded_hadoop_identity, False))
    checks.append(check(not hardcoded_email, "脚本无个人邮箱", "Scripts contain no personal email", hardcoded_email, False))

    source_dir = args.source_dir or (Path(os.environ["FANWA_SOURCE_DIR"]) if "FANWA_SOURCE_DIR" in os.environ else None)
    if source_dir and source_dir.is_dir():
        source_csv = pd.read_csv(source_dir / "06allres.csv", dtype={"uid": str})
        source_res = pd.read_csv(source_dir / "res.txt", sep="\t", header=None, dtype={1: str})
        source_feat = pd.read_csv(source_dir / "featt", sep="\x01", header=None, dtype={1: str})
        base_columns = [
            "r_owner", "uid", "pcode", "r_category", "liucun", "avg_com", "danmu", "fans",
            "dingyue_add", "danmu_only", "danmu_new", "live_mins", "gift_user", "gift_value",
        ]
        prediction_columns = ["predict_acu", "predict_laxin", "predict_yingshou", "predict_pay"]
        source_res.columns = base_columns + prediction_columns
        source_feat.columns = base_columns
        checks.append(check(source_feat.equals(source_csv[base_columns]), "featt与最终CSV基础字段一致", "featt matches final CSV base fields", True, True))
        for column in base_columns:
            left = source_csv[column].astype(str).replace({"nan": ""})
            right = source_res[column].astype(str).replace({"nan": ""})
            if not left.equals(right):
                checks.append(check(False, f"res.txt字段一致:{column}", f"res.txt field parity:{column}", False, True))
                break
        else:
            checks.append(check(True, "res.txt与最终CSV基础字段一致", "res.txt matches final CSV base fields", True, True))

    report = {
        "project": "external-streamer-reverse-poaching",
        "overall_status": "pass" if all(item["status"] == "pass" for item in checks) else "fail",
        "checks": checks,
    }
    if args.write_report:
        path = PROJECT_ROOT / "artifacts" / "validation-report.json"
        path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["overall_status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
