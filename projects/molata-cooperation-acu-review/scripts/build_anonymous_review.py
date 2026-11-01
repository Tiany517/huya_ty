#!/usr/bin/env python3
"""Build an identity-free review package for the 2026 cooperation ACU analysis.

The local source snapshot contains six streamer identifiers and nicknames. This
script reads them only in memory and writes labels, aggregate comparisons, and
source hashes. It never writes a source identifier or nickname to the output.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import pandas as pd
from openpyxl import load_workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = PROJECT_ROOT / "artifacts" / "anonymous-summary"

WINDOWS = {
    "pre_month": ("2026-05-24", "2026-06-23"),
    "event_week": ("2026-06-24", "2026-06-30"),
    "post_month_including_event": ("2026-06-24", "2026-07-23"),
    "post_month_excluding_event": ("2026-07-01", "2026-07-30"),
}

ROLE_LABEL = {
    "main_anchor": "main_anchor",
    "collaboration_five_total": "collaboration_five_total",
    "observed_six_total": "observed_six_total",
    "non_cohort_excluding_five": "non_cohort_excluding_five",
    "non_cohort_excluding_six": "non_cohort_excluding_six",
    "all_platform": "all_platform",
    "all_platform_excluding_outlier": "all_platform_excluding_outlier",
    "non_cohort_excluding_six_and_outlier": "non_cohort_excluding_six_and_outlier",
}

CN_COLUMNS = {
    "date": "日期",
    "phase": "窗口",
    "anchor_01": "主播01_有效ACU",
    "anchor_02": "主播02_有效ACU",
    "anchor_03": "主播03_有效ACU",
    "anchor_04": "主播04_有效ACU",
    "anchor_05": "主播05_有效ACU",
    "anchor_06": "主播06_有效ACU",
    "collaboration_five_total": "合作五人组合计有效ACU",
    "observed_six_total": "六人合计有效ACU",
    "non_cohort_excluding_five": "大盘剔合作五人_有效ACU",
    "non_cohort_excluding_six": "大盘剔六人_有效ACU",
    "all_platform": "全平台有效ACU",
    "all_platform_excluding_outlier": "全平台剔异常高ACU账号_有效ACU",
    "non_cohort_excluding_six_and_outlier": "大盘剔六人及异常高ACU账号_有效ACU",
    "platform_anchor_count": "全平台主播数",
    "market_implied_six_total": "大盘差值隐含六人有效ACU",
    "market_reconciliation_residual": "六人大盘勾稽残差",
    "six_share_excluding_outlier": "六人占大盘剔异常账号_份额",
    "five_share_excluding_outlier": "合作五人占大盘剔异常账号_份额",
    "unit": "统计单位",
    "window": "窗口",
    "start_date": "起始日",
    "end_date": "截止日",
    "calendar_days": "自然日数",
    "recorded_days": "有记录日数",
    "acu_sum": "ACU合计",
    "natural_day_daily_avg_acu": "自然日日均ACU",
    "recorded_day_daily_avg_acu": "有记录日日均ACU",
    "pre_daily_avg_acu": "合作前日均ACU",
    "post_including_event_daily_avg_acu": "后1月含合作期日均ACU",
    "post_including_event_delta_acu": "后1月含合作期增量ACU",
    "post_including_event_growth": "后1月含合作期增幅",
    "post_excluding_event_daily_avg_acu": "后1月剔合作期日均ACU",
    "post_excluding_event_delta_acu": "后1月剔合作期增量ACU",
    "post_excluding_event_growth": "后1月剔合作期增幅",
    "excess_pp_vs_all_platform_including_event": "较全平台超额pp_含合作期",
    "excess_pp_vs_all_platform_excluding_event": "较全平台超额pp_剔合作期",
    "excess_pp_vs_all_platform_excluding_outlier_including_event": "较全平台剔异常账号超额pp_含合作期",
    "excess_pp_vs_all_platform_excluding_outlier_excluding_event": "较全平台剔异常账号超额pp_剔合作期",
    "six_mean_daily_share": "六人平均日份额",
    "five_mean_daily_share": "合作五人平均日份额",
    "source_sum": "源数据合计",
    "market_implied_sum": "大盘差值隐含合计",
    "residual": "残差",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_csv(frame: pd.DataFrame, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False, encoding="utf-8-sig", lineterminator="\n")


def load_source(source_dir: Path) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    data_dir = source_dir / "data"
    anchor = pd.read_csv(
        data_dir / "anchor_daily.csv",
        encoding="utf-8-sig",
        dtype={"r_lid": str},
    )
    market = pd.read_csv(data_dir / "market_daily.csv", encoding="utf-8-sig")
    market_ex = pd.read_csv(data_dir / "market_exhh_daily.csv", encoding="utf-8-sig")
    for frame in (anchor, market, market_ex):
        frame["dt"] = pd.to_datetime(frame["dt"])
    if anchor.duplicated(["dt", "r_lid"]).any():
        raise ValueError("anchor_daily is not unique on dt + r_lid")
    if market["dt"].duplicated().any() or market_ex["dt"].duplicated().any():
        raise ValueError("market daily snapshots are not unique on dt")
    return anchor, market, market_ex


def infer_anchor_roles(anchor: pd.DataFrame) -> tuple[dict[str, str], list[str]]:
    totals = anchor.groupby("r_lid", sort=False)["valid_acu"].sum()
    ordered = sorted(totals.items(), key=lambda item: (-float(item[1]), item[0]))
    if len(ordered) != 6:
        raise ValueError(f"Expected six anchors, found {len(ordered)}")
    labels = {identifier: f"anchor_{index:02d}" for index, (identifier, _) in enumerate(ordered, 1)}
    collaboration = [identifier for identifier, _ in ordered[1:]]
    return labels, collaboration


def phase_for(day: pd.Timestamp) -> str:
    for label, (start, end) in WINDOWS.items():
        if pd.Timestamp(start) <= day <= pd.Timestamp(end):
            return label
    return "outside_review_windows"


def build_daily(
    anchor: pd.DataFrame,
    market: pd.DataFrame,
    market_ex: pd.DataFrame,
) -> tuple[pd.DataFrame, dict[str, str], list[str]]:
    labels, collaboration_ids = infer_anchor_roles(anchor)
    ordered_ids = sorted(labels, key=labels.get)
    pivot = anchor.pivot_table(
        index="dt",
        columns="r_lid",
        values="valid_acu",
        aggfunc="mean",
    ).reindex(columns=ordered_ids)
    market_all = market.set_index("dt").join(market_ex.set_index("dt"), how="outer")
    index = market_all.index.union(pivot.index).sort_values()
    market_all = market_all.reindex(index)
    pivot = pivot.reindex(index)

    daily = pd.DataFrame(index=index)
    daily.index.name = "date"
    for identifier in ordered_ids:
        daily[labels[identifier]] = pivot[identifier]
    daily["collaboration_five_total"] = pivot[collaboration_ids].fillna(0).sum(axis=1)
    daily["observed_six_total"] = pivot[ordered_ids].fillna(0).sum(axis=1)
    daily["non_cohort_excluding_five"] = market_all["acu_ex5"]
    daily["non_cohort_excluding_six"] = market_all["acu_ex6"]
    daily["all_platform"] = market_all["acu_all"]
    daily["all_platform_excluding_outlier"] = market_all["acu_ex_hh"]
    daily["non_cohort_excluding_six_and_outlier"] = market_all["acu_ex6_hh"]
    daily["platform_anchor_count"] = market_all["anchor_cnt_all"]
    daily["market_implied_six_total"] = daily["all_platform"] - daily["non_cohort_excluding_six"]
    daily["market_reconciliation_residual"] = (
        daily["market_implied_six_total"] - daily["observed_six_total"]
    )
    base = daily["all_platform_excluding_outlier"].where(daily["all_platform_excluding_outlier"].ne(0))
    daily["six_share_excluding_outlier"] = daily["observed_six_total"] / base
    daily["five_share_excluding_outlier"] = daily["collaboration_five_total"] / base
    daily["phase"] = daily.index.map(phase_for)
    return daily.reset_index(), labels, collaboration_ids


def window_stats(series: pd.Series, start: str, end: str) -> dict[str, float | int]:
    selected = series.loc[pd.Timestamp(start) : pd.Timestamp(end)]
    calendar_days = (pd.Timestamp(end) - pd.Timestamp(start)).days + 1
    recorded_days = int(selected.notna().sum())
    acu_sum = float(selected.fillna(0).sum())
    return {
        "calendar_days": calendar_days,
        "recorded_days": recorded_days,
        "acu_sum": acu_sum,
        "natural_day_daily_avg_acu": acu_sum / calendar_days,
        "recorded_day_daily_avg_acu": acu_sum / recorded_days if recorded_days else float("nan"),
    }


def build_window_summary(daily: pd.DataFrame) -> pd.DataFrame:
    indexed = daily.set_index("date")
    units = [
        "anchor_01",
        "anchor_02",
        "anchor_03",
        "anchor_04",
        "anchor_05",
        "anchor_06",
        "collaboration_five_total",
        "observed_six_total",
        "non_cohort_excluding_five",
        "non_cohort_excluding_six",
        "all_platform",
        "all_platform_excluding_outlier",
        "non_cohort_excluding_six_and_outlier",
    ]
    rows: list[dict[str, object]] = []
    for unit in units:
        for label, (start, end) in WINDOWS.items():
            rows.append(
                {
                    "unit": unit,
                    "window": label,
                    "start_date": start,
                    "end_date": end,
                    **window_stats(indexed[unit], start, end),
                }
            )
    return pd.DataFrame(rows)


def build_growth(summary: pd.DataFrame) -> pd.DataFrame:
    pivot = summary.pivot(index="unit", columns="window", values="natural_day_daily_avg_acu")
    rows: list[dict[str, object]] = []
    for unit in pivot.index:
        pre = float(pivot.loc[unit, "pre_month"])
        row: dict[str, object] = {"unit": unit, "pre_daily_avg_acu": pre}
        for prefix, window in (
            ("post_including_event", "post_month_including_event"),
            ("post_excluding_event", "post_month_excluding_event"),
        ):
            post = float(pivot.loc[unit, window])
            row[f"{prefix}_daily_avg_acu"] = post
            row[f"{prefix}_delta_acu"] = post - pre
            row[f"{prefix}_growth"] = post / pre - 1 if pre else float("nan")
        rows.append(row)
    growth = pd.DataFrame(rows).set_index("unit")
    for prefix in ("post_including_event", "post_excluding_event"):
        for benchmark, label in (
            ("all_platform", "all_platform"),
            ("all_platform_excluding_outlier", "all_platform_excluding_outlier"),
        ):
            growth[f"excess_pp_vs_{label}_{prefix.split('_', 1)[1]}"] = (
                growth[f"{prefix}_growth"] - growth.loc[benchmark, f"{prefix}_growth"]
            )
    return growth.reset_index()


def build_share_summary(daily: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for label, (start, end) in WINDOWS.items():
        selected = daily.loc[
            daily["date"].between(pd.Timestamp(start), pd.Timestamp(end))
        ]
        rows.append(
            {
                "window": label,
                "start_date": start,
                "end_date": end,
                "six_mean_daily_share": float(selected["six_share_excluding_outlier"].dropna().mean()),
                "five_mean_daily_share": float(selected["five_share_excluding_outlier"].dropna().mean()),
            }
        )
    return pd.DataFrame(rows)


def build_reconciliation(daily: pd.DataFrame, threshold: float = 0.11) -> pd.DataFrame:
    mask = daily["market_reconciliation_residual"].abs() > threshold
    result = daily.loc[
        mask,
        [
            "date",
            "observed_six_total",
            "market_implied_six_total",
            "market_reconciliation_residual",
        ],
    ].copy()
    return result.rename(
        columns={
            "observed_six_total": "source_sum",
            "market_implied_six_total": "market_implied_sum",
            "market_reconciliation_residual": "residual",
        }
    )


def build_source_manifest(source_dir: Path) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    classifications = {
        "data/anchor_daily.csv": ("included_source_snapshot", "Streamer-day source snapshot; identifiers not copied"),
        "data/market_daily.csv": ("included_source_snapshot", "Platform benchmark with cohort exclusions"),
        "data/market_exhh_daily.csv": ("included_source_snapshot", "Platform benchmark excluding the outlier account"),
        "output/莫拉塔与合作主播_合作前后1月_有效ACU_日明细_20261019.xlsx": ("excluded_identity_workbook", "Contains streamer identifiers and nicknames"),
        "scripts/build_report.py": ("excluded_source_script", "Contains hard-coded streamer identifiers and names"),
    }
    for path in sorted(item for item in source_dir.rglob("*") if item.is_file()):
        relative = path.relative_to(source_dir).as_posix()
        classification, reason = classifications.get(
            relative, ("excluded_unreviewed", "Not used by this review")
        )
        rows.append(
            {
                "relative_path": relative,
                "size_bytes": path.stat().st_size,
                "sha256": sha256(path),
                "classification": classification,
                "reason": reason,
            }
        )
    return pd.DataFrame(rows)


def translate(frame: pd.DataFrame) -> pd.DataFrame:
    return frame.rename(columns={key: CN_COLUMNS.get(key, key) for key in frame.columns})


def style_workbook(path: Path) -> None:
    workbook = load_workbook(path)
    fill = PatternFill("solid", fgColor="1F4E79")
    for sheet in workbook.worksheets:
        sheet.freeze_panes = "A2"
        for cell in sheet[1]:
            cell.font = Font(bold=True, color="FFFFFF")
            cell.fill = fill
            cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        for column in range(1, sheet.max_column + 1):
            values = [str(sheet.cell(row=row, column=column).value or "") for row in range(1, min(sheet.max_row, 80) + 1)]
            width = min(32, max(12, max(len(value) for value in values) + 2))
            sheet.column_dimensions[get_column_letter(column)].width = width
    workbook.save(path)


def write_workbook(path: Path, frames: dict[str, pd.DataFrame], notes: list[list[str]]) -> None:
    with pd.ExcelWriter(path, engine="openpyxl") as writer:
        for sheet_name, frame in frames.items():
            frame.to_excel(writer, sheet_name=sheet_name, index=False)
        pd.DataFrame(notes, columns=["item", "description"]).to_excel(
            writer, sheet_name="methodology", index=False
        )
    style_workbook(path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    source_dir = args.source_dir.resolve()
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    anchor, market, market_ex = load_source(source_dir)
    daily, labels, collaboration_ids = build_daily(anchor, market, market_ex)
    summary = build_window_summary(daily)
    growth = build_growth(summary)
    shares = build_share_summary(daily)
    reconciliation = build_reconciliation(daily)
    manifest = build_source_manifest(source_dir)

    frames = {
        "daily_series": daily,
        "window_summary": summary,
        "growth_comparison": growth,
        "share_summary": shares,
        "reconciliation_failures": reconciliation,
    }
    for name, frame in frames.items():
        write_csv(frame, output_dir / f"{name}.csv")
        write_csv(translate(frame), output_dir / f"{name}.zh.csv")
    write_csv(manifest, output_dir / "source-manifest.csv")

    cn_frames = {name.replace("_", " ")[:31]: translate(frame) for name, frame in frames.items()}
    en_frames = {name.replace("_", " ")[:31]: frame for name, frame in frames.items()}
    notes_cn = [
        ["业务问题", "六位主播在合作窗口前后的有效ACU变化，与平台基准进行描述性比较"],
        ["重算粒度", "主播×日；输出仅保留角色编号和匿名聚合"],
        ["窗口", "合作前31日、合作期7日、后1月含合作期30日、后1月剔合作期30日"],
        ["日均口径", "自然日日均=窗口ACU合计/全部日历日；缺失主播日按0计入组内合计"],
        ["基准", "全平台、剔除六人、剔除合作五人；另提供剔除异常高ACU账号的基准"],
        ["限制", "仅6位主播，窗口与赛事及暑期重叠，不能解释为合作因果效应"],
        ["已知问题", "13个日期的六人大盘差值无法与源主播合计勾稽，详见勾稽残差表"],
    ]
    notes_en = [
        ["Business question", "Describe the six-anchor valid-ACU change around the cooperation and compare it with platform benchmarks"],
        ["Grain", "Streamer-day input; only role labels and anonymous aggregates are written"],
        ["Windows", "31-day pre, 7-day event, 30-day post including event, and 30-day post excluding event"],
        ["Daily average", "Natural-day average = window ACU sum / all calendar days; missing anchor-days enter group totals as zero"],
        ["Benchmarks", "All platform, excluding six, excluding collaboration five, and variants removing the outlier account"],
        ["Limit", "Only six anchors; the window overlaps an event and summer period, so this is not a causal effect estimate"],
        ["Known issue", "On 13 dates, the market-derived six-person difference does not reconcile to the source anchor sum; see the reconciliation sheet"],
    ]
    write_workbook(output_dir / "cooperation-acu-anonymous-zh.xlsx", cn_frames, notes_cn)
    write_workbook(output_dir / "cooperation-acu-anonymous-en.xlsx", en_frames, notes_en)

    summary_json = {
        "source_files": len(manifest),
        "anchor_rows": len(anchor),
        "anchor_count": int(anchor["r_lid"].nunique()),
        "source_date_min": anchor["dt"].min().date().isoformat(),
        "source_date_max": anchor["dt"].max().date().isoformat(),
        "review_index_dates": len(daily),
        "windows": {key: list(value) for key, value in WINDOWS.items()},
        "collaboration_anchor_count": len(collaboration_ids),
        "market_reconciliation_failure_dates": len(reconciliation),
        "market_reconciliation_max_abs_residual": float(
            reconciliation["residual"].abs().max()
        )
        if not reconciliation.empty
        else 0.0,
        "privacy": {
            "identifiers_written": False,
            "nicknames_written": False,
            "source_identity_workbook_copied": False,
        },
    }
    (output_dir / "project-summary.json").write_text(
        json.dumps(summary_json, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary_json, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
