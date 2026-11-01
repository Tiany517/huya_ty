# Prompt Rules

## Story

Write in normal Chinese. Keep it useful for video, not encyclopedic.

Each story beat should contain:

- Time/life stage.
- One clear event.
- Why the event matters visually or emotionally.

## Image Prompts

Each storyboard prompt should include:

- Historical figure identity.
- Approximate age and appearance.
- Clothing, hairstyle, props.
- Setting and historical atmosphere.
- Emotion and posture.
- Documentary realism.

Avoid:

- Modern objects.
- Generated text.
- Watermarks.
- Overly abstract labels.

## Video Prompts

Each video prompt should explicitly say:

```text
竖屏9:16，真实电影纪录片质感。
首尾帧自然连接。
人物身份、服饰、色调连续。
清晰自然的中文成年男声口播，口型同步。
完整覆盖文案：[voiceover_cn]
不要生成背景音乐、字幕、标题、水印。
不要黑场、闪白、转场特效、淡入淡出。
结尾保持稳定0.3-0.5秒。
```

For chained segments after segment 1, include:

```text
本段第一帧来自上一段视频的真实末帧，必须像同一镜头继续拍摄，不要重新开场。
```

## Voiceover Timing

Do not set all segments to the same duration.

Estimate duration from:

- Chinese character count.
- Number of punctuation pauses.
- Emotional pause needed.
- Whether the clip needs visual transition time.

If the model tends to cut narration, add 1 to 2 seconds.

## BGM

Prompt should forbid per-clip BGM:

```text
不要生成背景音乐，不要配乐，不要鼓点，不要歌声，只保留轻微环境声和清晰人声。
```

Add BGM in post-production instead.
