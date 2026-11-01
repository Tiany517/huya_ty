# Historical Figure Video Workflow

## Pipeline

1. Create `<人物>_图片`.
2. Write `<人物>_情节.md`.
3. Write `huya_image_tasks.json`.
4. Generate storyboard images named `<人物>_情节_01.png`, `<人物>_情节_02.png`.
5. Write `story_video_plan_v1.json`.
6. Generate videos.
7. If continuity is important, use actual-last-frame chaining.
8. Render final video with title, subtitles, and unified BGM.
9. Run QA and write a run summary.

## File Naming

Use predictable names:

```text
<人物>_情节.md
<人物>_情节_01.png
<人物>_视频_01_chain_v2.mp4
<人物>_实际末帧_01.png
<人物>_成片_实际末帧链式版.mp4
```

## Continuity Modes

Fast draft:

```text
segment 1: storyboard 01 -> storyboard 02
segment 2: storyboard 02 -> storyboard 03
```

High continuity:

```text
segment 1: storyboard 01 -> storyboard 02
extract actual last frame from segment 1
segment 2: actual last frame 01 -> storyboard 03
```

Use high continuity for final samples or when the user complains about stiff transitions.

## Model Priority

Video model priority:

1. `seedance-2.0-fast-cn`
2. `seedance-2.0-cn`
3. `happyhorse-1.0`

Image model priority should follow the user's current Huya platform availability. Check model support before assuming exact provider/model IDs if the platform has changed.

## Post-Production

Final assembly should:

- Use crop-fill to 720x1280.
- Use hard concat only.
- Add title and subtitles in ASS.
- Add one continuous BGM track after generation.
- Avoid clip-level BGM in video prompts.

Do not use black fades to hide bad transitions. If a transition is poor, fix the generation strategy or trim unstable edge frames.
