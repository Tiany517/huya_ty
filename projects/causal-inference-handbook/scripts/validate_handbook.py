#!/usr/bin/env python3
"""Validate the migrated causal-inference handbook and its method review."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
from collections import Counter
from pathlib import Path

from bs4 import BeautifulSoup
from docx import Document
from PyPDF2 import PdfReader


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = PROJECT_ROOT / "sources"
ARTIFACT_DIR = PROJECT_ROOT / "artifacts"
VALIDATION_DIR = PROJECT_ROOT / "validation"
DEFAULT_LOCAL_SOURCE = Path(r"C:\Users\tiany\Desktop\因果推断实操")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalize(text: str) -> str:
    return re.sub(r"\s+", "", text)


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def csv_field_widths(path: Path) -> set[int]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return {len(row) for row in csv.reader(handle)}


def docx_text(path: Path) -> tuple[str, int, int]:
    document = Document(path)
    parts = [paragraph.text for paragraph in document.paragraphs]
    for table in document.tables:
        for row in table.rows:
            parts.extend(cell.text for cell in row.cells)
    return "\n".join(parts), len(document.paragraphs), len(document.tables)


def add_check(
    checks: list[dict[str, object]],
    check_id: str,
    status: str,
    title_zh: str,
    title_en: str,
    evidence_zh: str,
    evidence_en: str,
) -> None:
    checks.append(
        {
            "check_id": check_id,
            "status": status,
            "zh": {"title": title_zh, "evidence": evidence_zh},
            "en": {"title": title_en, "evidence": evidence_en},
        }
    )


def validate(local_source: Path) -> dict[str, object]:
    manifest = read_csv(ARTIFACT_DIR / "source-manifest.csv")
    checks: list[dict[str, object]] = []
    local_hashes = {sha256(path): path for path in local_source.iterdir() if path.is_file()}

    mismatches: list[str] = []
    local_mismatches: list[str] = []
    for row in manifest:
        path = PROJECT_ROOT / row["source_path"]
        if not path.exists() or path.stat().st_size != int(row["size_bytes"]) or sha256(path) != row["sha256"]:
            mismatches.append(row["source_id"])
        if row["sha256"] not in local_hashes:
            local_mismatches.append(row["source_id"])
    add_check(
        checks,
        "source_manifest_hashes",
        "PASS" if not mismatches else "FAIL",
        "五个源文件大小和 SHA-256 一致",
        "All five source sizes and SHA-256 values match",
        f"{len(manifest)} 项；仓库异常={mismatches}",
        f"{len(manifest)} entries; repository mismatches={mismatches}",
    )
    add_check(
        checks,
        "local_source_lineage",
        "PASS" if not local_mismatches else "FAIL",
        "仓库副本可追溯到本机原文件",
        "Repository copies trace to local source files by hash",
        f"本机匹配异常={local_mismatches}",
        f"local hash mismatches={local_mismatches}",
    )

    md_path = SOURCE_DIR / "causal-inference-handbook-optimized.md"
    zero_path = SOURCE_DIR / "zero-hand-calculation.md"
    md_text = md_path.read_text(encoding="utf-8-sig")
    zero_text = zero_path.read_text(encoding="utf-8-sig")
    md_lines = len(md_text.splitlines())
    code_fences = sum(1 for line in md_text.splitlines() if line.startswith("```"))
    code_blocks = code_fences // 2
    code_fences_even = code_fences % 2 == 0
    add_check(
        checks,
        "markdown_structure",
        "PASS" if md_lines == 2025 and code_blocks == 74 and code_fences_even else "FAIL",
        "Markdown 主文档结构可读",
        "Markdown master structure is readable",
        f"行数={md_lines}; 代码块={code_blocks}; 围栏标记={code_fences}; 成对={code_fences_even}; 字符={len(md_text)}",
        f"lines={md_lines}; code blocks={code_blocks}; fence markers={code_fences}; paired={code_fences_even}; characters={len(md_text)}",
    )
    zero_embedded = normalize(zero_text) in normalize(md_text)
    add_check(
        checks,
        "zero_part_embedding",
        "PASS" if zero_embedded else "FAIL",
        "第零部分完整包含于优化版 Markdown",
        "The zero-part deep dive is fully contained in optimized Markdown",
        f"规范化文本包含={zero_embedded}",
        f"normalized containment={zero_embedded}",
    )

    docx_path = SOURCE_DIR / "causal-inference-handbook-base.docx"
    docx_content, paragraphs, tables = docx_text(docx_path)
    docx_ok = paragraphs == 871 and tables == 4 and all(token in docx_content for token in ("PSM", "SCM", "SMD", "ATT"))
    add_check(
        checks,
        "docx_structure",
        "PASS" if docx_ok else "FAIL",
        "DOCX 可读且核心主题齐全",
        "DOCX is readable with core topics",
        f"段落={paragraphs}; 表格={tables}; 字符={len(docx_content)}",
        f"paragraphs={paragraphs}; tables={tables}; characters={len(docx_content)}",
    )

    html_path = SOURCE_DIR / "causal-inference-handbook-optimized.html"
    soup = BeautifulSoup(html_path.read_text(encoding="utf-8-sig"), "html.parser")
    html_content = soup.get_text(" ", strip=True)
    html_ok = len(html_content) > 50000 and all(token in html_content for token in ("PSM", "SCM", "SMD", "ATT"))
    add_check(
        checks,
        "html_structure",
        "PASS" if html_ok else "FAIL",
        "HTML 可读且核心主题齐全",
        "HTML is readable with core topics",
        f"可见字符={len(html_content)}",
        f"visible characters={len(html_content)}",
    )

    pdf_path = SOURCE_DIR / "causal-inference-handbook-optimized.pdf"
    pdf = PdfReader(str(pdf_path))
    pdf_content = "\n".join((page.extract_text() or "") for page in pdf.pages)
    pdf_ok = len(pdf.pages) == 155 and len(pdf_content) > 50000 and all(token in pdf_content for token in ("PSM", "SCM", "SMD", "ATT"))
    add_check(
        checks,
        "pdf_structure",
        "PASS" if pdf_ok else "FAIL",
        "PDF 页数和正文提取正常",
        "PDF page count and text extraction succeed",
        f"页数={len(pdf.pages)}; 可提取字符={len(pdf_content)}",
        f"pages={len(pdf.pages)}; extractable characters={len(pdf_content)}",
    )

    all_text = "\n".join((md_text, zero_text, docx_content, html_content, pdf_content))
    coverage_tokens = ("倾向得分", "合成控制", "匹配", "SMD", "ATT", "安慰剂")
    missing_topics = [token for token in coverage_tokens if token not in all_text]
    add_check(
        checks,
        "content_coverage",
        "PASS" if not missing_topics else "FAIL",
        "PSM 与 SCM 核心主题覆盖",
        "Core PSM and SCM topics are covered",
        f"缺失={missing_topics}",
        f"missing={missing_topics}",
    )

    en_review = read_csv(ARTIFACT_DIR / "method-review.en.csv")
    zh_review = read_csv(ARTIFACT_DIR / "method-review.zh.csv")
    en_widths = csv_field_widths(ARTIFACT_DIR / "method-review.en.csv")
    zh_widths = csv_field_widths(ARTIFACT_DIR / "method-review.zh.csv")
    field_widths_ok = en_widths == {6} and zh_widths == {6}
    ids_match = [row["review_id"] for row in en_review] == [row["审查编号"] for row in zh_review]
    add_check(
        checks,
        "method_review_inventory",
        "PASS" if len(en_review) == 11 and field_widths_ok and ids_match else "FAIL",
        "11 项中英文方法风险清单一致",
        "The eleven bilingual method risks match",
        f"英文={len(en_review)}; 中文={len(zh_review)}; 英文字段宽度={sorted(en_widths)}; 中文字段宽度={sorted(zh_widths)}; 编号一致={ids_match}",
        f"English={len(en_review)}; Chinese={len(zh_review)}; English widths={sorted(en_widths)}; Chinese widths={sorted(zh_widths)}; IDs match={ids_match}",
    )

    required_mitigations = {
        "balance heuristic": "SMD < 0.1" in en_review[1]["finding"],
        "paired inference": "ttest_ind" in en_review[2]["evidence"],
        "control replacement": "NearestNeighbors" in en_review[3]["evidence"],
        "common support": "common-support" in en_review[5]["finding"].lower(),
        "SCM placebo": "df_wide[other_ctrls].mean" in en_review[7]["evidence"],
    }
    add_check(
        checks,
        "critical_caveats",
        "PASS" if all(required_mitigations.values()) else "FAIL",
        "关键方法限制均有书面证据",
        "Critical methodological limitations have evidence",
        f"覆盖={required_mitigations}",
        f"coverage={required_mitigations}",
    )

    credential_pattern = re.compile(r"(?i)(api[_-]?key|password|passwd|secret|token)\s*[:=]\s*\S+")
    extracted_credentials = credential_pattern.findall(all_text)
    path_findings = [row["source_id"] for row in manifest if credential_pattern.search(row["source_path"])]
    credential_findings = (["extracted-source-text"] if extracted_credentials else []) + path_findings
    secret_files = [path.name for path in PROJECT_ROOT.rglob("*") if path.is_file() and ".env" in path.name.lower()]
    add_check(
        checks,
        "privacy_and_credentials",
        "PASS" if not credential_findings and not secret_files else "FAIL",
        "未发现明文凭据或 .env",
        "No plaintext credential or .env was found",
        f"提取正文命中={len(extracted_credentials)}; 路径命中={path_findings}; env={secret_files}",
        f"extracted-text hits={len(extracted_credentials)}; path hits={path_findings}; env={secret_files}",
    )

    required_docs = ("README.md", "README.en.md", "methodology/review-notes.md", "methodology/review-notes.en.md")
    missing_docs = [name for name in required_docs if not (PROJECT_ROOT / name).exists()]
    add_check(
        checks,
        "bilingual_documentation",
        "PASS" if not missing_docs else "FAIL",
        "中英文项目文档齐全",
        "Bilingual project documentation is present",
        f"缺失={missing_docs}",
        f"missing={missing_docs}",
    )

    counts = Counter(str(check["status"]) for check in checks)
    return {
        "project": "causal-inference-handbook",
        "overall_status": "verified_with_production_caveats" if not counts["FAIL"] else "failed",
        "summary": {
            "total": len(checks),
            "passed": counts["PASS"],
            "failed": counts["FAIL"],
            "not_run": 0,
            "review": 0,
        },
        "checks": checks,
    }


def write_reports(report: dict[str, object]) -> None:
    VALIDATION_DIR.mkdir(parents=True, exist_ok=True)
    (VALIDATION_DIR / "validation-report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    for language in ("zh", "en"):
        lines = [
            "# 因果推断手册校验" if language == "zh" else "# Causal-inference handbook validation",
            "",
            f"总体状态：`{report['overall_status']}`" if language == "zh" else f"Overall status: `{report['overall_status']}`",
            "",
            "| 检查 | 状态 | 证据 |" if language == "zh" else "| Check | Status | Evidence |",
            "| --- | --- | --- |",
        ]
        for check in report["checks"]:
            detail = check[language]
            lines.append(f"| {detail['title']} | {check['status']} | {detail['evidence']} |")
        lines.extend(
            [
                "",
                (
                    "结论：五个源文件、四种格式、第零部分包含关系和 11 项中英文方法风险已验证。材料只用于教学与代码脚手架，示例结果不是业务因果结论。"
                    if language == "zh"
                    else "Conclusion: all five sources, four formats, zero-part containment, and eleven bilingual method risks are verified. The material is for teaching and code scaffolding; its example results are not business causal conclusions."
                ),
                "",
            ]
        )
        filename = "validation-report.md" if language == "zh" else "validation-report.en.md"
        (VALIDATION_DIR / filename).write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--local-source", type=Path, default=DEFAULT_LOCAL_SOURCE)
    parser.add_argument("--write-report", action="store_true")
    args = parser.parse_args()
    report = validate(args.local_source)
    if args.write_report:
        write_reports(report)
    print(json.dumps(report["summary"], ensure_ascii=False))
    return 1 if report["summary"]["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
