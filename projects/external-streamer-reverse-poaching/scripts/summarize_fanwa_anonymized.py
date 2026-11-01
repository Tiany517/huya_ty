#!/usr/bin/env python3
"""Create identifier-free, reproducible summaries from the fanwa archive."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

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


def numeric(series: pd.Series) -> pd.Series:
    return pd.to_numeric(series.replace({"\\N": None, "": None}), errors="coerce")


def quantile(series: pd.Series, q: float) -> float:
    values = numeric(series).dropna()
    return float(values.quantile(q)) if len(values) else math.nan


def build_platform_summary(frame: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    rows = []
    for platform, group in frame.groupby("pcode", sort=True):
        rows.append(
            {
                "平台": platform,
                "记录数": len(group),
                "唯一主播ID数": int(group["uid"].nunique()),
                "预测ACU为零比例_pct": round(float((numeric(group["predict_acu"]) <= 0).mean() * 100), 3),
                "预测拉新为零比例_pct": round(float((numeric(group["predict_laxin"]) <= 0).mean() * 100), 3),
                "预测ACU_P10": round(quantile(group["predict_acu"], 0.1), 3),
                "预测ACU_P50": round(quantile(group["predict_acu"], 0.5), 3),
                "预测ACU_P90": round(quantile(group["predict_acu"], 0.9), 3),
                "预测拉新_P50": round(quantile(group["predict_laxin"], 0.5), 3),
                "留存特征_P50": round(quantile(group["liucun"], 0.5), 6),
                "月直播分钟_P50": round(quantile(group["live_mins"], 0.5), 3),
                "预测收入特征_P50": round(quantile(group["predict_yingshou"], 0.5), 3),
                "预测月薪_P50": round(quantile(group["predict_pay"], 0.5), 3),
            }
        )
    zh = pd.DataFrame(rows)
    en = zh.rename(
        columns={
            "平台": "platform",
            "记录数": "records",
            "唯一主播ID数": "unique_anchor_ids",
            "预测ACU为零比例_pct": "zero_predict_acu_rate_pct",
            "预测拉新为零比例_pct": "zero_predict_laxin_rate_pct",
            "预测ACU_P10": "predict_acu_p10",
            "预测ACU_P50": "predict_acu_p50",
            "预测ACU_P90": "predict_acu_p90",
            "预测拉新_P50": "predict_laxin_p50",
            "留存特征_P50": "retention_feature_p50",
            "月直播分钟_P50": "live_minutes_p50",
            "预测收入特征_P50": "predicted_revenue_proxy_p50",
            "预测月薪_P50": "predicted_salary_p50",
        }
    )
    return zh, en


def build_category_summary(frame: pd.DataFrame, minimum_records: int = 20) -> tuple[pd.DataFrame, pd.DataFrame]:
    rows = []
    for (platform, category), group in frame.groupby(["pcode", "r_category"], dropna=False):
        if len(group) < minimum_records:
            continue
        rows.append(
            {
                "平台": platform,
                "品类": category,
                "记录数": len(group),
                "唯一主播ID数": int(group["uid"].nunique()),
                "预测ACU_P50": round(quantile(group["predict_acu"], 0.5), 3),
                "预测拉新_P50": round(quantile(group["predict_laxin"], 0.5), 3),
                "预测月薪_P50": round(quantile(group["predict_pay"], 0.5), 3),
                "预测ACU为零比例_pct": round(float((numeric(group["predict_acu"]) <= 0).mean() * 100), 3),
            }
        )
    zh = pd.DataFrame(rows).sort_values(["平台", "记录数", "品类"], ascending=[True, False, True])
    en = zh.rename(
        columns={
            "平台": "platform",
            "品类": "category",
            "记录数": "records",
            "唯一主播ID数": "unique_anchor_ids",
            "预测ACU_P50": "predict_acu_p50",
            "预测拉新_P50": "predict_laxin_p50",
            "预测月薪_P50": "predicted_salary_p50",
            "预测ACU为零比例_pct": "zero_predict_acu_rate_pct",
        }
    )
    return zh, en


def build_benchmark_summary(path: Path) -> tuple[pd.DataFrame, pd.DataFrame, dict[str, object]]:
    frame = pd.read_csv(path, encoding="gb18030")
    if frame.shape[1] != 3:
        raise ValueError(f"Expected 3 benchmark columns, found {frame.shape[1]}")
    frame.columns = ["dt", "anchor_acu", "anchor_count"]
    frame["dt"] = pd.to_datetime(frame["dt"], errors="raise")
    frame["anchor_acu"] = pd.to_numeric(frame["anchor_acu"], errors="raise")
    frame["anchor_count"] = pd.to_numeric(frame["anchor_count"], errors="raise")
    monthly = (
        frame.assign(month=frame["dt"].dt.to_period("M").astype(str))
        .groupby("month", as_index=False)
        .agg(
            observations=("dt", "size"),
            avg_daily_total_anchor_acu=("anchor_acu", "mean"),
            avg_daily_anchor_count=("anchor_count", "mean"),
        )
    )
    monthly["avg_acu_per_anchor"] = monthly["avg_daily_total_anchor_acu"] / monthly["avg_daily_anchor_count"]
    monthly = monthly.round(
        {"avg_daily_total_anchor_acu": 3, "avg_daily_anchor_count": 3, "avg_acu_per_anchor": 6}
    )
    zh = monthly.rename(
        columns={
            "month": "月份",
            "observations": "自然日观测数",
            "avg_daily_total_anchor_acu": "日均主播ACU合计",
            "avg_daily_anchor_count": "日均主播数",
            "avg_acu_per_anchor": "日均单主播ACU",
        }
    )
    en = monthly.rename(
        columns={
            "month": "month",
            "observations": "calendar_day_observations",
            "avg_daily_total_anchor_acu": "avg_daily_total_anchor_acu",
            "avg_daily_anchor_count": "avg_daily_anchor_count",
            "avg_acu_per_anchor": "avg_daily_acu_per_anchor",
        }
    )
    profile = {
        "source_rows": int(len(frame)),
        "first_date": frame["dt"].min().strftime("%Y-%m-%d"),
        "last_date": frame["dt"].max().strftime("%Y-%m-%d"),
        "duplicate_dates": int(frame["dt"].duplicated().sum()),
        "nonpositive_anchor_counts": int((frame["anchor_count"] <= 0).sum()),
    }
    return zh, en, profile


def write_csv(frame: pd.DataFrame, path: Path) -> None:
    frame.to_csv(path, index=False, encoding="utf-8-sig", lineterminator="\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path, help="Original 06allres.csv")
    parser.add_argument("--benchmark", required=True, type=Path, help="Original dd benchmark file")
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--minimum-category-records", type=int, default=20)
    args = parser.parse_args()

    frame = pd.read_csv(args.source, dtype={"uid": str})
    missing = [column for column in BASE_COLUMNS + PREDICTION_COLUMNS if column not in frame.columns]
    if missing:
        raise ValueError(f"Missing required columns: {missing}")
    if (frame["uid"].isna() | frame["pcode"].isna() | frame["r_category"].isna()).any():
        raise ValueError("uid, pcode, and r_category must be populated")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    platform_zh, platform_en = build_platform_summary(frame)
    category_zh, category_en = build_category_summary(frame, args.minimum_category_records)
    benchmark_zh, benchmark_en, benchmark_profile = build_benchmark_summary(args.benchmark)

    write_csv(platform_zh, args.output_dir / "platform-summary.csv")
    write_csv(platform_en, args.output_dir / "platform-summary.en.csv")
    write_csv(category_zh, args.output_dir / "platform-category-summary.csv")
    write_csv(category_en, args.output_dir / "platform-category-summary.en.csv")
    write_csv(benchmark_zh, args.output_dir / "huya-anchor-market-monthly.csv")
    write_csv(benchmark_en, args.output_dir / "huya-anchor-market-monthly.en.csv")

    profile = {
        "source_rows": int(len(frame)),
        "source_columns": int(frame.shape[1]),
        "platforms": {str(k): int(v) for k, v in frame.groupby("pcode").size().items()},
        "unique_anchor_ids": int(frame["uid"].nunique()),
        "duplicate_uid_platform_category_rows": int(frame.duplicated(["uid", "pcode", "r_category"]).sum()),
        "minimum_category_records": args.minimum_category_records,
        "category_rows_retained": int(len(category_zh)),
        "benchmark": benchmark_profile,
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
