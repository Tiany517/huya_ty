from __future__ import annotations

import hashlib
import json
from pathlib import Path

import openpyxl


ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = ROOT / "artifacts" / "zh"
EXPECTED = {
    "2026-06-25_世界杯_Top10视频分析.xlsx": {
        "bytes": 17592,
        "sha256": "dd433ebd4a9530be5c972ca62ae9b8ee6e103a37550b6d63b7ced11532f357a1",
        "max_rows": [6, 11, 11],
    },
    "2026-06-25_小钟Johnny_Top10视频分析.xlsx": {
        "bytes": 19549,
        "sha256": "835138adecac01f558869ddb21cf1bd6fcb6962816f5401445dbfa7e688fe135",
        "max_rows": [25, 13, 13],
    },
    "2026-06-25_小Lin说_Top10视频分析.xlsx": {
        "bytes": 19282,
        "sha256": "758f4004b37a907945fc61fb11618ef3cf8f1940ac40ee48da314acd21b7d9ea",
        "max_rows": [11, 13, 13],
    },
    "黄士铨看世界_Top10视频分析.xlsx": {
        "bytes": 19212,
        "sha256": "4d603cb3c806291ee7b0899839e67ae293e7b860b503e131eca8ce16728b797c",
        "max_rows": [12, 13, 13],
    },
}
FORMULA_ERRORS = {"#REF!", "#DIV/0!", "#VALUE!", "#N/A", "#NAME?", "#NULL!", "#NUM!"}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    checks: list[dict[str, object]] = []
    for name, expected in EXPECTED.items():
        path = ARTIFACTS / name
        item: dict[str, object] = {"file": name, "passed": True, "issues": []}
        if not path.is_file():
            item["passed"] = False
            item["issues"].append("missing file")
            checks.append(item)
            continue
        if path.stat().st_size != expected["bytes"]:
            item["passed"] = False
            item["issues"].append("byte count mismatch")
        if sha256(path) != expected["sha256"]:
            item["passed"] = False
            item["issues"].append("SHA-256 mismatch")

        workbook = openpyxl.load_workbook(path, read_only=True, data_only=False)
        if len(workbook.worksheets) != 3:
            item["passed"] = False
            item["issues"].append("worksheet count is not 3")
        formula_count = 0
        error_cells: list[str] = []
        observed_max_rows = [sheet.max_row for sheet in workbook.worksheets]
        for sheet in workbook.worksheets:
            for row in sheet.iter_rows():
                for cell in row:
                    if cell.data_type == "f":
                        formula_count += 1
                    if isinstance(cell.value, str) and cell.value.strip() in FORMULA_ERRORS:
                        error_cells.append(f"{sheet.title}!{cell.coordinate}={cell.value}")
        if observed_max_rows != expected["max_rows"]:
            item["passed"] = False
            item["issues"].append("worksheet dimensions changed")
        if formula_count != 0:
            item["passed"] = False
            item["issues"].append("unexpected formulas")
        if error_cells:
            item["passed"] = False
            item["issues"].append("formula error cells found")
        item.update(
            {
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
                "worksheets": len(workbook.worksheets),
                "max_rows": observed_max_rows,
                "formula_count": formula_count,
                "formula_error_count": len(error_cells),
            }
        )
        checks.append(item)

    passed = sum(bool(item["passed"]) for item in checks)
    result = {
        "project": "douyin-playwright-video-analysis",
        "checks": checks,
        "summary": {
            "files": len(checks),
            "passed": passed,
            "failed": len(checks) - passed,
            "total_video_records": 40,
            "formula_errors": 0,
        },
        "status": "passed" if passed == len(checks) else "failed",
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
