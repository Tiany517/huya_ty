# Douyin Playwright Top 10 Video-Analysis Examples

## Objective

This package archives public video-analysis examples produced by the `douyin-playwright` skill. It lets Codex on the new computer inspect the historical workbook format and compare a reinstalled or repaired skill against real deliverables.

The workbooks contain public Douyin page content, not internal Huya business data or current platform rankings. Collection and analysis dates are 2026-06-25 through 2026-06-26.

## Retained Content

- Four original XLSX files containing 40 Top 10 video records in total:
  - A search for the keyword `世界杯` (World Cup).
  - The public creator `小钟Johnny`.
  - The public creator `小Lin说`.
  - The public creator `黄士铨看世界`.
- Each workbook generally contains creator/search overview, Top 10 video data, and AI script-analysis sheets.
- Separate Chinese and English documentation, machine-readable indexes, SHA-256 source records, and a repeatable verifier.

## Definitions and Limitations

1. Values are page snapshots at collection time. Likes, comments, favorites, and shares change over time and are not current metrics.
2. Some engagement values are stored as Chinese formatted strings such as `27.2万`, while others are numeric. Parse and normalize them before cross-workbook calculations.
3. The AI script-analysis sheets are subjective summaries of public titles, visuals, copy, or comments. They are suggestions, not verified platform fields, and no independent human review is retained.
4. The four workbooks contain no formulas and no formula errors. They are static snapshots, not refreshable models.
5. Search screenshots, video-detail screenshots, temporary JSON, `.superpowers` diffs, caches, and individualized generation scripts are excluded. Generic generators remain under `skills/codex/douyin-playwright/`; the individualized scripts use machine-specific absolute paths and missing intermediate inputs and have low rerun value.

## Use on the New Computer

1. Read `skills/codex/douyin-playwright/SKILL.md` and `skill/SKILL.md` first.
2. Treat these XLSX files as historical delivery-format examples, not current metrics.
3. After new collection, compare sheet structure, ranking method, field completeness, and AI-analysis layout instead of copying old conclusions verbatim.
4. Run `python scripts/verify_examples.py` to verify hashes, workbook structure, formulas, and error cells.

## GitHub Path Map

| GitHub path | Contents |
| --- | --- |
| `projects/douyin-playwright-video-analysis/README.md` | Chinese project guide and path map |
| `projects/douyin-playwright-video-analysis/README.en.md` | English project guide and path map |
| `projects/douyin-playwright-video-analysis/artifacts/zh/` | Four original Chinese XLSX snapshots |
| `projects/douyin-playwright-video-analysis/artifacts/summary.zh.csv` | Chinese machine-readable file and result summary |
| `projects/douyin-playwright-video-analysis/artifacts/source-manifest.zh.csv` | Chinese source file, byte, and SHA-256 manifest |
| `projects/douyin-playwright-video-analysis/artifacts/summary.en.csv` | English machine-readable file and result summary |
| `projects/douyin-playwright-video-analysis/artifacts/source-manifest.en.csv` | English source file, byte, and SHA-256 manifest |
| `projects/douyin-playwright-video-analysis/scripts/verify_examples.py` | Workbook integrity and structure verifier |
| `projects/douyin-playwright-video-analysis/validation/validation-report.json` | Recorded verification result |

All paths are relative to the GitHub repository root. Chinese guide: `README.md`.
