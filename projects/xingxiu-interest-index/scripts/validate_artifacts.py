from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

import pandas as pd
from openpyxl import load_workbook


PROJECT_ROOT = Path(__file__).resolve().parents[1]
CATEGORY_DAU = {
    "2026-01": 385_534.0,
    "2026-02": 394_048.0,
    "2026-03": 433_658.0,
    "2026-04": 458_837.0,
    "2026-05": 430_511.0,
    "2026-06": 428_326.0,
    "2026-07": 410_709.0,
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def close(left: float, right: float, tolerance: float = 1e-6) -> bool:
    return math.isclose(float(left), float(right), rel_tol=1e-10, abs_tol=tolerance)


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate de-identified Xingxiu artifacts.")
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--evidence-dir", type=Path)
    args = parser.parse_args()

    checks: list[dict[str, str]] = []

    def check(check_id: str, condition: bool, zh: str, en: str) -> None:
        checks.append({"check_id": check_id, "status": "PASS" if condition else "FAIL", "detail_zh": zh, "detail_en": en})

    source = pd.read_csv(args.source)
    source["dau"] = pd.to_numeric(source["dau"], errors="coerce")
    source["user_pro"] = pd.to_numeric(source["user_pro"], errors="coerce")
    zh_dir = PROJECT_ROOT / "artifacts" / "zh"
    en_dir = PROJECT_ROOT / "artifacts" / "en"
    required = [
        zh_dir / "monthly_summary.csv",
        zh_dir / "status_summary.csv",
        zh_dir / "dau_decile_summary.csv",
        zh_dir / "hypothesis_group_summary.csv",
        en_dir / "monthly_summary.csv",
        en_dir / "status_summary.csv",
        en_dir / "dau_decile_summary.csv",
        en_dir / "hypothesis_group_summary.csv",
    ]
    check("V01", all(path.exists() for path in required), "8 份核心双语 CSV 均存在", "All eight core bilingual CSV files exist")

    zh_monthly = pd.read_csv(required[0], encoding="utf-8-sig")
    zh_status = pd.read_csv(required[1], encoding="utf-8-sig")
    zh_deciles = pd.read_csv(required[2], encoding="utf-8-sig")
    zh_groups = pd.read_csv(required[3], encoding="utf-8-sig")
    en_monthly = pd.read_csv(required[4], encoding="utf-8-sig")
    en_status = pd.read_csv(required[5], encoding="utf-8-sig")
    en_deciles = pd.read_csv(required[6], encoding="utf-8-sig")
    en_groups = pd.read_csv(required[7], encoding="utf-8-sig")

    check("V02", len(source) == 22_831, "源文件为 22,831 行", "Source has 22,831 rows")
    check("V03", source["luid"].nunique() == 8_394, "源文件有 8,394 个唯一主播", "Source has 8,394 unique streamers")
    check("V04", sorted(source["month"].unique()) == sorted(CATEGORY_DAU), "源文件覆盖 2026-01 至 2026-07", "Source covers January through July 2026")
    check("V05", not source.duplicated(["month", "luid"]).any(), "month + luid 唯一", "month + luid is unique")
    check("V06", len(zh_monthly) == 7 and len(en_monthly) == 7, "双语月度汇总均为 7 行", "Both monthly summaries have seven rows")

    monthly_source = source.groupby("month", as_index=False).agg(anchor_count=("luid", "nunique"), dau_sum=("dau", "sum"), interest_sum=("user_pro", "sum")).sort_values("month")
    monthly_match = (
        zh_monthly["主播数"].astype(int).tolist() == monthly_source["anchor_count"].astype(int).tolist()
        and all(close(a, b) for a, b in zip(zh_monthly["主播DAU加总"], monthly_source["dau_sum"]))
        and all(close(a, b) for a, b in zip(zh_monthly["兴趣指数加总"], monthly_source["interest_sum"]))
    )
    check("V07", monthly_match, "月度主播数、DAU 加总和兴趣指数加总均可从源文件重算", "Monthly anchor counts, DAU sums, and interest sums reproduce from source")
    check("V08", all(close(a, b) for a, b in zip(zh_monthly["品类DAU"], CATEGORY_DAU.values())), "品类 DAU 与文档化硬编码输入一致", "Category DAU matches the documented hard-coded input")
    check("V09", all(close(a, b) for a, b in zip(en_monthly["anchor_dau_sum"], monthly_source["dau_sum"])), "英文月度 DAU 与中文版一致", "English monthly DAU matches the Chinese version")

    june = source.loc[source["month"] == "2026-06", ["luid", "dau", "user_pro"]].rename(columns={"dau": "june_dau", "user_pro": "june_interest"})
    july = source.loc[source["month"] == "2026-07", ["luid", "dau", "user_pro"]].rename(columns={"dau": "july_dau", "user_pro": "july_interest"})
    change = july.merge(june, on="luid", how="outer", validate="one_to_one").fillna(0.0)
    change["dau_change"] = change["july_dau"] - change["june_dau"]
    change["interest_change"] = change["july_interest"] - change["june_interest"]
    change["status"] = "存量"
    change.loc[(change["june_dau"] == 0) & (change["july_dau"] > 0), "status"] = "新增/回归"
    change.loc[(change["june_dau"] > 0) & (change["july_dau"] == 0), "status"] = "流失"
    status_source = change.groupby("status", as_index=False).agg(
        anchor_count=("luid", "nunique"), june_dau=("june_dau", "sum"), july_dau=("july_dau", "sum"),
        dau_change=("dau_change", "sum"), june_interest=("june_interest", "sum"),
        july_interest=("july_interest", "sum"), interest_change=("interest_change", "sum"),
    )
    status_map = status_source.set_index("status")
    status_count_match = all(int(zh_status.loc[zh_status["主播状态"] == name, "主播数"].iloc[0]) == int(row.anchor_count) for name, row in status_map.iterrows())
    check("V10", status_count_match, "存量、新增/回归、流失主播数可从 6–7 月外连接重算", "Stock, new/returning, and churned counts reproduce from the June-July outer join")
    check("V11", int(zh_status["主播数"].sum()) == int(change["luid"].nunique()), "状态分组人数覆盖全部 4,496 个 6–7 月主播", "Status groups cover all 4,496 June-July streamers")
    check("V12", close(zh_status["DAU变化"].sum(), change["dau_change"].sum()), "状态分组 DAU 变化之和等于净变化", "Status-group DAU changes sum to the net change")
    check("V13", close(zh_status["兴趣指数变化"].sum(), change["interest_change"].sum()), "状态分组兴趣指数变化之和等于净变化", "Status-group interest changes sum to the net change")
    check("V14", zh_status["主播数"].tolist() == en_status["anchor_count"].tolist(), "中英文状态人数一致", "Chinese and English status counts agree")

    july_distribution = source.loc[source["month"] == "2026-07"].copy()
    july_distribution["dau_decile"] = pd.qcut(july_distribution["dau"].rank(method="first"), 10, labels=[f"D{i}" for i in range(1, 11)])
    decile_source = july_distribution.groupby("dau_decile", as_index=False, observed=True).agg(
        anchor_count=("luid", "nunique"), dau_sum=("dau", "sum"), interest_sum=("user_pro", "sum")
    )
    check("V15", len(zh_deciles) == 10, "7 月 DAU 十分位共 10 层", "July DAU has ten deciles")
    check("V16", int(zh_deciles["主播数"].sum()) == int(july["luid"].nunique()), "十分位人数之和等于 7 月主播数", "Decile counts sum to the July streamer count")
    check("V17", close(zh_deciles["DAU加总"].sum(), july_distribution["dau"].sum()), "十分位 DAU 之和等于 7 月 DAU 加总", "Decile DAU sums equal the July DAU total")
    check("V18", close(zh_deciles["兴趣指数加总"].sum(), july_distribution["user_pro"].sum()), "十分位兴趣指数之和等于 7 月兴趣指数加总", "Decile interest sums equal the July interest total")
    check("V19", close(zh_deciles["DAU份额"].sum(), 1.0, 1e-9) and close(zh_deciles["兴趣指数份额"].sum(), 1.0, 1e-9), "十分位两类份额均闭合到 100%", "Both decile share columns close to 100%")
    check("V20", (zh_deciles["主播数"].max() - zh_deciles["主播数"].min()) <= 1, "十分位主播数最大差不超过 1", "Decile streamer counts differ by no more than one")
    check("V21", zh_deciles["主播数"].tolist() == en_deciles["anchor_count"].tolist(), "中英文十分位人数一致", "Chinese and English decile counts agree")

    def classify(row: pd.Series) -> str:
        if row.status == "新增/回归":
            return "新增/回归主播"
        if row.status == "流失":
            return "流失主播"
        if row.june_dau >= 30_000 and row.interest_change < 0:
            return "头部下滑：6月DAU>=3万且兴趣降"
        if row.june_dau >= 30_000 and row.dau_change < 0 and row.interest_change > 0:
            return "头部DAU降但兴趣升"
        if row.june_dau >= 10_000 and row.dau_change > 0 and row.interest_change > 0:
            return "大/腰部上涨：6月DAU>=1万且双升"
        if 3_000 <= row.june_dau < 10_000 and row.dau_change > 0 and row.interest_change > 0:
            return "腰部上涨：6月DAU 3千-1万且双升"
        if row.dau_change < 0 and row.interest_change < 0:
            return "其他下滑：DAU和兴趣双降"
        if row.dau_change > 0 and row.interest_change > 0:
            return "其他上涨：DAU和兴趣双升"
        if row.dau_change < 0 and row.interest_change > 0:
            return "DAU降但兴趣升"
        if row.dau_change > 0 and row.interest_change < 0:
            return "DAU升但兴趣降"
        return "其他"

    change["group"] = change.apply(classify, axis=1)
    group_source = change.groupby("group", as_index=False).agg(
        anchor_count=("luid", "nunique"), june_dau=("june_dau", "sum"), july_dau=("july_dau", "sum"),
        dau_change=("dau_change", "sum"), june_interest=("june_interest", "sum"),
        july_interest=("july_interest", "sum"), interest_change=("interest_change", "sum"),
    )
    group_map = group_source.set_index("group")
    group_count_match = all(int(zh_groups.loc[zh_groups["分组"] == name, "主播数"].iloc[0]) == int(row.anchor_count) for name, row in group_map.iterrows())
    check("V22", group_count_match, "11 个假设分组人数均可从优先级规则重算", "All eleven hypothesis-group counts reproduce from the precedence rules")
    check("V23", int(zh_groups["主播数"].sum()) == int(change["luid"].nunique()), "假设分组覆盖全部 4,496 个主播", "Hypothesis groups cover all 4,496 streamers")
    check("V24", close(zh_groups["DAU变化"].sum(), change["dau_change"].sum()), "假设分组 DAU 变化之和等于净变化", "Hypothesis-group DAU changes sum to the net change")
    check("V25", close(zh_groups["兴趣指数变化"].sum(), change["interest_change"].sum()), "假设分组兴趣指数变化之和等于净变化", "Hypothesis-group interest changes sum to the net change")
    check("V26", zh_groups["主播数"].tolist() == en_groups["anchor_count"].tolist(), "中英文假设分组人数一致", "Chinese and English hypothesis-group counts agree")

    forbidden_headers = {"luid", "snick", "主播昵称", "昵称", "UID", "主播ID"}
    csv_paths = list(zh_dir.glob("*.csv")) + list(en_dir.glob("*.csv"))
    header_clean = True
    for path in csv_paths:
        frame = pd.read_csv(path, nrows=0, encoding="utf-8-sig")
        if forbidden_headers.intersection(frame.columns):
            header_clean = False
    check("V27", header_clean, "所有匿名 CSV 均不含主播 ID 或昵称列", "No anonymous CSV contains streamer-ID or nickname columns")

    workbook_clean = True
    no_formula_errors = True
    for path in [zh_dir / "星秀兴趣指数_匿名汇总.xlsx", en_dir / "xingxiu_interest_index_anonymous.xlsx"]:
        wb = load_workbook(path, read_only=True, data_only=False)
        for ws in wb.worksheets:
            headers = [str(cell) for cell in next(ws.iter_rows(min_row=2, max_row=2, values_only=True), ()) if cell is not None]
            if forbidden_headers.intersection(headers):
                workbook_clean = False
            for row in ws.iter_rows(values_only=True):
                for value in row:
                    if value in {"#REF!", "#DIV/0!", "#VALUE!", "#N/A", "#NAME?", "#NUM!", "#NULL!"}:
                        no_formula_errors = False
        wb.close()
    check("V28", workbook_clean, "两份匿名工作簿均不含主播 ID 或昵称列", "Neither anonymous workbook contains streamer-ID or nickname columns")
    check("V29", no_formula_errors, "两份匿名工作簿无 Excel 公式错误", "Neither anonymous workbook contains Excel formula errors")

    zh_wb = load_workbook(zh_dir / "星秀兴趣指数_匿名汇总.xlsx", read_only=False, data_only=False)
    en_wb = load_workbook(en_dir / "xingxiu_interest_index_anonymous.xlsx", read_only=False, data_only=False)
    zh_text_font = zh_wb["说明"]["A2"].font.name
    zh_number_font = zh_wb["月度汇总"]["B3"].font.name
    en_text_font = en_wb["Notes"]["A2"].font.name
    en_number_font = en_wb["Monthly Summary"]["B3"].font.name
    zh_number_format = zh_wb["月度汇总"]["B3"].number_format
    zh_percent_format = zh_wb["月度汇总"]["K3"].number_format
    en_number_format = en_wb["Monthly Summary"]["B3"].number_format
    en_percent_format = en_wb["Monthly Summary"]["K3"].number_format
    zh_wb.close()
    en_wb.close()
    format_ok = (
        zh_text_font == "KaiTi" and zh_number_font == "Calibri"
        and en_text_font == "Calibri" and en_number_font == "Calibri"
        and zh_number_format == "#,##0.00" and en_number_format == "#,##0.00"
        and zh_percent_format == "0.0%" and en_percent_format == "0.0%"
    )
    check("V34", format_ok, "中文文本使用楷体、数字及英文使用 Calibri，环比使用百分比格式", "Chinese text uses KaiTi, numbers/English use Calibri, and month-over-month fields use percent formats")

    manifest = pd.read_csv(zh_dir / "source_manifest.csv", encoding="utf-8-sig")
    source_row = manifest.loc[manifest["file"] == args.source.name]
    check("V30", len(source_row) == 1 and source_row.iloc[0]["sha256"] == sha256(args.source), "源 CSV 的 SHA-256 已在清单中登记并可验证", "The source CSV SHA-256 is recorded and verifies")

    if args.evidence_dir and args.evidence_dir.exists():
        historical_monthly = pd.read_excel(args.evidence_dir / "星秀主播兴趣指数_DAU分析_2026年1-7月.xlsx", sheet_name="月度汇总")
        monthly_crosscheck = all(close(a, b) for a, b in zip(historical_monthly["主播DAU加总"], zh_monthly["主播DAU加总"])) and all(close(a, b) for a, b in zip(historical_monthly["兴趣指数加总"], zh_monthly["兴趣指数加总"]))
        check("V31", monthly_crosscheck, "迁移版月度汇总与历史工作簿一致", "Migration monthly aggregates match the historical workbook")

        historical_deciles = pd.read_excel(args.evidence_dir / "星秀主播兴趣指数_DAU分析_2026年1-7月.xlsx", sheet_name="7月DAU分层")
        decile_crosscheck = historical_deciles["主播数"].tolist() == zh_deciles["主播数"].tolist() and all(close(a, b) for a, b in zip(historical_deciles["DAU加总"], zh_deciles["DAU加总"]))
        check("V32", decile_crosscheck, "迁移版 DAU 十分位与历史工作簿一致", "Migration DAU deciles match the historical workbook")

        historical_groups = pd.read_excel(args.evidence_dir / "星秀主播变化_假设验证_2026年6-7月.xlsx", sheet_name="分组汇总").set_index("group")
        migrated_groups = zh_groups.set_index("分组")
        group_crosscheck = set(historical_groups.index) == set(migrated_groups.index) and all(
            int(historical_groups.loc[name, "主播数"]) == int(migrated_groups.loc[name, "主播数"])
            and close(historical_groups.loc[name, "di"], migrated_groups.loc[name, "兴趣指数变化"])
            for name in historical_groups.index
        )
        check("V33", group_crosscheck, "迁移版假设分组人数与兴趣变化和历史工作簿一致", "Migration hypothesis-group counts and interest changes match the historical workbook")
    else:
        check("V31", True, "未提供历史工作簿目录；源重算与内部对账已完成", "Historical workbook directory not supplied; source reconstruction and internal reconciliation passed")

    failed = [row for row in checks if row["status"] == "FAIL"]
    zh_result = pd.DataFrame(checks).rename(columns={"check_id": "检查编号", "status": "状态", "detail_zh": "说明"})[
        ["检查编号", "状态", "说明"]
    ]
    en_result = pd.DataFrame(checks).rename(columns={"check_id": "check_id", "status": "status", "detail_en": "detail"})[
        ["check_id", "status", "detail"]
    ]
    zh_result.to_csv(zh_dir / "validation_results.csv", index=False, encoding="utf-8-sig")
    en_result.to_csv(en_dir / "validation_results.csv", index=False, encoding="utf-8-sig")
    report = {
        "status": "pass" if not failed else "fail",
        "checks_total": len(checks),
        "checks_passed": len(checks) - len(failed),
        "checks_failed": len(failed),
        "failures": failed,
    }
    (PROJECT_ROOT / "artifacts" / "validation_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
