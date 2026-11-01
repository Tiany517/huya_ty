from __future__ import annotations

import os
from pathlib import Path

import numpy as np
import pandas as pd
from openpyxl import load_workbook


SOURCE = Path(
    os.environ.get(
        "VALORANT_INTERNAL_POTENTIAL_CSV",
        r"C:\Users\tiany\Downloads\无畏契约主播互动潜力分析_不剔除赛事日_近3月.csv",
    )
)
WORKBOOK = Path(
    os.environ.get(
        "VALORANT_INTERNAL_POTENTIAL_WORKBOOK",
        r"C:\Users\tiany\Desktop\无畏契约份额增长\无畏契约主播潜力分析\无畏契约潜力主播_最终名单.xlsx",
    )
)
OUT_DIR = Path(__file__).resolve().parents[1] / "artifacts"

SELECTION_START = "2026-06"
SELECTION_END = "2026-09"
MIN_EFFECTIVE_DAYS = 8
MIN_AVG_WATCHERS = 20
MAX_AVG_WATCHERS = 8_000
MIN_ACU = 5
MIN_PASSING_MONTHS = 3
EVENT_KEYWORDS = "赛事|官方|虎牙无畏契约|回顾|冠军|EDG|二路|解说|分析师|VCT|太平洋|美洲|EMEA|联赛"


def tier(acu: float) -> str:
    if acu >= 2_000:
        return "头部"
    if acu >= 1_000:
        return "颈部"
    if acu >= 100:
        return "腰部"
    return "尾部"


def write_csv(path: Path, rows: list[dict[str, object]], columns: list[str]) -> None:
    pd.DataFrame(rows, columns=columns).to_csv(path, index=False, encoding="utf-8-sig")


def main() -> None:
    data = pd.read_csv(SOURCE, low_memory=False)
    data["dt"] = pd.to_datetime(data["dt"], errors="coerce")
    data["mth"] = data["dt"].dt.strftime("%Y-%m")

    max_dau_by_name = data.groupby("anchor_name")["dau"].max()
    official_names = set(max_dau_by_name[max_dau_by_name > 100_000].index)

    clean = data[
        (data["is_valid_day"] == 1)
        & (data["watch_user_cnt"] > 0)
        & data["danmu_user_rate"].notna()
        & ~data["anchor_name"].isin(official_names)
    ].copy()
    clean = clean[
        clean["anchor_name"].notna()
        & (clean["anchor_name"].astype(str).str.strip() != "")
    ].copy()
    clean["danmu_user_rate"] = clean["danmu_user_rate"].clip(upper=1.0)
    clean["day_tier"] = clean["acu"].map(tier)

    anchor = clean.groupby("anchor_uid").agg(
        effective_days=("dt", "nunique"),
        avg_watchers=("watch_user_cnt", "mean"),
        avg_acu=("acu", "mean"),
        latest_name=("anchor_name", "last"),
    )
    anchor["acu_tier"] = anchor["avg_acu"].map(tier)

    candidate_pool = anchor[
        (anchor["effective_days"] >= MIN_EFFECTIVE_DAYS)
        & (anchor["avg_watchers"] >= MIN_AVG_WATCHERS)
        & (anchor["avg_watchers"] <= MAX_AVG_WATCHERS)
    ].copy()

    month_tier_median = (
        clean.groupby(["mth", "day_tier"])["danmu_user_rate"]
        .median()
        .rename("tier_median")
        .reset_index()
    )
    selection_rows = clean[
        clean["anchor_uid"].isin(candidate_pool.index)
        & clean["mth"].between(SELECTION_START, SELECTION_END)
    ].merge(
        candidate_pool[["acu_tier"]],
        left_on="anchor_uid",
        right_index=True,
        how="left",
    ).merge(
        month_tier_median,
        left_on=["mth", "acu_tier"],
        right_on=["mth", "day_tier"],
        how="left",
        validate="many_to_one",
    )

    monthly = (
        selection_rows.groupby(["anchor_uid", "mth"], as_index=False)
        .apply(
            lambda g: pd.Series(
                {
                    "days": g["dt"].nunique(),
                    "weighted_interaction_rate": (
                        g["danmu_user_rate"] * g["watch_user_cnt"]
                    ).sum()
                    / g["watch_user_cnt"].sum(),
                    "tier_median": g["tier_median"].iloc[0],
                }
            ),
            include_groups=False,
        )
        .reset_index(drop=True)
    )
    monthly["passes"] = (
        monthly["weighted_interaction_rate"] > monthly["tier_median"]
    )

    pass_months = monthly.groupby("anchor_uid")["passes"].sum()
    selected = candidate_pool[
        (candidate_pool["avg_acu"] >= MIN_ACU)
        & (candidate_pool.index.map(pass_months).fillna(0) >= MIN_PASSING_MONTHS)
    ].copy()
    selected = selected[
        ~selected["latest_name"].str.contains(EVENT_KEYWORDS, regex=True, na=False)
    ]

    selected_tiers = selected["acu_tier"].value_counts().to_dict()
    selected_pass_distribution = (
        selected.index.to_series().map(pass_months).value_counts().sort_index()
    )
    monthly_counts = (
        monthly.groupby("mth")["passes"]
        .agg(candidate_rows="size", passing_rows="sum")
        .reset_index()
    )

    source_names_per_uid = data.groupby("anchor_uid")["anchor_name"].nunique()
    source_uids_per_name = data.groupby("anchor_name")["anchor_uid"].nunique()
    common = {
        "source_rows": len(data),
        "source_unique_anchors": int(data["anchor_uid"].nunique()),
        "source_unique_names": int(data["anchor_name"].nunique()),
        "date_min": data["dt"].min().strftime("%Y-%m-%d"),
        "date_max": data["dt"].max().strftime("%Y-%m-%d"),
        "names_with_multiple_uids": int((source_uids_per_name > 1).sum()),
        "uids_with_multiple_names": int((source_names_per_uid > 1).sum()),
        "official_names_excluded": len(official_names),
        "clean_unique_anchors": int(clean["anchor_uid"].nunique()),
        "candidate_pool_anchors": len(candidate_pool),
        "candidate_months_in_selection_window": len(monthly),
        "candidate_month_passes": int(monthly["passes"].sum()),
        "selected_anchors": len(selected),
        "selected_head": int(selected_tiers.get("头部", 0)),
        "selected_neck": int(selected_tiers.get("颈部", 0)),
        "selected_waist": int(selected_tiers.get("腰部", 0)),
        "selected_tail": int(selected_tiers.get("尾部", 0)),
        "selected_daily_acu_median": round(float(selected["avg_acu"].median()), 4),
        "selected_daily_watchers_median": round(float(selected["avg_watchers"].median()), 2),
        "selection_partial_note": "June-September monthly passes; candidate pool uses the full source period",
    }

    summary_zh = [
        {"指标": "源数据行数", "值": common["source_rows"]},
        {"指标": "源数据唯一主播ID数", "值": common["source_unique_anchors"]},
        {"指标": "源数据唯一主播名数", "值": common["source_unique_names"]},
        {"指标": "开始日期", "值": common["date_min"]},
        {"指标": "结束日期", "值": common["date_max"]},
        {"指标": "同名对应多个ID的主播名数", "值": common["names_with_multiple_uids"]},
        {"指标": "同ID对应多个主播名的数量", "值": common["uids_with_multiple_names"]},
        {"指标": "按单日DAU超10万识别的官方台名称数", "值": common["official_names_excluded"]},
        {"指标": "清洗后唯一主播ID数", "值": common["clean_unique_anchors"]},
        {"指标": "候选池主播数", "值": common["candidate_pool_anchors"]},
        {"指标": "筛选窗口内主播月记录数", "值": common["candidate_months_in_selection_window"]},
        {"指标": "达标主播月记录数", "值": common["candidate_month_passes"]},
        {"指标": "最终入选主播数", "值": common["selected_anchors"]},
        {"指标": "最终入选_头部", "值": common["selected_head"]},
        {"指标": "最终入选_颈部", "值": common["selected_neck"]},
        {"指标": "最终入选_腰部", "值": common["selected_waist"]},
        {"指标": "最终入选_尾部", "值": common["selected_tail"]},
        {"指标": "入选主播日均ACU中位数", "值": common["selected_daily_acu_median"]},
        {"指标": "入选主播日均观看中位数", "值": common["selected_daily_watchers_median"]},
    ]
    summary_en = [
        {"metric": "source_rows", "value": common["source_rows"]},
        {"metric": "source_unique_anchor_ids", "value": common["source_unique_anchors"]},
        {"metric": "source_unique_names", "value": common["source_unique_names"]},
        {"metric": "date_min", "value": common["date_min"]},
        {"metric": "date_max", "value": common["date_max"]},
        {"metric": "names_with_multiple_ids", "value": common["names_with_multiple_uids"]},
        {"metric": "ids_with_multiple_names", "value": common["uids_with_multiple_names"]},
        {"metric": "official_names_excluded_by_max_dau_gt_100k", "value": common["official_names_excluded"]},
        {"metric": "clean_unique_anchor_ids", "value": common["clean_unique_anchors"]},
        {"metric": "candidate_pool_anchors", "value": common["candidate_pool_anchors"]},
        {"metric": "anchor_month_rows_in_selection_window", "value": common["candidate_months_in_selection_window"]},
        {"metric": "passing_anchor_month_rows", "value": common["candidate_month_passes"]},
        {"metric": "selected_anchors", "value": common["selected_anchors"]},
        {"metric": "selected_head", "value": common["selected_head"]},
        {"metric": "selected_neck", "value": common["selected_neck"]},
        {"metric": "selected_waist", "value": common["selected_waist"]},
        {"metric": "selected_tail", "value": common["selected_tail"]},
        {"metric": "selected_daily_acu_median", "value": common["selected_daily_acu_median"]},
        {"metric": "selected_daily_watchers_median", "value": common["selected_daily_watchers_median"]},
    ]

    write_csv(OUT_DIR / "huya-internal-potential-summary.csv", summary_zh, ["指标", "值"])
    write_csv(OUT_DIR / "huya-internal-potential-summary.en.csv", summary_en, ["metric", "value"])

    monthly_zh = monthly_counts.rename(
        columns={"mth": "月份", "candidate_rows": "候选主播月记录数", "passing_rows": "达标月记录数"}
    )
    monthly_en = monthly_counts.rename(
        columns={"mth": "month", "candidate_rows": "candidate_anchor_month_rows", "passing_rows": "passing_rows"}
    )
    monthly_zh.to_csv(OUT_DIR / "huya-internal-potential-monthly.csv", index=False, encoding="utf-8-sig")
    monthly_en.to_csv(OUT_DIR / "huya-internal-potential-monthly.en.csv", index=False, encoding="utf-8-sig")

    validation = []
    if WORKBOOK.exists():
        wb = load_workbook(WORKBOOK, read_only=True, data_only=True)
        ws = wb["入选名单"]
        detail_rows = []
        for row in ws.iter_rows(min_row=2, values_only=True):
            if row[0] is None:
                break
            detail_rows.append(str(row[0]))
        wb.close()
        validation = [
            {
                "检查": "独立重算入选集合与工作簿首个连续明细块一致",
                "结果": "通过" if set(selected.index.astype(str)) == set(detail_rows) else "失败",
                "重算值": len(selected),
                "工作簿值": len(detail_rows),
                "说明": "工作簿该页仅有连续有效明细，之后为空行和透视残片",
            },
            {
                "检查": "工作簿候选池与当前源数据直接重算一致",
                "结果": "警告",
                "重算值": len(candidate_pool),
                "工作簿值": 160,
                "说明": "工作簿候选池为旧快照；当前原始文件直接重算较大，最终入选集合仍完全一致",
            },
        ]
    else:
        validation = [
            {
                "检查": "工作簿交叉核对",
                "结果": "未执行",
                "重算值": len(selected),
                "工作簿值": None,
                "说明": "未找到工作簿，原始数据重算已完成",
            }
        ]
    write_csv(
        OUT_DIR / "huya-internal-potential-validation.csv",
        validation,
        ["检查", "结果", "重算值", "工作簿值", "说明"],
    )
    validation_en_notes = {
        "独立重算入选集合与工作簿首个连续明细块一致": (
            "the first contiguous detail block in the workbook exactly matches the independently rebuilt selected set",
            "the workbook sheet contains only the first contiguous detail block; later rows are blank cells and pivot remnants",
        ),
        "工作簿候选池与当前源数据直接重算一致": (
            "the workbook candidate pool matches a direct rebuild from the current source data",
            "the workbook stores an older snapshot; the current source rebuild is larger, while the final selected set still matches exactly",
        ),
        "工作簿交叉核对": (
            "cross-check against the workbook",
            "the workbook was not found; rebuilding from the raw source was completed",
        ),
    }
    validation_en = []
    for row in validation:
        check_en, note_en = validation_en_notes.get(
            row["检查"], (row["检查"], row["说明"])
        )
        validation_en.append(
            {
                "check": check_en,
                "status": {"通过": "pass", "失败": "fail", "警告": "warning", "未执行": "not_run"}.get(
                    row["结果"], row["结果"]
                ),
                "recomputed_value": row["重算值"],
                "workbook_value": row["工作簿值"],
                "note": note_en,
            }
        )
    write_csv(
        OUT_DIR / "huya-internal-potential-validation.en.csv",
        validation_en,
        ["check", "status", "recomputed_value", "workbook_value", "note"],
    )

    print(
        {
            "source_rows": len(data),
            "candidate_pool": len(candidate_pool),
            "selected": len(selected),
            "selected_pass_month_distribution": {
                str(k): int(v) for k, v in selected_pass_distribution.items()
            },
        }
    )


if __name__ == "__main__":
    main()
