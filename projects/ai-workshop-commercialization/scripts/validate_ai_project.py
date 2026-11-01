#!/usr/bin/env python3
"""Validate the curated AI workshop migration snapshot."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import re
from datetime import date
from pathlib import Path

from openpyxl import load_workbook
from pptx import Presentation


LONG_NUMERIC_ID = re.compile(r"^\d{8,}$")
BANNED_HEADER = re.compile(r"(^|_)(uid|nickname|user_id|creator_uid|item_id|prompt)($|_)", re.I)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def workbook_rows(path: Path, sheet_name: str) -> list[list[object]]:
    workbook = load_workbook(path, read_only=True, data_only=True)
    try:
        return [list(row) for row in workbook[sheet_name].iter_rows(values_only=True)]
    finally:
        workbook.close()


def close_enough(actual: float, expected: float, tolerance: float = 1e-10) -> bool:
    return math.isclose(float(actual), expected, rel_tol=0, abs_tol=tolerance)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    root = args.project_root.resolve()

    expected_files = [
        "README.md",
        "README.en.md",
        "artifacts/final-report/ai-workshop-psm7-f2-report.xlsx",
        "artifacts/final-report/ai-workshop-psm8-ab-did-report.xlsx",
        "artifacts/final-slides/ai-workshop-commercial-value-20260921.pptx",
        "artifacts/version-analysis/ai-workshop-version-conversion-report.xlsx",
        "artifacts/version-analysis/ai-workshop-version-daily-detail.csv",
        "artifacts/charts/propensity-score-overlap.png",
        "artifacts/charts/propensity-score-ecdf.png",
        "artifacts/charts/propensity-score-qq.png",
        "artifacts/anonymous-summary/ai-gift-primary-category-summary.en.csv",
        "artifacts/anonymous-summary/ai-gift-secondary-category-summary.en.csv",
        "artifacts/anonymous-summary/ai-vs-regular-gift-category-acu-flow.en.csv",
    ]
    missing = [relative for relative in expected_files if not (root / relative).exists()]
    if missing:
        raise AssertionError(f"Missing files: {missing}")

    psm7 = root / "artifacts/final-report/ai-workshop-psm7-f2-report.xlsx"
    sample_rows = workbook_rows(psm7, "样本与匹配")
    sample = {str(row[0]): row[1] for row in sample_rows[1:] if row and row[0]}
    assert sample["主方案匹配对数"] == 1804
    assert close_enough(sample["主方案实验组覆盖率"], 0.4359594006766554)
    assert close_enough(sample["主方案最大绝对SMD"], 0.03956218681799889)
    assert sample["是否所有前置SMD<0.1"] == "是"

    did_rows = workbook_rows(psm7, "DID净效应")
    did_header = did_rows[1]
    did = {
        row[1]: dict(zip(did_header, row))
        for row in did_rows[2:]
        if row and row[0] == "后7日" and row[1]
    }
    amount = did["整体打赏金额（元/人/日）"]
    assert close_enough(amount["DID"], 84.99669253510716)
    assert close_enough(amount["p值"], 1.652249293700031e-05, 1e-18)
    assert amount["稳健显著"] == "是"

    psm8 = root / "artifacts/final-report/ai-workshop-psm8-ab-did-report.xlsx"
    psm8_sample = {str(row[0]): row[1] for row in workbook_rows(psm8, "样本与匹配")[1:] if row and row[0]}
    assert psm8_sample["匹配对数"] == 3520
    assert close_enough(psm8_sample["实验组覆盖率"], 0.8506524891251812)

    version_workbook = root / "artifacts/version-analysis/ai-workshop-version-conversion-report.xlsx"
    version_sheets = load_workbook(version_workbook, read_only=True).sheetnames
    assert version_sheets == ["版本周日均转换率", "版本窗口曝光占比", "版本周明细", "口径说明", "源数据_版本天"]
    version_rows = workbook_rows(version_workbook, "源数据_版本天")
    version_dates = [str(row[0]) for row in version_rows[1:] if row and row[0]]
    assert min(version_dates) == "2026-07-13"
    assert max(version_dates) == "2026-09-14"
    assert len(set(version_dates)) == 64
    assert len({str(row[1]) for row in version_rows[1:] if row and row[1]}) == 8

    slide_path = root / "artifacts/final-slides/ai-workshop-commercial-value-20260921.pptx"
    presentation = Presentation(slide_path)
    assert len(presentation.slides) == 1
    slide_text = " ".join(
        shape.text for shape in presentation.slides[0].shapes if hasattr(shape, "text")
    )
    for phrase in ["PSM-DID", "ROI", "2.0万元", "500元/日"]:
        assert phrase in slide_text, phrase

    summary_dir = root / "artifacts/anonymous-summary"
    summary_counts: dict[str, int] = {}
    for path in sorted(summary_dir.glob("*.csv")):
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.reader(handle)
            header = next(reader)
            rows = list(reader)
        banned = [column for column in header if BANNED_HEADER.search(column)]
        assert not banned, f"Restricted columns in {path.name}: {banned}"
        summary_counts[path.name] = len(rows)
    assert summary_counts["ai-gift-primary-category-summary.en.csv"] == 13
    assert summary_counts["ai-gift-secondary-category-summary.en.csv"] == 26
    assert summary_counts["ai-workshop-category-exposure.en.csv"] == 1742
    assert summary_counts["ai-vs-regular-gift-category-acu-flow.en.csv"] == 2788
    assert summary_counts["ai-vs-regular-gift-category-flow.en.csv"] == 788

    files = sorted(
        path
        for path in root.rglob("*")
        if path.is_file()
        and "__pycache__" not in path.parts
        and path.relative_to(root).as_posix() != "artifacts/validation-report.json"
    )
    manifest = [
        {"path": path.relative_to(root).as_posix(), "bytes": path.stat().st_size, "sha256": sha256(path)}
        for path in files
    ]
    report = {
        "status": "pass",
        "checks": [
            "expected files present",
            "PSM7 sample/matching/DID values reconciled",
            "PSM8 sample/matching values reconciled",
            "version report date range and version count reconciled",
            "final slide count and required result wording verified",
            "anonymous CSV headers contain no UID/nickname/item/prompt fields",
            "anonymous summary row counts verified",
        ],
        "summary_row_counts": summary_counts,
        "files": manifest,
    }
    rendered = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
    print(rendered, end="")


if __name__ == "__main__":
    main()
