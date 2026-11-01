#!/usr/bin/env python3
"""Validate the Kuaishou Honor of Kings reverse-poaching migration package."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from compare_fanwa_versions import ROLE_PATTERNS, find_input, stable_ids
from diagnose_fanwa_rules import feature_profile, monthly_panel, rule_variants


PROJECT_DIR = Path(__file__).resolve().parents[1]
ARTIFACT_DIR = PROJECT_DIR / "artifacts" / "anonymous-summary"
DEFAULT_SOURCE_DIR = Path(r"C:\Users\tiany\Desktop\快手王者荣耀主播反挖数据")
CJK_RE = re.compile(r"[\u3400-\u9fff]")


def check(records: list[dict[str, Any]], name: str, passed: bool, observed: Any) -> None:
    records.append({"check": name, "status": "pass" if passed else "fail", "observed": observed})


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def artifact_checks(records: list[dict[str, Any]]) -> dict[str, Any]:
    expected = {
        "candidate-month-profile.csv",
        "candidate-month-profile.en.csv",
        "huya-market-monthly.csv",
        "huya-market-monthly.en.csv",
        "huya-waist-comparison.csv",
        "huya-waist-comparison.en.csv",
        "rule-reconciliation.csv",
        "rule-reconciliation.en.csv",
        "source-coverage.csv",
        "source-coverage.en.csv",
        "source-manifest.csv",
        "source-manifest.en.csv",
        "summary-profile.json",
        "version-comparison.csv",
        "version-comparison.en.csv",
        "version-overlap.csv",
        "version-overlap.en.csv",
        "workbook-inventory.csv",
        "workbook-inventory.en.csv",
    }
    actual = {path.name for path in ARTIFACT_DIR.iterdir() if path.is_file()}
    check(records, "artifact_file_set", actual == expected, sorted(actual))

    profile = json.loads((ARTIFACT_DIR / "summary-profile.json").read_text(encoding="utf-8"))
    check(
        records,
        "summary_candidate_counts",
        profile["candidate_counts"]
        == {
            "initial_5_7_model": 53,
            "old_5_7_columns": 15,
            "old_5_7_conditioned": 43,
            "v2_5_7_columns": 15,
            "v2_4_7_50pct": 8,
            "v2_5_7_conditioned": 15,
        },
        profile["candidate_counts"],
    )
    check(
        records,
        "summary_source_coverage",
        profile["v1"] == {"rows": 453551, "unique_anchors": 327768, "anchor_months": 431103}
        and profile["v2"] == {"rows": 579868, "unique_anchors": 402290, "anchor_months": 551212},
        {"v1": profile["v1"], "v2": profile["v2"]},
    )
    check(
        records,
        "prediction_duplicate_disclosed",
        profile["v2_prediction_rows"] == 46
        and profile["v2_prediction_anchor_months"] == 45
        and profile["v2_duplicate_prediction_anchor_months"] == 1
        and profile["v2_duplicate_prediction_values_identical"] is True,
        {
            "rows": profile["v2_prediction_rows"],
            "anchor_months": profile["v2_prediction_anchor_months"],
            "duplicate_anchor_months": profile["v2_duplicate_prediction_anchor_months"],
        },
    )
    check(
        records,
        "huya_waist_reconciliation",
        profile["v2_final_observed_above_waist_all_three"] == 3
        and profile["v2_final_predicted_above_waist_all_three"] == 7
        and profile["v2_final_predicted_pay_year_p50"] == 158400.0,
        {
            "observed_all_three": profile["v2_final_observed_above_waist_all_three"],
            "predicted_all_three": profile["v2_final_predicted_above_waist_all_three"],
            "predicted_pay_year_p50": profile["v2_final_predicted_pay_year_p50"],
        },
    )
    check(
        records,
        "summary_anonymization_flags",
        all(
            profile[key] is False
            for key in ("raw_identifiers_exported", "raw_anchor_names_exported", "raw_user_level_rows_exported")
        ),
        {key: profile[key] for key in ("raw_identifiers_exported", "raw_anchor_names_exported", "raw_user_level_rows_exported")},
    )

    version_en = pd.read_csv(ARTIFACT_DIR / "version-comparison.en.csv")
    candidate_en = pd.read_csv(ARTIFACT_DIR / "candidate-month-profile.en.csv")
    check(
        records,
        "english_version_text",
        not version_en[["description", "conclusion"]].astype(str).apply(lambda col: col.str.contains(CJK_RE)).any().any(),
        "description and conclusion contain no CJK characters",
    )
    check(
        records,
        "english_candidate_labels",
        not candidate_en["candidate_set"].astype(str).str.contains(CJK_RE).any(),
        sorted(candidate_en["candidate_set"].unique().tolist()),
    )

    pair_stems = [
        "candidate-month-profile",
        "huya-market-monthly",
        "huya-waist-comparison",
        "rule-reconciliation",
        "source-coverage",
        "source-manifest",
        "version-comparison",
        "version-overlap",
        "workbook-inventory",
    ]
    pair_shapes: dict[str, list[int]] = {}
    pair_ok = True
    for stem in pair_stems:
        zh = pd.read_csv(ARTIFACT_DIR / f"{stem}.csv")
        en = pd.read_csv(ARTIFACT_DIR / f"{stem}.en.csv")
        pair_shapes[stem] = [len(zh), len(en), len(zh.columns), len(en.columns)]
        pair_ok &= len(zh) == len(en) and len(zh.columns) == len(en.columns)
    check(records, "bilingual_csv_shapes", pair_ok, pair_shapes)

    document_pairs = [
        ("README.md", "README.en.md"),
        ("methodology/reverse-poaching-rules.md", "methodology/reverse-poaching-rules.en.md"),
        ("validation/validation-report.md", "validation/validation-report.en.md"),
    ]
    document_shapes: dict[str, list[int]] = {}
    document_ok = True
    for zh_name, en_name in document_pairs:
        zh_text = (PROJECT_DIR / zh_name).read_text(encoding="utf-8")
        en_text = (PROJECT_DIR / en_name).read_text(encoding="utf-8")
        zh_shape = [len(re.findall(r"^#", zh_text, re.MULTILINE)), zh_text.count("| --- |")]
        en_shape = [len(re.findall(r"^#", en_text, re.MULTILINE)), en_text.count("| --- |")]
        document_shapes[zh_name] = zh_shape + en_shape
        document_ok &= zh_shape == en_shape
    check(records, "bilingual_document_structure", document_ok, document_shapes)

    file_sizes = {path.name: path.stat().st_size for path in ARTIFACT_DIR.iterdir() if path.is_file()}
    check(records, "artifact_size_budget", max(file_sizes.values()) < 1024 * 1024, max(file_sizes.values()))
    copied_raw = [path.name for path in PROJECT_DIR.rglob("*") if path.is_file() and path.suffix.lower() in {".xlsx", ".xls"}]
    check(records, "no_workbook_copied", copied_raw == [], copied_raw)
    return profile


def source_checks(records: list[dict[str, Any]], source_dir: Path) -> None:
    expected_files = 9
    source_files = [path for path in source_dir.iterdir() if path.is_file()]
    check(records, "source_file_count", len(source_files) == expected_files, len(source_files))

    manifest = pd.read_csv(ARTIFACT_DIR / "source-manifest.en.csv")
    manifest_ok = len(manifest) == expected_files
    manifest_mismatches: list[str] = []
    for row in manifest.itertuples(index=False):
        path = source_dir / row.source_file
        if not path.exists() or path.stat().st_size != row.bytes or sha256(path) != row.sha256:
            manifest_mismatches.append(row.source_file)
            manifest_ok = False
    check(records, "source_manifest_integrity", manifest_ok, manifest_mismatches)

    v1_path = source_dir / "快手王者荣耀主播反挖数据_加上快手ACU数据_全量.csv"
    v2_path = source_dir / "快手王者荣耀主播反挖数据_加上快手ACU数据_全量_V2.csv"
    v1 = monthly_panel(v1_path)
    v2 = monthly_panel(v2_path)
    actual_sets: dict[str, set[str]] = {}
    for role, pattern in ROLE_PATTERNS.items():
        frame = pd.read_excel(find_input(source_dir, role, pattern), sheet_name=0)
        id_column = next(column for column in ("r_lid", "lid") if column in frame.columns)
        actual_sets[role] = set(stable_ids(frame[id_column].tolist()))

    check(
        records,
        "source_candidate_counts",
        {role: len(ids) for role, ids in actual_sets.items()}
        == {
            "initial_5_7_model": 53,
            "old_5_7_columns": 15,
            "old_5_7_conditioned": 43,
            "v2_5_7_columns": 15,
            "v2_4_7_50pct": 8,
            "v2_5_7_conditioned": 15,
        },
        {role: len(ids) for role, ids in actual_sets.items()},
    )

    v1_rules = rule_variants(v1)
    v2_rules = rule_variants(v2)
    early = v1_rules["decline_5_7_live80_endpoint"]
    old_rule = v1_rules["acu100_live80_chain_no_acu_decline"]
    final_rule = v2_rules["acu100_decline_5_7_live80_chain"]
    four_month_rule = v2_rules["acu100_decline_4_7_live50_chain"]
    check(records, "initial_shortlist_subset", actual_sets["initial_5_7_model"].issubset(early), len(actual_sets["initial_5_7_model"]))
    check(records, "initial_rule_population_undocumented", len(early) == 1190, len(early))
    check(records, "initial_acu_above_100_count", feature_profile(v1, actual_sets["initial_5_7_model"])["all_auc_over_100"] == 16, 16)
    check(records, "old_43_exact_weaker_rule", old_rule == actual_sets["old_5_7_conditioned"], len(old_rule))
    old_profile = feature_profile(v1, actual_sets["old_5_7_conditioned"])
    check(records, "old_43_label_defect", old_profile["strict_decline_5_7"] == 15, old_profile["strict_decline_5_7"])
    check(records, "v2_final_exact_rule", final_rule == actual_sets["v2_5_7_conditioned"], len(final_rule))
    final_profile = feature_profile(v2, actual_sets["v2_5_7_conditioned"])
    check(
        records,
        "v2_final_rule_profile",
        final_profile["found"] == 15
        and final_profile["all_auc_over_100"] == 15
        and final_profile["strict_decline_5_7"] == 15
        and final_profile["minimum_adjacent_live_ratio_5_7"] >= 0.8,
        {key: final_profile[key] for key in ("found", "all_auc_over_100", "strict_decline_5_7", "minimum_adjacent_live_ratio_5_7")},
    )
    check(records, "v2_four_month_exact_rule", four_month_rule == actual_sets["v2_4_7_50pct"], len(four_month_rule))

    common_month_checks: dict[str, Any] = {}
    common_ok = True
    for month in ("2026-05", "2026-06", "2026-07", "2026-08"):
        metrics = ["month_acu", "daily_live", "days"]
        columns = ["r_lid"] + [f"{metric}_{month}" for metric in metrics]
        left = v1[columns].dropna().sort_values("r_lid")
        right = v2[columns].dropna().sort_values("r_lid")
        same_ids = left["r_lid"].tolist() == right["r_lid"].tolist()
        max_diffs = {
            metric: float(np.max(np.abs(left[f"{metric}_{month}"].to_numpy() - right[f"{metric}_{month}"].to_numpy())))
            for metric in metrics
        }
        passed = same_ids and all(value <= 1e-9 for value in max_diffs.values())
        common_month_checks[month] = {"rows": len(left), "same_ids": same_ids, "max_abs_diff": max_diffs}
        common_ok &= passed
    check(records, "v1_v2_common_month_exact", common_ok, common_month_checks)

    workbook_reconciliation: dict[str, Any] = {}
    workbook_ok = True
    workbook_specs = [
        ("initial", "快手王者荣耀主播_ACU连续三个月下降且开播时长稳定_含虎牙预测_含腰部ACU对比_连续三个月_含快手ACU_202605-202607.xlsx", v1_path),
        ("old_conditioned", "快手王者荣耀主播_筛选_ACU均大于100且连续下降且开播稳定_全量信息.xlsx", v1_path),
        ("v2_conditioned", "快手王者荣耀主播_V2筛选_5-7月ACU均大于100且连续下降且开播稳定_全量信息.xlsx", v2_path),
    ]
    panel_cache = {"v1": v1, "v2": v2}
    for label, filename, source_path in workbook_specs:
        workbook = pd.ExcelFile(source_dir / filename)
        detail = None
        for sheet_name in workbook.sheet_names:
            candidate = pd.read_excel(source_dir / filename, sheet_name=sheet_name)
            if {"r_lid", "mth", "month_acu", "daily_live_mins", "actual_days"}.issubset(candidate.columns):
                detail = candidate.astype({"r_lid": str, "mth": str})
                break
        if detail is None:
            raise ValueError(f"Monthly calculation sheet not found in {filename}")
        panel = panel_cache["v1" if source_path == v1_path else "v2"]
        long_parts = []
        for month in sorted(detail["mth"].dropna().unique()):
            columns = ["r_lid", f"month_acu_{month}", f"daily_live_{month}", f"days_{month}"]
            part = panel[columns].dropna().rename(
                columns={
                    f"month_acu_{month}": "month_acu",
                    f"daily_live_{month}": "daily_live_mins",
                    f"days_{month}": "actual_days",
                }
            ).assign(mth=month)
            long_parts.append(part)
        rebuilt = pd.concat(long_parts, ignore_index=True)
        merged = detail.merge(rebuilt, on=["r_lid", "mth"], how="left", suffixes=("_workbook", "_rebuilt"), indicator=True)
        diffs = {
            metric: float(
                np.nanmax(
                    np.abs(
                        pd.to_numeric(merged[f"{metric}_workbook"], errors="coerce")
                        - pd.to_numeric(merged[f"{metric}_rebuilt"], errors="coerce")
                    )
                )
            )
            for metric in ("actual_days", "daily_live_mins", "month_acu")
        }
        passed = merged["_merge"].eq("both").all() and all(value <= 1e-9 for value in diffs.values())
        workbook_reconciliation[label] = {"rows": len(detail), "max_abs_diff": diffs}
        workbook_ok &= passed
    check(records, "workbook_monthly_reconciliation", workbook_ok, workbook_reconciliation)

    identifier_columns = {"r_lid", "lid", "huya_predict_uid", "r_owner", "nickname", "user_id", "uid"}
    identifier_exported = False
    all_candidate_ids: set[str] = set()
    for ids in actual_sets.values():
        all_candidate_ids.update(ids)
    for path in ARTIFACT_DIR.glob("*.csv"):
        frame = pd.read_csv(path, dtype=str)
        if any(column.lower() in identifier_columns for column in frame.columns):
            identifier_exported = True
            continue
        cells = set(frame.astype(str).to_numpy().ravel())
        if cells & all_candidate_ids:
            identifier_exported = True
    check(records, "no_source_identifiers_in_artifacts", not identifier_exported, identifier_exported)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=Path(os.environ.get("KUAISHOU_FANWA_SOURCE_DIR", DEFAULT_SOURCE_DIR)),
    )
    parser.add_argument("--write-report", action="store_true")
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")

    records: list[dict[str, Any]] = []
    artifact_checks(records)
    if args.source_dir.exists():
        source_checks(records, args.source_dir)
        source_status = "executed"
    else:
        records.append(
            {
                "check": "source_dependent_checks",
                "status": "not_run",
                "observed": f"source directory not found: {args.source_dir}",
            }
        )
        source_status = "not_run"

    failed = [record for record in records if record["status"] == "fail"]
    report = {
        "status": "fail" if failed else ("pass" if source_status == "executed" else "incomplete"),
        "source_dependent_checks": source_status,
        "checks_total": len(records),
        "checks_passed": sum(record["status"] == "pass" for record in records),
        "checks_failed": len(failed),
        "checks_not_run": sum(record["status"] == "not_run" for record in records),
        "records": records,
    }
    if args.write_report:
        output = PROJECT_DIR / "artifacts" / "validation-report.json"
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if not failed and source_status == "executed" else (1 if failed else 2)


if __name__ == "__main__":
    raise SystemExit(main())
