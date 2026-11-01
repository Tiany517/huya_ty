#!/usr/bin/env python3
"""Inspect Kuaishou Honor of Kings reverse-poaching workbooks without editing them."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from openpyxl import load_workbook


def cell_value(value: Any) -> Any:
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    return str(value)


def nonempty_rows(worksheet, limit: int, max_columns: int) -> list[list[Any]]:
    rows: list[list[Any]] = []
    for row in worksheet.iter_rows(min_row=1, max_row=worksheet.max_row, max_col=min(worksheet.max_column, max_columns)):
        values = [cell_value(cell.value) for cell in row]
        if any(value not in (None, "") for value in values):
            rows.append(values)
            if len(rows) >= limit:
                break
    return rows


def inspect_workbook(
    path: Path,
    preview_rows: int,
    preview_columns: int,
    summary_only: bool,
) -> dict[str, Any]:
    workbook = load_workbook(path, read_only=False, data_only=False)
    sheets = []
    for worksheet in workbook.worksheets:
        preview = nonempty_rows(worksheet, preview_rows, preview_columns)
        sheet = {
            "title": worksheet.title,
            "state": worksheet.sheet_state,
            "max_row": worksheet.max_row,
            "max_column": worksheet.max_column,
            "headers": preview[0] if preview else [],
            "merged_ranges": [str(item) for item in worksheet.merged_cells.ranges],
        }
        if not summary_only:
            sheet["preview"] = preview
        sheets.append(sheet)
    workbook.close()
    return {"file": path.name, "bytes": path.stat().st_size, "sheets": sheets}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--preview-rows", type=int, default=8)
    parser.add_argument("--preview-columns", type=int, default=18)
    parser.add_argument("--summary-only", action="store_true")
    args = parser.parse_args()

    sys.stdout.reconfigure(encoding="utf-8")
    results = [
        inspect_workbook(path, args.preview_rows, args.preview_columns, args.summary_only)
        for path in sorted(args.source_dir.glob("*.xlsx"))
    ]
    print(json.dumps(results, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
