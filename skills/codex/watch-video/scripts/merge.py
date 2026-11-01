#!/usr/bin/env python3
"""Merge segment notes into a single report.

Usage:
    python merge.py <manifest.json> [--notes-dir DIR] [--out PATH]

Looks for markdown notes files next to the manifest or in --notes-dir.
Expected naming: <video-stem>-seg01-notes.md, <video-stem>-seg02-notes.md, …
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


def find_notes(manifest_path: Path, notes_dir: Path | None = None) -> list[Path]:
    base = manifest_path.stem.replace(".manifest", "")
    search_dir = notes_dir or manifest_path.parent
    pattern = re.compile(re.escape(base) + r"-seg\d+-notes\.md$")
    files = sorted([p for p in search_dir.glob("*.md") if pattern.search(p.name)])
    return files


def main() -> int:
    ap = argparse.ArgumentParser(
        prog="merge",
        description="Merge segment notes into a single markdown report.",
    )
    ap.add_argument("manifest", help="Path to the manifest JSON from fetch.py")
    ap.add_argument("--notes-dir", type=str, default=None, help="Directory containing segment notes (default: same as manifest)")
    ap.add_argument("--out", type=str, default=None, help="Output file (default: <video-stem>-report.md)")
    args = ap.parse_args()

    manifest_path = Path(args.manifest).expanduser().resolve()
    if not manifest_path.exists():
        raise SystemExit(f"Manifest not found: {manifest_path}")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    notes_dir = Path(args.notes_dir).expanduser().resolve() if args.notes_dir else None
    notes_files = find_notes(manifest_path, notes_dir)

    if not notes_files:
        raise SystemExit(
            f"No segment notes found for '{manifest_path.stem}' in {notes_dir or manifest_path.parent}.\n"
            "Expected files like: *-seg01-notes.md, *-seg02-notes.md, …"
        )

    out_path = Path(args.out).expanduser().resolve() if args.out else manifest_path.with_suffix(".report.md")

    lines: list[str] = []
    lines.append(f"# {manifest.get('title', 'Video Report')}")
    lines.append("")
    lines.append(f"- **Source:** {manifest['source']}")
    if manifest.get("uploader"):
        lines.append(f"- **Uploader:** {manifest['uploader']}")
    lines.append(f"- **Duration:** {manifest.get('duration_formatted', '?')}")
    lines.append("")
    lines.append("---")
    lines.append("")

    for seg in manifest.get("segments", []):
        seg_idx = seg["index"]
        seg_file = next((f for f in notes_files if f"-seg{seg_idx:02d}-" in f.name or f"-seg{seg_idx}-" in f.name), None)
        if seg_file is None:
            lines.append(f"> **Segment {seg_idx:02d}** ({seg['start']} → {seg['end']}) — notes not found.")
            lines.append("")
            continue

        content = seg_file.read_text(encoding="utf-8")
        # Remove the top-level H1 if present to avoid duplicate titles
        content = re.sub(r"^# .+\n+", "", content, count=1)
        lines.append(f"## Segment {seg_idx:02d}: {seg['start']} → {seg['end']}")
        lines.append("")
        lines.append(content.strip())
        lines.append("")
        lines.append("---")
        lines.append("")

    out_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"[merge] wrote {out_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
