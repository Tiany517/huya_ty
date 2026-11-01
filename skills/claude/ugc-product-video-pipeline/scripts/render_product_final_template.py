"""Generic product UGC final-cut renderer.

Config-driven. No hardcoded product, market, or historical names.
Reads a JSON render config and produces a 9:16 hard-concat final cut with
ASS-burned title + subtitles and an optional single-track BGM.

Usage:
    python render_product_final_template.py --config render_config.json

Render config schema (render_config.json):

{
  "title": "厨房用水先过滤",
  "aspect": "9:16",                       // optional, default "9:16" -> 720x1280
  "clips": ["seg_01.mp4", "seg_02.mp4"],  // ordered approved segment paths
  "subtitle_cues": [                      // one entry per clip, in order
    {
      "text": "整段口播字幕文本",            // auto-paginated; use \\N for manual line break
      "start_offset": 0.35,               // optional, seconds after clip start, default 0.35
      "end_offset": -0.25                 // optional, seconds before clip end, default -0.25
    }
  ],
  "subtitle_style": {                     // all optional, sensible defaults
    "title_fontsize": 68,
    "caption_fontsize": 48,
    "caption_color": "&H0000D7FF",        // ASS color, yellow default
    "title_color": "&H00FFFFFF",          // white
    "outline_color": "&H00000000",        // black
    "caption_margin_v": 188,
    "title_margin_v": 138,
    "caption_max_chars_per_page": 18,
    "caption_wrap_width": 9,
    "fontname": "Microsoft YaHei"
  },
  "video_eq": "contrast=1.02:brightness=-0.01:saturation=1.03",  // optional, "" to skip
  "voice_volume": 1.05,                   // optional, default 1.0
  "bgm": {                                // optional; omit or set path null to skip BGM
    "path": "bgm/track.mp3",
    "volume": 0.052,
    "start_at": 8.0,
    "fade_in": 1.2,
    "fade_out_duration": 4.5
  },
  "output": "final_cut/产品_成片.mp4"
}
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import List, Tuple


def run(cmd: List[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=True, capture_output=True, text=True)


def ffprobe_duration(path: Path) -> float:
    result = run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(path),
        ]
    )
    return float(result.stdout.strip())


def ass_time(seconds: float) -> str:
    total_cs = int(round(seconds * 100))
    hours = total_cs // 360000
    minutes = (total_cs % 360000) // 6000
    secs = (total_cs % 6000) // 100
    cs = total_cs % 100
    return f"{hours}:{minutes:02d}:{secs:02d}.{cs:02d}"


def wrap_cn(text: str, width: int, max_lines: int) -> str:
    """Wrap a single subtitle page into at most max_lines using \\N."""
    if "\\N" in text:
        return text
    chunks: List[str] = []
    remaining = text
    for _ in range(max_lines):
        if len(remaining) <= width:
            chunks.append(remaining)
            remaining = ""
            break
        pivot = width
        punctuation = [i for i, ch in enumerate(remaining[: width + 3]) if ch in "，。；、！？,.!?;"]
        if punctuation:
            pivot = punctuation[-1] + 1
        chunks.append(remaining[:pivot])
        remaining = remaining[pivot:]
    return "\\N".join(chunks[:max_lines])


def split_caption_pages(text: str, max_chars: int) -> List[str]:
    """Split a long cue into pages by punctuation, each <= max_chars."""
    clauses: List[str] = []
    current = ""
    for ch in text:
        current += ch
        if ch in "，。；、！？,.!?;":
            clauses.append(current)
            current = ""
    if current:
        clauses.append(current)

    pages: List[str] = []
    current = ""
    for clause in clauses:
        if current and len(current) + len(clause) > max_chars:
            pages.append(current)
            current = clause
        else:
            current += clause
    if current:
        pages.append(current)
    return pages or [text]


def paginate_cue(text: str, max_chars: int, wrap_width: int) -> List[str]:
    """Return a list of ASS page strings (each may contain \\N)."""
    text = text.replace("\n", "")
    if "\\N" in text:
        return [text]
    return [wrap_cn(page, wrap_width, 2) for page in split_caption_pages(text, max_chars)]


def build_ass(
    title: str,
    cues: List[Tuple[float, float, str]],
    total_duration: float,
    style: dict,
) -> str:
    fontname = style.get("fontname", "Microsoft YaHei")
    header = f"""[Script Info]
Title: Product UGC Final Cut
ScriptType: v4.00+
WrapStyle: 2
PlayResX: 720
PlayResY: 1280
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name,Fontname,Fontsize,PrimaryColour,SecondaryColour,OutlineColour,BackColour,Bold,Italic,Underline,StrikeOut,ScaleX,ScaleY,Spacing,Angle,BorderStyle,Outline,Shadow,Alignment,MarginL,MarginR,MarginV,Encoding
Style: Title,{fontname},{style['title_fontsize']},{style['title_color']},{style['title_color']},{style['outline_color']},&H00000000,-1,0,0,0,100,100,1,0,1,6,1,8,24,24,{style['title_margin_v']},1
Style: Caption,{fontname},{style['caption_fontsize']},{style['caption_color']},{style['caption_color']},{style['outline_color']},&H00000000,-1,0,0,0,100,100,1,0,1,4.8,1.2,2,54,54,{style['caption_margin_v']},1

[Events]
Format: Layer,Start,End,Style,Name,MarginL,MarginR,MarginV,Effect,Text
"""
    events = [f"Dialogue: 0,{ass_time(0.0)},{ass_time(total_duration)},Title,,0,0,0,,{title}"]
    for start, end, text in cues:
        events.append(
            f"Dialogue: 0,{ass_time(start)},{ass_time(end)},Caption,,0,0,0,,{text}"
        )
    return header + "\n".join(events) + "\n"


def build_filter(
    n_clips: int,
    durations: List[float],
    total_duration: float,
    has_bgm: bool,
    bgm_index: int,
    ass_escaped: str,
    video_eq: str,
    voice_volume: float,
) -> str:
    parts: List[str] = []
    for i in range(n_clips):
        eq = f",{video_eq}" if video_eq else ""
        parts.append(
            f"[{i}:v]fps=30,scale=720:1280:force_original_aspect_ratio=increase,"
            f"crop=720:1280,setsar=1{eq},format=yuv420p[v{i}]"
        )
        parts.append(
            f"[{i}:a]aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo,"
            f"acompressor=threshold=-18dB:ratio=2.0:attack=15:release=200,volume={voice_volume}[a{i}]"
        )
    concat_inputs = "".join(f"[v{i}][a{i}]" for i in range(n_clips))
    parts.append(f"{concat_inputs}concat=n={n_clips}:v=1:a=1[vcat][voice]")

    if has_bgm:
        bgm_fade_start = max(total_duration - 4.5, 0)
        parts.append(
            f"[{bgm_index}:a]atrim=start=0:duration={total_duration},asetpts=PTS-STARTPTS,"
            f"aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo,"
            f"volume=0.052,afade=t=in:st=0:d=1.2,afade=t=out:st={bgm_fade_start}:d=4.5[bgm]"
        )
        parts.append("[voice][bgm]amix=inputs=2:duration=first:dropout_transition=0[aout]")
    else:
        parts.append("[voice]anull[aout]")

    parts.append(f"[vcat]ass='{ass_escaped}',format=yuv420p[vout]")
    return ";".join(parts)


def load_config(config_path: Path) -> dict:
    return json.loads(config_path.read_text(encoding="utf-8"))


def resolve_clip_paths(config: dict, base_dir: Path) -> List[Path]:
    clips = []
    for entry in config["clips"]:
        p = Path(entry)
        if not p.is_absolute():
            p = base_dir / p
        if not p.exists():
            raise FileNotFoundError(f"Missing approved video clip: {p}")
        clips.append(p)
    return clips


def build_cues(
    config: dict,
    clips: List[Path],
    durations: List[float],
) -> List[Tuple[float, float, str]]:
    style = config.get("subtitle_style", {})
    max_chars = style.get("caption_max_chars_per_page", 18)
    wrap_width = style.get("caption_wrap_width", 9)
    cues = []
    starts = [0.0]
    for i in range(1, len(durations)):
        starts.append(starts[-1] + durations[i - 1])

    for idx, clip_duration in enumerate(durations):
        cue = config["subtitle_cues"][idx] if idx < len(config.get("subtitle_cues", [])) else {}
        text = cue.get("text", "")
        start_offset = cue.get("start_offset", 0.35)
        end_offset = cue.get("end_offset", -0.25)
        seg_start = starts[idx] + start_offset
        seg_end = starts[idx] + clip_duration + end_offset
        if seg_end <= seg_start:
            seg_end = seg_start + 1.0
        pages = paginate_cue(text, max_chars, wrap_width)
        page_duration = max((seg_end - seg_start) / len(pages), 1.0)
        for page_index, page in enumerate(pages):
            page_start = seg_start + page_index * page_duration
            page_end = min(seg_start + (page_index + 1) * page_duration, seg_end)
            cues.append((page_start, page_end, page))
    return cues


def render(config_path: Path) -> Path:
    config = load_config(config_path)
    base_dir = config_path.parent
    output_path = Path(config["output"])
    if not output_path.is_absolute():
        output_path = base_dir / output_path
    output_path.parent.mkdir(parents=True, exist_ok=True)

    clips = resolve_clip_paths(config, base_dir)
    durations = [ffprobe_duration(p) for p in clips]
    total_duration = sum(durations)

    style = {
        "title_fontsize": 68,
        "caption_fontsize": 48,
        "caption_color": "&H0000D7FF",
        "title_color": "&H00FFFFFF",
        "outline_color": "&H00000000",
        "caption_margin_v": 188,
        "title_margin_v": 138,
        "caption_max_chars_per_page": 18,
        "caption_wrap_width": 9,
        "fontname": "Microsoft YaHei",
    }
    style.update(config.get("subtitle_style", {}))

    cues = build_cues(config, clips, durations)
    ass_path = output_path.with_suffix(".ass")
    ass_path.write_text(build_ass(config["title"], cues, total_duration, style), encoding="utf-8")

    bgm_cfg = config.get("bgm") or {}
    bgm_path_raw = bgm_cfg.get("path")
    has_bgm = bool(bgm_path_raw)
    bgm_index = len(clips) if has_bgm else -1
    if has_bgm:
        bgm_path = Path(bgm_path_raw)
        if not bgm_path.is_absolute():
            bgm_path = base_dir / bgm_path
        if not bgm_path.exists():
            raise FileNotFoundError(f"Missing BGM file: {bgm_path}")

    ass_escaped = str(ass_path).replace("\\", "\\\\").replace(":", "\\:")
    filter_complex = build_filter(
        n_clips=len(clips),
        durations=durations,
        total_duration=total_duration,
        has_bgm=has_bgm,
        bgm_index=bgm_index,
        ass_escaped=ass_escaped,
        video_eq=config.get("video_eq", ""),
        voice_volume=config.get("voice_volume", 1.0),
    )

    cmd = ["ffmpeg", "-y"]
    for clip in clips:
        cmd.extend(["-i", str(clip)])
    if has_bgm:
        cmd.extend(["-i", str(bgm_path)])
    cmd.extend(
        [
            "-filter_complex",
            filter_complex,
            "-map",
            "[vout]",
            "-map",
            "[aout]",
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-profile:v",
            "high",
            "-level:v",
            "4.0",
            "-preset",
            "medium",
            "-crf",
            "18",
            "-c:a",
            "aac",
            "-b:a",
            "192k",
            "-movflags",
            "+faststart",
            str(output_path),
        ]
    )
    subprocess.run(cmd, check=True)

    packaging_plan = {
        "title": config["title"],
        "strategy": "actual_last_frame_chained_generation_direct_concat",
        "subtitle_style": style,
        "bgm_strategy": "single_track_low_volume_trimmed" if has_bgm else "omitted",
        "bgm_file": bgm_path_raw if has_bgm else None,
        "clips": [str(p) for p in clips],
        "durations": durations,
        "total_duration": total_duration,
        "output": str(output_path),
    }
    output_path.with_name(output_path.stem + "_packaging_plan.json").write_text(
        json.dumps(packaging_plan, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return output_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Generic product UGC final-cut renderer.")
    parser.add_argument("--config", required=True, help="Path to render_config.json")
    args = parser.parse_args()
    out = render(Path(args.config).resolve())
    print(out)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
