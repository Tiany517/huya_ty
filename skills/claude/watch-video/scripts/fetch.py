#!/usr/bin/env python3
"""Pre-fetch a video outside Claude Code to avoid spawnSync timeouts.

Usage:
    python fetch.py <url-or-path> [--out-dir DIR] [--segment-minutes N]

This script:
1. Downloads the video via yt-dlp (if a URL) or validates the local path.
2. Probes duration with ffprobe.
3. Prints recommended --start/--end segments for staged analysis.
4. Writes a manifest JSON you can feed into batch processing.

Run this IN A TERMINAL outside Claude Code. yt-dlp downloads can take
minutes to hours; Claude Code's spawnSync limit (~30–60 s) will kill it.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse

SCRIPT_DIR = Path(__file__).parent.resolve()
sys.path.insert(0, str(SCRIPT_DIR))

from download import download, is_url  # noqa: E402
from frames import format_time, get_metadata  # noqa: E402


def segment_plan(duration_seconds: float, segment_minutes: float = 10.0) -> list[dict]:
    """Build a list of {start, end, label} dicts for staged analysis."""
    if duration_seconds <= 0:
        return []
    seg = segment_minutes * 60
    plans = []
    start = 0.0
    idx = 1
    while start < duration_seconds:
        end = min(start + seg, duration_seconds)
        plans.append({
            "index": idx,
            "start_seconds": start,
            "end_seconds": end,
            "start": format_time(start),
            "end": format_time(end),
            "duration_seconds": round(end - start, 1),
        })
        start = end
        idx += 1
    return plans


def main() -> int:
    ap = argparse.ArgumentParser(
        prog="fetch",
        description="Download a video and build a segment plan for staged analysis.",
    )
    ap.add_argument("source", help="Video URL or local file path")
    ap.add_argument("--out-dir", type=str, default=None, help="Output directory (default: current dir)")
    ap.add_argument("--segment-minutes", type=float, default=10.0, help="Segment length in minutes (default: 10)")
    ap.add_argument("--keep-info-json", action="store_true", help="Keep yt-dlp info.json after run")
    args = ap.parse_args()

    out_dir = Path(args.out_dir).expanduser().resolve() if args.out_dir else Path.cwd()
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"[fetch] output directory: {out_dir}", file=sys.stderr)

    # Step 1: download or validate
    print("[fetch] step 1/3: obtain video…", file=sys.stderr)
    work = out_dir / "_fetch_work"
    work.mkdir(parents=True, exist_ok=True)
    result = download(args.source, work / "video")
    video_path = Path(result["video_path"])

    # Move video to a stable name in out_dir if it lives in the temp work dir
    if video_path.parent == (work / "video"):
        stable_name = out_dir / video_path.name
        if stable_name.exists():
            stable_name.unlink()
        video_path.rename(stable_name)
        video_path = stable_name
        result["video_path"] = str(stable_name)

    # Clean up temp work dir unless we need the info.json
    if not args.keep_info_json:
        for f in (work / "video").glob("*"):
            f.unlink()
        (work / "video").rmdir()
        work.rmdir()

    print(f"[fetch] video: {video_path}", file=sys.stderr)

    # Step 2: probe
    print("[fetch] step 2/3: probe metadata…", file=sys.stderr)
    meta = get_metadata(str(video_path))
    duration = meta.get("duration_seconds", 0)
    print(f"[fetch] duration: {format_time(duration)} ({duration:.1f}s)", file=sys.stderr)

    # Step 3: segment plan
    print("[fetch] step 3/3: build segment plan…", file=sys.stderr)
    plans = segment_plan(duration, segment_minutes=args.segment_minutes)

    manifest = {
        "source": args.source,
        "video_path": str(video_path),
        "title": (result.get("info") or {}).get("title") or video_path.stem,
        "uploader": (result.get("info") or {}).get("uploader"),
        "duration_seconds": duration,
        "duration_formatted": format_time(duration),
        "resolution": f"{meta.get('width')}x{meta.get('height')}" if meta.get("width") else None,
        "segment_minutes": args.segment_minutes,
        "segments": plans,
    }

    manifest_path = out_dir / f"{video_path.stem}.manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")

    # Print human-readable summary
    print()
    print("=" * 60)
    print("FETCH COMPLETE")
    print("=" * 60)
    print(f"Video:      {video_path}")
    print(f"Duration:   {manifest['duration_formatted']} ({duration:.1f}s)")
    if manifest['resolution']:
        print(f"Resolution: {manifest['resolution']}")
    print(f"Manifest:   {manifest_path}")
    print()
    print("RECOMMENDED SEGMENTS FOR STAGED ANALYSIS")
    print("-" * 60)
    for seg in plans:
        print(f"  Segment {seg['index']:02d}: {seg['start']} → {seg['end']}  ({seg['duration_seconds']:.0f}s)")
        print(f"              /watch-video \"{video_path}\" --start {seg['start']} --end {seg['end']}")
    print()
    print("NEXT STEPS")
    print("-" * 60)
    print("1. Copy one of the /watch-video commands above into Claude Code.")
    print("2. Run each segment in a separate conversation to avoid the 15-turn limit.")
    print("3. After all segments are done, ask Claude to merge the notes into a PDF.")
    print()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
