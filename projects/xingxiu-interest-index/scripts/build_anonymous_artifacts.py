from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import pandas as pd
from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter


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
STATUS_LABELS = {
    "存量": "存量",
    "新增/回归": "新增/回归",
    "流失": "流失",
}
GROUP_LABELS_EN = {
    "头部下滑：6月DAU>=3万且兴趣降": "Head decline: June DAU >= 30k with interest decline",
    "头部DAU降但兴趣升": "Head: DAU decline with interest increase",
    "大/腰部上涨：6月DAU>=1万且双升": "Large/mid-tier rise: June DAU >= 10k with both metrics up",
    "腰部上涨：6月DAU 3千-1万且双升": "Mid-tier rise: June DAU 3k-10k with both metrics up",
    "新增/回归主播": "New/returning anchors",
    "流失主播": "Churned anchors",
    "其他下滑：DAU和兴趣双降": "Other: both DAU and interest down",
    "其他上涨：DAU和兴趣双升": "Other: both DAU and interest up",
    "DAU降但兴趣升": "DAU down with interest up",
    "DAU升但兴趣降": "DAU up with interest down",
    "其他": "Other",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def pct_change(series: pd.Series) -> pd.Series:
    return series.astype(float).pct_change()


def classify_status(row: pd.Series) -> str:
    if row["june_dau"] == 0 and row["july_dau"] > 0:
        return "新增/回归"
    if row["june_dau"] > 0 and row["july_dau"] == 0:
        return "流失"
    return "存量"


def classify_group(row: pd.Series) -> str:
    if row["status"] == "新增/回归":
        return "新增/回归主播"
    if row["status"] == "流失":
        return "流失主播"
    if row["june_dau"] >= 30_000 and row["interest_change"] < 0:
        return "头部下滑：6月DAU>=3万且兴趣降"
    if row["june_dau"] >= 30_000 and row["dau_change"] < 0 and row["interest_change"] > 0:
        return "头部DAU降但兴趣升"
    if row["june_dau"] >= 10_000 and row["dau_change"] > 0 and row["interest_change"] > 0:
        return "大/腰部上涨：6月DAU>=1万且双升"
    if 3_000 <= row["june_dau"] < 10_000 and row["dau_change"] > 0 and row["interest_change"] > 0:
        return "腰部上涨：6月DAU 3千-1万且双升"
    if row["dau_change"] < 0 and row["interest_change"] < 0:
        return "其他下滑：DAU和兴趣双降"
    if row["dau_change"] > 0 and row["interest_change"] > 0:
        return "其他上涨：DAU和兴趣双升"
    if row["dau_change"] < 0 and row["interest_change"] > 0:
        return "DAU降但兴趣升"
    if row["dau_change"] > 0 and row["interest_change"] < 0:
        return "DAU升但兴趣降"
    return "其他"


def write_csv(frame: pd.DataFrame, paths: list[Path]) -> None:
    for path in paths:
        path.parent.mkdir(parents=True, exist_ok=True)
        frame.to_csv(path, index=False, encoding="utf-8-sig", float_format="%.12g")


def style_sheet(ws, numeric_columns: set[str], language: str) -> None:
    title_fill = PatternFill("solid", fgColor="D9EAF7")
    header_fill = PatternFill("solid", fgColor="EAF2F8")
    text_font = "KaiTi" if language == "zh" else "Calibri"
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=ws.max_column)
    title = ws.cell(1, 1)
    title.font = Font(name=text_font, size=14, bold=True, color="1F1F1F")
    title.fill = title_fill
    title.alignment = Alignment(horizontal="center")
    ws.row_dimensions[1].height = 24
    ws.freeze_panes = "A3"
    ws.auto_filter.ref = ws.dimensions
    for cell in ws[2]:
        cell.font = Font(name=text_font, size=10, bold=True)
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
    numeric_headers = {cell.column_letter: str(cell.value) for cell in ws[2] if cell.value in numeric_columns}
    percent_letters = {
        letter
        for letter, header in numeric_headers.items()
        if any(token in header for token in ("环比", "份额", "_mom", "share"))
    }
    for row in ws.iter_rows(min_row=3):
        for cell in row:
            font_name = "Calibri" if cell.column_letter in numeric_headers else text_font
            cell.font = Font(name=font_name, size=10)
            if cell.column_letter in numeric_headers and isinstance(cell.value, (int, float)):
                cell.number_format = "0.0%" if cell.column_letter in percent_letters else "#,##0.00"
    for index, column in enumerate(ws.columns, start=1):
        width = min(max(max(len(str(cell.value or "")) for cell in column) + 2, 12), 42)
        ws.column_dimensions[get_column_letter(index)].width = width


def add_data_sheet(wb: Workbook, title: str, frame: pd.DataFrame, numeric: set[str] | None, language: str) -> None:
    ws = wb.create_sheet(title)
    ws.append([title])
    ws.append(list(frame.columns))
    for values in frame.itertuples(index=False, name=None):
        ws.append(list(values))
    style_sheet(ws, numeric or set(), language)


def build_workbook(path: Path, language: str, sheets: list[tuple[str, pd.DataFrame, set[str]]], notes: pd.DataFrame) -> None:
    wb = Workbook()
    wb.remove(wb.active)
    note_title = "说明" if language == "zh" else "Notes"
    add_data_sheet(wb, note_title, notes, set(), language)
    for title, frame, numeric in sheets:
        add_data_sheet(wb, title, frame, numeric, language)
    path.parent.mkdir(parents=True, exist_ok=True)
    wb.save(path)


def main() -> None:
    parser = argparse.ArgumentParser(description="Build de-identified Xingxiu interest-index artifacts.")
    parser.add_argument("--source", required=True, type=Path, help="Monthly anchor CSV supplied locally")
    parser.add_argument("--evidence-workbook", action="append", type=Path, default=[], help="Optional original workbook for manifest only")
    args = parser.parse_args()

    if not args.source.exists():
        raise FileNotFoundError(args.source)
    raw = pd.read_csv(args.source)
    required = {"month", "luid", "snick", "game_name", "dau", "user_pro"}
    missing = required.difference(raw.columns)
    if missing:
        raise ValueError(f"Missing source columns: {sorted(missing)}")
    raw["month"] = raw["month"].astype(str)
    raw["dau"] = pd.to_numeric(raw["dau"], errors="coerce")
    raw["user_pro"] = pd.to_numeric(raw["user_pro"], errors="coerce")
    if raw.duplicated(["month", "luid"]).any():
        raise ValueError("Source violates month + luid uniqueness")

    months = sorted(CATEGORY_DAU)
    if sorted(raw["month"].unique()) != months:
        raise ValueError("Source month coverage differs from the documented January-July 2026 scope")
    raw["interest_to_dau"] = raw["user_pro"] / raw["dau"].where(raw["dau"] != 0)
    monthly = (
        raw.groupby("month", as_index=False)
        .agg(
            anchor_count=("luid", "nunique"),
            dau_sum=("dau", "sum"),
            interest_sum=("user_pro", "sum"),
            dau_median=("dau", "median"),
            interest_median=("user_pro", "median"),
            interest_dau_ratio_mean=("interest_to_dau", "mean"),
            interest_dau_ratio_median=("interest_to_dau", "median"),
            missing_interest_count=("user_pro", lambda values: int(values.isna().sum())),
        )
        .sort_values("month")
    )
    monthly["category_dau"] = monthly["month"].map(CATEGORY_DAU)
    monthly["anchor_dau_mom"] = pct_change(monthly["dau_sum"])
    monthly["interest_sum_mom"] = pct_change(monthly["interest_sum"])
    monthly["interest_dau_ratio_median_mom"] = pct_change(monthly["interest_dau_ratio_median"])
    monthly["category_dau_mom"] = pct_change(monthly["category_dau"])
    monthly["anchor_dau_over_category_dau"] = monthly["dau_sum"] / monthly["category_dau"]
    monthly["interest_sum_over_category_dau"] = monthly["interest_sum"] / monthly["category_dau"]

    base_columns = ["luid", "dau", "user_pro"]
    june = raw.loc[raw["month"] == "2026-06", base_columns].rename(
        columns={"dau": "june_dau", "user_pro": "june_interest"}
    )
    july = raw.loc[raw["month"] == "2026-07", base_columns].rename(
        columns={"dau": "july_dau", "user_pro": "july_interest"}
    )
    change = july.merge(june, on="luid", how="outer", validate="one_to_one")
    for column in ["june_dau", "july_dau", "june_interest", "july_interest"]:
        change[column] = change[column].fillna(0.0)
    change["dau_change"] = change["july_dau"] - change["june_dau"]
    change["interest_change"] = change["july_interest"] - change["june_interest"]
    change["status"] = change.apply(classify_status, axis=1)
    change["group"] = change.apply(classify_group, axis=1)

    status = (
        change.groupby("status", as_index=False)
        .agg(
            anchor_count=("luid", "nunique"),
            june_dau=("june_dau", "sum"),
            july_dau=("july_dau", "sum"),
            dau_change=("dau_change", "sum"),
            june_interest=("june_interest", "sum"),
            july_interest=("july_interest", "sum"),
            interest_change=("interest_change", "sum"),
        )
        .sort_values("interest_change", ascending=False)
    )

    july_distribution = raw.loc[raw["month"] == "2026-07"].copy()
    july_distribution["dau_decile"] = pd.qcut(
        july_distribution["dau"].rank(method="first"), 10, labels=[f"D{i}" for i in range(1, 11)]
    )
    deciles = (
        july_distribution.groupby("dau_decile", as_index=False, observed=True)
        .agg(
            anchor_count=("luid", "nunique"),
            dau_sum=("dau", "sum"),
            interest_sum=("user_pro", "sum"),
            interest_dau_ratio_median=("interest_to_dau", "median"),
        )
        .sort_values("dau_decile")
    )
    deciles["dau_share"] = deciles["dau_sum"] / deciles["dau_sum"].sum()
    deciles["interest_share"] = deciles["interest_sum"] / deciles["interest_sum"].sum()

    groups = (
        change.groupby("group", as_index=False)
        .agg(
            anchor_count=("luid", "nunique"),
            june_dau=("june_dau", "sum"),
            july_dau=("july_dau", "sum"),
            dau_change=("dau_change", "sum"),
            june_interest=("june_interest", "sum"),
            july_interest=("july_interest", "sum"),
            interest_change=("interest_change", "sum"),
        )
        .sort_values("interest_change", ascending=False)
    )

    quality_en = pd.DataFrame(
        [
            {"finding_id": "Q01", "severity": "medium", "finding": "Category DAU is a seven-month hard-coded input; no source query or dashboard extract is present in the project folder.", "impact": "Category-level ratios and month-over-month changes cannot be independently traced beyond the copied values."},
            {"finding_id": "Q02", "severity": "medium", "finding": "Anchor-level DAU values are summed across anchors and may double-count viewers who watched multiple anchors.", "impact": "The anchor DAU sum is not a deduplicated category DAU."},
            {"finding_id": "Q03", "severity": "medium", "finding": "Field dictionaries for dau and user_pro are absent, and user_pro is summed before division by category DAU.", "impact": "Interest-index units and the business meaning of summed user_pro/category DAU require owner confirmation."},
            {"finding_id": "Q04", "severity": "low", "finding": "One anchor has missing user_pro in all seven months; the historical June-July change workbook treats missing interest as zero.", "impact": "The archived status and hypothesis results reproduce that convention, while monthly sums use observed non-null values."},
            {"finding_id": "Q05", "severity": "low", "finding": "The hypothesis-validation workbook has no retained generation script.", "impact": "The migration rebuilds its aggregate classifications and confirms the recorded counts and sums from the retained source CSV."},
            {"finding_id": "Q06", "severity": "low", "finding": "Two July source rows have no game_name; all other 22,829 rows are labelled Xingxiu.", "impact": "The missing labels do not affect this project because game_name is not used for grouping."},
            {"finding_id": "Q07", "severity": "medium", "finding": "The streamer-level user_pro/dau ratio has a heavy tail: 33 of 22,831 rows exceed 100 and the maximum is about 4,271.61.", "impact": "The ratio units require owner confirmation; aggregate outputs therefore report medians rather than relying only on the mean."},
        ]
    )
    quality_zh = pd.DataFrame(
        [
            {"finding_id": "Q01", "severity": "中", "finding": "品类 DAU 是 7 个月的硬编码输入，项目目录中没有源查询或看板导出。", "impact": "只能核对复制值，无法从底层数据继续追溯品类比例及环比来源。"},
            {"finding_id": "Q02", "severity": "中", "finding": "主播级 DAU 直接跨主播相加，可能重复统计同时观看多个主播的用户。", "impact": "主播 DAU 加总不是去重后的品类 DAU，不能替代品类大盘。"},
            {"finding_id": "Q03", "severity": "中", "finding": "缺少 dau 和 user_pro 的字段字典，且先将 user_pro 加总再除以品类 DAU。", "impact": "兴趣指数单位以及 user_pro/品类 DAU 比值的业务含义需要数据 owner 确认。"},
            {"finding_id": "Q04", "severity": "低", "finding": "有 1 个主播 7 个月均缺失 user_pro；历史 6–7 月变化工作簿把缺失兴趣指数按 0 处理。", "impact": "迁移版沿用该历史规则以复现状态和假设分组；月度汇总只对非空值求和。"},
            {"finding_id": "Q05", "severity": "低", "finding": "历史假设验证工作簿没有保留生成脚本。", "impact": "迁移版从保留的源 CSV 重建聚合分组，并已核对原工作簿的人数与汇总值。"},
            {"finding_id": "Q06", "severity": "低", "finding": "7 月有 2 行源数据缺失 game_name；其余 22,829 行均标记为星秀。", "impact": "本项目不使用 game_name 分组，因此缺失标签不影响本次聚合。"},
            {"finding_id": "Q07", "severity": "中", "finding": "主播级 user_pro/dau 比值存在长尾：22,831 行中有 33 行大于 100，最大约 4,271.61。", "impact": "比值单位仍需 owner 确认；因此聚合输出同时报告中位数，避免只依赖均值。"},
        ]
    )

    notes_zh = pd.DataFrame(
        {
            "项目": ["星秀兴趣指数分析", "时间范围", "粒度", "隐私", "解释边界"],
            "说明": [
                "2026 年 1–7 月星秀主播月度 DAU 与兴趣指数复盘",
                "2026-01 至 2026-07",
                "月 × 主播；输出仅保留聚合结果，不保留主播键或昵称",
                "工作簿不含 luid、昵称、Top 主播或原始逐主播数据",
                "主播 DAU 加总是主播月均值之和，不是去重品类 DAU；品类 DAU 为硬编码外部口径",
            ],
        }
    )
    notes_en = pd.DataFrame(
        {
            "Item": ["Project", "Period", "Grain", "Privacy", "Interpretation limit"],
            "Description": [
                "Monthly DAU and interest-index review for Xingxiu streamers",
                "January through July 2026",
                "Month x streamer; outputs retain aggregates only, with no streamer keys or nicknames",
                "The workbook contains no anchor IDs, nicknames, top-anchor tables, or raw streamer-level data",
                "Anchor DAU sums add monthly averages and are not deduplicated category DAU; category DAU is a hard-coded external input",
            ],
        }
    )

    zh_monthly = monthly.rename(
        columns={
            "month": "月份", "anchor_count": "主播数", "dau_sum": "主播DAU加总", "interest_sum": "兴趣指数加总",
            "dau_median": "DAU中位数", "interest_median": "兴趣指数中位数", "interest_dau_ratio_mean": "兴趣_DAU比均值",
            "interest_dau_ratio_median": "兴趣_DAU比中位数", "missing_interest_count": "兴趣缺失行数", "category_dau": "品类DAU",
            "anchor_dau_mom": "主播DAU加总环比", "interest_sum_mom": "兴趣指数加总环比", "interest_dau_ratio_median_mom": "兴趣_DAU比中位数环比",
            "category_dau_mom": "品类DAU环比", "anchor_dau_over_category_dau": "主播DAU加总_品类DAU比",
            "interest_sum_over_category_dau": "兴趣指数加总_品类DAU比",
        }
    )
    zh_status = status.replace({"status": STATUS_LABELS}).rename(
        columns={"status": "主播状态", "anchor_count": "主播数", "june_dau": "6月DAU", "july_dau": "7月DAU", "dau_change": "DAU变化", "june_interest": "6月兴趣指数", "july_interest": "7月兴趣指数", "interest_change": "兴趣指数变化"}
    )
    zh_deciles = deciles.rename(
        columns={"dau_decile": "DAU十分位", "anchor_count": "主播数", "dau_sum": "DAU加总", "interest_sum": "兴趣指数加总", "interest_dau_ratio_median": "兴趣_DAU比中位数", "dau_share": "DAU份额", "interest_share": "兴趣指数份额"}
    )
    zh_groups = groups.rename(
        columns={"group": "分组", "anchor_count": "主播数", "june_dau": "6月DAU", "july_dau": "7月DAU", "dau_change": "DAU变化", "june_interest": "6月兴趣指数", "july_interest": "7月兴趣指数", "interest_change": "兴趣指数变化"}
    )

    en_monthly = monthly.rename(
        columns={"month": "month", "anchor_count": "anchor_count", "dau_sum": "anchor_dau_sum", "interest_sum": "interest_sum", "dau_median": "dau_median", "interest_median": "interest_median", "interest_dau_ratio_mean": "interest_dau_ratio_mean", "interest_dau_ratio_median": "interest_dau_ratio_median", "missing_interest_count": "missing_interest_rows", "category_dau": "category_dau", "anchor_dau_mom": "anchor_dau_mom", "interest_sum_mom": "interest_sum_mom", "interest_dau_ratio_median_mom": "interest_dau_ratio_median_mom", "category_dau_mom": "category_dau_mom", "anchor_dau_over_category_dau": "anchor_dau_over_category_dau", "interest_sum_over_category_dau": "interest_sum_over_category_dau"}
    )
    en_status = status.rename(
        columns={"status": "anchor_status", "anchor_count": "anchor_count", "june_dau": "june_dau", "july_dau": "july_dau", "dau_change": "dau_change", "june_interest": "june_interest", "july_interest": "july_interest", "interest_change": "interest_change"}
    )
    en_deciles = deciles.rename(
        columns={"dau_decile": "dau_decile", "anchor_count": "anchor_count", "dau_sum": "dau_sum", "interest_sum": "interest_sum", "interest_dau_ratio_median": "interest_dau_ratio_median", "dau_share": "dau_share", "interest_share": "interest_share"}
    )
    en_groups = groups.assign(group_en=groups["group"].map(GROUP_LABELS_EN)).rename(
        columns={"group": "group_zh", "group_en": "group_en", "anchor_count": "anchor_count", "june_dau": "june_dau", "july_dau": "july_dau", "dau_change": "dau_change", "june_interest": "june_interest", "july_interest": "july_interest", "interest_change": "interest_change"}
    )

    numeric_zh = set(zh_monthly.columns) - {"月份"}
    numeric_status = set(zh_status.columns) - {"主播状态"}
    numeric_deciles = set(zh_deciles.columns) - {"DAU十分位"}
    numeric_groups = set(zh_groups.columns) - {"分组"}

    zh_dir = PROJECT_ROOT / "artifacts" / "zh"
    en_dir = PROJECT_ROOT / "artifacts" / "en"
    write_csv(zh_monthly, [zh_dir / "monthly_summary.csv"])
    write_csv(zh_status, [zh_dir / "status_summary.csv"])
    write_csv(zh_deciles, [zh_dir / "dau_decile_summary.csv"])
    write_csv(zh_groups, [zh_dir / "hypothesis_group_summary.csv"])
    write_csv(quality_zh, [zh_dir / "quality_findings.csv"])
    write_csv(quality_en, [en_dir / "quality_findings.csv"])
    write_csv(en_monthly, [en_dir / "monthly_summary.csv"])
    write_csv(en_status, [en_dir / "status_summary.csv"])
    write_csv(en_deciles, [en_dir / "dau_decile_summary.csv"])
    write_csv(en_groups, [en_dir / "hypothesis_group_summary.csv"])

    manifest_rows = [
        {"file": args.source.name, "role": "monthly source CSV", "bytes": args.source.stat().st_size, "sha256": sha256(args.source), "uploaded": "no - contains anchor IDs and nicknames"}
    ]
    for workbook in args.evidence_workbook:
        if workbook.exists():
            manifest_rows.append(
                {"file": workbook.name, "role": "historical workbook", "bytes": workbook.stat().st_size, "sha256": sha256(workbook), "uploaded": "no - aggregate evidence only is retained"}
            )
    existing_manifest_path = zh_dir / "source_manifest.csv"
    if existing_manifest_path.exists():
        existing_manifest = pd.read_csv(existing_manifest_path, encoding="utf-8-sig")
        known_files = {row["file"] for row in manifest_rows}
        manifest_rows.extend(
            row
            for row in existing_manifest.to_dict("records")
            if row.get("file") not in known_files
        )
    manifest_en = pd.DataFrame(manifest_rows)
    manifest_zh = manifest_en.copy()
    manifest_zh["role"] = manifest_zh["role"].replace(
        {"monthly source CSV": "月度源 CSV", "historical workbook": "历史工作簿"}
    )
    manifest_zh["uploaded"] = manifest_zh["uploaded"].replace(
        {
            "no - contains anchor IDs and nicknames": "否 - 含主播 ID 和昵称",
            "no - aggregate evidence only is retained": "否 - 仅保留匿名聚合证据",
        }
    )
    write_csv(manifest_zh, [zh_dir / "source_manifest.csv"])
    write_csv(manifest_en, [en_dir / "source_manifest.csv"])

    write_csv(
        pd.DataFrame(
            [
                {"version": "2026-11-02", "change": "迁移复盘从本地源 CSV 重建聚合结果，移除主播身份，并拆分中英文产出"},
                {"version": "2026-08-03", "change": "原始分析工作簿在本地生成；逐主播工作表和榜单未迁移"},
            ]
        ),
        [zh_dir / "version_history.csv"],
    )
    write_csv(
        pd.DataFrame(
            [
                {"version": "2026-11-02", "change": "Migration review rebuilt aggregates from the local source CSV, removed streamer identifiers, and separated Chinese and English outputs"},
                {"version": "2026-08-03", "change": "Original analysis workbooks created locally; per-streamer sheets and top lists were not migrated"},
            ]
        ),
        [en_dir / "version_history.csv"],
    )

    build_workbook(
        zh_dir / "星秀兴趣指数_匿名汇总.xlsx",
        "zh",
        [
            ("月度汇总", zh_monthly, numeric_zh),
            ("主播状态", zh_status, numeric_status),
            ("DAU十分位", zh_deciles, numeric_deciles),
            ("假设分组", zh_groups, numeric_groups),
            ("质量说明", quality_zh.rename(columns={"finding_id": "编号", "severity": "严重度", "finding": "发现", "impact": "影响"}), set()),
        ],
        notes_zh,
    )
    build_workbook(
        en_dir / "xingxiu_interest_index_anonymous.xlsx",
        "en",
        [
            ("Monthly Summary", en_monthly, set(en_monthly.columns) - {"month"}),
            ("Streamer Status", en_status, set(en_status.columns) - {"anchor_status"}),
            ("DAU Deciles", en_deciles, set(en_deciles.columns) - {"dau_decile"}),
            ("Hypothesis Groups", en_groups, set(en_groups.columns) - {"group_zh", "group_en"}),
            ("Quality Findings", quality_en, set()),
        ],
        notes_en,
    )

    july_row = monthly.loc[monthly["month"] == "2026-07"].iloc[0]
    june_row = monthly.loc[monthly["month"] == "2026-06"].iloc[0]
    summary = {
        "source_rows": int(len(raw)),
        "unique_streamers": int(raw["luid"].nunique()),
        "months": months,
        "june_to_july": {
            "anchor_dau_change": float(july_row["dau_sum"] - june_row["dau_sum"]),
            "anchor_dau_change_pct": float(july_row["dau_sum"] / june_row["dau_sum"] - 1),
            "interest_change": float(july_row["interest_sum"] - june_row["interest_sum"]),
            "interest_change_pct": float(july_row["interest_sum"] / june_row["interest_sum"] - 1),
            "category_dau_change_pct": float(july_row["category_dau"] / june_row["category_dau"] - 1),
        },
        "status_counts": {row.status: int(row.anchor_count) for row in status.itertuples()},
        "july_top_decile_dau_share": float(deciles.iloc[-1]["dau_share"]),
        "july_top_decile_interest_share": float(deciles.iloc[-1]["interest_share"]),
    }
    (PROJECT_ROOT / "artifacts" / "project_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
