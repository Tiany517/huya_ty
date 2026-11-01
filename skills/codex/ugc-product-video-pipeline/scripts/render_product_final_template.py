import json
import subprocess
from pathlib import Path
from typing import List, Tuple


ROOT = Path(r"C:\Users\tiany\Desktop\历史人物测试")
BASE_DIR = ROOT / "曹操_图片"
VIDEOS_DIR = BASE_DIR / "videos_chain_v2_huya"
OUTPUT_DIR = BASE_DIR / "final_cut_chain_v2"
PLAN_PATH = BASE_DIR / "story_video_plan_v1.json"
STATE_PATH = BASE_DIR / "huya_chained_video_tasks_state.json"
ASS_PATH = OUTPUT_DIR / "caocao_chain_v2.ass"
PACKAGING_PLAN_PATH = OUTPUT_DIR / "caocao_chain_v2_packaging_plan.json"
OUTPUT_PATH = OUTPUT_DIR / "曹操_成片_实际末帧链式版.mp4"
BGM_PATH = ROOT / "bgm" / "imperial-china-cinematic.mp3"

TITLE = "曹操 传奇的一生"


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


def wrap_cn(text: str, width: int = 9, max_lines: int = 2) -> str:
    chunks: List[str] = []
    remaining = text
    for _ in range(max_lines):
        if len(remaining) <= width:
            chunks.append(remaining)
            remaining = ""
            break
        pivot = width
        punctuation = [i for i, ch in enumerate(remaining[: width + 3]) if ch in "，。；、"]
        if punctuation:
            pivot = punctuation[-1] + 1
        chunks.append(remaining[:pivot])
        remaining = remaining[pivot:]
    return "\\N".join(chunks[:max_lines])


def split_caption_pages(text: str, max_chars: int = 18) -> List[str]:
    clauses: List[str] = []
    current = ""
    for ch in text:
        current += ch
        if ch in "，。；、":
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


def load_plan() -> dict:
    return json.loads(PLAN_PATH.read_text(encoding="utf-8"))


def load_state() -> dict:
    return json.loads(STATE_PATH.read_text(encoding="utf-8"))


def pick_video_files(segment_count: int) -> List[Path]:
    return [VIDEOS_DIR / f"曹操_视频_{index:02d}_chain_v2.mp4" for index in range(1, segment_count + 1)]


def build_ass(cues: List[Tuple[float, float, str]], total_duration: float) -> str:
    header = """[Script Info]
Title: Cao Cao Chain V2 Final Cut
ScriptType: v4.00+
WrapStyle: 2
PlayResX: 720
PlayResY: 1280
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name,Fontname,Fontsize,PrimaryColour,SecondaryColour,OutlineColour,BackColour,Bold,Italic,Underline,StrikeOut,ScaleX,ScaleY,Spacing,Angle,BorderStyle,Outline,Shadow,Alignment,MarginL,MarginR,MarginV,Encoding
Style: TitleStyle,Microsoft YaHei,72,&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,-1,0,0,0,100,100,1,0,1,5.8,1.6,8,26,26,132,1
Style: CaptionStyle,Microsoft YaHei,42,&H0000D7FF,&H0000D7FF,&H00000000,&H00000000,-1,0,0,0,100,100,1,0,1,4.2,1.1,2,64,64,348,1

[Events]
Format: Layer,Start,End,Style,Name,MarginL,MarginR,MarginV,Effect,Text
"""
    events = [
        f"Dialogue: 0,{ass_time(0.0)},{ass_time(total_duration)},TitleStyle,,0,0,0,,{TITLE}"
    ]
    for start, end, text in cues:
        events.append(
            f"Dialogue: 0,{ass_time(start)},{ass_time(end)},CaptionStyle,,0,0,0,,{wrap_cn(text)}"
        )
    return header + "\n".join(events) + "\n"


def build_filter(durations: List[float], total_duration: float) -> Tuple[str, List[float]]:
    parts: List[str] = []
    starts = [0.0]
    for i, _duration in enumerate(durations):
        parts.append(
            f"[{i}:v]fps=30,scale=720:1280:force_original_aspect_ratio=increase,"
            f"crop=720:1280,setsar=1,"
            f"eq=contrast=1.02:brightness=-0.01:saturation=1.03,"
            f"format=yuv420p[v{i}]"
        )
        parts.append(
            f"[{i}:a]aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo,"
            f"acompressor=threshold=-18dB:ratio=2.0:attack=15:release=200,volume=1.05[a{i}]"
        )
        if i > 0:
            starts.append(starts[-1] + durations[i - 1])

    concat_inputs = "".join(f"[v{i}][a{i}]" for i in range(len(durations)))
    parts.append(f"{concat_inputs}concat=n={len(durations)}:v=1:a=1[vcat][voice]")

    bgm_fade_start = max(total_duration - 4.5, 0)
    parts.append(
        f"[{len(durations)}:a]atrim=start=8:duration={total_duration},asetpts=PTS-STARTPTS,"
        f"aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo,"
        f"volume=0.052,afade=t=in:st=0:d=1.2,afade=t=out:st={bgm_fade_start}:d=4.5[bgm]"
    )
    parts.append("[voice][bgm]amix=inputs=2:duration=first:dropout_transition=0[aout]")

    ass_escaped = str(ASS_PATH).replace("\\", "\\\\").replace(":", "\\:")
    parts.append(f"[vcat]ass='{ass_escaped}',format=yuv420p[vout]")
    return ";".join(parts), starts


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    plan = load_plan()
    state = load_state()
    segments = plan["segments"]
    video_files = pick_video_files(len(segments))
    missing = [str(path) for path in video_files if not path.exists()]
    if missing:
        raise FileNotFoundError(f"缺少视频文件: {missing}")
    if not BGM_PATH.exists():
        raise FileNotFoundError(f"缺少 BGM 文件: {BGM_PATH}")

    durations = [ffprobe_duration(path) for path in video_files]
    total_duration = sum(durations)

    starts = [0.0]
    for i in range(1, len(durations)):
        starts.append(starts[-1] + durations[i - 1])

    cues: List[Tuple[float, float, str]] = []
    for idx, segment in enumerate(segments):
        segment_start = starts[idx] + 0.45
        segment_end = starts[idx] + durations[idx] - 0.35
        pages = split_caption_pages(segment["voiceover_cn"])
        page_duration = max((segment_end - segment_start) / len(pages), 1.0)
        for page_index, page in enumerate(pages):
            start = segment_start + page_index * page_duration
            end = min(segment_start + (page_index + 1) * page_duration, segment_end)
            cues.append((start, end, page))

    ASS_PATH.write_text(build_ass(cues, total_duration), encoding="utf-8")
    filter_complex, render_starts = build_filter(durations, total_duration)
    PACKAGING_PLAN_PATH.write_text(
        json.dumps(
            {
                "title": TITLE,
                "strategy": "actual_last_frame_chained_generation_direct_concat",
                "subtitle_style": {
                    "title_font_size": 72,
                    "caption_font_size": 42,
                    "caption_max_chars_per_page": 18,
                    "caption_wrap_width": 9,
                    "caption_margin_v": 348,
                },
                "bgm_strategy": "single_track_low_volume_trimmed_no_clip_bgm",
                "bgm_file": str(BGM_PATH),
                "bgm_attribution": "Music by Shane Ivers - https://www.silvermansound.com",
                "video_files": [str(path) for path in video_files],
                "durations": durations,
                "segment_starts": render_starts,
                "total_duration": total_duration,
                "chain_state": state,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    cmd = ["ffmpeg", "-y"]
    for path in video_files:
        cmd.extend(["-i", str(path)])
    cmd.extend(["-i", str(BGM_PATH)])
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
            str(OUTPUT_PATH),
        ]
    )
    subprocess.run(cmd, check=True)
    print(OUTPUT_PATH)


if __name__ == "__main__":
    main()
