# Post-Production And QA

## Generation Audio Strategy

Ask the video model for:

- Target-language speech.
- Mouth movement synced to speech.
- Light real environment sound.

Forbid:

- Clip-level BGM.
- Songs.
- Drum hits.
- Restarting music per segment.

Add one continuous BGM track in post.

## Video Assembly

Use hard concat. Avoid:

- `xfade`.
- `fadeblack`.
- `fade`.
- `pad`.
- Black cards.
- Audio `acrossfade` for narration.

For 9:16:

```text
scale=720:1280:force_original_aspect_ratio=increase,crop=720:1280,setsar=1
```

## Title And Subtitles

Default style:

- Title: large white text, black outline, top third.
- Subtitles: yellow text, black outline, lower-middle safe area.
- Max two subtitle lines.
- Avoid overflowing screen edges.

Do not ask generation models to create text inside frames.

## QA Commands

Run:

```powershell
ffprobe -v error -show_entries stream=codec_type,codec_name,width,height,sample_aspect_ratio,display_aspect_ratio -show_entries format=duration,size,bit_rate -of json "<final.mp4>"
```

Run:

```powershell
ffmpeg -hide_banner -i "<final.mp4>" -vf blackdetect=d=0.05:pix_th=0.02 -an -f null - 2>&1 | Select-String 'black'
```

Extract:

- First frame.
- Middle frame.
- End frame.
- Frames near each segment boundary.

Inspect product, subtitles, title, black frames, and transition continuity.
