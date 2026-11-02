#!/usr/bin/env python3
"""Export anonymized monthly-report appendix series from reviewed source files."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Callable

from openpyxl import load_workbook
from pptx import Presentation


def clean_name(value: Any) -> str:
    return str(value or "").strip()


def numeric(value: Any) -> float | None:
    if value in (None, ""):
        return None
    return float(value)


def month_from_label(value: Any, default_year: int | None = None) -> str:
    label = clean_name(value)
    if not label:
        raise ValueError("Empty month label")

    padded = label.replace("年", "-").replace("月", "")
    parts = padded.split("-")
    if len(parts) == 2 and parts[0].isdigit() and parts[1].isdigit():
        year = int(parts[0])
        if year < 100:
            year += 2000
        return f"{year:04d}-{int(parts[1]):02d}"

    if label.endswith("月") and label[:-1].isdigit() and default_year is not None:
        return f"{default_year:04d}-{int(label[:-1]):02d}"

    raise ValueError(f"Unrecognized month label: {label!r}")


def chart_data(chart) -> tuple[list[Any], list[tuple[str, list[Any]]]]:
    categories = list(chart.plots[0].categories)
    series = []
    for plot in chart.plots:
        series.extend((clean_name(item.name), list(item.values)) for item in plot.series)
    return categories, series


def find_chart(slide, predicate: Callable[[list[Any], list[tuple[str, list[Any]]]], bool]):
    for shape in slide.shapes:
        if not getattr(shape, "has_chart", False):
            continue
        categories, series = chart_data(shape.chart)
        if predicate(categories, series):
            return categories, series
    raise LookupError("Required chart was not found")


def series_map(series: list[tuple[str, list[Any]]]) -> dict[str, list[Any]]:
    return {name.strip(): values for name, values in series}


def fmt_number(value: Any, digits: int = 6) -> str:
    number = numeric(value)
    if number is None:
        return ""
    rounded = round(number, digits)
    if rounded.is_integer():
        return str(int(rounded))
    return f"{rounded:.{digits}f}".rstrip("0").rstrip(".")


def write_csv(path: Path, headers: list[str], rows: list[list[Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(headers)
        writer.writerows(rows)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def export_platform_monthly(deck_path: Path, output_dir: Path) -> dict[str, Any]:
    presentation = Presentation(deck_path)
    categories, series = find_chart(
        presentation.slides[0],
        lambda cats, items: {"抖音", "视频号", "其他", "总计"}.issubset(
            {name.strip() for name, _ in items}
        ),
    )
    values = series_map(series)
    rows = []
    maximum_difference = 0.0
    for index, category in enumerate(categories):
        month = month_from_label(category, default_year=2026)
        douyin = numeric(values["抖音"][index])
        video_channel = numeric(values["视频号"][index])
        other = numeric(values["其他"][index])
        total = numeric(values["总计"][index])
        component_total = sum(value or 0.0 for value in (douyin, video_channel, other))
        maximum_difference = max(maximum_difference, abs(component_total - (total or 0.0)))
        rows.append(
            [
                month,
                fmt_number(douyin),
                fmt_number(video_channel),
                fmt_number(other),
                fmt_number(total),
                "October 2026 is partial through 2026-10-20" if month == "2026-10" else "complete month",
            ]
        )
    write_csv(
        output_dir / "external-ecosystem-dau-monthly-2026.csv",
        ["month", "douyin_dau", "video_channel_dau", "other_dau", "total_dau", "period_status"],
        rows,
    )
    return {
        "rows": len(rows),
        "minimum_month": rows[0][0],
        "maximum_month": rows[-1][0],
        "maximum_platform_sum_difference": maximum_difference,
    }


def export_video_channel_monthly(deck_path: Path, output_dir: Path) -> dict[str, Any]:
    presentation = Presentation(deck_path)
    categories, series = find_chart(
        presentation.slides[0],
        lambda cats, items: {"单播", "双播老内容", "列1"}.issubset(
            {name.strip() for name, _ in items}
        ),
    )
    values = series_map(series)
    rows = []
    maximum_difference = 0.0
    for index, category in enumerate(categories):
        month = month_from_label(category)
        single = numeric(values["单播"][index])
        double = numeric(values["双播老内容"][index])
        total = numeric(values["列1"][index])
        maximum_difference = max(
            maximum_difference,
            abs((single or 0.0) + (double or 0.0) - (total or 0.0)),
        )
        rows.append(
            [
                month,
                fmt_number(single),
                fmt_number(double),
                fmt_number(total),
                "October 2026 is partial through 2026-10-20" if month == "2026-10" else "complete month",
            ]
        )
    write_csv(
        output_dir / "video-channel-stream-type-monthly.csv",
        ["month", "single_stream_dau", "double_stream_old_content_dau", "total_dau", "period_status"],
        rows,
    )
    return {
        "rows": len(rows),
        "minimum_month": rows[0][0],
        "maximum_month": rows[-1][0],
        "maximum_stream_sum_difference": maximum_difference,
        "monthly_means": {
            str(category): {
                "single_stream_dau": numeric(values["单播"][index]),
                "double_stream_old_content_dau": numeric(values["双播老内容"][index]),
            }
            for index, category in enumerate(categories)
        },
    }


def export_douyin_mcn_categories(deck_path: Path, output_dir: Path) -> dict[str, Any]:
    presentation = Presentation(deck_path)
    required = {"王者荣耀", "三角洲行动", "CF&CFM", "LOL&云顶", "无畏契约", "和平精英", "逆水寒", "鹅鸭杀", "其他", "总计"}
    categories, series = find_chart(
        presentation.slides[0],
        lambda cats, items: len(cats) == 10
        and clean_name(cats[0]) == "26-1月"
        and required.issubset({name.strip() for name, _ in items}),
    )
    values = series_map(series)
    dimension_names = ["王者荣耀", "三角洲行动", "CF&CFM", "LOL&云顶", "无畏契约", "和平精英", "逆水寒", "鹅鸭杀", "其他"]
    rows = []
    maximum_difference = 0.0
    for index, category in enumerate(categories):
        month = month_from_label(category, default_year=2026)
        dimensions = [numeric(values[name][index]) for name in dimension_names]
        total = numeric(values["总计"][index])
        component_total = sum(value or 0.0 for value in dimensions)
        maximum_difference = max(maximum_difference, abs(component_total - (total or 0.0)))
        rows.append(
            [month, *[fmt_number(value) for value in dimensions], fmt_number(total)]
        )
    headers = ["month", "honor_of_kings_dau", "delta_force_dau", "cf_cfm_dau", "lol_tft_dau", "valorant_dau", "pubg_mobile_dau", "justice_online_dau", "goose_goose_duck_dau", "other_dau", "total_dau"]
    write_csv(output_dir / "douyin-mcn-category-dau-monthly-2026.csv", headers, rows)
    return {
        "rows": len(rows),
        "minimum_month": rows[0][0],
        "maximum_month": rows[-1][0],
        "maximum_category_sum_difference": maximum_difference,
    }


def export_app_game_exclusive(workbook_path: Path, output_dir: Path) -> dict[str, Any]:
    workbook = load_workbook(workbook_path, read_only=True, data_only=True)
    worksheet = workbook["独占"]
    header_row = None
    for row_number in range(1, min(worksheet.max_row, 30) + 1):
        if worksheet.cell(row_number, 5).value == "mth":
            header_row = row_number
            break
    if header_row is None:
        raise ValueError("Could not locate the game-exclusive header row")

    rows = []
    maximum_share_difference = 0.0
    maximum_share_sum_difference = 0.0
    for row_number in range(header_row + 1, worksheet.max_row + 1):
        month_value = worksheet.cell(row_number, 5).value
        if not isinstance(month_value, datetime):
            continue
        month = month_value.strftime("%Y-%m")
        total_users = int(worksheet.cell(row_number, 6).value)
        game_users = int(worksheet.cell(row_number, 7).value)
        entertainment_users = int(worksheet.cell(row_number, 8).value)
        overlap_users = int(worksheet.cell(row_number, 9).value)
        game_share = float(worksheet.cell(row_number, 10).value)
        entertainment_share = float(worksheet.cell(row_number, 11).value)
        overlap_share = float(worksheet.cell(row_number, 12).value)
        game_exclusive_users = game_users - overlap_users
        entertainment_exclusive_users = entertainment_users - overlap_users
        maximum_share_difference = max(
            maximum_share_difference,
            abs(game_share - game_exclusive_users / total_users),
            abs(entertainment_share - entertainment_exclusive_users / total_users),
            abs(overlap_share - overlap_users / total_users),
        )
        maximum_share_sum_difference = max(
            maximum_share_sum_difference,
            abs(game_share + entertainment_share + overlap_share - 1.0),
        )
        rows.append(
            [
                month,
                total_users,
                game_exclusive_users,
                entertainment_exclusive_users,
                overlap_users,
                fmt_number(game_share),
                fmt_number(entertainment_share),
                fmt_number(overlap_share),
            ]
        )
    workbook.close()
    write_csv(
        output_dir / "app-game-exclusive-monthly.csv",
        ["month", "total_users", "game_exclusive_users", "entertainment_exclusive_users", "overlap_users", "game_exclusive_share", "entertainment_exclusive_share", "overlap_share"],
        rows,
    )
    return {
        "rows": len(rows),
        "minimum_month": rows[0][0],
        "maximum_month": rows[-1][0],
        "maximum_recomputed_share_difference": maximum_share_difference,
        "maximum_share_sum_difference": maximum_share_sum_difference,
    }


def export_app_retention(deck_path: Path, output_dir: Path) -> dict[str, Any]:
    presentation = Presentation(deck_path)
    categories, series = find_chart(
        presentation.slides[0],
        lambda cats, items: any(name.strip() == "ratio" for name, _ in items),
    )
    values = series_map(series)
    rows = [[month_from_label(category), fmt_number(value)] for category, value in zip(categories, values["ratio"])]
    write_csv(output_dir / "app-next-month-retention-monthly.csv", ["month", "next_month_retention_rate"], rows)
    return {
        "rows": len(rows),
        "minimum_month": rows[0][0],
        "maximum_month": rows[-1][0],
    }


def parse_integer(value: str) -> int:
    return int(value.replace(",", "").strip())


def parse_float(value: str) -> float:
    return float(value.replace(",", "").strip())


def export_video_channel_daily(source_csv: Path, output_dir: Path) -> dict[str, Any]:
    rows = []
    with source_csv.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.reader(handle)
        next(reader)
        for raw in reader:
            if len(raw) < 6:
                continue
            try:
                day = datetime.strptime(raw[0].strip(), "%Y/%m/%d").strftime("%Y-%m-%d")
            except ValueError:
                continue
            stream_type = raw[1].strip()
            if stream_type not in {"单播", "双播"}:
                continue
            rows.append(
                [
                    day,
                    stream_type,
                    parse_integer(raw[2]),
                    parse_float(raw[3]),
                    parse_integer(raw[4]),
                    parse_integer(raw[5]),
                ]
            )
    rows.sort(key=lambda row: (row[0], row[1]))
    write_csv(
        output_dir / "video-channel-mcn-daily-2026-05-25_2026-08-18.csv",
        ["date", "stream_type", "anchor_count", "average_live_hours", "dau", "effective_dau"],
        rows,
    )
    keys = {(row[0], row[1]) for row in rows}
    days = {row[0] for row in rows}
    types_per_day = {day: sorted(row[1] for row in rows if row[0] == day) for day in days}
    duplicate_keys = len(rows) - len(keys)
    incomplete_days = [day for day, types in types_per_day.items() if types != ["单播", "双播"]]
    current = datetime.strptime(min(days), "%Y-%m-%d")
    end = datetime.strptime(max(days), "%Y-%m-%d")
    missing_days = []
    while current <= end:
        day = current.strftime("%Y-%m-%d")
        if day not in days:
            missing_days.append(day)
        current += timedelta(days=1)
    monthly_values = defaultdict(list)
    for row in rows:
        monthly_values[(row[0][:7], row[1])].append(row[4])
    return {
        "rows": len(rows),
        "unique_dates": len(days),
        "minimum_date": min(days),
        "maximum_date": max(days),
        "duplicate_date_stream_type_keys": duplicate_keys,
        "dates_without_exactly_two_stream_types": incomplete_days,
        "missing_calendar_dates": missing_days,
        "monthly_means": {
            f"{month}|{stream_type}": sum(values) / len(values)
            for (month, stream_type), values in sorted(monthly_values.items())
        },
    }


def make_manifest(source_root: Path, output_dir: Path) -> list[dict[str, Any]]:
    relative_paths = [
        "月报外生态/外生态通报_1024.pptx",
        "月报外生态/视频号MCN日均_单播_双播_DAU_0820.csv",
        "月报APP端DAU_游戏独占DAU/月报附录_202604.pptx",
        "月报APP端DAU_游戏独占DAU/游戏独占用户_处理模板.xlsx",
        "月报外生态/视频号月报_单播_双播_DAU取数.sql",
        "月报APP端DAU_游戏独占DAU/视频号DAU_分单播和双播_主播下钻.sql",
        "月报APP端DAU_游戏独占DAU/视频号单双播主播下钻_final.sql",
        "月报APP端DAU_游戏独占DAU/游戏独占用户取数模板.sql",
    ]
    manifest = []
    for relative_path in relative_paths:
        path = source_root / relative_path
        manifest.append(
            {
                "source_file": relative_path.replace("\\", "/"),
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
            }
        )
    write_csv(output_dir / "source-manifest.csv", ["source_file", "bytes", "sha256"], [[row[key] for key in ("source_file", "bytes", "sha256")] for row in manifest])
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()

    source_root = args.source_dir.resolve()
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    validation = {
        "external_platform_monthly": export_platform_monthly(
            source_root / "月报外生态/外生态通报_1024.pptx", output_dir
        ),
        "video_channel_stream_type_monthly": export_video_channel_monthly(
            source_root / "月报外生态/外生态通报_1024.pptx", output_dir
        ),
        "douyin_mcn_categories_monthly": export_douyin_mcn_categories(
            source_root / "月报外生态/外生态通报_1024.pptx", output_dir
        ),
        "app_game_exclusive_monthly": export_app_game_exclusive(
            source_root / "月报APP端DAU_游戏独占DAU/游戏独占用户_处理模板.xlsx", output_dir
        ),
        "app_next_month_retention_monthly": export_app_retention(
            source_root / "月报APP端DAU_游戏独占DAU/月报附录_202604.pptx", output_dir
        ),
        "video_channel_mcn_daily": export_video_channel_daily(
            source_root / "月报外生态/视频号MCN日均_单播_双播_DAU_0820.csv", output_dir
        ),
    }
    validation["source_manifest"] = make_manifest(source_root, output_dir)
    validation["review"] = {
        "status": "reviewed_with_known_source_gaps",
        "known_limitations": [
            "October 2026 external ecosystem values are partial through 2026-10-20.",
            "The daily video-channel CSV omits 2026-08-01; the missing day is disclosed and is not filled as zero.",
            "The Douyin MCN category chart does not fully reconcile to its total in 2026-04 through 2026-08; source values are retained without adjustment.",
            "Full source workbooks and decks are excluded because they contain anchor identities, contracts, or commercial detail.",
            "The APP next-month retention series is recovered from a deck chart because no underlying query was present in the reviewed folder.",
        ],
    }
    with (output_dir / "validation-summary.json").open("w", encoding="utf-8") as handle:
        json.dump(validation, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(json.dumps(validation, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
