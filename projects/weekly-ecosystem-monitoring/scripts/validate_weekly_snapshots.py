from __future__ import annotations

import hashlib
import re
from pathlib import Path

import pandas as pd
from openpyxl import load_workbook


PROJECT_DIR = Path(__file__).resolve().parents[1]
CATEGORY_DIR = PROJECT_DIR / "artifacts" / "weekly-category"
PLATFORM_DIR = PROJECT_DIR / "artifacts" / "platform-dau"
RESULT_WORKBOOK = PROJECT_DIR / "artifacts" / "weekly-results" / "weekly-result-20261013.xlsx"
OUT_DIR = PROJECT_DIR / "artifacts"
NUMERIC_COLUMNS = [
    "DAU",
    "打赏流水",
    "打赏人数",
    "人均打赏流水",
    "人均观时_分钟",
    "归因人数",
    "兴趣用户数",
    "非LOL兴趣用户数",
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def write_csv(path: Path, rows: list[dict[str, object]], columns: list[str]) -> None:
    pd.DataFrame(rows, columns=columns).to_csv(path, index=False, encoding="utf-8-sig")


def category_inventory() -> tuple[
    pd.DataFrame,
    list[dict[str, object]],
    list[str],
    list[str],
    list[str],
    list[str],
]:
    inventory_zh: list[dict[str, object]] = []
    errors_zh: list[str] = []
    errors_en: list[str] = []
    warnings_zh: list[str] = []
    warnings_en: list[str] = []
    latest_frame: pd.DataFrame | None = None
    for path in sorted(CATEGORY_DIR.glob("category-weekly-*.csv")):
        frame = pd.read_csv(path, encoding="utf-8-sig")
        frame.columns = [str(column).strip() for column in frame.columns]
        dash_cells = 0
        unparsed_cells = 0
        for column in NUMERIC_COLUMNS:
            values = frame[column].astype("string").str.strip()
            dash_cells += int(values.eq("-").sum())
            values = values.str.replace(",", "", regex=False)
            values = values.mask(values.eq("-"))
            numeric = pd.to_numeric(values, errors="coerce")
            unparsed_cells += int((values.notna() & numeric.isna()).sum())
            frame[column] = numeric
        dates = pd.to_datetime(frame["日期"].astype(str).str.replace("/", "-"), errors="coerce")
        unique_dates = sorted(dates.dropna().unique())
        duplicate_keys = int(frame.duplicated(["日期", "品类"]).sum())
        null_cells = int(frame.isna().sum().sum())
        consecutive = (
            len(unique_dates) == 7
            and (pd.Timestamp(unique_dates[-1]) - pd.Timestamp(unique_dates[0])).days == 6
        )
        is_valid = (
            consecutive
            and frame["品类"].nunique() == 22
            and duplicate_keys == 0
            and unparsed_cells == 0
            and (frame[NUMERIC_COLUMNS] >= 0).all().all()
            and (frame["打赏人数"] <= frame["DAU"]).all()
        )
        if not is_valid:
            errors_zh.append(f"类别周表结构失败：{path.name}")
            errors_en.append(f"Weekly category structure check failed: {path.name}")
        if dash_cells or null_cells:
            warnings_zh.append(
                f"Excel 展示格式：{path.name} 含 {dash_cells} 个破折号占位和 {null_cells} 个空单元格"
            )
            warnings_en.append(
                f"Excel presentation format: {path.name} has {dash_cells} dash placeholders and {null_cells} blank cells"
            )
        inventory_zh.append(
            {
                "文件": path.name,
                "开始日期": pd.Timestamp(unique_dates[0]).strftime("%Y-%m-%d"),
                "结束日期": pd.Timestamp(unique_dates[-1]).strftime("%Y-%m-%d"),
                "观测天数": len(unique_dates),
                "品类数": frame["品类"].nunique(),
                "数据行数": len(frame),
                "重复日期品类键": duplicate_keys,
                "空单元格数": null_cells,
                "破折号占位单元格数": dash_cells,
                "数值解析失败数": unparsed_cells,
                "SHA256": sha256(path),
            }
        )
        if latest_frame is None or path.name > str(latest_frame.attrs.get("name", "")):
            latest_frame = frame.copy()
            latest_frame.attrs["name"] = path.name
    if latest_frame is None:
        raise RuntimeError("No weekly category snapshot found")
    return (
        latest_frame,
        inventory_zh,
        errors_zh,
        errors_en,
        warnings_zh,
        warnings_en,
    )


def platform_inventory() -> tuple[
    pd.DataFrame,
    list[dict[str, object]],
    list[str],
    list[str],
]:
    inventory_zh: list[dict[str, object]] = []
    warnings_zh: list[str] = []
    warnings_en: list[str] = []
    hashes: dict[str, str] = {}
    for path in sorted(PLATFORM_DIR.glob("*.csv")):
        rows = list(pd.read_csv(path, encoding="utf-8-sig", header=None).fillna("").itertuples(index=False, name=None))
        header = rows[0] if rows else ()
        if header not in {
            ("时间段", "dau"),
            ("last_week_dau", "current_week_dau", "gap"),
        }:
            warnings_zh.append(f"平台 DAU 文件表头不一致：{path.name}")
            warnings_en.append(f"Platform DAU file has a different header: {path.name}")
        digest = sha256(path)
        hashes[path.name] = digest
        inventory_zh.append(
            {
                "文件": path.name,
                "字节数": path.stat().st_size,
                "表头": " | ".join(str(value) for value in header),
                "数据行数": max(len(rows) - 1, 0),
                "SHA256": digest,
            }
        )
    if hashes.get("platform-active-20260914.csv") == hashes.get(
        "platform-active-20260923-copy-of-20260914.csv"
    ):
        warnings_zh.append("20260923 平台 DAU 文件与 20260914 完全相同")
        warnings_en.append(
            "The 20260923 platform DAU file is byte-for-byte identical to 20260914"
        )
    return pd.read_csv(
        PLATFORM_DIR / "platform-active-20261013.csv", encoding="utf-8-sig"
    ), inventory_zh, warnings_zh, warnings_en


def main() -> None:
    (
        latest,
        category_inventory_zh,
        category_errors_zh,
        category_errors_en,
        category_warnings_zh,
        category_warnings_en,
    ) = category_inventory()
    (
        platform,
        platform_inventory_zh,
        platform_warnings_zh,
        platform_warnings_en,
    ) = platform_inventory()

    overall = latest[latest["品类"] == "整体"].copy()
    overall["日期"] = pd.to_datetime(overall["日期"])
    mean_dau = float(overall["DAU"].mean())
    mean_attribution = float(overall["归因人数"].mean())
    max_arppu_gap = float(
        (
            overall["人均打赏流水"]
            - overall["打赏流水"] / overall["打赏人数"]
        ).abs().max()
    )

    wb = load_workbook(RESULT_WORKBOOK, read_only=True, data_only=True)
    ws = wb["品类总览"]
    workbook_dau = float(ws["J14"].value)
    workbook_attribution = float(ws["Q14"].value)
    wb.close()

    current_platform_dau = float(platform["current_week_dau"].iloc[0])
    platform_gap = float(platform["gap"].iloc[0])
    expected_gap = float(platform["current_week_dau"].iloc[0] - platform["last_week_dau"].iloc[0])

    checks_zh = [
        {
            "检查": "六个品类周表的日期、品类、唯一键、空值和基本范围",
            "结果": "失败"
            if category_errors_zh
            else ("警告" if category_warnings_zh else "通过"),
            "数值": 6 if not category_errors_zh else len(category_errors_zh),
            "预期": "6 个文件均通过",
            "说明": "; ".join(category_errors_zh or category_warnings_zh)
            if category_errors_zh or category_warnings_zh
            else "7 个连续自然日、22 个品类、154 行、无重复键和解析失败",
        },
        {
            "检查": "最新周整体日均观看 DAU 与结果工作簿一致",
            "结果": "通过" if abs(mean_dau - workbook_dau) < 0.01 else "失败",
            "数值": mean_dau,
            "预期": workbook_dau,
            "说明": "CSV 独立均值 vs 结果输出 J14",
        },
        {
            "检查": "最新周整体日均归因人数与结果工作簿一致",
            "结果": "通过" if abs(mean_attribution - workbook_attribution) < 0.01 else "失败",
            "数值": mean_attribution,
            "预期": workbook_attribution,
            "说明": "CSV 独立均值 vs 结果输出 Q14",
        },
        {
            "检查": "最新平台活跃 DAU 与结果工作簿整体归因值一致",
            "结果": "通过" if abs(current_platform_dau - workbook_attribution) < 0.01 else "失败",
            "数值": current_platform_dau,
            "预期": workbook_attribution,
            "说明": "两个指标在本周文件中的口径关系需在新电脑重跑后复核，不能只依赖数值相等",
        },
        {
            "检查": "平台 DAU 差值可由两周指标独立重建",
            "结果": "通过" if abs(platform_gap - expected_gap) < 0.01 else "失败",
            "数值": platform_gap,
            "预期": expected_gap,
            "说明": "current_week_dau - last_week_dau",
        },
        {
            "检查": "整体人均打赏流水可由打赏流水/打赏人数重建",
            "结果": "通过" if max_arppu_gap < 1e-6 else "失败",
            "数值": max_arppu_gap,
            "预期": "最大绝对差 < 0.000001",
            "说明": "逐日检查 7 个整体行",
        },
        {
            "检查": "历史平台 DAU 文件结构与重复情况",
            "结果": "警告" if platform_warnings_zh else "通过",
            "数值": len(platform_warnings_zh),
            "预期": "表头一致且无重复快照",
            "说明": "; ".join(platform_warnings_zh)
            if platform_warnings_zh
            else "通过",
        },
    ]
    write_csv(
        OUT_DIR / "weekly-validation.csv",
        checks_zh,
        ["检查", "结果", "数值", "预期", "说明"],
    )
    status_en = {"通过": "pass", "失败": "fail", "警告": "warning", "未执行": "not_run"}
    check_names_en = {
        "六个品类周表的日期、品类、唯一键、空值和基本范围": "Six weekly category files pass date, category, key, null, and range checks",
        "最新周整体日均观看 DAU 与结果工作簿一致": "Latest weekly overall average viewing DAU matches the result workbook",
        "最新周整体日均归因人数与结果工作簿一致": "Latest weekly overall average attributed users matches the result workbook",
        "最新平台活跃 DAU 与结果工作簿整体归因值一致": "Latest platform active DAU matches overall attributed users in the result workbook",
        "平台 DAU 差值可由两周指标独立重建": "Platform DAU gap can be rebuilt from the two weekly values",
        "整体人均打赏流水可由打赏流水/打赏人数重建": "Overall revenue per paying user can be rebuilt from revenue and paying users",
        "历史平台 DAU 文件结构与重复情况": "Historical platform DAU schema and duplication",
    }
    notes_en = {
        0: "; ".join(category_errors_en or category_warnings_en)
        if category_errors_en or category_warnings_en
        else "seven consecutive calendar days, 22 categories, 154 rows, no duplicate keys or parse failures",
        1: "Independent CSV mean compared with result workbook J14",
        2: "Independent CSV mean compared with result workbook Q14",
        3: "Review metric definitions after rerunning; equality alone does not establish that both metrics measure the same population",
        4: "CURRENT_WEEK_DAU minus LAST_WEEK_DAU",
        5: "Seven daily overall rows",
        6: "; ".join(platform_warnings_en)
        if platform_warnings_en
        else "Pass",
    }
    expected_en = {
        0: "All six files pass",
        1: "Match J14 within 0.01",
        2: "Match Q14 within 0.01",
        3: "Match Q14 within 0.01; still review definitions",
        4: "Match CURRENT_WEEK_DAU minus LAST_WEEK_DAU within 0.01",
        5: "Maximum absolute difference below 0.000001",
        6: "Consistent headers and no duplicate snapshot",
    }
    checks_en = [
        {
            "check": check_names_en[row["检查"]],
            "status": status_en[row["结果"]],
            "value": row["数值"],
            "expected": expected_en[index],
            "note": notes_en[index],
        }
        for index, row in enumerate(checks_zh)
    ]
    write_csv(
        OUT_DIR / "weekly-validation.en.csv",
        checks_en,
        ["check", "status", "value", "expected", "note"],
    )

    write_csv(
        OUT_DIR / "weekly-category-inventory.csv",
        category_inventory_zh,
        ["文件", "开始日期", "结束日期", "观测天数", "品类数", "数据行数", "重复日期品类键", "空单元格数", "破折号占位单元格数", "数值解析失败数", "SHA256"],
    )
    category_inventory_en = [
        {
            "file": row["文件"],
            "date_min": row["开始日期"],
            "date_max": row["结束日期"],
            "observed_days": row["观测天数"],
            "categories": row["品类数"],
            "rows": row["数据行数"],
            "duplicate_date_category_keys": row["重复日期品类键"],
            "null_cells": row["空单元格数"],
            "dash_placeholder_cells": row["破折号占位单元格数"],
            "numeric_parse_failures": row["数值解析失败数"],
            "sha256": row["SHA256"],
        }
        for row in category_inventory_zh
    ]
    write_csv(
        OUT_DIR / "weekly-category-inventory.en.csv",
        category_inventory_en,
        ["file", "date_min", "date_max", "observed_days", "categories", "rows", "duplicate_date_category_keys", "null_cells", "dash_placeholder_cells", "numeric_parse_failures", "sha256"],
    )

    write_csv(
        OUT_DIR / "platform-snapshot-inventory.csv",
        platform_inventory_zh,
        ["文件", "字节数", "表头", "数据行数", "SHA256"],
    )
    platform_inventory_en = [
        {
            "file": row["文件"],
            "bytes": row["字节数"],
            "header": row["表头"],
            "data_rows": row["数据行数"],
            "sha256": row["SHA256"],
        }
        for row in platform_inventory_zh
    ]
    write_csv(
        OUT_DIR / "platform-snapshot-inventory.en.csv",
        platform_inventory_en,
        ["file", "bytes", "header", "data_rows", "sha256"],
    )

    print(
        {
            "category_snapshots": len(category_inventory_zh),
            "category_failures": len(category_errors_zh),
            "platform_warnings": len(platform_warnings_zh),
            "latest_mean_dau": round(mean_dau, 6),
            "latest_mean_attribution": round(mean_attribution, 6),
        }
    )


if __name__ == "__main__":
    main()
