from __future__ import annotations

import os
from pathlib import Path

import numpy as np
import pandas as pd
from openpyxl import load_workbook


SOURCE = Path(
    os.environ.get(
        "DOUYIN_VALORANT_ACU_CSV",
        r"C:\Users\tiany\Downloads\抖音无畏主播有效ACU_剔除大赛事日.csv",
    )
)
V1_WORKBOOK = Path(
    os.environ.get(
        "DOUYIN_VALORANT_V1_WORKBOOK",
        r"C:\Users\tiany\Desktop\无畏契约份额增长\无畏契约主播潜力分析\抖音无畏主播_月日均ACU持续领先分层_20261010.xlsx",
    )
)
V2_WORKBOOK = Path(
    os.environ.get(
        "DOUYIN_VALORANT_V2_WORKBOOK",
        r"C:\Users\tiany\Desktop\无畏契约份额增长\无畏契约主播潜力分析\抖音无畏主播_相邻环比持续领先分层_20261010.xlsx",
    )
)
OUT_DIR = Path(__file__).resolve().parents[1] / "artifacts"

MIN_MONTH_DAYS = 3
MIN_ANCHOR_MONTH_DAYS = 3
MIN_COMPARABLE_PAIRS = 2


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


def leading_counts(frame: pd.DataFrame) -> pd.DataFrame:
    return frame.groupby("r_lid").agg(
        comparable_pairs=("leads", "size"),
        leading_pairs=("leads", "sum"),
    )


def main() -> None:
    data = pd.read_csv(
        SOURCE,
        encoding="utf-8-sig",
        dtype={"r_lid": "string", "valid_acu_value": "float64"},
    )
    data["dt"] = pd.to_datetime(data["dt"], errors="coerce")
    data["month_no"] = data["mth"].str.replace("M", "", regex=False).astype(int)

    all_anchor_acu = data.groupby("r_lid")["valid_acu_value"].mean()
    all_anchor_tier = all_anchor_acu.map(tier)
    month_coverage = (
        data.groupby("month_no")
        .agg(
            observed_days=("dt", "nunique"),
            anchor_rows=("r_lid", "size"),
            unique_anchors=("r_lid", "nunique"),
            date_min=("dt", "min"),
            date_max=("dt", "max"),
        )
        .reset_index()
    )
    valid_months = sorted(
        month_coverage.loc[month_coverage["observed_days"] >= MIN_MONTH_DAYS, "month_no"]
    )

    raw_month = (
        data.groupby(["r_lid", "month_no"], as_index=False)["valid_acu_value"]
        .agg(month_acu="mean", observed_rows="size")
    )

    # V1: calendar-adjacent pairs, retaining one-day and two-day months.
    v1_pairs = [(1, 2), (2, 3), (5, 6), (6, 7), (7, 8), (8, 9), (9, 10)]
    tier_month_v1 = (
        raw_month.assign(tier=raw_month["r_lid"].map(all_anchor_tier))
        .groupby(["tier", "month_no"], as_index=False)["month_acu"]
        .mean()
        .rename(columns={"month_acu": "tier_acu"})
    )
    raw_pivot = raw_month.pivot(index="r_lid", columns="month_no", values="month_acu")
    tier_pivot = tier_month_v1.pivot(index="tier", columns="month_no", values="tier_acu")
    v1_mom_rows: list[pd.DataFrame] = []
    for previous, current in v1_pairs:
        if previous not in raw_pivot.columns or current not in raw_pivot.columns:
            continue
        paired = raw_pivot[[previous, current]].dropna()
        v1_mom_rows.append(
            pd.DataFrame(
                {
                    "r_lid": paired.index,
                    "month_no": current,
                    "anchor_mom": paired[current] / paired[previous].replace(0, np.nan) - 1,
                }
            )
        )
    tier_mom_rows: list[pd.DataFrame] = []
    for previous, current in v1_pairs:
        if previous not in tier_pivot.columns or current not in tier_pivot.columns:
            continue
        tier_mom_rows.append(
            pd.DataFrame(
                {
                    "tier": tier_pivot.index,
                    "month_no": current,
                    "tier_mom": tier_pivot[current] / tier_pivot[previous] - 1,
                }
            )
        )
    v1_compare = pd.concat(v1_mom_rows, ignore_index=True)
    v1_compare["tier"] = v1_compare["r_lid"].map(all_anchor_tier)
    v1_compare = v1_compare.merge(
        pd.concat(tier_mom_rows, ignore_index=True),
        on=["tier", "month_no"],
        how="left",
        validate="many_to_one",
    )
    v1_compare["leads"] = (v1_compare["anchor_mom"] > v1_compare["tier_mom"]).astype(int)
    v1 = leading_counts(v1_compare)
    v1_sustained = v1[
        (v1["comparable_pairs"] >= MIN_COMPARABLE_PAIRS)
        & (v1["leading_pairs"] == v1["comparable_pairs"])
    ]

    # V2: globally valid months and anchor-month minimum days; compare each
    # anchor with its previous available valid month, even if calendar months are missing.
    anchor_month_days = (
        data[data["month_no"].isin(valid_months)]
        .groupby(["r_lid", "month_no"], as_index=False)
        .agg(month_acu=("valid_acu_value", "mean"), observed_days=("dt", "nunique"))
    )
    anchor_month = anchor_month_days[
        anchor_month_days["observed_days"] >= MIN_ANCHOR_MONTH_DAYS
    ].copy()
    anchor_month["tier"] = anchor_month["r_lid"].map(all_anchor_tier)
    tier_month_v2 = (
        anchor_month.groupby(["tier", "month_no"], as_index=False)["month_acu"]
        .mean()
        .rename(columns={"month_acu": "tier_acu"})
    )
    tier_month_v2 = tier_month_v2.sort_values(["tier", "month_no"])
    tier_month_v2["tier_mom"] = (
        tier_month_v2["tier_acu"]
        / tier_month_v2.groupby("tier")["tier_acu"].shift(1).replace(0, np.nan)
        - 1
    )
    anchor_month = anchor_month.sort_values(["r_lid", "month_no"])
    anchor_month["previous_acu"] = anchor_month.groupby("r_lid")["month_acu"].shift(1)
    anchor_month["anchor_mom"] = (
        anchor_month["month_acu"] / anchor_month["previous_acu"].replace(0, np.nan) - 1
    )
    v2_compare = anchor_month.dropna(subset=["anchor_mom"]).merge(
        tier_month_v2[["tier", "month_no", "tier_mom"]],
        on=["tier", "month_no"],
        how="left",
        validate="many_to_one",
    )
    v2_compare["leads"] = (v2_compare["anchor_mom"] > v2_compare["tier_mom"]).astype(int)
    v2 = leading_counts(v2_compare)
    v2_sustained = v2[
        (v2["comparable_pairs"] >= MIN_COMPARABLE_PAIRS)
        & (v2["leading_pairs"] == v2["comparable_pairs"])
    ]

    def tier_counts(index: pd.Index) -> dict[str, int]:
        counts = all_anchor_tier.reindex(index).value_counts().to_dict()
        return {name: int(counts.get(name, 0)) for name in ["头部", "颈部", "腰部", "尾部"]}

    v1_tiers = tier_counts(v1_sustained.index)
    v2_tiers = tier_counts(v2_sustained.index)
    month_counts = {
        int(row.month_no): int(row.observed_days) for row in month_coverage.itertuples()
    }

    summary_zh = [
        {"指标": "源数据行数", "值": len(data)},
        {"指标": "源数据唯一主播ID数", "值": int(data["r_lid"].nunique())},
        {"指标": "开始日期", "值": data["dt"].min().strftime("%Y-%m-%d")},
        {"指标": "结束日期", "值": data["dt"].max().strftime("%Y-%m-%d")},
        {"指标": "有效月份", "值": ",".join(f"M{month}" for month in valid_months)},
        {"指标": "有至少2个可比月的_v2样本主播数", "值": int((v2["comparable_pairs"] >= MIN_COMPARABLE_PAIRS).sum())},
        {"指标": "v2_相邻可用月持续领先主播数", "值": len(v2_sustained)},
        {"指标": "v2_头部", "值": v2_tiers["头部"]},
        {"指标": "v2_颈部", "值": v2_tiers["颈部"]},
        {"指标": "v2_腰部", "值": v2_tiers["腰部"]},
        {"指标": "v2_尾部", "值": v2_tiers["尾部"]},
        {"指标": "v1_日历相邻月持续领先主播数", "值": len(v1_sustained)},
        {"指标": "v1_头部", "值": v1_tiers["头部"]},
        {"指标": "v1_颈部", "值": v1_tiers["颈部"]},
        {"指标": "v1_腰部", "值": v1_tiers["腰部"]},
        {"指标": "v1_尾部", "值": v1_tiers["尾部"]},
    ]
    summary_en = [
        {"metric": "source_rows", "value": len(data)},
        {"metric": "source_unique_anchor_ids", "value": int(data["r_lid"].nunique())},
        {"metric": "date_min", "value": data["dt"].min().strftime("%Y-%m-%d")},
        {"metric": "date_max", "value": data["dt"].max().strftime("%Y-%m-%d")},
        {"metric": "valid_months", "value": ",".join(f"M{month}" for month in valid_months)},
        {"metric": "v2_anchors_with_at_least_2_comparable_pairs", "value": int((v2["comparable_pairs"] >= MIN_COMPARABLE_PAIRS).sum())},
        {"metric": "v2_sustained_leaders", "value": len(v2_sustained)},
        {"metric": "v2_head", "value": v2_tiers["头部"]},
        {"metric": "v2_neck", "value": v2_tiers["颈部"]},
        {"metric": "v2_waist", "value": v2_tiers["腰部"]},
        {"metric": "v2_tail", "value": v2_tiers["尾部"]},
        {"metric": "v1_calendar_adjacent_sustained_leaders", "value": len(v1_sustained)},
        {"metric": "v1_head", "value": v1_tiers["头部"]},
        {"metric": "v1_neck", "value": v1_tiers["颈部"]},
        {"metric": "v1_waist", "value": v1_tiers["腰部"]},
        {"metric": "v1_tail", "value": v1_tiers["尾部"]},
    ]
    write_csv(OUT_DIR / "douyin-potential-summary.csv", summary_zh, ["指标", "值"])
    write_csv(OUT_DIR / "douyin-potential-summary.en.csv", summary_en, ["metric", "value"])

    coverage_zh = []
    coverage_en = []
    for row in month_coverage.itertuples():
        status = "有效" if row.month_no in valid_months else "无效"
        status_en = "valid" if row.month_no in valid_months else "invalid"
        coverage_zh.append(
            {
                "月份": f"M{row.month_no}",
                "观测天数": int(row.observed_days),
                "主播行数": int(row.anchor_rows),
                "唯一主播数": int(row.unique_anchors),
                "最早日期": row.date_min.strftime("%Y-%m-%d"),
                "最晚日期": row.date_max.strftime("%Y-%m-%d"),
                "状态": status,
            }
        )
        coverage_en.append(
            {
                "month": f"M{row.month_no}",
                "observed_days": int(row.observed_days),
                "anchor_rows": int(row.anchor_rows),
                "unique_anchors": int(row.unique_anchors),
                "date_min": row.date_min.strftime("%Y-%m-%d"),
                "date_max": row.date_max.strftime("%Y-%m-%d"),
                "status": status_en,
            }
        )
    write_csv(
        OUT_DIR / "douyin-potential-month-coverage.csv",
        coverage_zh,
        ["月份", "观测天数", "主播行数", "唯一主播数", "最早日期", "最晚日期", "状态"],
    )
    write_csv(
        OUT_DIR / "douyin-potential-month-coverage.en.csv",
        coverage_en,
        ["month", "observed_days", "anchor_rows", "unique_anchors", "date_min", "date_max", "status"],
    )

    comparison = [
        {
            "method": "v1_calendar_adjacent",
            "sustained": len(v1_sustained),
            "head": v1_tiers["头部"],
            "neck": v1_tiers["颈部"],
            "waist": v1_tiers["腰部"],
            "tail": v1_tiers["尾部"],
        },
        {
            "method": "v2_available_month_adjacent",
            "sustained": len(v2_sustained),
            "head": v2_tiers["头部"],
            "neck": v2_tiers["颈部"],
            "waist": v2_tiers["腰部"],
            "tail": v2_tiers["尾部"],
        },
    ]
    write_csv(
        OUT_DIR / "douyin-potential-method-comparison.en.csv",
        comparison,
        ["method", "sustained", "head", "neck", "waist", "tail"],
    )
    comparison_zh = [
        {
            "方法": "v1_日历相邻月" if row["method"] == "v1_calendar_adjacent" else "v2_相邻可用月",
            "持续领先主播数": row["sustained"],
            "头部": row["head"],
            "颈部": row["neck"],
            "腰部": row["waist"],
            "尾部": row["tail"],
        }
        for row in comparison
    ]
    write_csv(
        OUT_DIR / "douyin-potential-method-comparison.csv",
        comparison_zh,
        ["方法", "持续领先主播数", "头部", "颈部", "腰部", "尾部"],
    )

    checks = []
    for label, path, expected in [
        ("v1_workbook", V1_WORKBOOK, len(v1_sustained)),
        ("v2_workbook", V2_WORKBOOK, len(v2_sustained)),
    ]:
        if not path.exists():
            checks.append({"check": label, "status": "not_run", "recomputed": expected, "workbook": None})
            continue
        wb = load_workbook(path, read_only=True, data_only=True)
        ws = wb["持续领先主播名单"]
        workbook_rows = max(ws.max_row - 1, 0)
        wb.close()
        checks.append(
            {
                "check": label,
                "status": "pass" if workbook_rows == expected else "fail",
                "recomputed": expected,
                "workbook": workbook_rows,
            }
        )
    write_csv(
        OUT_DIR / "douyin-potential-validation.en.csv",
        checks,
        ["check", "status", "recomputed", "workbook"],
    )
    checks_zh = [
        {
            "检查": "v1工作簿" if row["check"] == "v1_workbook" else "v2工作簿",
            "结果": {"pass": "通过", "fail": "失败", "not_run": "未执行"}[row["status"]],
            "重算值": row["recomputed"],
            "工作簿值": row["workbook"],
        }
        for row in checks
    ]
    write_csv(
        OUT_DIR / "douyin-potential-validation.csv",
        checks_zh,
        ["检查", "结果", "重算值", "工作簿值"],
    )

    print(
        {
            "source_rows": len(data),
            "valid_month_days": month_counts,
            "v1_sustained": len(v1_sustained),
            "v2_comparable_anchors": int((v2["comparable_pairs"] >= MIN_COMPARABLE_PAIRS).sum()),
            "v2_sustained": len(v2_sustained),
        }
    )


if __name__ == "__main__":
    main()
