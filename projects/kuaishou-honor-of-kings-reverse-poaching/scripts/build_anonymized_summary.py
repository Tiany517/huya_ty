#!/usr/bin/env python3
"""Build identifier-free Kuaishou reverse-poaching summaries."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

import pandas as pd
from openpyxl import load_workbook

from compare_fanwa_versions import ROLE_PATTERNS, stable_ids
from diagnose_fanwa_rules import comparison, monthly_panel, rule_variants


ROLE_META = {
    "initial_5_7_model": {
        "label_zh": "早期5-7月模型初筛",
        "label_en": "Initial May-July model screen",
        "note_zh": "53人均满足5-7月ACU严格下降和7月/5月日均开播时长>=80%；除这两个条件外的入选边界未留下说明。",
        "note_en": "All 53 satisfy strict May-July ACU decline and July/May daily live minutes >=80%; the additional shortlist rule is undocumented.",
    },
    "old_5_7_conditioned": {
        "label_zh": "旧版条件汇总",
        "label_en": "Old conditioned summary",
        "note_zh": "文件名声称连续下降，但43人独立重算并非都严格下降；43人实际精确等于“ACU>100且相邻月开播比例>=80%”，未应用ACU下降条件。",
        "note_en": "The filename claims consecutive decline, but only 15 of 43 strictly decline; all 43 match the weaker rule ACU>100 plus adjacent live-time ratio >=80%, with no ACU-decline test.",
    },
    "v2_5_7_conditioned": {
        "label_zh": "V2条件汇总",
        "label_en": "V2 conditioned summary",
        "note_zh": "15人精确复现：5-7月ACU均>100、严格下降，且6/5和7/6日均开播时长比例均>=80%。",
        "note_en": "All 15 are reproduced exactly by ACU >100 in May-July, strict monthly decline, and adjacent daily-live-minute ratios >=80%.",
    },
    "old_5_7_columns": {
        "label_zh": "旧版指定列名结果",
        "label_en": "Old specified-column result",
        "note_zh": "15个候选ID与V2最终15人完全一致。",
        "note_en": "Its 15 candidate IDs exactly match the V2 final set of 15.",
    },
    "v2_5_7_columns": {
        "label_zh": "V2最终15人",
        "label_en": "V2 final 15",
        "note_zh": "15人精确复现，作为本项目的V2最终口径。",
        "note_en": "The 15 candidates are reproduced exactly and are the final V2 definition for this review.",
    },
    "v2_4_7_50pct": {
        "label_zh": "V2四个月50%开播比例情景",
        "label_en": "V2 four-month 50% live-ratio scenario",
        "note_zh": "当前CSV精确复现全部8人；先前草稿中的7/8判断已被独立重算推翻，不作为结论。",
        "note_en": "The current CSV reproduces all eight candidates exactly; the earlier 7/8 draft was disproved by independent recomputation.",
    },
}

TIMELINE = [
    "initial_5_7_model",
    "old_5_7_conditioned",
    "v2_5_7_conditioned",
    "old_5_7_columns",
    "v2_5_7_columns",
    "v2_4_7_50pct",
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def read_workbook_ids(source_dir: Path, role: str) -> tuple[Path, set[str]]:
    path = sorted(source_dir.glob(ROLE_PATTERNS[role]))
    if len(path) != 1:
        raise ValueError(f"Expected one workbook for {role}, found {len(path)}")
    frame = pd.read_excel(path[0], sheet_name=0)
    id_column = next(column for column in ("r_lid", "lid") if column in frame.columns)
    ids = stable_ids(frame[id_column].tolist())
    return path[0], set(ids)


def read_raw_coverage(path: Path) -> tuple[pd.DataFrame, dict[str, Any]]:
    frame = pd.read_csv(path, usecols=["mth", "r_lid"], dtype={"mth": str, "r_lid": str})
    coverage = (
        frame.groupby("mth", as_index=False)
        .agg(rows=("r_lid", "size"), unique_anchors=("r_lid", "nunique"))
        .sort_values("mth")
    )
    profile = {
        "rows": int(len(frame)),
        "unique_anchors": int(frame["r_lid"].nunique()),
        "anchor_months": int(frame[["mth", "r_lid"]].drop_duplicates().shape[0]),
    }
    return coverage, profile


def write_pair(frame_zh: pd.DataFrame, output_dir: Path, stem: str, english_columns: dict[str, str]) -> None:
    frame_zh.to_csv(output_dir / f"{stem}.csv", index=False, encoding="utf-8-sig", lineterminator="\n")
    frame_en = frame_zh.rename(columns=english_columns)
    frame_en.to_csv(output_dir / f"{stem}.en.csv", index=False, encoding="utf-8-sig", lineterminator="\n")


def workbook_inventory(source_dir: Path) -> pd.DataFrame:
    rows = []
    for path in sorted(source_dir.glob("*.xlsx")):
        workbook = load_workbook(path, read_only=True, data_only=False)
        for worksheet in workbook.worksheets:
            rows.append(
                {
                    "文件": path.name,
                    "工作表": worksheet.title,
                    "状态": worksheet.sheet_state,
                    "最大行": worksheet.max_row,
                    "最大列": worksheet.max_column,
                    "数据行不超过": max(worksheet.max_row - 1, 0),
                }
            )
        workbook.close()
    return pd.DataFrame(rows)


def source_manifest(source_dir: Path) -> pd.DataFrame:
    rows = []
    for path in sorted(source_dir.iterdir()):
        if not path.is_file():
            continue
        if path.name.endswith("全量.csv") or "_全量_V2.csv" in path.name:
            treatment = "analysis_only_not_copied"
            reason = "raw anchor rows and file exceeds Git-friendly size"
        elif path.suffix.lower() == ".xlsx":
            treatment = "analysis_only_not_copied"
            reason = "contains anchor IDs and names; workbook structure and anonymous aggregates retained"
        else:
            treatment = "aggregate_copied_normalized"
            reason = "identifier-free monthly tier benchmark"
        rows.append(
            {
                "source_file": path.name,
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
                "repo_treatment": treatment,
                "reason": reason,
            }
        )
    return pd.DataFrame(rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    args.output_dir.mkdir(parents=True, exist_ok=True)

    v1_path = args.source_dir / "快手王者荣耀主播反挖数据_加上快手ACU数据_全量.csv"
    v2_path = args.source_dir / "快手王者荣耀主播反挖数据_加上快手ACU数据_全量_V2.csv"
    v1 = monthly_panel(v1_path)
    v2 = monthly_panel(v2_path)
    actual_sets = {role: read_workbook_ids(args.source_dir, role)[1] for role in ROLE_PATTERNS}
    final_ids = actual_sets["v2_5_7_columns"]

    version_rows = []
    for role in TIMELINE:
        path, ids = read_workbook_ids(args.source_dir, role)
        version_rows.append(
            {
                "版本": role,
                "中文说明": ROLE_META[role]["label_zh"],
                "文件": path.name,
                "最后修改时间": path.stat().st_mtime_ns,
                "候选数": len(ids),
                "唯一候选ID数": len(ids),
                "与V2最终15人重合": len(ids & final_ids),
                "与V2最终15人重合率_pct": round(len(ids & final_ids) / len(final_ids) * 100, 6),
                "结论": ROLE_META[role]["note_zh"],
            }
        )
    versions_zh = pd.DataFrame(version_rows)
    versions_zh["最后修改时间"] = pd.to_datetime(versions_zh["最后修改时间"], unit="ns").dt.strftime("%Y-%m-%d %H:%M:%S")
    write_pair(
        versions_zh,
        args.output_dir,
        "version-comparison",
        {
            "版本": "version",
            "中文说明": "description_zh",
            "文件": "file",
            "最后修改时间": "last_modified",
            "候选数": "candidates",
            "唯一候选ID数": "unique_candidate_ids",
            "与V2最终15人重合": "overlap_with_v2_final",
            "与V2最终15人重合率_pct": "overlap_rate_pct",
            "结论": "conclusion_zh",
        },
    )
    versions_en = pd.DataFrame(
        [
            {
                "version": role,
                "description": ROLE_META[role]["label_en"],
                "file": row["文件"],
                "last_modified": modified,
                "candidates": row["候选数"],
                "unique_candidate_ids": row["唯一候选ID数"],
                "overlap_with_v2_final": row["与V2最终15人重合"],
                "overlap_rate_pct": row["与V2最终15人重合率_pct"],
                "conclusion": ROLE_META[role]["note_en"],
            }
            for role, row, modified in zip(TIMELINE, version_rows, versions_zh["最后修改时间"].tolist())
        ]
    )
    versions_en.to_csv(
        args.output_dir / "version-comparison.en.csv", index=False, encoding="utf-8-sig", lineterminator="\n"
    )

    overlap_rows = []
    for position, left in enumerate(TIMELINE):
        for right in TIMELINE[position + 1 :]:
            left_ids = actual_sets[left]
            right_ids = actual_sets[right]
            overlap_rows.append(
                {
                    "版本A": left,
                    "版本B": right,
                    "交集": len(left_ids & right_ids),
                    "仅版本A": len(left_ids - right_ids),
                    "仅版本B": len(right_ids - left_ids),
                }
            )
    write_pair(
        pd.DataFrame(overlap_rows),
        args.output_dir,
        "version-overlap",
        {"版本A": "version_a", "版本B": "version_b", "交集": "overlap", "仅版本A": "only_a", "仅版本B": "only_b"},
    )

    v1_rules = rule_variants(v1)
    v2_rules = rule_variants(v2)
    rule_rows = []
    rule_specs = [
        (
            "早期初筛",
            "早期初筛：5-7月ACU严格下降且7月/5月日均开播分钟>=80%",
            "initial_screen",
            "Initial screen: strict May-July ACU decline and July/May daily live minutes >=80%",
            v1_rules["decline_5_7_live80_endpoint"],
            actual_sets["initial_5_7_model"],
            "全部53人满足该规则；但规则总体有1,190人，工作簿只保留53人，额外截断规则未记录。",
            "All 53 satisfy the rule, but 1,190 pass overall; the additional shortlist rule is undocumented.",
            "incomplete",
        ),
        (
            "旧版错误标签",
            "旧版：ACU>100且6/5、7/6日均开播比例>=80%，未检查ACU下降",
            "old_actual_rule",
            "Old workbook: ACU >100 and adjacent live ratios >=80%, without an ACU-decline test",
            v1_rules["acu100_live80_chain_no_acu_decline"],
            actual_sets["old_5_7_conditioned"],
            "独立重算与43人完全一致，证明旧版没有真正执行“连续下降”。",
            "The independent rebuild matches all 43 exactly, proving the old workbook did not enforce consecutive ACU decline.",
            "confirmed_defect",
        ),
        (
            "V2最终规则",
            "V2：5-7月ACU均>100且严格下降，6/5和7/6日均开播比例>=80%",
            "v2_final_rule",
            "V2: ACU >100 and strict decline in May-July; adjacent daily-live ratios >=80%",
            v2_rules["acu100_decline_5_7_live80_chain"],
            actual_sets["v2_5_7_conditioned"],
            "规则复算15人，与V2工作簿15人完全一致。",
            "The rule reproduces 15 candidates, exactly matching the V2 workbook.",
            "pass",
        ),
        (
            "V2四个月50%情景",
            "V2：4-7月ACU均>100且严格下降，相邻月日均开播比例>=50%",
            "v2_four_month_rule",
            "V2: ACU >100 and strict decline for April-July; adjacent daily-live ratios >=50%",
            v2_rules["acu100_decline_4_7_live50_chain"],
            actual_sets["v2_4_7_50pct"],
            "当前CSV精确复现全部8人；先前草稿中的7/8判断已被独立重算推翻，不作为结论。",
            "The current CSV reproduces all eight candidates exactly; the earlier 7/8 draft was disproved by independent recomputation.",
            "pass",
        ),
    ]
    for name_zh, rule_zh, name_en, rule_en, predicted, actual, note_zh, note_en, status in rule_specs:
        result = comparison(predicted, actual)
        rule_rows.append(
            {
                "检查": name_zh,
                "中文规则": rule_zh,
                "规则复算人数": result["predicted"],
                "工作簿人数": result["actual"],
                "精确重合": result["overlap"],
                "仅规则": result["predicted_only"],
                "仅工作簿": result["actual_only"],
                "状态": status,
                "结论": note_zh,
                "check_en": name_en,
                "rule_en": rule_en,
                "conclusion_en": note_en,
            }
        )
    rules_zh = pd.DataFrame(rule_rows).drop(columns=["check_en", "rule_en", "conclusion_en"])
    write_pair(
        rules_zh,
        args.output_dir,
        "rule-reconciliation",
        {
            "检查": "check",
            "中文规则": "rule_zh",
            "规则复算人数": "rule_population",
            "工作簿人数": "workbook_population",
            "精确重合": "exact_overlap",
            "仅规则": "rule_only",
            "仅工作簿": "workbook_only",
            "状态": "status",
            "结论": "conclusion_zh",
        },
    )
    rules_en = pd.DataFrame(
        [
            {
                "check": row["check_en"],
                "rule": row["rule_en"],
                "rule_population": row["规则复算人数"],
                "workbook_population": row["工作簿人数"],
                "exact_overlap": row["精确重合"],
                "rule_only": row["仅规则"],
                "workbook_only": row["仅工作簿"],
                "status": row["状态"],
                "conclusion": row["conclusion_en"],
            }
            for row in rule_rows
        ]
    )
    rules_en.to_csv(args.output_dir / "rule-reconciliation.en.csv", index=False, encoding="utf-8-sig", lineterminator="\n")

    v1_coverage, v1_profile = read_raw_coverage(v1_path)
    v2_coverage, v2_profile = read_raw_coverage(v2_path)
    coverage_rows = []
    for version, coverage in (("V1", v1_coverage), ("V2", v2_coverage)):
        for row in coverage.itertuples(index=False):
            coverage_rows.append({"数据版本": version, "月份": row.mth, "原始行数": int(row.rows), "唯一主播数": int(row.unique_anchors)})
    coverage_zh = pd.DataFrame(coverage_rows)
    write_pair(
        coverage_zh,
        args.output_dir,
        "source-coverage",
        {"数据版本": "source_version", "月份": "month", "原始行数": "raw_rows", "唯一主播数": "unique_anchors"},
    )

    profile_rows_zh = []
    profile_rows_en = []
    profile_sets = {
        "initial_5_7_model": ("早期初筛", "Initial screen", v1, actual_sets["initial_5_7_model"]),
        "old_5_7_conditioned": ("旧版条件汇总", "Old conditioned summary", v1, actual_sets["old_5_7_conditioned"]),
        "v2_5_7_conditioned": ("V2最终15人", "V2 final 15", v2, actual_sets["v2_5_7_conditioned"]),
        "v2_4_7_50pct": ("V2四个月50%情景", "V2 four-month 50% scenario", v2, actual_sets["v2_4_7_50pct"]),
    }
    for label_zh, label_en, frame, ids in profile_sets.values():
        selected = frame[frame["r_lid"].isin(ids)]
        for month in ("2026-04", "2026-05", "2026-06", "2026-07"):
            acu_column = f"month_acu_{month}"
            live_column = f"daily_live_{month}"
            if acu_column not in selected.columns:
                continue
            acu = pd.to_numeric(selected[acu_column], errors="coerce").dropna()
            live = pd.to_numeric(selected[live_column], errors="coerce").dropna()
            metrics = (
                int(len(selected)),
                round(float(acu.min()), 6),
                round(float(acu.median()), 6),
                round(float(acu.quantile(0.9)), 6),
                round(float(live.median()), 6),
            )
            profile_rows_zh.append(
                {
                    "候选集": label_zh,
                    "月份": month,
                    "可计算人数": metrics[0],
                    "ACU最小值": metrics[1],
                    "ACU_P50": metrics[2],
                    "ACU_P90": metrics[3],
                    "日均开播分钟_P50": metrics[4],
                }
            )
            profile_rows_en.append(
                {
                    "candidate_set": label_en,
                    "month": month,
                    "evaluable_candidates": metrics[0],
                    "acu_min": metrics[1],
                    "acu_p50": metrics[2],
                    "acu_p90": metrics[3],
                    "daily_live_minutes_p50": metrics[4],
                }
            )
    write_pair(
        pd.DataFrame(profile_rows_zh),
        args.output_dir,
        "candidate-month-profile",
        {
            "候选集": "candidate_set_zh",
            "月份": "month",
            "可计算人数": "evaluable_candidates",
            "ACU最小值": "acu_min",
            "ACU_P50": "acu_p50",
            "ACU_P90": "acu_p90",
            "日均开播分钟_P50": "daily_live_minutes_p50",
        },
    )
    pd.DataFrame(profile_rows_en).to_csv(
        args.output_dir / "candidate-month-profile.en.csv", index=False, encoding="utf-8-sig", lineterminator="\n"
    )

    final_path = read_workbook_ids(args.source_dir, "v2_5_7_columns")[0]
    final = pd.read_excel(final_path, sheet_name=0)
    prediction_frame = pd.read_csv(
        v2_path,
        usecols=["mth", "r_lid", "huya_predict_acu", "huya_predict_viewhours", "huya_predict_pay_year"],
        dtype={"mth": str, "r_lid": str},
    )
    prediction_frame = prediction_frame[
        prediction_frame["r_lid"].isin(final_ids) & prediction_frame["mth"].between("2026-05", "2026-07")
    ].copy()
    prediction_rows_raw = len(prediction_frame)
    prediction_duplicate_groups = prediction_frame.groupby(["r_lid", "mth"]).agg(
        acu_values=("huya_predict_acu", "nunique"),
        viewhours_values=("huya_predict_viewhours", "nunique"),
        pay_values=("huya_predict_pay_year", "nunique"),
        rows=("r_lid", "size"),
    )
    prediction_duplicate_keys = prediction_duplicate_groups[prediction_duplicate_groups["rows"].gt(1)]
    if prediction_duplicate_keys[["acu_values", "viewhours_values", "pay_values"]].gt(1).any().any():
        raise ValueError("Duplicate candidate-month prediction rows contain conflicting values")
    for column in ("huya_predict_acu", "huya_predict_viewhours", "huya_predict_pay_year"):
        prediction_frame[column] = pd.to_numeric(prediction_frame[column], errors="coerce")
    prediction_by_month = prediction_frame.drop_duplicates(["r_lid", "mth"]).groupby(["r_lid", "mth"], as_index=False).agg(
        predicted_acu=("huya_predict_acu", "first"),
        predicted_viewhours=("huya_predict_viewhours", "first"),
        predicted_pay_year=("huya_predict_pay_year", "first"),
    )
    actual_by_month = final.melt(
        id_vars=["lid"],
        value_vars=[f"{month}_月日均ACU" for month in ("2026-05", "2026-06", "2026-07")],
        var_name="column",
        value_name="actual_acu",
    )
    actual_by_month["mth"] = actual_by_month["column"].str[:7]
    actual_by_month = actual_by_month.rename(columns={"lid": "r_lid"})[['r_lid', 'mth', 'actual_acu']]
    joined = actual_by_month.merge(prediction_by_month, on=["r_lid", "mth"], how="left")
    benchmark = pd.read_csv(args.source_dir / "王者各等级主播的月ACU均值.csv")
    waist = benchmark[benchmark["zhubo_level"].eq("腰部主播")].set_index("month")["月日均acu均值"]
    waist_rows = []
    for month in ("2026-05", "2026-06", "2026-07"):
        selected = joined[joined["mth"].eq(month)]
        waist_rows.append(
            {
                "月份": month,
                "虎牙腰部ACU基准": round(float(waist[month]), 6),
                "实际ACU_P50": round(float(selected["actual_acu"].median()), 6),
                "实际ACU高于腰部人数": int((selected["actual_acu"] > waist[month]).sum()),
                "预测ACU_P50": round(float(selected["predicted_acu"].median()), 6),
                "预测ACU高于腰部人数": int((selected["predicted_acu"] > waist[month]).sum()),
                "候选人数": int(len(selected)),
            }
        )
    write_pair(
        pd.DataFrame(waist_rows),
        args.output_dir,
        "huya-waist-comparison",
        {
            "月份": "month",
            "虎牙腰部ACU基准": "huya_waist_acu_benchmark",
            "实际ACU_P50": "observed_acu_p50",
            "实际ACU高于腰部人数": "observed_above_waist",
            "预测ACU_P50": "predicted_acu_p50",
            "预测ACU高于腰部人数": "predicted_above_waist",
            "候选人数": "candidates",
        },
    )

    benchmark_en = benchmark.copy()
    benchmark_en["zhubo_level"] = benchmark_en["zhubo_level"].map(
        {"头部主播": "head", "腰部主播": "waist", "尾部主播": "tail"}
    )
    write_pair(
        benchmark,
        args.output_dir,
        "huya-market-monthly",
        {
            "month": "month",
            "zhubo_level": "anchor_tier_zh",
            "月日均acu均值": "avg_daily_acu",
            "月日均开播时长": "avg_daily_live_duration_value",
            "主播数": "anchor_count",
        },
    )
    benchmark_en.rename(
        columns={
            "month": "month",
            "zhubo_level": "anchor_tier",
            "月日均acu均值": "avg_daily_acu",
            "月日均开播时长": "avg_daily_live_duration_value",
            "主播数": "anchor_count",
        }
    ).to_csv(args.output_dir / "huya-market-monthly.en.csv", index=False, encoding="utf-8-sig", lineterminator="\n")

    workbook_rows = workbook_inventory(source_dir=args.source_dir)
    workbook_rows.to_csv(
        args.output_dir / "workbook-inventory.csv", index=False, encoding="utf-8-sig", lineterminator="\n"
    )
    workbook_rows_en = workbook_rows.rename(
        columns={
            "文件": "source_file",
            "工作表": "source_sheet",
            "状态": "sheet_visibility",
            "最大行": "max_row",
            "最大列": "max_column",
            "数据行不超过": "max_data_rows",
        }
    )
    workbook_rows_en["sheet_visibility"] = workbook_rows_en["sheet_visibility"].map(
        {"visible": "visible", "hidden": "hidden", "veryHidden": "very_hidden"}
    ).fillna(workbook_rows_en["sheet_visibility"])
    workbook_rows_en.to_csv(
        args.output_dir / "workbook-inventory.en.csv", index=False, encoding="utf-8-sig", lineterminator="\n"
    )
    manifest_frame = source_manifest(args.source_dir)
    manifest_zh = manifest_frame.rename(
        columns={
            "source_file": "源文件",
            "bytes": "字节数",
            "sha256": "SHA256",
            "repo_treatment": "仓库处理方式",
            "reason": "原因",
        }
    )
    treatment_zh = {
        "analysis_only_not_copied": "仅分析，不复制到仓库",
        "aggregate_copied_normalized": "匿名汇总已复制并规范化",
    }
    reason_zh = {
        "raw anchor rows and file exceeds Git-friendly size": "含主播级原始记录，且文件过大",
        "contains anchor IDs and names; workbook structure and anonymous aggregates retained": "含主播ID和昵称；仅保留工作簿结构与匿名汇总",
        "identifier-free monthly tier benchmark": "无身份标识的月度分层基准",
    }
    manifest_zh["仓库处理方式"] = manifest_zh["仓库处理方式"].map(treatment_zh)
    manifest_zh["原因"] = manifest_zh["原因"].map(reason_zh)
    manifest_zh.to_csv(
        args.output_dir / "source-manifest.csv", index=False, encoding="utf-8-sig", lineterminator="\n"
    )
    manifest_frame.to_csv(
        args.output_dir / "source-manifest.en.csv", index=False, encoding="utf-8-sig", lineterminator="\n"
    )

    actual_above_all = int((joined.pivot(index="r_lid", columns="mth", values="actual_acu") > waist).all(axis=1).sum())
    predicted_above_all = int(
        (
            joined.pivot(index="r_lid", columns="mth", values="predicted_acu") > waist
        ).all(axis=1).sum()
    )
    profile = {
        "source_files": int(len(manifest_frame)),
        "v1": v1_profile,
        "v2": v2_profile,
        "v2_added_anchors": v2_profile["unique_anchors"] - v1_profile["unique_anchors"],
        "candidate_counts": {role: len(ids) for role, ids in actual_sets.items()},
        "v2_final_candidates": len(final_ids),
        "v2_final_candidate_months": int(len(joined)),
        "v2_prediction_rows": int(prediction_rows_raw),
        "v2_prediction_anchor_months": int(prediction_frame[["r_lid", "mth"]].drop_duplicates().shape[0]),
        "v2_duplicate_prediction_anchor_months": int(len(prediction_duplicate_keys)),
        "v2_duplicate_prediction_values_identical": True,
        "v2_final_observed_above_waist_all_three": actual_above_all,
        "v2_final_predicted_above_waist_all_three": predicted_above_all,
        "v2_final_predicted_pay_year_p50": round(float(prediction_frame["huya_predict_pay_year"].median()), 6),
        "v2_final_missing_predict_laxin": True,
        "v2_final_missing_predict_yingshou": True,
        "raw_identifiers_exported": False,
        "raw_anchor_names_exported": False,
        "raw_user_level_rows_exported": False,
    }
    (args.output_dir / "summary-profile.json").write_text(
        json.dumps(profile, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(profile, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
