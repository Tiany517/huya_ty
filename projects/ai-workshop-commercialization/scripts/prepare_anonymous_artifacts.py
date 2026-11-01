#!/usr/bin/env python3
"""Extract reviewed, anonymous project summaries from the local AI workshop sources.

The source workbooks are intentionally not committed because they contain item-level
prompts, streamer IDs/nicknames, or large user-level caches. This script keeps only
the aggregate tables needed to understand and continue the analysis.
"""

from __future__ import annotations

import argparse
import csv
from decimal import Decimal
from pathlib import Path

from openpyxl import load_workbook


def parse_number(value: object) -> object:
    if value is None:
        return ""
    if isinstance(value, (int, float, Decimal)):
        return value
    text = str(value).strip().replace(",", "")
    if not text:
        return ""
    if text.endswith("%"):
        return float(Decimal(text[:-1]) / Decimal(100))
    try:
        return int(text)
    except ValueError:
        try:
            return float(text)
        except ValueError:
            return text


def write_csv(path: Path, header: list[str], rows: list[list[object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(header)
        writer.writerows(rows)


def extract_gift_category_summaries(source_root: Path, output_dir: Path) -> tuple[int, int]:
    source = source_root / "AI送礼偏好汇总" / "AI送礼礼物_item_id_语义打标统计_v7_final.xlsx"
    workbook = load_workbook(source, read_only=True, data_only=True)
    try:
        specs = [
            (
                "一级类目汇总",
                "ai-gift-primary-category-summary",
                ["一级排序", "一级类目", "送礼次数", "送礼人数", "消费金额", "礼物数", "待复核礼物数", "送礼次数占比", "送礼人数占比", "消费金额占比"],
                ["primary_rank", "primary_category", "gift_order_count", "gift_user_count", "consumption_amount", "gift_item_count", "pending_review_item_count", "order_share", "user_share", "amount_share"],
            ),
            (
                "二级类目汇总",
                "ai-gift-secondary-category-summary",
                ["一级排序", "一级类目", "二级类目", "送礼次数", "送礼人数", "消费金额", "礼物数", "送礼次数占比", "送礼人数占比", "消费金额占比"],
                ["primary_rank", "primary_category", "secondary_category", "gift_order_count", "gift_user_count", "consumption_amount", "gift_item_count", "order_share", "user_share", "amount_share"],
            ),
        ]
        counts: list[int] = []
        for sheet_name, stem, chinese_header, english_header in specs:
            sheet = workbook[sheet_name]
            source_header = [cell.value for cell in next(sheet.iter_rows(min_row=1, max_row=1))]
            index = {name: source_header.index(name) for name in chinese_header}
            rows: list[list[object]] = []
            for row in sheet.iter_rows(min_row=2, values_only=True):
                if not any(value is not None for value in row):
                    continue
                values = [row[index[name]] for name in chinese_header]
                if all(value is None for value in values):
                    continue
                rows.append(values)
            write_csv(output_dir / f"{stem}.csv", chinese_header, rows)
            write_csv(output_dir / f"{stem}.en.csv", english_header, rows)
            counts.append(len(rows))
        return counts[0], counts[1]
    finally:
        workbook.close()


def extract_flow_tables(source_root: Path, output_dir: Path) -> tuple[int, int]:
    workbook_path = source_root / "AI礼物和普通礼物各个ACU分层的流水分布_final.xlsx"
    workbook = load_workbook(workbook_path, read_only=True, data_only=True)
    try:
        category_sheet = workbook["各个品类曝光人数和点击人数"]
        category_header = [cell.value for cell in next(category_sheet.iter_rows(min_row=1, max_row=1))][:9]
        category_rows: list[list[object]] = []
        for row in category_sheet.iter_rows(min_row=2, min_col=1, max_col=9, values_only=True):
            if all(value is None for value in row):
                continue
            category_rows.append(list(row))
        write_csv(output_dir / "ai-workshop-category-exposure.csv", category_header, category_rows)
        write_csv(
            output_dir / "ai-workshop-category-exposure.en.csv",
            ["game_label", "game_id", "game_name", "exposure_user_count", "click_user_count", "click_rate", "pay_user_count", "exposure_pay_rate", "click_conversion_rate"],
            category_rows,
        )

        acu_sheet = workbook["各个品类和ACU的流水分布"]
        acu_header = [cell.value for cell in next(acu_sheet.iter_rows(min_row=1, max_row=1))][:8]
        acu_rows: list[list[object]] = []
        for row in acu_sheet.iter_rows(min_row=2, min_col=1, max_col=8, values_only=True):
            if all(value is None for value in row):
                continue
            acu_rows.append(list(row))
        write_csv(output_dir / "ai-vs-regular-gift-category-acu-flow.csv", [str(value).strip() if value else "" for value in acu_header], acu_rows)
        write_csv(
            output_dir / "ai-vs-regular-gift-category-acu-flow.en.csv",
            ["gift_type", "game_label", "game_name", "acu_bin", "order_count", "consumption_amount", "amount_share", "matched_minute_count"],
            acu_rows,
        )
        return len(category_rows), len(acu_rows)
    finally:
        workbook.close()


def extract_legacy_gift_flow(source_root: Path, output_dir: Path) -> int:
    source = source_root / "AI礼物和普通礼物各个ACU分层的流水分布_final.csv"
    rows: list[list[object]] = []
    with source.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.reader(handle)
        next(reader)
        for row in reader:
            if len(row) < 5 or not row[0].strip():
                continue
            rows.append([row[0].strip(), row[1].strip(), row[2].strip(), parse_number(row[3]), parse_number(row[4])])
    write_csv(
        output_dir / "ai-vs-regular-gift-category-flow.csv",
        ["is_ai", "game_label", "game_name", "user_consume_amount", "consume_amount_ratio"],
        rows,
    )
    write_csv(
        output_dir / "ai-vs-regular-gift-category-flow.en.csv",
        ["gift_type", "game_label", "game_name", "user_consume_amount", "consume_amount_ratio"],
        rows,
    )
    return len(rows)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()

    primary_count, secondary_count = extract_gift_category_summaries(args.source_root, args.output_dir)
    category_count, acu_count = extract_flow_tables(args.source_root, args.output_dir)
    legacy_count = extract_legacy_gift_flow(args.source_root, args.output_dir)
    print(
        f"primary_categories={primary_count} secondary_categories={secondary_count} "
        f"category_rows={category_count} acu_rows={acu_count} legacy_flow_rows={legacy_count}"
    )


if __name__ == "__main__":
    main()
