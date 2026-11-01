from __future__ import annotations

import csv
import json
import math
import sys
from pathlib import Path

import openpyxl
from docx import Document


PROJECT = Path(__file__).resolve().parents[1]
ARTIFACTS = PROJECT / "artifacts"
REPORTS = ARTIFACTS / "final-reports"
SUMMARIES = ARTIFACTS / "anonymous-summary"
OUTPUT = ARTIFACTS / "validation-report.json"

REQUIRED = [
    PROJECT / "README.md",
    PROJECT / "README.en.md",
    PROJECT / "methodology" / "report-revisions.md",
    PROJECT / "methodology" / "report-revisions.en.md",
    REPORTS / "activity-psm-did-report-20260615.docx",
    REPORTS / "activity-psm-did-results-20260615.xlsx",
    REPORTS / "exposure-current-dota2-report-20260616.docx",
    REPORTS / "exposure-current-dota2-results-20260616.xlsx",
    REPORTS / "exposure-april-interest-report-20260616.docx",
    REPORTS / "exposure-april-interest-results-20260616.xlsx",
    SUMMARIES / "activity-did-result-20260615.csv",
    SUMMARIES / "activity-psm-balance-20260615.csv",
    SUMMARIES / "exposure-current-dota2-did-result-20260616.csv",
    SUMMARIES / "exposure-april-interest-did-result-20260616.csv",
]

EXPECTED_TEXT = {
    REPORTS / "activity-psm-did-report-20260615.docx": ["13,846", "0.0403"],
    REPORTS / "exposure-current-dota2-report-20260616.docx": ["7,631", "0.0350"],
    REPORTS / "exposure-april-interest-report-20260616.docx": ["7,175", "0.0589"],
}

EXPECTED_SHEETS = {
    REPORTS / "activity-psm-did-results-20260615.xlsx": ["DID净效应数据"],
    REPORTS / "exposure-current-dota2-results-20260616.xlsx": ["DID净效应数据", "中位数DID数据"],
    REPORTS / "exposure-april-interest-results-20260616.xlsx": ["DID净效应数据", "DID净效应数据-中位数", "SMD平衡检验"],
}

EXPECTED_DID = {
    SUMMARIES / "activity-did-result-20260615.csv": {
        "after_watch_duration": 53.23,
        "after_consume_amount": 7.98,
        "ltv_pay_rate": 1.7622,
    },
    SUMMARIES / "exposure-current-dota2-did-result-20260616.csv": {
        "after_watch_duration": -19.97,
        "after_watch_dcnt": 0.07,
        "ltv_pay_rate": -1.009,
    },
    SUMMARIES / "exposure-april-interest-did-result-20260616.csv": {
        "after_watch_duration": 9.39,
        "after_watch_dcnt": 0.19,
        "ltv_pay_rate": -0.1672,
    },
}

PII_HEADER_TOKENS = ("uid", "nickname", "user_id", "account_id", "ayyuid", "luid")


def docx_text(path: Path) -> str:
    document = Document(path)
    chunks = [paragraph.text for paragraph in document.paragraphs]
    for table in document.tables:
        for row in table.rows:
            chunks.extend(cell.text for cell in row.cells)
    return "\n".join(chunks)


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def numeric(value: object) -> float:
    if value is None or value == "":
        return math.nan
    return float(value)


def main() -> int:
    failures: list[str] = []
    warnings: list[str] = []
    checks: list[dict[str, object]] = []

    for path in REQUIRED:
        exists = path.is_file()
        checks.append({"check": "required_file", "path": str(path.relative_to(PROJECT)), "pass": exists})
        if not exists:
            failures.append(f"Missing required file: {path.relative_to(PROJECT)}")

    for path, expected in EXPECTED_TEXT.items():
        if not path.is_file():
            continue
        text = docx_text(path)
        missing = [value for value in expected if value not in text]
        checks.append({
            "check": "docx_expected_text",
            "path": str(path.relative_to(PROJECT)),
            "expected": expected,
            "pass": not missing,
        })
        if missing:
            failures.append(f"{path.name} is missing expected text: {missing}")

    for path, expected_sheets in EXPECTED_SHEETS.items():
        if not path.is_file():
            continue
        workbook = openpyxl.load_workbook(path, read_only=True, data_only=True)
        sheets = workbook.sheetnames
        checks.append({
            "check": "xlsx_sheet_names",
            "path": str(path.relative_to(PROJECT)),
            "expected": expected_sheets,
            "actual": sheets,
            "pass": sheets == expected_sheets,
        })
        if sheets != expected_sheets:
            failures.append(f"{path.name} sheet mismatch: expected {expected_sheets}, got {sheets}")
        workbook.close()

    for path, expected_values in EXPECTED_DID.items():
        if not path.is_file():
            continue
        rows = read_csv(path)
        header = list(rows[0].keys()) if rows else []
        pii_hits = [name for name in header if any(token in name.lower() for token in PII_HEADER_TOKENS)]
        checks.append({
            "check": "anonymous_csv_header",
            "path": str(path.relative_to(PROJECT)),
            "pass": not pii_hits,
            "pii_hits": pii_hits,
        })
        if pii_hits:
            failures.append(f"{path.name} has user-level headers: {pii_hits}")

        by_outcome = {row["outcome"]: row for row in rows if row.get("outcome")}
        for outcome, expected in expected_values.items():
            row = by_outcome.get(outcome)
            actual = numeric(row.get("did_effect")) if row else math.nan
            passed = not math.isnan(actual) and math.isclose(actual, expected, rel_tol=0, abs_tol=1e-4)
            checks.append({
                "check": "key_did_value",
                "path": str(path.relative_to(PROJECT)),
                "outcome": outcome,
                "expected": expected,
                "actual": actual,
                "pass": passed,
            })
            if not passed:
                failures.append(f"{path.name} {outcome}: expected {expected}, got {actual}")

    current = REPORTS / "exposure-current-dota2-results-20260616.xlsx"
    if current.is_file():
        workbook = openpyxl.load_workbook(current, read_only=True, data_only=True)
        sheet = workbook["中位数DID数据"]
        labels = {}
        for row in sheet.iter_rows(min_row=4, max_row=11, values_only=True):
            if row[1]:
                labels[str(row[1])] = (row[10], row[11])
        for metric in ("观看天数", "观看游戏数"):
            p_value, label = labels.get(metric, (None, None))
            if p_value is not None and float(p_value) < 0.05 and label and "不显著" in str(label):
                warnings.append(f"Current DOTA2 median {metric}: p={p_value}, label={label}")
        workbook.close()

    april = REPORTS / "exposure-april-interest-results-20260616.xlsx"
    if april.is_file():
        workbook = openpyxl.load_workbook(april, read_only=True, data_only=True)
        sheet = workbook["DID净效应数据-中位数"]
        labels = {}
        for row in sheet.iter_rows(min_row=4, max_row=11, values_only=True):
            if row[1]:
                labels[str(row[1])] = (row[10], row[11])
        for metric in ("观看主播数", "观看游戏数", "活跃天数"):
            p_value, label = labels.get(metric, (None, None))
            if p_value is not None and float(p_value) < 0.05 and label and "不显著" in str(label):
                warnings.append(f"April-interest median {metric}: p={p_value}, label={label}")
        workbook.close()

    status = "fail" if failures else ("pass_with_documented_warnings" if warnings else "pass")
    result = {
        "project": "buxiucup-popup-psm",
        "status": status,
        "hard_failures": failures,
        "documented_warnings": warnings,
        "checks": checks,
        "summary": {
            "hard_check_count": len(checks),
            "hard_failure_count": len(failures),
            "warning_count": len(warnings),
        },
    }
    OUTPUT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result["summary"], ensure_ascii=False, indent=2))
    print(f"Validation report: {OUTPUT}")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
