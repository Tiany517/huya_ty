# QA Checklist

## Required Technical Checks

Run `ffprobe`:

```powershell
ffprobe -v error -show_entries stream=codec_type,codec_name,width,height,sample_aspect_ratio,display_aspect_ratio -show_entries format=duration,size,bit_rate -of json "<final.mp4>"
```

Expected:

- Video codec: H.264.
- Audio codec: AAC.
- Width: 720.
- Height: 1280.
- Display aspect ratio: 9:16.

Run `blackdetect`:

```powershell
ffmpeg -hide_banner -i "<final.mp4>" -vf blackdetect=d=0.05:pix_th=0.02 -an -f null - 2>&1 | Select-String 'black'
```

No output normally means no black segment was detected.

## Required Visual Checks

Extract and inspect:

- First visible frame.
- Middle frame.
- Final or near-final frame.
- Frames near segment boundaries if transitions are the user's concern.

Check:

- No top black strip.
- No black first frame.
- No black frame between segments.
- Title is large enough and not too close to platform UI.
- Subtitles fit inside screen, max two lines.
- Subtitles are readable against the background.
- Character identity is acceptably stable.

## Subjective Checks

Technical QA cannot guarantee:

- Mouth-sync quality.
- Generated voice quality.
- Whether narration is fully spoken.
- Whether BGM taste fits.
- Whether transitions feel natural.

Report these as residual risks if not manually watched end-to-end.
