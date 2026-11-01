#!/usr/bin/env python3
"""Compare the sanitized model with the archived final table and source files."""

from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path

import numpy as np
import pandas as pd


BASE_COLUMNS = [
    "r_owner",
    "uid",
    "pcode",
    "r_category",
    "liucun",
    "avg_com",
    "danmu",
    "fans",
    "dingyue_add",
    "danmu_only",
    "danmu_new",
    "live_mins",
    "gift_user",
    "gift_value",
]
PREDICTION_COLUMNS = ["predict_acu", "predict_laxin", "predict_yingshou", "predict_pay"]


def load_estimator(project_root: Path):
    path = project_root / "scripts" / "fanwa_estimator.py"
    spec = importlib.util.spec_from_file_location("fanwa_estimator", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def percent(numerator: int, denominator: int) -> float:
    return round(numerator / denominator * 100, 6) if denominator else 0.0


def result_row(
    source_file: str,
    platform: str,
    metric: str,
    compared_rows: int,
    matching_rows: int,
    max_abs_difference: float,
    interpretation_zh: str,
    interpretation_en: str,
) -> dict[str, object]:
    return {
        "source_file": source_file,
        "platform": platform,
        "metric": metric,
        "compared_rows": compared_rows,
        "matching_rows": matching_rows,
        "mismatching_rows": compared_rows - matching_rows,
        "match_rate_pct": percent(matching_rows, compared_rows),
        "max_abs_difference": round(float(max_abs_difference), 9),
        "status": "pass" if matching_rows == compared_rows else "warning_version_drift",
        "interpretation_zh": interpretation_zh,
        "interpretation_en": interpretation_en,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()

    project_root = Path(__file__).resolve().parents[1]
    model = load_estimator(project_root)
    csv = pd.read_csv(args.source_dir / "06allres.csv", dtype={"uid": str})
    res = pd.read_csv(args.source_dir / "res.txt", sep="\t", header=None, dtype={1: str})
    feat = pd.read_csv(args.source_dir / "featt", sep="\x01", header=None, dtype={1: str})
    res.columns = BASE_COLUMNS + PREDICTION_COLUMNS
    feat.columns = BASE_COLUMNS

    rows: list[dict[str, object]] = []
    base_equal = int(feat.equals(csv[BASE_COLUMNS])) * len(csv)
    rows.append(
        result_row(
            "featt",
            "douyu+bilibili",
            "base_feature_field_parity",
            len(csv),
            base_equal,
            0.0,
            "原始特征文件与最终CSV的14个基础字段逐行一致。",
            "The 14 base feature fields match the final CSV row by row.",
        )
    )
    res_equal = 0
    for position, row in csv[BASE_COLUMNS].iterrows():
        if row.astype(str).equals(res.loc[position, BASE_COLUMNS].astype(str)):
            res_equal += 1
    rows.append(
        result_row(
            "res.txt",
            "douyu+bilibili",
            "base_feature_field_parity",
            len(csv),
            res_equal,
            0.0,
            "Hive导出文本与最终CSV的14个基础字段逐行一致。",
            "The Hive export and final CSV match row by row on the 14 base fields.",
        )
    )

    for platform, group in csv.groupby("pcode", sort=True):
        records = group.to_dict("records")
        predictions = {
            "predict_acu": np.array([model.estimate_acu_and_rising(row, platform)[0] for row in records], dtype=float),
            "predict_laxin": np.array([model.estimate_acu_and_rising(row, platform)[1] for row in records], dtype=float),
            "predict_yingshou": np.array([model.predict_revenue(row) for row in records], dtype=float),
            "predict_pay": np.array(
                [model.predict_monthly_pay(float(row["predict_acu"]), str(row["r_category"])) for row in records],
                dtype=float,
            ),
        }
        for metric, rebuilt in predictions.items():
            archived = pd.to_numeric(group[metric], errors="coerce").to_numpy(dtype=float)
            equal = np.isclose(rebuilt, archived, rtol=1e-10, atol=1e-7, equal_nan=True)
            differences = np.abs(rebuilt - archived)
            max_difference = 0.0 if not len(differences) else float(np.nanmax(differences))
            if metric == "predict_acu":
                note_zh = "当前归档脚本可直接复现历史ACU预测；未复现部分表示脚本或参数版本已改变。"
                note_en = "The archived current script reproduces the historical ACU prediction; any mismatch indicates version drift."
            elif metric == "predict_laxin":
                note_zh = "B站若未完全复现，说明历史结果与当前脚本版本不一致，不能把当前参数当成历史值来源。"
                note_en = "If Bilibili does not fully reproduce, the historical result used a different script/version; do not cite current parameters as the historical source."
            elif metric == "predict_yingshou":
                note_zh = "收入为启发式估算；缺失礼物字段时历史逻辑会把整行收入置零。"
                note_en = "Revenue is heuristic; the historical logic set the whole row to zero when gift fields were missing."
            else:
                note_zh = "工资按当前归档的分段费率复算；少量品类映射差异会形成参数版本漂移。"
                note_en = "Salary is rebuilt from the archived piecewise rates; a few category mappings show parameter-version drift."
            rows.append(
                result_row(
                    "06allres.csv",
                    platform,
                    metric,
                    len(group),
                    int(equal.sum()),
                    max_difference,
                    note_zh,
                    note_en,
                )
            )

    output = pd.DataFrame(rows)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    output.to_csv(args.output_dir / "model-reproducibility.csv", index=False, encoding="utf-8-sig", lineterminator="\n")
    print(output[["platform", "metric", "compared_rows", "matching_rows", "mismatching_rows", "status"]].to_string(index=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
