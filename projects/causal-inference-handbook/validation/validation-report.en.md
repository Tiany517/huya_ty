# Causal-inference handbook validation

Overall status: `verified_with_production_caveats`

| Check | Status | Evidence |
| --- | --- | --- |
| All five source sizes and SHA-256 values match | PASS | 5 entries; repository mismatches=[] |
| Repository copies trace to local source files by hash | PASS | local hash mismatches=[] |
| Markdown master structure is readable | PASS | lines=2025; code blocks=74; fence markers=148; paired=True; characters=56721 |
| The zero-part deep dive is fully contained in optimized Markdown | PASS | normalized containment=True |
| DOCX is readable with core topics | PASS | paragraphs=871; tables=4; characters=31016 |
| HTML is readable with core topics | PASS | visible characters=53107 |
| PDF page count and text extraction succeed | PASS | pages=155; extractable characters=55958 |
| Core PSM and SCM topics are covered | PASS | missing=[] |
| The eleven bilingual method risks match | PASS | English=11; Chinese=11; English widths=[6]; Chinese widths=[6]; IDs match=True |
| Critical methodological limitations have evidence | PASS | coverage={'balance heuristic': True, 'paired inference': True, 'control replacement': True, 'common support': True, 'SCM placebo': True} |
| No plaintext credential or .env was found | PASS | extracted-text hits=0; path hits=[]; env=[] |
| Bilingual project documentation is present | PASS | missing=[] |

Conclusion: all five sources, four formats, zero-part containment, and eleven bilingual method risks are verified. The material is for teaching and code scaffolding; its example results are not business causal conclusions.
