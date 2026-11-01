---
name: historical-figure-video-pipeline
description: Build complete vertical historical figure narration videos from a named人物 or existing story folder. Use this skill whenever the user wants historical人物短视频, 历史人物一生, 分镜图, SeeDance/Seedance图生视频, Huya Art API生成, 首尾帧/实际末帧链式生成, 标题字幕BGM后期拼接, or wants to turn historical story/images into a final 9:16 video. This skill should trigger even if the user only says “跑刘备/曹操/诸葛亮” or “做一条历史人物视频”.
---

# Historical Figure Video Pipeline

Use this skill to produce a complete historical figure short-video package:

```text
人物 -> 情节文案 -> 分镜图 JSON prompt -> 分镜图图片 -> 口播视频任务 -> 实际末帧链式图生视频 -> 标题/字幕/BGM后期 -> QA -> 成片
```

The workflow was distilled from the Zhuge Liang, Sun Quan, Liu Bei, and Cao Cao experiments in `C:\Users\tiany\Desktop\历史人物测试`.

## When To Use

Use this skill when the user asks for any of these:

- Create a historical figure narration video.
- Generate story and storyboard prompts for a historical人物.
- Use Huya Art API, Seedance, SeeDance, or image-to-video for historical content.
- Use first/last frame or actual-last-frame chaining.
- Fix black bars, black frames, stiff transitions, title/subtitle layout, BGM continuity, or mouth-sync problems in historical videos.
- Package a reusable pipeline for historical figure videos.

Do not use this skill for product-selling UGC videos unless the user explicitly says they are using historical人物 only as a test case. Product videos need stricter product consistency and claim-safety rules.

## Required Environment

- Windows PowerShell is the assumed shell.
- `python` must be available.
- `ffmpeg` and `ffprobe` must be available on PATH.
- For Huya Art API generation, the current shell must have:

```powershell
$env:HUYA_ART_API_KEY='AI-...'
```

Never print or persist the user's API key in files. Set it only in the active command when needed.

## Folder Contract

For a task named `曹操`, create or reuse:

```text
<project-root>/曹操_图片/
├── 曹操_情节.md
├── huya_image_tasks.json
├── story_video_plan_v1.json
├── huya_video_tasks_v1.json
├── videos_chain_v2_huya/
├── chain_v2_frames/
├── final_cut_chain_v2/
└── huya_*_state.json / huya_*_log.jsonl
```

Use names ending in `_01`, `_02`, etc. for storyboard images and video segments. Prefer `任务_情节_顺序` style:

```text
曹操_情节_01.png
曹操_情节_02.png
曹操_视频_01_chain_v2.mp4
曹操_实际末帧_01.png
```

Keep each new experiment in a new output folder or suffix. Do not overwrite prior successful outputs unless the user explicitly asks.

## Core Workflow

### 1. Build The Story

Create `<人物>_图片/<人物>_情节.md`.

Write the story in normal Chinese, not JSON. Cover the full life arc, but keep it short enough for video.

Recommended structure:

```markdown
# 曹操 传奇的一生

## 情节

1. 青年曹操看见乱世将起...
2. 起兵后的曹操...
```

For historical accuracy:

- Use cautious wording for disputed ages/events.
- Do not invent facts.
- Prefer 5 to 8 visual stages for a short video.
- Historical jumps across decades are acceptable, but note they reduce one-shot continuity.

### 2. Build Storyboard Image Prompts

Create `huya_image_tasks.json` or equivalent.

Each image prompt must describe:

- Same figure identity and historical period.
- Age-stage appearance.
- Clothing, hair, props, environment, mood.
- Chinese ancient historical documentary style.
- No modern text, no watermark, no subtitles.

Use `scripts/generate_huya_story_media.py --mode images` when using Huya image generation.

### 3. Design Voiceover Before Video Generation

Do not generate video prompts before locking the voiceover.

For each segment:

- Write the exact Chinese voiceover text.
- Estimate duration from text length, punctuation, and required pauses.
- Do not force all segments to 5 seconds.
- Prefer slightly longer clips over clipped narration.

Practical estimate:

```text
duration_seconds = ceil(chinese_chars / 4.0 + punctuation_pauses + 1.5)
minimum 8 seconds for narration clips
```

### 4. Build Video Plan

Create `story_video_plan_v1.json`.

Minimum segment fields:

```json
{
  "segment_id": "曹操_视频_01_v1",
  "client_business_id": "caocao-v1-seg-01",
  "first_frame_file": "曹操_情节_01.png",
  "last_frame_file": "曹操_情节_02.png",
  "output_file": "曹操_视频_01_v1.mp4",
  "duration": 9,
  "voiceover_cn": "曹操的起点，不只是野心。",
  "visual_goal": "从洛阳动荡街巷自然推进到军营起兵。"
}
```

### 5. Choose Continuity Mode

Use actual-last-frame chaining by default when the user complains about hard transitions, wants 一镜到底感, or plans to reuse the workflow for UGC/product videos.

Chained workflow:

```text
segment 1: storyboard 01 -> storyboard 02
extract actual last frame from segment 1
segment 2: actual last frame 01 -> storyboard 03
extract actual last frame from segment 2
```

This is slower because video generation becomes sequential. Parallelism is still useful for image generation, prompt review, BGM selection, subtitle prep, and QA.

Use planned storyboard pair generation only for fast drafts:

```text
segment 1: storyboard 01 -> storyboard 02
segment 2: storyboard 02 -> storyboard 03
```

### 6. Video Prompt Rules

Each video prompt should explicitly include:

- Vertical 9:16 historical narration video.
- First/last frame transition relationship.
- Same person continuity.
- Exact voiceover text.
- Natural Chinese adult male voice unless user asks otherwise.
- Mouth movement synced with narration.
- Slow camera motion.
- No clip-level BGM.
- No subtitles/title/watermark in generated frames.
- No black screen, flash, transition effect, fade in, fade out.
- Stable final 0.3 to 0.5 seconds for chaining.

Use this pattern:

```text
制作一段中国历史人物口播短视频，竖屏9:16，真实电影纪录片质感。
本段第一帧来自上一段视频的真实末帧，必须像同一镜头继续拍摄，不要重新开场。
使用首尾帧模式，但不要做闪白、黑场、跳切、转场特效、淡入淡出。
镜头运动要慢，优先使用轻微推近、横移、人物自然转身或环境运动来连接首尾帧。
人物身份保持为同一个[人物]，脸型、服饰质感、时代背景、色调连续。
本段视觉目标：[visual_goal]
必须生成清晰自然的中文成年男声口播，并让人物口型和口播同步。
完整覆盖这段文案：[voiceover_cn]
口播语速偏慢，句间有停顿，不要抢话，不要在结尾截断。
不要生成背景音乐，不要配乐，不要鼓点，不要歌声，只保留轻微环境声和清晰人声。
不要字幕，不要标题，不要水印。结尾保持画面稳定0.5秒。
```

### 7. Generate Videos

For normal storyboard-pair generation:

```powershell
$env:HUYA_ART_API_KEY='AI-...'
python scripts\generate_huya_story_media.py --mode videos --config "<人物>_图片\huya_video_tasks_v1.json" --max-wait-seconds 3600
```

For actual-last-frame chaining:

```powershell
$env:HUYA_ART_API_KEY='AI-...'
python scripts\generate_huya_chained_story_videos.py --plan "<人物>_图片\story_video_plan_v1.json" --max-wait-seconds 3600
```

If a submitted task gets stuck or the local process dies after task submission, recover without resubmitting:

```powershell
$env:HUYA_ART_API_KEY='AI-...'
python scripts\resume_huya_chained_task.py --base-dir "<人物>_图片" --business-id "<business-id>" --max-wait-seconds 3600
```

### 8. Render Final Video

Post-production owns:

- Title.
- Subtitles.
- BGM.
- Final crop/fill.
- QA frames.

Do not ask the video model to render title or subtitles.

Render rules:

- Use hard `concat`.
- Do not use `xfade`, `fadeblack`, `fade`, `pad`, black cards, or audio `acrossfade`.
- Source clips may be 720x1254. Final must use crop-fill:

```text
scale=720:1280:force_original_aspect_ratio=increase,crop=720:1280,setsar=1
```

Recommended subtitle style:

- Title: white, bold, black outline, large, top third.
- Subtitle: yellow, bold, black outline, center-lower safe area.
- Max two subtitle lines per page.
- Split long voiceover into caption pages.

Use one continuous low-volume BGM in post. Pick a low/mid-energy section and fade out over the final 3 to 5 seconds.

### 9. QA Before Delivery

Always run:

```powershell
ffprobe -v error -show_entries stream=codec_type,codec_name,width,height,sample_aspect_ratio,display_aspect_ratio -show_entries format=duration,size,bit_rate -of json "<final.mp4>"
ffmpeg -hide_banner -i "<final.mp4>" -vf blackdetect=d=0.05:pix_th=0.02 -an -f null - 2>&1 | Select-String 'black'
```

Extract representative frames:

```powershell
ffmpeg -y -ss 0.2 -i "<final.mp4>" -frames:v 1 "<final_dir>\frame_check_00s.png"
ffmpeg -y -ss <middle> -i "<final.mp4>" -frames:v 1 "<final_dir>\frame_check_mid.png"
ffmpeg -y -ss <end> -i "<final.mp4>" -frames:v 1 "<final_dir>\frame_check_end.png"
```

Inspect frames visually. Technical checks do not catch lip-sync quality, narration completeness, or visual taste.

## Known Failure Modes

- Segment transitions feel stiff when each segment starts from a planned storyboard instead of the actual previous output.
- Per-clip BGM makes every segment feel like a new video.
- Post-only TTS cannot match mouth movement unless a dedicated lip-sync step is added.
- Long voiceover gets clipped if duration is forced too short.
- Generated text in video frames is unstable; keep text for post-production.
- `pad` or fade transitions can create black bars/black frames.
- On Windows Chinese paths, avoid `subprocess.run(..., capture_output=True, text=True)` for ffmpeg commands; use binary capture or redirect to `DEVNULL`.
- Huya/Seedance tasks may remain `running` for a long time; preserve task IDs and recover rather than resubmit.

## Bundled Resources

Read these references when needed:

- `references/workflow.md`: detailed pipeline and file contracts.
- `references/prompt_rules.md`: prompt patterns for story/image/video.
- `references/qa_checklist.md`: final delivery checks.
- `references/cao_cao_chain_result.md`: actual-last-frame experiment summary.

Use these scripts as starting points:

- `scripts/generate_huya_story_media.py`
- `scripts/generate_huya_chained_story_videos.py`
- `scripts/resume_huya_chained_task.py`
- `scripts/render_caocao_chain_v2_final.py` as a renderer template to generalize per人物.

## Final Response Contract

When delivering a video, include:

- Final video path.
- Story/image/video task folder path.
- Whether actual-last-frame chaining was used.
- Model(s) used.
- Duration, resolution, aspect ratio.
- Black frame check result.
- Any remaining subjective risks: lip sync, generated voice quality, visual continuity, BGM taste.
